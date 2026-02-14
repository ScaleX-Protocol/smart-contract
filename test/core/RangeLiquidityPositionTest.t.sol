// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RangeLiquidityTestBase} from "./RangeLiquidityTestBase.t.sol";
import {IRangeLiquidityManager} from "@scalexcore/interfaces/IRangeLiquidityManager.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {PoolKey} from "@scalexcore/libraries/Pool.sol";

contract RangeLiquidityPositionTest is RangeLiquidityTestBase {
    function testFullLiquidityProviderFlow() public {
        // Step 1: LP creates position
        vm.startPrank(liquidityProvider);

        uint256 positionId = _createDefaultPosition();

        IRangeLiquidityManager.RangePosition memory position = rangeLiquidityManager.getPosition(positionId);
        assertTrue(position.isActive, "Position should be active");
        assertTrue(position.buyOrderIds.length > 0, "Should have buy orders");
        assertTrue(position.sellOrderIds.length > 0, "Should have sell orders");

        vm.stopPrank();

        // Step 2: Verify orders are on orderbook
        IPoolManager.Pool memory pool = poolManager.getPool(poolManager.createPoolKey(wbtc, usdc));

        IOrderBook.PriceVolume memory bestBid = pool.orderBook.getBestPrice(IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestAsk = pool.orderBook.getBestPrice(IOrderBook.Side.SELL);

        assertTrue(bestBid.price > 0, "Should have buy orders on book");
        assertTrue(bestAsk.price > 0, "Should have sell orders on book");
        assertTrue(bestBid.volume > 0, "Buy orders should have volume");
        assertTrue(bestAsk.volume > 0, "Sell orders should have volume");

        // Step 3: Trader executes against LP's orders
        vm.startPrank(trader);
        router.placeMarketOrder(pool, 0.1e8, IOrderBook.Side.SELL, 0.1e8, 0);
        vm.stopPrank();

        // Step 4: Check position value after trade
        vm.startPrank(liquidityProvider);
        IRangeLiquidityManager.PositionValue memory value = rangeLiquidityManager.getPositionValue(positionId);
        assertTrue(value.totalValueInQuote > 0, "Position should have value");
        vm.stopPrank();
    }

    function testMultiplePositionsDifferentStrategies() public {
        vm.startPrank(owner);
        poolManager.createPool(wbtc, usdc, defaultTradingRules, 50); // 0.5% fee tier
        vm.stopPrank();

        vm.startPrank(liquidityProvider);

        // Position 1: Uniform strategy, 0.2% fee tier
        uint256 positionId1 = _createPosition(
            IRangeLiquidityManager.Strategy.UNIFORM,
            70_000e8, 80_000e8, 10, 50_000e6, false, 0
        );

        // Close first position to create another for same pool
        rangeLiquidityManager.closePosition(positionId1);

        // Position 2: Bid Heavy strategy
        uint256 positionId2 = _createPosition(
            IRangeLiquidityManager.Strategy.BID_HEAVY,
            72_000e8, 78_000e8, 8, 50_000e6, false, 0
        );

        IRangeLiquidityManager.RangePosition memory position2 = rangeLiquidityManager.getPosition(positionId2);
        assertEq(uint8(position2.strategy), uint8(IRangeLiquidityManager.Strategy.BID_HEAVY), "Should be BID_HEAVY");

        uint256[] memory userPositions = rangeLiquidityManager.getUserPositions(liquidityProvider);
        assertEq(userPositions.length, 2, "Should have 2 positions created");

        vm.stopPrank();
    }
}
