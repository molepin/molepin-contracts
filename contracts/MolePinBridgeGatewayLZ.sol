// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/* ============================================================================
 *  MolePinBridgeGatewayLZ — NATIVE-FEE FRONT DOOR for the LayerZero OFT mesh
 * ----------------------------------------------------------------------------
 *  WHAT THIS IS (KO: 이게 뭔지):
 *  A SEND-SIDE-ONLY gateway that wraps the MolePin OFT/OFTAdapter `send()` so that
 *  every cross-chain transfer pays a MolePin business fee in the chain's NATIVE
 *  token (BNB/POL/ETH/...) — collected to the treasury IN THE SAME TRANSACTION as
 *  the LayerZero send. This is the LayerZero re-implementation of the CCT gateway's
 *  native-fee philosophy ("token is pure; all fee policy lives in the gateway").
 *  (KO: OFT.send를 감싸 비즈니스 수수료를 네이티브 토큰으로 한 트랜잭션에 함께 징수.
 *   CCT 게이트웨이의 native-fee 철학을 LayerZero로 재구현. 토큰은 순수, 정책은 게이트웨이.)
 *
 *  WHY SEND-SIDE ONLY (KO: 왜 송신 전용인가):
 *  Unlike CCIP — which capped the destination mint path at 90k gas for EOA receivers
 *  and FORCED a receiver gateway to forward minted tokens — LayerZero OFT credits the
 *  end user DIRECTLY in _credit() on the destination, with receive gas controlled via
 *  lzReceiveOption in extraOptions. So there is NO receive-side gateway and NO
 *  ccipReceive forwarding. The whole "gateway-as-receiver / CREATE2 same-address"
 *  machinery from the CCT design is UNNECESSARY here.
 *  (KO: CCIP는 EOA 90k 한도 때문에 수신 게이트웨이가 토큰을 유저에게 forward해야 했음.
 *   OFT는 _credit이 유저에게 직접 mint하고 수신 가스는 extraOptions로 제어 → 수신 게이트웨이
 *   불필요, ccipReceive 불필요. CCT의 CREATE2 동일주소 강박도 여기선 불필요.)
 *
 *  CROSS-CHAIN SECURITY (KO: 크로스체인 보안):
 *  Sender authenticity is enforced by the OFT's own `peers` mapping (setPeer), the
 *  LayerZero-standard trust model — it REPLACES the CCT gateway's trustedRemoteGateway
 *  check. The gateway here is a thin send wrapper and is NOT a security boundary for
 *  inbound messages (there are none to it).
 *  (KO: 발신자 진위는 OFT의 peers(setPeer)가 강제 — CCT의 trustedRemoteGateway를 대체.
 *   이 게이트웨이는 송신 래퍼일 뿐 인바운드 보안 경계가 아님.)
 *
 *  DEPLOYED ON EVERY CHAIN (KO: 모든 체인에 배포):
 *  Same bytecode on BSC + every remote chain so a native fee is charged wherever the
 *  user departs from. Per-chain behaviour is injected ONCE via configure():
 *    · BSC  (home)   → FEE_MODE_USD_FIXED  : $1 fixed via oracle, capped at $5.
 *    · others (remote) → FEE_MODE_LZ_MULTIPLE : molepinFee = lzFee * (bps/10000).
 *  (KO: 모든 체인에 동일 바이트코드. configure로 체인별 모드 주입.
 *   BSC=오라클 $1 고정($5 상한), 나머지=lzFee 배수(기본 2배).)
 * ==========================================================================*/

/// @notice Chainlink-style native/USD price feed (used only in FEE_MODE_USD_FIXED).
interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/* ----------------------------------------------------------------------------
 *  Inline LayerZero OFT types. MUST match @layerzerolabs/oft-evm byte-for-byte so
 *  the real OFT/OFTAdapter ABI-encodes/decodes against these structs.
 *  (KO: 실제 OFT가 ABI 인/디코딩하므로 LayerZero 타입과 정확히 일치해야 함.)
 * --------------------------------------------------------------------------*/
struct SendParam {
    uint32  dstEid;        // destination LayerZero endpoint id
    bytes32 to;            // recipient (the END USER, left-padded to bytes32)
    uint256 amountLD;      // amount in local decimals (gross, before OFT-side fee/dust)
    uint256 minAmountLD;   // min received in local decimals (slippage floor)
    bytes   extraOptions;  // execution options (lzReceiveOption gas etc.)
    bytes   composeMsg;    // composed message (unused here)
    bytes   oftCmd;        // OFT command (unused in default OFT)
}

