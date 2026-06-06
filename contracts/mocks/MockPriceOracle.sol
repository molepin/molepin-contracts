// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal mock of a Chainlink AggregatorV3 feed for local testing.
///         Supports overriding updatedAt to test the gateway's staleness check.
/// (KO: 로컬 테스트용 Chainlink AggregatorV3 mock. staleness 테스트 위해
///  updatedAt override 지원.)
contract MockPriceOracle {
    uint8 private immutable _decimals;
    int256 private _answer;
    uint256 private _updatedAtOverride; // 0 = use block.timestamp

    constructor(uint8 decimals_, int256 answer_) {
        _decimals = decimals_;
        _answer = answer_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        uint256 ts = _updatedAtOverride == 0 ? block.timestamp : _updatedAtOverride;
        return (1, _answer, ts, ts, 1);
    }

    function setAnswer(int256 answer_) external {
        _answer = answer_;
    }

    /// @notice Set a fixed updatedAt to simulate a stale feed (0 = live timestamp).
    /// (KO: 오래된 피드 시뮬레이션용 고정 updatedAt 설정.)
    function setUpdatedAt(uint256 ts) external {
        _updatedAtOverride = ts;
    }
}
