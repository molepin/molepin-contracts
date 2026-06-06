// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/* External interfaces declared inline: @chainlink pins OZ 4.8.3 (version clash with OZ 5.x).
   Signatures match the real Chainlink contracts, so interaction is compatible.
   (KO: 버전 충돌 회피 위해 필요한 시그니처만 직접 선언. 실제 Chainlink와 호환.) */

/// @notice Chainlink Data Feed (AggregatorV3) — reads the chain's native-token/USD price.
interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @notice CCIP Client message structs (subset used here).
library Client {
    struct EVMTokenAmount { address token; uint256 amount; }
    struct EVM2AnyMessage { bytes receiver; bytes data; EVMTokenAmount[] tokenAmounts; address feeToken; bytes extraArgs; }
}

/// @notice CCIP Router (subset used here).
interface IRouterClient {
    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage memory message) external view returns (uint256 fee);
    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message) external payable returns (bytes32);
}

/**
 * @title MolePinBridgeGateway
 * @notice The single front door for MOL cross-chain transfers. Same code deploys to any EVM chain;
 *         per-chain addresses (MOL, CCIP Router, native/USD feed) are injected at deployment.
 *         (KO: MOL 멀티체인 이동의 유일한 정문. 어느 EVM 체인에든 동일 코드로 배포, 주소만 주입.)
 *
 * @dev Fee policy (final): every cross-chain transfer is charged, on every chain. The fee is an extra
 *      "$N worth" of the SOURCE chain's native gas token (BNB on BSC, POL on Polygon, ETH on Base/Arb/Op).
 *      Default $1, owner-adjustable, hard-capped at $5 (MAX_FEE_USD, immutable). Sent to treasury.
 *      MOL itself is never touched (sent amount arrives intact). CCIP's own fee is paid separately to
 *      the router; MolePin's fee is added on top.
 *      (KO: 모든 체인에서 이동 시 무조건 수수료. 출발 체인 native로 $N(기본$1, 상한$5). 배포지갑으로.)
 *
 * @dev Expansion: a new EVM chain = deploy this (inject addresses) + setDestChain(selector). No code change.
 *      (Non-EVM: TON/Solana/Sui need separate languages — roadmap, not here.)
 *
 * @dev Oracle safety: price must be positive & fresh, else revert. Feed decimals are read dynamically
 *      (8/18 etc. vary by chain/feed) to avoid mispricing.
 */
