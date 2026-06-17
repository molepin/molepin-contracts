// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/* External interfaces declared inline: @chainlink pins OZ 4.8.3 (version clash with OZ 5.x). */

interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/**
 * @dev Inline CCIP Client types. MUST match Chainlink's Client library byte-for-byte so the
 *      real CCIP Router/OffRamp can ABI-encode/decode against these structs.
 *      (KO: 실제 CCIP Router/OffRamp가 ABI 인/디코딩하므로 Chainlink Client와 정확히 일치해야 함.)
 *  - EVM2AnyMessage : send side (source chain)  → used by bridge()
 *  - Any2EVMMessage : receive side (dest chain) → used by ccipReceive()
 *  - EVMExtraArgsV2 : gasLimit + allowOutOfOrderExecution (encoded for extraArgs)
 */
library Client {
    struct EVMTokenAmount { address token; uint256 amount; }

    struct EVM2AnyMessage {
        bytes receiver;
        bytes data;
        EVMTokenAmount[] tokenAmounts;
        address feeToken;
        bytes extraArgs;
    }

    struct Any2EVMMessage {
        bytes32 messageId;
        uint64 sourceChainSelector;
        bytes sender;                 // abi-encoded source gateway address
        bytes data;                   // abi-encoded final user address (set by bridge())
        EVMTokenAmount[] destTokenAmounts;
    }

    // EVMExtraArgsV2 tag = bytes4(keccak256("CCIP EVMExtraArgsV2"))
    bytes4 public constant EVM_EXTRA_ARGS_V2_TAG = 0x181dcf10;
    struct EVMExtraArgsV2 { uint256 gasLimit; bool allowOutOfOrderExecution; }

    function _argsToBytes(EVMExtraArgsV2 memory extraArgs) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(EVM_EXTRA_ARGS_V2_TAG, extraArgs);
    }
}

interface IRouterClient {
    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage memory message) external view returns (uint256 fee);
    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message) external payable returns (bytes32);
}

/// @notice CCIP receiver interface. OffRamp calls ccipReceive on the destination gateway.
interface IAny2EVMMessageReceiver {
    function ccipReceive(Client.Any2EVMMessage calldata message) external;
}

