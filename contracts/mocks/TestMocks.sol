// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MolePinLzOptions} from "../MolePinLzOptions.sol";

/* ============================================================================
 *  Test mocks for MolePinBridgeGatewayLZ
 *  These intentionally mock ONLY the surface the gateway calls. Real LayerZero
 *  message passing is verified separately at the testnet-integration stage —
 *  here we isolate and stress the GATEWAY's fee math, atomicity, and refunds.
 *  (KO: 게이트웨이가 호출하는 표면만 mock. 실제 LZ 메시지 패싱은 testnet 통합에서.
 *   여기선 게이트웨이의 fee 산식·원자성·환불을 격리 검증.)
 * ==========================================================================*/

/// @notice Minimal MOL token for tests. Freely mintable to set up balances.
contract MockMOL is ERC20 {
    constructor() ERC20("MolePin", "MOL") {}
    function mint(address to, uint256 amt) external { _mint(to, amt); }
}

/// @notice Chainlink-style price feed mock. setUpdatedAt() lets us test staleness.
contract MockPriceOracle {
    uint8 public decimals;
    int256 private _price;
    uint256 private _updatedAt;

    constructor(uint8 _decimals, int256 initialPrice) {
        decimals = _decimals;
        _price = initialPrice;
        _updatedAt = block.timestamp;
    }
    function setPrice(int256 p) external { _price = p; _updatedAt = block.timestamp; }
    function setUpdatedAt(uint256 t) external { _updatedAt = t; }
    function latestRoundData()
        external view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, _price, _updatedAt, _updatedAt, 1);
    }
}

/// @notice Mock OFT. Implements token()/quoteSend()/send() exactly as the gateway expects.
///         send() pulls the approved MOL (mimics OFTAdapter lock / OFT burn debit) and
///         records what it received so tests can assert atomic behaviour.
struct SendParam {
    uint32 dstEid; bytes32 to; uint256 amountLD; uint256 minAmountLD;
    bytes extraOptions; bytes composeMsg; bytes oftCmd;
}
struct MessagingFee { uint256 nativeFee; uint256 lzTokenFee; }
struct MessagingReceipt { bytes32 guid; uint64 nonce; MessagingFee fee; }
struct OFTReceipt { uint256 amountSentLD; uint256 amountReceivedLD; }

contract MockOFT {
    address public token;
    uint256 public quotedFee;            // lzFee that quoteSend returns
    bool public approvalRequired = true;

    // capture last send for assertions
    uint256 public lastValueReceived;
    uint256 public lastAmountLD;
    bytes32 public lastTo;
    uint32  public lastDstEid;
    uint256 public sendCallCount;

    constructor(address _token, uint256 _quotedFee) {
        token = _token;
        quotedFee = _quotedFee;
    }
    function setQuotedFee(uint256 f) external { quotedFee = f; }

    function quoteSend(SendParam calldata, bool) external view returns (MessagingFee memory) {
        return MessagingFee({nativeFee: quotedFee, lzTokenFee: 0});
    }

    function send(SendParam calldata p, MessagingFee calldata f, address)
        external payable returns (MessagingReceipt memory, OFTReceipt memory)
    {
        // gateway must forward exactly lzFee as msg.value
        lastValueReceived = msg.value;
        require(msg.value == f.nativeFee, "MockOFT: value != nativeFee");
        // mimic debit: pull the approved tokens (lock/burn). Proves gateway approved correctly.
        IERC20(token).transferFrom(msg.sender, address(this), p.amountLD);
        lastAmountLD = p.amountLD;
        lastTo = p.to;
        lastDstEid = p.dstEid;
        sendCallCount++;
        return (
            MessagingReceipt({guid: keccak256(abi.encode(sendCallCount)), nonce: uint64(sendCallCount), fee: f}),
            OFTReceipt({amountSentLD: p.amountLD, amountReceivedLD: p.amountLD})
        );
    }
}

/// @notice Treasury that rejects native (to test "fee transfer failed" path).
contract RejectingTreasury {
    receive() external payable { revert("no native"); }
}

/// @notice Wrapper exposing MolePinLzOptions internal funcs for tests.
contract LzOptionsHarness {
    function lzReceive(uint128 gas, uint128 value) external pure returns (bytes memory) {
        return MolePinLzOptions.lzReceive(gas, value);
    }
    function lzReceiveNoValue(uint128 gas) external pure returns (bytes memory) {
        return MolePinLzOptions.lzReceive(gas);
    }
}
