// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RangeLiquidityTestBase} from "./RangeLiquidityTestBase.t.sol";
import {IRangeLiquidityManager} from "@scalexcore/interfaces/IRangeLiquidityManager.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";

contract RangeLiquidityRebalanceTest is RangeLiquidityTestBase {
    function testRebalancingFlow() public {
        // Step 1: Create position
        vm.startPrank(liquidityProvider);
        uint256 positionId = _createDefaultPosition();

        IRangeLiquidityManager.RangePosition memory positionBefore = rangeLiquidityManager.getPosition(positionId);
        uint128 centerPriceBefore = positionBefore.centerPriceAtCreation;

        vm.stopPrank();

        // Step 2: Change oracle price to trigger rebalance threshold
        vm.startPrank(owner);
        IPoolManager.Pool memory pool = poolManager.getPool(poolManager.createPoolKey(wbtc, usdc));
        oracle.setPrice(address(pool.orderBook), 79_000e8); // +5.33% from 75k
        vm.stopPrank();

        // Step 3: Set authorized bot
        vm.startPrank(liquidityProvider);
        rangeLiquidityManager.setAuthorizedBot(positionId, bot);
        vm.stopPrank();

        // Step 4: Check if can rebalance
        (bool canRebalance, uint256 drift) = rangeLiquidityManager.canRebalance(positionId);
        assertTrue(canRebalance, "Should be able to rebalance");
        assertTrue(drift >= 500, "Drift should exceed threshold");

        // Step 5: Bot rebalances
        vm.startPrank(bot);
        rangeLiquidityManager.rebalancePosition(positionId);
        vm.stopPrank();

        // Step 6: Verify rebalance
        IRangeLiquidityManager.RangePosition memory positionAfter = rangeLiquidityManager.getPosition(positionId);

        assertTrue(positionAfter.centerPriceAtCreation != centerPriceBefore, "Center price should have changed");
        assertEq(positionAfter.rebalanceCount, 1, "Rebalance count should be 1");
        assertTrue(positionAfter.lastRebalancedAt > positionBefore.createdAt, "Last rebalanced time should be updated");

        assertTrue(positionAfter.buyOrderIds.length > 0, "Should have new buy orders");
        assertTrue(positionAfter.sellOrderIds.length > 0, "Should have new sell orders");
    }

    function testCannotRebalanceWithoutThreshold() public {
        vm.startPrank(liquidityProvider);
        uint256 positionId = _createDefaultPosition();
        rangeLiquidityManager.setAuthorizedBot(positionId, bot);
        vm.stopPrank();

        // Try to rebalance without price movement
        vm.startPrank(bot);

        (bool canRebalance,) = rangeLiquidityManager.canRebalance(positionId);
        assertFalse(canRebalance, "Should not be able to rebalance without drift");

        vm.expectRevert(); // Should revert with RebalanceThresholdNotMet
        rangeLiquidityManager.rebalancePosition(positionId);

        vm.stopPrank();
    }

    function testOwnerCanAlwaysRebalance() public {
        vm.startPrank(liquidityProvider);
        uint256 positionId = _createDefaultPosition();

        // Owner can rebalance without meeting threshold
        rangeLiquidityManager.rebalancePosition(positionId);

        IRangeLiquidityManager.RangePosition memory position = rangeLiquidityManager.getPosition(positionId);
        assertEq(position.rebalanceCount, 1, "Owner should be able to rebalance anytime");

        vm.stopPrank();
    }
}