/// @notice Minimal IERC165 (declared inline, OZ-version-agnostic).
interface IERC165_ {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @title MolePinBridgeGateway
 * @notice Single front door for MOL cross-chain transfers, BIDIRECTIONAL (send + receive).
 *         SAME bytecode + SAME constructor args (owner, treasury) on every EVM chain → identical
 *         CREATE2 address. ALL per-chain addresses (MOL token, CCIP Router, native/USD feed) are
 *         injected ONCE via configure(). This is the V3 change: mol moved out of the constructor so
 *         the gateway address stays identical even in the LockRelease model where the BSC home token
 *         and the remote token have DIFFERENT addresses.
 *         (KO: V3 — mol을 생성자에서 빼 configure로 주입. LockRelease는 홈/리모트 토큰 주소가 달라도
 *          게이트웨이 CREATE2 동일주소를 유지하기 위함. 수수료는 native($1 기본, $5 상한) 그대로.)
 *
 * @dev WHY a gateway receiver (vs sending tokens straight to a user EOA):
 *      CCIP caps the destination mint path (balanceOf + releaseOrMint + balanceOf) at a default
 *      90,000 gas when the receiver is an EOA (extraArgs.gasLimit is IGNORED for EOAs). A first
 *      mint to a fresh address costs ~81k+ (new storage slot = +20k), which OVERFLOWS 90k and
 *      fails with TokenHandlingError (out of gas). When the receiver is a CONTRACT, extraArgs.gasLimit
 *      IS applied to the ccipReceive callback, so we can budget enough gas. The token is minted to
 *      THIS gateway, then ccipReceive forwards it to the real user. The gateway address is the SAME
 *      on every chain (CREATE2), so its balance slot is warmed once and every later mint is cheap.
 *      (KO: EOA 직접 수신은 CCIP 90k mint 한도에 걸려 첫 mint가 실패. 컨트랙트 수신은 extraArgs.gasLimit이
 *       적용되어 한도 회피. 토큰은 게이트웨이로 mint된 뒤 ccipReceive가 유저에게 전달.)
 *
 *      WHY NOT inherit Chainlink's CCIPReceiver:
 *      CCIPReceiver fixes the router as an immutable constructor arg. That would make the constructor
 *      args differ per chain and BREAK CREATE2 same-address. Instead we implement the receiver
 *      interface directly and validate against the router injected via configure().
 *      (KO: CCIPReceiver는 router를 생성자 immutable로 고정 → CREATE2 동일주소 깨짐. 직접 구현.)
 */
contract MolePinBridgeGateway is Ownable2Step, ReentrancyGuard, IAny2EVMMessageReceiver, IERC165_ {
    using SafeERC20 for IERC20;

    /// @notice MOL token on this chain. Injected via configure() — NOT immutable, NOT a constructor arg.
    ///         LockRelease model: BSC home token != remote token (different addresses). Keeping mol out
    ///         of the constructor is what lets the gateway keep an identical CREATE2 address on every
    ///         chain even though the underlying token address differs per chain.
    /// (KO: LockRelease는 홈 토큰≠리모트 토큰이라 mol이 체인마다 다름. 생성자에서 빼고 configure로 주입해야
    ///  게이트웨이 CREATE2 동일주소가 유지됨. router/feed와 동일한 패턴.)
    IERC20 public MOL;

    /// @notice CCIP router on this chain. Injected post-deploy (per-chain) → NOT immutable.
    IRouterClient public ROUTER;
    /// @notice native-token/USD feed on this chain. Injected post-deploy (per-chain) → NOT immutable.
    IAggregatorV3 public NATIVE_USD;
    uint8 public NATIVE_FEED_DECIMALS;

    bool public configured;

    uint256 public constant MAX_FEE_USD = 5 * 1e18;
    uint256 public constant PRICE_STALE_AFTER = 3600;

    /// @notice Gas budget for the destination ccipReceive callback (token mint + forward transfer).
    ///         Must comfortably exceed first-mint cost (~81k) + forward transfer (~30k). 250k default.
    uint256 public destGasLimit = 250_000;

    uint256 public feeUsd = 1 * 1e18;
    address public treasury;
    mapping(uint64 => bool) public allowedDestChains;

    /// @notice Trusted source chain → gateway address allowed to deliver into ccipReceive.
    ///         Since the gateway is the SAME address on every chain (CREATE2), this is normally
    ///         address(this) for each remote selector, but kept explicit for safety/flexibility.
    /// (KO: 신뢰하는 출발 체인별 게이트웨이 주소. CREATE2라 보통 자기 주소와 동일하나 명시적으로 관리.)
    mapping(uint64 => address) public trustedRemoteGateway;

    event FeeUsdUpdated(uint256 oldFeeUsd, uint256 newFeeUsd);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event DestChainUpdated(uint64 indexed selector, bool allowed);
    event TrustedRemoteUpdated(uint64 indexed selector, address indexed gateway);
    event DestGasLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event GatewayConfigured(address indexed token, address indexed router, address indexed nativeUsdFeed, uint8 feedDecimals);
    event BridgeInitiated(
        address indexed sender, uint64 indexed destChainSelector, address indexed finalRecipient,
        uint256 molAmount, uint256 ccipFee, uint256 molepinFeeNative, bytes32 messageId
    );
    event BridgeReceived(
        bytes32 indexed messageId, uint64 indexed sourceChainSelector,
        address indexed finalRecipient, uint256 molAmount
    );

    /// @param initialOwner Owner (2-step). SAME on every chain → identical CREATE2 address.
    /// @param treasury_     Fee recipient. SAME on every chain.
    /// @dev mol/router/feed are ALL injected post-deploy via configure() so the constructor args are
    ///      identical across chains (only owner + treasury, both global) → same CREATE2 address.
    constructor(address initialOwner, address treasury_)
        Ownable(initialOwner)
    {
        require(treasury_ != address(0), "zero addr");
        treasury = treasury_;
    }

    /// @notice One-time injection of per-chain addresses (token, router, feed). Owner-only.
    /// @dev mol differs per chain in the LockRelease model (BSC home token vs remote token), so it is
    ///      injected here rather than in the constructor — that keeps the CREATE2 address identical.
    function configure(address mol, address router, address nativeUsdFeed) external onlyOwner {
        require(!configured, "configured");
        require(mol != address(0) && router != address(0) && nativeUsdFeed != address(0), "zero addr");
        require(mol.code.length > 0 && router.code.length > 0 && nativeUsdFeed.code.length > 0, "not contract");

        MOL = IERC20(mol);
        ROUTER = IRouterClient(router);
        NATIVE_USD = IAggregatorV3(nativeUsdFeed);
        uint8 dec = IAggregatorV3(nativeUsdFeed).decimals();
        NATIVE_FEED_DECIMALS = dec;
        configured = true;

        emit GatewayConfigured(mol, router, nativeUsdFeed, dec);
    }

    modifier onlyConfigured() {
        require(configured, "not configured");
        _;
    }

    function molepinFeeInNative() public view onlyConfigured returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = NATIVE_USD.latestRoundData();
        require(price > 0, "bad oracle price");
        require(block.timestamp - updatedAt <= PRICE_STALE_AFTER, "stale oracle");
        return (feeUsd * (10 ** NATIVE_FEED_DECIMALS)) / uint256(price);
    }

