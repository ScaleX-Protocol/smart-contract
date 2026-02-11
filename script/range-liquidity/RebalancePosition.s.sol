// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {RangeLiquidityManager} from "@scalexcore/RangeLiquidityManager.sol";
import {IRangeLiquidityManager} from "@scalexcore/interfaces/IRangeLiquidityManager.sol";

contract RebalancePosition is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(privateKey);

        address rangeLiquidityManagerAddr = vm.envAddress("RANGE_LIQUIDITY_MANAGER");
        uint256 positionId = vm.envUint("POSITION_ID");

        console.log("=== REBALANCING POSITION ===");
        console.log("Caller:", caller);
        console.log("RangeLiquidityManager:", rangeLiquidityManagerAddr);
        console.log("Position ID:", positionId);
        console.log("");

        RangeLiquidityManager rangeLiquidityManager = RangeLiquidityManager(rangeLiquidityManagerAddr);

        // Check if can rebalance
        (bool canReb, uint256 drift) = rangeLiquidityManager.canRebalance(positionId);
        console.log("Pre-Rebalance Status:");
        console.log("  Can Rebalance:", canReb);
        console.log("  Current Drift:", drift, "bps");
        console.log("");

        IRangeLiquidityManager.RangePosition memory positionBefore = rangeLiquidityManager.getPosition(positionId);
        console.log("Position Before Rebalance:");
        console.log("  Center Price:", positionBefore.centerPriceAtCreation);
        console.log("  Lower Price:", positionBefore.lowerPrice);
        console.log("  Upper Price:", positionBefore.upperPrice);
        console.log("  Rebalance Count:", positionBefore.rebalanceCount);
        console.log("");

        vm.startBroadcast(privateKey);

        // Rebalance
        console.log("Executing rebalance...");
        rangeLiquidityManager.rebalancePosition(positionId);
        console.log("[OK] Position rebalanced!");

        vm.stopBroadcast();

        // Get updated position
        IRangeLiquidityManager.RangePosition memory positionAfter = rangeLiquidityManager.getPosition(positionId);
        console.log("");
        console.log("Position After Rebalance:");
        console.log("  Center Price:", positionAfter.centerPriceAtCreation);
        console.log("  Lower Price:", positionAfter.lowerPrice);
        console.log("  Upper Price:", positionAfter.upperPrice);
        console.log("  Rebalance Count:", positionAfter.rebalanceCount);
        console.log("  Last Rebalanced:", positionAfter.lastRebalancedAt);

        console.log("");
        console.log("=== REBALANCE COMPLETE ===");
    }
}
