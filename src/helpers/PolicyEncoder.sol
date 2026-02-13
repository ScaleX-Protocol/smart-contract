// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../ai-agents/PolicyFactory.sol";

/**
 * @title PolicyEncoder
 * @notice Helper to encode policy installation calldata
 */
contract PolicyEncoder {
    /**
     * @notice Get the encoded calldata for installing a permissive policy
     * @param agentId The agent token ID
     * @return The encoded calldata for PolicyFactory.installAgent()
     */
    function getInstallPolicyCalldata(uint256 agentId) external pure returns (bytes memory) {
        address[] memory empty = new address[](0);

        PolicyFactory.Policy memory policy = PolicyFactory.Policy({
            enabled: false,
            installedAt: 0,
            expiryTimestamp: type(uint256).max, // Never expires
            agentTokenId: agentId,
            maxOrderSize: 1000000e6,
            minOrderSize: 1e6,
            whitelistedTokens: empty,
            blacklistedTokens: empty,
            allowMarketOrders: true,
            allowLimitOrders: true,
            allowSwap: true,
            allowBorrow: false,
            allowRepay: false,
            allowSupplyCollateral: false,
            allowWithdrawCollateral: false,
            allowPlaceLimitOrder: true,
            allowCancelOrder: true,
            allowBuy: true,
            allowSell: true,
            allowAutoBorrow: false,
            maxAutoBorrowAmount: 0,
            allowAutoRepay: false,
            minDebtToRepay: 0,
            minHealthFactor: 1e18,  // 100% minimum
            maxSlippageBps: 10000,
            minTimeBetweenTrades: 0,
            emergencyRecipient: address(0),
            dailyVolumeLimit: 0,
            weeklyVolumeLimit: 0,
            maxDailyDrawdown: 0,
            maxWeeklyDrawdown: 0,
            maxTradeVsTVLBps: 0,
            minWinRateBps: 0,
            minSharpeRatio: 0,
            maxPositionConcentrationBps: 0,
            maxCorrelationBps: 0,
            maxTradesPerDay: 0,
            maxTradesPerHour: 0,
            tradingStartHour: 0,
            tradingEndHour: 23,
            minReputationScore: 0,
            useReputationMultiplier: false,
            requiresChainlinkFunctions: false
        });

        return abi.encodeCall(PolicyFactory.installAgent, (agentId, policy));
    }
}