    // ── Quote (view) ─────────────────────────────────────────────────────────────
    /**
     * @notice Pre-send estimate of the total native value required to bridge `molAmount` MOL to
     *         `finalRecipient` on `destChainSelector`. The frontend/script should call this first,
     *         then send `totalNative` (plus a small buffer for price drift) as msg.value to bridge().
     *         This eliminates "insufficient native" failures from guessing the fee.
     *         (KO: bridge() 전에 필요한 총 native를 미리 견적. 이 값(+소량 버퍼)을 msg.value로 보내면
     *          "insufficient native" 실패가 사라짐. 초과분은 bridge()가 자동 환불.)
     * @dev Builds the EXACT same CCIP message as bridge() (receiver, data, tokenAmounts, feeToken,
     *      extraArgs) so ROUTER.getFee returns the identical ccipFee that bridge() will compute.
     *      View-only: no token transfer, no approval, no state change.
     * @return totalNative ccipFee + molepinFee — send at least this as msg.value.
     * @return ccipFee     CCIP protocol fee in native (paid to the router).
     * @return molepinFee  MolePin native fee in native (paid to the treasury).
     */
    function quoteBridgeNative(uint64 destChainSelector, address finalRecipient, uint256 molAmount)
        external view onlyConfigured
        returns (uint256 totalNative, uint256 ccipFee, uint256 molepinFee)
    {
        require(molAmount > 0, "zero amount");
        require(finalRecipient != address(0), "zero recipient");
        address destGateway = trustedRemoteGateway[destChainSelector];
        require(destGateway != address(0), "no remote gateway");

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(MOL), amount: molAmount});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destGateway),
            data: abi.encode(finalRecipient),
            tokenAmounts: tokenAmounts,
            feeToken: address(0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({gasLimit: destGasLimit, allowOutOfOrderExecution: true})
            )
        });

        ccipFee = ROUTER.getFee(destChainSelector, message);
        molepinFee = molepinFeeInNative();
        totalNative = ccipFee + molepinFee;
    }

    // ── Send side ──────────────────────────────────────────────────────────────
    /**
     * @notice Bridge `molAmount` MOL to `finalRecipient` on the destination chain.
     * @dev Receiver of the CCIP message is the DESTINATION GATEWAY (a contract), NOT the user.
     *      The user's address travels in `data`. The destination gateway's ccipReceive forwards
     *      the minted MOL to the user. extraArgs is built internally with destGasLimit so the
     *      callback always has enough gas (this is the core fix for the 90k EOA limit).
     */
    function bridge(uint64 destChainSelector, address finalRecipient, uint256 molAmount)
        external payable nonReentrant onlyConfigured returns (bytes32 messageId)
    {
        require(molAmount > 0, "zero amount");
        require(finalRecipient != address(0), "zero recipient");
        require(allowedDestChains[destChainSelector], "dest not allowed");
        address destGateway = trustedRemoteGateway[destChainSelector];
        require(destGateway != address(0), "no remote gateway");

        MOL.safeTransferFrom(msg.sender, address(this), molAmount);
        MOL.forceApprove(address(ROUTER), molAmount);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(MOL), amount: molAmount});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destGateway),                 // destination GATEWAY (contract)
            data: abi.encode(finalRecipient),                  // real user → forwarded by ccipReceive
            tokenAmounts: tokenAmounts,
            feeToken: address(0),                              // native fee
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({gasLimit: destGasLimit, allowOutOfOrderExecution: true})
            )
        });

        uint256 ccipFee = ROUTER.getFee(destChainSelector, message);
        uint256 molepinFee = molepinFeeInNative();
        uint256 required = ccipFee + molepinFee;
        require(msg.value >= required, "insufficient native");

        (bool okFee, ) = payable(treasury).call{value: molepinFee}("");
        require(okFee, "fee transfer failed");

        messageId = ROUTER.ccipSend{value: ccipFee}(destChainSelector, message);

        uint256 refund = msg.value - required;
        if (refund > 0) {
            (bool okRef, ) = payable(msg.sender).call{value: refund}("");
            require(okRef, "refund failed");
        }

        emit BridgeInitiated(msg.sender, destChainSelector, finalRecipient, molAmount, ccipFee, molepinFee, messageId);
    }

    // ── Receive side ─────────────────────────────────────────────────────────────
    /**
     * @notice Called by the CCIP Router/OffRamp on the destination chain after tokens are minted
     *         to THIS gateway. Forwards them to the real user encoded in `message.data`.
     * @dev Security: only the configured router may call; source chain + sender gateway must be trusted.
     */
    function ccipReceive(Client.Any2EVMMessage calldata message) external override nonReentrant {
        require(msg.sender == address(ROUTER), "only router");
        address srcGateway = trustedRemoteGateway[message.sourceChainSelector];
        require(srcGateway != address(0), "untrusted source chain");
        require(abi.decode(message.sender, (address)) == srcGateway, "untrusted sender");
        require(message.destTokenAmounts.length == 1, "bad token count");
        require(message.destTokenAmounts[0].token == address(MOL), "bad token");

        address user = abi.decode(message.data, (address));
        require(user != address(0), "zero user");
        uint256 amount = message.destTokenAmounts[0].amount;

        MOL.safeTransfer(user, amount);

        emit BridgeReceived(message.messageId, message.sourceChainSelector, user, amount);
    }

    /// @notice CCIP checks this to decide whether to call ccipReceive. MUST return true for
    ///         IAny2EVMMessageReceiver, else OffRamp would only transfer tokens (and skip forwarding).
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId
            || interfaceId == type(IERC165_).interfaceId;
    }

    // ── Owner config ─────────────────────────────────────────────────────────────
    function setFeeUsd(uint256 newFeeUsd) external onlyOwner {
        require(newFeeUsd <= MAX_FEE_USD, "exceeds max $5");
        emit FeeUsdUpdated(feeUsd, newFeeUsd);
        feeUsd = newFeeUsd;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "zero addr");
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    function setDestChain(uint64 selector, bool allowed) external onlyOwner {
        allowedDestChains[selector] = allowed;
        emit DestChainUpdated(selector, allowed);
    }

    /// @notice Register the trusted gateway address for a remote chain (usually address(this) since CREATE2).
    function setTrustedRemoteGateway(uint64 selector, address gateway) external onlyOwner {
        require(gateway != address(0), "zero addr");
        trustedRemoteGateway[selector] = gateway;
        emit TrustedRemoteUpdated(selector, gateway);
    }

    function setDestGasLimit(uint256 newLimit) external onlyOwner {
        require(newLimit >= 100_000 && newLimit <= 1_000_000, "out of range");
        emit DestGasLimitUpdated(destGasLimit, newLimit);
        destGasLimit = newLimit;
    }

    function sweepNative(address to) external onlyOwner {
        require(to != address(0), "zero addr");
        (bool ok, ) = payable(to).call{value: address(this).balance}("");
        require(ok, "sweep failed");
    }

    receive() external payable {}
}
