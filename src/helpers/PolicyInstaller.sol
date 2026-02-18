// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../ai-agents/AgentRouter.sol";
import "../ai-agents/PolicyFactory.sol";

/**
 * @title PolicyInstaller
 * @notice Helper contract to install a simple permissive policy for an agent
 */
contract PolicyInstaller {
    AgentRouter public immutable agentRouter;

    constructor(address _agentRouter) {
        agentRouter = AgentRouter(_agentRouter);
    }

    /**
     * @notice Install a permissive trading policy for an agent
     * @param agentId The strategy agent token ID
     */
    function installPermissivePolicy(uint256 agentId) external {
        address[] memory empty = new address[](0);

        PolicyFactory.Policy memory policy = PolicyFactory.Policy({
            // Metadata
            enabled: false,
            installedAt: 0,
            expiryTimestamp: 0,  // No expiry

            // Order Size
            maxOrderSize: 1000000e6,  // 1M max per order
            minOrderSize: 1e6,        // 1 minimum

            // Allowed Markets
            whitelistedTokens: empty,  // All tokens allowed
            blacklistedTokens: empty,  // No tokens blocked

            // Order Types
            allowMarketOrders: true,
            allowLimitOrders: true,

            // Operations
            allowSwap: true,
            allowBorrow: false,
            allowRepay: false,
            allowSupplyCollateral: false,
            allowWithdrawCollateral: false,
            allowPlaceLimitOrder: true,
            allowCancelOrder: true,

            // Buy/Sell Direction
            allowBuy: true,
            allowSell: true,

            // Auto-Borrow
            allowAutoBorrow: false,
            maxAutoBorrowAmount: 0,

            // Auto-Repay
            allowAutoRepay: false,
            minDebtToRepay: 0,

            // Safety
            minHealthFactor: 0,
            maxSlippageBps: 10000,  // 100% max slippage (no limit)
            minTimeBetweenTrades: 0,  // No cooldown
            emergencyRecipient: address(0),

            // Volume Limits - all disabled
            dailyVolumeLimit: 0,
            weeklyVolumeLimit: 0,

            // Drawdown Limits
            maxDailyDrawdown: 0,
            maxWeeklyDrawdown: 0,

            // Market Depth
            maxTradeVsTVLBps: 0,

            // Performance Requirements
            minWinRateBps: 0,
            minSharpeRatio: 0,

            // Position Management
            maxPositionConcentrationBps: 0,
            maxCorrelationBps: 0,

            // Trade Frequency
            maxTradesPerDay: 0,
            maxTradesPerHour: 0,

            // Trading Hours (UTC)
            tradingStartHour: 0,
            tradingEndHour: 23,

            // Reputation
            minReputationScore: 0,
            useReputationMultiplier: false,

            // Optimization Flag
            requiresChainlinkFunctions: false
        });

        agentRouter.authorize(agentId, policy);
    }
}
