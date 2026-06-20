// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract MockChainlinkFeed {
    int256 private s_price;
    uint8 private s_decimals;
    uint256 private s_updatedAt;

    constructor(int256 initialPrice, uint8 decimals_) {
        s_price = initialPrice;
        s_decimals = decimals_;
        s_updatedAt = block.timestamp;
    }

    function setPrice(int256 price) external {
        s_price = price;
    }

    function setUpdatedAt(uint256 updatedAt) external {
        s_updatedAt = updatedAt;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, s_price, block.timestamp, s_updatedAt, 1);
    }

    function decimals() external view returns (uint8) {
        return s_decimals;
    }
}
