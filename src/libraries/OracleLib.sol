// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Zhernovkov Maxim
 * @notice This library is used to check ChainLink oracle for stale data. If a price is stale,
 * the function will revert, and render the DSCEngine unusable - this is by design.
 * We want the DSCEngine to freeze, if prices become stale. So if the ChainLink network explodes
 * and you have a lot of money locked in the protocol ... too bad.
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60 = 10800 seconds - giving a feed a bit more than official heartbeat

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        // NOTE: We should probably ask feed for the heartbeat value but for our example here just hardcoded above
        uint256 secondsSince = block.timestamp - updatedAt;

        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