struct MessagingFee {
    uint256 nativeFee;     // LayerZero messaging fee in native gas
    uint256 lzTokenFee;    // LayerZero messaging fee in ZRO (we always pay native → 0)
}

struct MessagingReceipt {
    bytes32 guid;
    uint64  nonce;
    MessagingFee fee;
}

struct OFTReceipt {
    uint256 amountSentLD;
    uint256 amountReceivedLD;
}

/// @notice Subset of the LayerZero OFT interface the gateway calls.
interface IOFT {
    /// @dev OFTAdapter returns token()==innerToken; pure OFT returns token()==address(this).
    function token() external view returns (address);
    /// @dev True when send() must pull ERC20 via approve (adapter & most OFTs). Kept for clarity.
    function approvalRequired() external view returns (bool);
    function quoteSend(SendParam calldata _sendParam, bool _payInLzToken)
        external view returns (MessagingFee memory);
    function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
        external payable returns (MessagingReceipt memory, OFTReceipt memory);
}

contract MolePinBridgeGatewayLZ is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ── Fee modes ────────────────────────────────────────────────────────────
    /// @notice BSC home chain: business fee is a fixed USD amount via oracle (capped at $5).
    uint8 public constant FEE_MODE_USD_FIXED = 0;
    /// @notice Remote chains: business fee = lzFee * feeMultiplierBps / 10000 (default 2x).
    uint8 public constant FEE_MODE_LZ_MULTIPLE = 1;

    // ── Per-chain config (injected ONCE via configure) ─────────────────────────
    /// @notice The OFT (remote) or OFTAdapter (BSC home) on THIS chain.
    IOFT public OFT;
    /// @notice The MOL token the user holds on THIS chain (OFT.token()). Cached at configure.
    IERC20 public MOL;
    /// @notice native/USD feed — REQUIRED for FEE_MODE_USD_FIXED, ignored otherwise.
    IAggregatorV3 public NATIVE_USD;
    uint8 public NATIVE_FEED_DECIMALS;
    uint8 public feeMode;
    bool  public configured;

    // ── Fee policy ─────────────────────────────────────────────────────────────
    /// @notice USD fee for FEE_MODE_USD_FIXED, 18-dec. Default $1. Hard cap $5.
    uint256 public feeUsd = 1 * 1e18;
    uint256 public constant MAX_FEE_USD = 5 * 1e18;
    uint256 public constant PRICE_STALE_AFTER = 3600;

    /// @notice Multiplier for FEE_MODE_LZ_MULTIPLE in bps. Default 20000 = 2.00x the lzFee.
    ///         e.g. lzFee=0.01 ETH, bps=20000 → molepinFee=0.02 ETH (user pays 0.03 total).
    /// (KO: lzFee 배수(bps). 20000=2배. lzFee 0.01 → 수수료 0.02 → 총 0.03 지불.)
    uint16 public feeMultiplierBps = 20_000;
    uint16 public constant MAX_FEE_MULTIPLIER_BPS = 50_000; // hard cap 5x (안전 상한)

    address public treasury;
    mapping(uint32 => bool) public allowedDstEid;

    // ── Events ───────────────────────────────────────────────────────────────
    event GatewayConfigured(address indexed oft, address indexed mol, address indexed nativeUsdFeed, uint8 feeMode, uint8 feedDecimals);
    event FeeUsdUpdated(uint256 oldFeeUsd, uint256 newFeeUsd);
    event FeeMultiplierUpdated(uint16 oldBps, uint16 newBps);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event DstEidUpdated(uint32 indexed dstEid, bool allowed);
    event BridgeInitiated(
        address indexed sender, uint32 indexed dstEid, address indexed finalRecipient,
        uint256 molAmount, uint256 lzFee, uint256 molepinFeeNative, bytes32 guid
    );

    /// @param initialOwner Owner (2-step). On mainnet → timelock+multisig.
    /// @param treasury_    Native-fee recipient.
    /// @dev oft/mol/feed/mode are injected post-deploy via configure(), mirroring the CCT
    ///      gateway's pattern (constructor stays minimal & chain-agnostic).
    constructor(address initialOwner, address treasury_) Ownable(initialOwner) {
        require(treasury_ != address(0), "zero addr");
        treasury = treasury_;
    }

    // ── Configuration ──────────────────────────────────────────────────────────
    /// @notice One-time per-chain injection. Owner-only.
    /// @param oft_         OFT (remote) or OFTAdapter (BSC) on this chain.
    /// @param nativeUsdFeed native/USD feed; MUST be set for FEE_MODE_USD_FIXED, else address(0).
    /// @param feeMode_     FEE_MODE_USD_FIXED (BSC) or FEE_MODE_LZ_MULTIPLE (remote).
    function configure(address oft_, address nativeUsdFeed, uint8 feeMode_) external onlyOwner {
        require(!configured, "configured");
        require(oft_ != address(0) && oft_.code.length > 0, "bad oft");
        require(feeMode_ <= FEE_MODE_LZ_MULTIPLE, "bad mode");

        OFT = IOFT(oft_);
        address molToken = IOFT(oft_).token();
        require(molToken != address(0) && molToken.code.length > 0, "bad token");
        MOL = IERC20(molToken);

        if (feeMode_ == FEE_MODE_USD_FIXED) {
            require(nativeUsdFeed != address(0) && nativeUsdFeed.code.length > 0, "feed required");
            NATIVE_USD = IAggregatorV3(nativeUsdFeed);
            uint8 dec = IAggregatorV3(nativeUsdFeed).decimals();
            NATIVE_FEED_DECIMALS = dec;
            emit GatewayConfigured(oft_, molToken, nativeUsdFeed, feeMode_, dec);
        } else {
            // FEE_MODE_LZ_MULTIPLE: no oracle needed.
            emit GatewayConfigured(oft_, molToken, address(0), feeMode_, 0);
        }

        feeMode = feeMode_;
        configured = true;
    }

    modifier onlyConfigured() {
        require(configured, "not configured");
        _;
    }

    // ── Fee views ───────────────────────────────────────────────────────────────
    /// @notice Business fee in native token for FEE_MODE_USD_FIXED (oracle-priced $feeUsd).
    /// @dev Reverts if used on a chain configured for FEE_MODE_LZ_MULTIPLE.
    function molepinFeeUsdFixed() public view onlyConfigured returns (uint256) {
        require(feeMode == FEE_MODE_USD_FIXED, "wrong mode");
        (, int256 price,, uint256 updatedAt,) = NATIVE_USD.latestRoundData();
        require(price > 0, "bad oracle price");
        require(block.timestamp - updatedAt <= PRICE_STALE_AFTER, "stale oracle");
        return (feeUsd * (10 ** NATIVE_FEED_DECIMALS)) / uint256(price);
    }

    /// @notice Business fee in native token for a given lzFee in FEE_MODE_LZ_MULTIPLE.
    function molepinFeeLzMultiple(uint256 lzFee) public view onlyConfigured returns (uint256) {
        require(feeMode == FEE_MODE_LZ_MULTIPLE, "wrong mode");
        return (lzFee * feeMultiplierBps) / 10_000;
    }

    /// @notice Build the canonical SendParam for an outbound bridge. View helper so the
    ///         frontend can quote with the EXACT same params used on-chain.
    /// @dev recipient goes directly into `to` (end user) — NO gateway forwarding (vs CCT).
    function buildSendParam(uint32 dstEid, address finalRecipient, uint256 molAmount, uint256 minAmountLD, bytes calldata extraOptions)
        public pure returns (SendParam memory)
    {
        return SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(finalRecipient))),
            amountLD: molAmount,
            minAmountLD: minAmountLD,
            extraOptions: extraOptions,
            composeMsg: "",
            oftCmd: ""
        });
    }

    /// @notice Full quote: (lzFee, molepinFee, total) the caller must attach as msg.value.
    function quote(uint32 dstEid, address finalRecipient, uint256 molAmount, uint256 minAmountLD, bytes calldata extraOptions)
        external view onlyConfigured
        returns (uint256 lzFee, uint256 molepinFee, uint256 total)
    {
        SendParam memory sp = buildSendParam(dstEid, finalRecipient, molAmount, minAmountLD, extraOptions);
        MessagingFee memory mf = OFT.quoteSend(sp, false); // pay in native, never ZRO
        lzFee = mf.nativeFee;
        molepinFee = (feeMode == FEE_MODE_USD_FIXED)
            ? molepinFeeUsdFixed()
            : molepinFeeLzMultiple(lzFee);
        total = lzFee + molepinFee;
    }

    // ── Send ─────────────────────────────────────────────────────────────────────
    /**
     * @notice Bridge `molAmount` MOL to `finalRecipient` on `dstEid`, paying the LayerZero
     *         messaging fee + the MolePin native business fee in ONE transaction.
     * @dev Single-tx flow (mirrors the CCT gateway, ccipSend→OFT.send):
     *      1. pull MOL from the user into this gateway, approve the OFT
     *      2. quote lzFee for the EXACT SendParam
     *      3. compute molepinFee by this chain's fee mode
     *      4. require msg.value covers lzFee + molepinFee
     *      5. pay molepinFee → treasury (native)
     *      6. OFT.send{value: lzFee} — refundAddress = user (LZ refunds its own excess)
     *      7. refund any leftover (msg.value - lzFee - molepinFee) → user
     */
    function bridge(
        uint32 dstEid,
        address finalRecipient,
        uint256 molAmount,
        uint256 minAmountLD,
        bytes calldata extraOptions
    ) external payable nonReentrant onlyConfigured returns (bytes32 guid) {
        require(molAmount > 0, "zero amount");
        require(finalRecipient != address(0), "zero recipient");
        require(allowedDstEid[dstEid], "dst not allowed");

        // 1. pull + approve. Gross molAmount is what the OFT debits (its own _debit may take an
        //    OFT-side fee, but per the supplied OFT design bridgeFeeBps defaults to 0; the business
        //    fee is charged HERE in native, not in MOL).
        MOL.safeTransferFrom(msg.sender, address(this), molAmount);
        MOL.forceApprove(address(OFT), molAmount);

        // 2. quote against the exact params we will send.
        SendParam memory sp = buildSendParam(dstEid, finalRecipient, molAmount, minAmountLD, extraOptions);
        uint256 lzFee = OFT.quoteSend(sp, false).nativeFee;

        // 3. business fee in native by mode.
        uint256 molepinFee = (feeMode == FEE_MODE_USD_FIXED)
            ? molepinFeeUsdFixed()
            : molepinFeeLzMultiple(lzFee);

        // 4. funding check (lzFee + molepinFee).
        require(msg.value >= lzFee + molepinFee, "insufficient native");

        // 5. collect business fee → treasury.
        if (molepinFee > 0) {
            (bool okFee, ) = payable(treasury).call{value: molepinFee}("");
            require(okFee, "fee transfer failed");
        }

        // 6. LayerZero send. refundAddress=user: the OFT/endpoint refunds ITS OWN excess
        //    directly to the user. We pass exactly lzFee so there is nothing for LZ to refund,
        //    but user is the correct sink for any protocol-side rounding refund.
        (MessagingReceipt memory receipt, ) =
            OFT.send{value: lzFee}(sp, MessagingFee({nativeFee: lzFee, lzTokenFee: 0}), finalRecipient);
        guid = receipt.guid;

        // 7. refund the gateway-level leftover (over-payment buffer) back to the caller.
        if (msg.value > lzFee + molepinFee) {
            (bool okRef, ) = payable(msg.sender).call{value: msg.value - lzFee - molepinFee}("");
            require(okRef, "refund failed");
        }

        emit BridgeInitiated(msg.sender, dstEid, finalRecipient, molAmount, lzFee, molepinFee, guid);
    }

    // ── Owner config ──────────────────────────────────────────────────────────────
    function setFeeUsd(uint256 newFeeUsd) external onlyOwner {
        require(newFeeUsd <= MAX_FEE_USD, "exceeds max $5");
        emit FeeUsdUpdated(feeUsd, newFeeUsd);
        feeUsd = newFeeUsd;
    }

    function setFeeMultiplierBps(uint16 newBps) external onlyOwner {
        require(newBps <= MAX_FEE_MULTIPLIER_BPS, "exceeds 5x");
        emit FeeMultiplierUpdated(feeMultiplierBps, newBps);
        feeMultiplierBps = newBps;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "zero addr");
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    function setDstEid(uint32 dstEid, bool allowed) external onlyOwner {
        allowedDstEid[dstEid] = allowed;
        emit DstEidUpdated(dstEid, allowed);
    }

    /// @notice Recover native accidentally stuck (e.g. failed refund). Owner-only.
    function sweepNative(address to) external onlyOwner {
        require(to != address(0), "zero addr");
        (bool ok, ) = payable(to).call{value: address(this).balance}("");
        require(ok, "sweep failed");
    }

    /// @notice Recover ERC20 accidentally stuck. Does NOT touch user funds mid-bridge
    ///         (bridge() is atomic & nonReentrant; no MOL should ever rest here).
    function sweepToken(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "zero addr");
        IERC20(token).safeTransfer(to, amount);
    }

    receive() external payable {}
}