contract MolePinBridgeGateway is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable MOL;                  // MOL token on this chain
    IRouterClient public immutable ROUTER;        // CCIP router on this chain
    IAggregatorV3 public immutable NATIVE_USD;    // native-token/USD feed on this chain
    uint8 public immutable NATIVE_FEED_DECIMALS;  // feed decimals, read once at deploy

    /// @notice Fee hard cap = $5 (USD in 18 decimals, internal standard). Immutable.
    uint256 public constant MAX_FEE_USD = 5 * 1e18;
    /// @notice Oracle freshness limit (seconds). Older data is rejected.
    uint256 public constant PRICE_STALE_AFTER = 3600;

    /// @notice MolePin fee in USD (18 decimals). Default $1. Owner-adjustable within the cap.
    uint256 public feeUsd = 1 * 1e18;
    /// @notice Fee recipient (deployer wallet / treasury).
    address public treasury;
    /// @notice Allowed destination chains (CCIP selectors). Owner registers new chains.
    mapping(uint64 => bool) public allowedDestChains;

    event FeeUsdUpdated(uint256 oldFeeUsd, uint256 newFeeUsd);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event DestChainUpdated(uint64 indexed selector, bool allowed);
    event BridgeInitiated(
        address indexed sender, uint64 indexed destChainSelector, bytes receiver,
        uint256 molAmount, uint256 ccipFee, uint256 molepinFeeNative, bytes32 messageId
    );

    /// @param initialOwner Owner (2-step).
    /// @param mol           MOL token address on this chain.
    /// @param router        CCIP router address on this chain.
    /// @param nativeUsdFeed Native-token/USD Chainlink feed on this chain (e.g. POL/USD on Polygon).
    /// @param treasury_     Fee recipient.
    constructor(address initialOwner, address mol, address router, address nativeUsdFeed, address treasury_)
        Ownable(initialOwner)
    {
        require(mol != address(0) && router != address(0) && nativeUsdFeed != address(0) && treasury_ != address(0), "zero addr");
        MOL = IERC20(mol);
        ROUTER = IRouterClient(router);
        NATIVE_USD = IAggregatorV3(nativeUsdFeed);
        NATIVE_FEED_DECIMALS = IAggregatorV3(nativeUsdFeed).decimals();
        treasury = treasury_;
    }

    /// @notice MolePin fee converted to native gas token (wei). Feed decimals applied dynamically.
    /// (KO: MolePin 수수료를 그 체인 native토큰으로 환산. 피드 decimals 동적 반영.)
    function molepinFeeInNative() public view returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = NATIVE_USD.latestRoundData();
        require(price > 0, "bad oracle price");
        require(block.timestamp - updatedAt <= PRICE_STALE_AFTER, "stale oracle");
        return (feeUsd * (10 ** NATIVE_FEED_DECIMALS)) / uint256(price);
    }

    /// @notice Quote total native needed (= CCIP fee + MolePin fee) before bridging.
    function quoteTotalFee(uint64 destChainSelector, Client.EVM2AnyMessage calldata message)
        external view returns (uint256 ccipFee, uint256 molepinFee, uint256 total)
    {
        ccipFee = ROUTER.getFee(destChainSelector, message);
        molepinFee = molepinFeeInNative();
        total = ccipFee + molepinFee;
    }

    /// @notice Bridge MOL to another chain. msg.value pays (CCIP fee + MolePin fee) in native gas token.
    /// @param destChainSelector CCIP selector of the destination chain.
    /// @param receiver          Destination receiver, abi.encode(address).
    /// @param molAmount         MOL amount to bridge (arrives intact).
    /// @param extraArgs         CCIP extraArgs (e.g. gasLimit).
    function bridge(uint64 destChainSelector, bytes calldata receiver, uint256 molAmount, bytes calldata extraArgs)
        external payable nonReentrant returns (bytes32 messageId)
    {
        require(molAmount > 0, "zero amount");
        require(allowedDestChains[destChainSelector], "dest not allowed");

        // Pull user's MOL, approve router.
        MOL.safeTransferFrom(msg.sender, address(this), molAmount);
        MOL.forceApprove(address(ROUTER), molAmount);

        // Build CCIP message (pay CCIP fee in native -> feeToken = address(0)).
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(MOL), amount: molAmount});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: receiver, data: "", tokenAmounts: tokenAmounts, feeToken: address(0), extraArgs: extraArgs
        });

        // Fees.
        uint256 ccipFee = ROUTER.getFee(destChainSelector, message);
        uint256 molepinFee = molepinFeeInNative();
        uint256 required = ccipFee + molepinFee;
        require(msg.value >= required, "insufficient native");

        // MolePin fee -> treasury.
        (bool okFee, ) = payable(treasury).call{value: molepinFee}("");
        require(okFee, "fee transfer failed");

        // Send via CCIP (only the CCIP fee goes to the router).
        messageId = ROUTER.ccipSend{value: ccipFee}(destChainSelector, message);

        // Refund any excess native.
        uint256 refund = msg.value - required;
        if (refund > 0) {
            (bool okRef, ) = payable(msg.sender).call{value: refund}("");
            require(okRef, "refund failed");
        }

        emit BridgeInitiated(msg.sender, destChainSelector, receiver, molAmount, ccipFee, molepinFee, messageId);
    }

    // ── Owner config ─────────────────────────────────────────────────────────
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

    /// @notice Add/remove a destination EVM chain. Expands reach with no code change.
    /// (KO: 새 EVM 체인 추가/제거. 코드 수정 없이 확장.)
    function setDestChain(uint64 selector, bool allowed) external onlyOwner {
        allowedDestChains[selector] = allowed;
        emit DestChainUpdated(selector, allowed);
    }

    /// @notice Recover stranded native (rare given refund logic; safety valve).
    function sweepNative(address to) external onlyOwner {
        require(to != address(0), "zero addr");
        (bool ok, ) = payable(to).call{value: address(this).balance}("");
        require(ok, "sweep failed");
    }

    receive() external payable {}
}
