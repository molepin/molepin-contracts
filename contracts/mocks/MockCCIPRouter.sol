// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal mock of the CCIP Router for local testing of the gateway.
///         Returns a fixed fee and a dummy messageId; does not move tokens cross-chain.
/// (KO: 게이트웨이 로컬 테스트용 CCIP Router mock. 고정 수수료 + 더미 messageId 반환.)
library Client {
    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }
    struct EVM2AnyMessage {
        bytes receiver;
        bytes data;
        EVMTokenAmount[] tokenAmounts;
        address feeToken;
        bytes extraArgs;
    }
}

contract MockCCIPRouter {
    uint256 public fixedFee;

    constructor(uint256 fixedFee_) {
        fixedFee = fixedFee_;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external view returns (uint256) {
        return fixedFee;
    }

    function ccipSend(uint64, Client.EVM2AnyMessage calldata) external payable returns (bytes32) {
        // Accept the native fee, return a dummy message id.
        return keccak256(abi.encodePacked(block.timestamp, msg.sender, msg.value));
    }

    function setFee(uint256 fixedFee_) external {
        fixedFee = fixedFee_;
    }
}
