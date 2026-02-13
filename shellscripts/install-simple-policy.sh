#!/bin/bash

# Install Simple Trading Policy
# Creates a permissive policy that allows all basic trading operations

source .env

POLICY_FACTORY="0x4605f626dF4A684139186B7fF15C8cABD8178EC8"
AGENT_ID="100"
PRIMARY_KEY="$PRIMARY_WALLET_KEY"

echo "Installing simple trading policy..."
echo ""

# We need to call installAgent with a full Policy struct
# This is complex, so let's use forge script instead

# Create a simple Solidity script to do this
cat > /tmp/InstallPolicy.s.sol << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PolicyFactory} from "src/ai-agents/PolicyFactory.sol";

contract InstallPolicy is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIMARY_WALLET_KEY");
        address policyFactory = 0x4605f626dF4A684139186B7fF15C8cABD8178EC8;
        uint256 agentId = 100;

        address[] memory empty = new address[](0);

        PolicyFactory.Policy memory policy = PolicyFactory.Policy({
            enabled: false,
            installedAt: 0,
            expiryTimestamp: 0,
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
            minHealthFactor: 0,
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

        vm.startBroadcast(privateKey);
        PolicyFactory(policyFactory).installAgent(agentId, policy);
        vm.stopBroadcast();

        console.log("Policy installed for agent", agentId);
    }
}
EOF

echo "Compiling and running policy installation..."
forge script /tmp/InstallPolicy.s.sol:InstallPolicy --rpc-url "$SCALEX_CORE_RPC" --broadcast --legacy

echo ""
echo "Policy installation complete!"
