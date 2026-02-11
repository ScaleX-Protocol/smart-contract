// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {RangeLiquidityManager} from "@scalexcore/RangeLiquidityManager.sol";
import {IRangeLiquidityManager} from "@scalexcore/interfaces/IRangeLiquidityManager.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";

contract ViewPosition is Script {
    function run() external view {
        address rangeLiquidityManagerAddr = vm.envAddress("RANGE_LIQUIDITY_MANAGER");
        uint256 positionId = vm.envUint("POSITION_ID");

        console.log("=== VIEWING RANGE LIQUIDITY POSITION ===");
        console.log("RangeLiquidityManager:", rangeLiquidityManagerAddr);
        console.log("Position ID:", positionId);
        console.log("");

        RangeLiquidityManager rangeLiquidityManager = RangeLiquidityManager(rangeLiquidityManagerAddr);

        // Get position details
        IRangeLiquidityManager.RangePosition memory position = rangeLiquidityManager.getPosition(positionId);

        console.log("=== POSITION OVERVIEW ===");
        console.log("Owner:", position.owner);
        console.log("Active:", position.isActive);
        console.log("Position ID:", position.positionId);
        console.log("");

        console.log("=== CONFIGURATION ===");
        console.log("Strategy:", _strategyToString(position.strategy));
        console.log("Tick Count:", position.tickCount);
        console.log("Auto-Rebalance Enabled:", position.autoRebalanceEnabled);
        console.log("Rebalance Threshold:", position.rebalanceThresholdBps, "bps");
        console.log("Authorized Bot:", position.authorizedBot);
        console.log("");

        console.log("=== PRICE RANGE ===");
        console.log("Lower Price:", position.lowerPrice);
        console.log("Upper Price:", position.upperPrice);
        console.log("Center Price (at creation):", position.centerPriceAtCreation);
        console.log("");

        console.log("=== CAPITAL ===");
        console.log("Initial Deposit Amount:", position.initialDepositAmount);
        console.log("Initial Deposit Currency:", address(uint160(uint256(keccak256(abi.encode(position.initialDepositCurrency))))));
        console.log("");

        console.log("=== ORDERS ===");
        console.log("Buy Orders:", position.buyOrderIds.length);
        console.log("Sell Orders:", position.sellOrderIds.length);
        console.log("Total Orders:", position.buyOrderIds.length + position.sellOrderIds.length);
        console.log("");

        // List buy orders
        console.log("Buy Order IDs:");
        for (uint i = 0; i < position.buyOrderIds.length; i++) {
            if (position.buyOrderIds[i] != 0) {
                console.log("  [", i, "]", position.buyOrderIds[i]);
            }
        }
        console.log("");

        // List sell orders
        console.log("Sell Order IDs:");
        for (uint i = 0; i < position.sellOrderIds.length; i++) {
            if (position.sellOrderIds[i] != 0) {
                console.log("  [", i, "]", position.sellOrderIds[i]);
            }
        }
        console.log("");

        console.log("=== TIMESTAMPS ===");
        console.log("Created At:", position.createdAt, "(", _timestampToDate(position.createdAt), ")");
        console.log("Last Rebalanced:", position.lastRebalancedAt, "(", _timestampToDate(position.lastRebalancedAt), ")");
        console.log("Rebalance Count:", position.rebalanceCount);
        console.log("");

        // Get position value
        IRangeLiquidityManager.PositionValue memory value = rangeLiquidityManager.getPositionValue(positionId);

        console.log("=== CURRENT VALUE ===");
        console.log("Total Value (Quote):", value.totalValueInQuote);
        console.log("Base Amount:", value.baseAmount);
        console.log("Quote Amount:", value.quoteAmount);
        console.log("Locked in Orders:", value.lockedInOrders);
        console.log("Free Balance:", value.freeBalance);
        console.log("");

        // Check rebalance status
        (bool canReb, uint256 drift) = rangeLiquidityManager.canRebalance(positionId);

        console.log("=== REBALANCE STATUS ===");
        console.log("Can Rebalance:", canReb);
        console.log("Current Price Drift:", drift, "bps (", _bpsToPercent(drift), "%)");
        console.log("Threshold:", position.rebalanceThresholdBps, "bps (", _bpsToPercent(position.rebalanceThresholdBps), "%)");

        if (canReb) {
            console.log("");
            console.log("[!] Position is ready for rebalancing");
        } else if (position.autoRebalanceEnabled) {
            uint256 remaining = position.rebalanceThresholdBps > drift ? position.rebalanceThresholdBps - drift : 0;
            console.log("Drift needed for rebalance:", remaining, "bps (", _bpsToPercent(remaining), "%)");
        }

        console.log("");
        console.log("=== VIEW COMPLETE ===");
    }

    function _strategyToString(IRangeLiquidityManager.Strategy strategy) internal pure returns (string memory) {
        if (strategy == IRangeLiquidityManager.Strategy.UNIFORM) return "UNIFORM (50/50)";
        if (strategy == IRangeLiquidityManager.Strategy.BID_HEAVY) return "BID_HEAVY (70/30)";
        if (strategy == IRangeLiquidityManager.Strategy.ASK_HEAVY) return "ASK_HEAVY (30/70)";
        return "UNKNOWN";
    }

    function _timestampToDate(uint48 timestamp) internal pure returns (string memory) {
        if (timestamp == 0) return "Never";
        // Simple conversion - just return the timestamp
        return vm.toString(timestamp);
    }

    function _bpsToPercent(uint256 bps) internal pure returns (string memory) {
        uint256 percent = bps / 100;
        uint256 decimal = bps % 100;
        return string(abi.encodePacked(vm.toString(percent), ".", vm.toString(decimal)));
    }
}
