// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {RangeLiquidityDistribution} from "@scalexcore/libraries/RangeLiquidityDistribution.sol";
import {IRangeLiquidityManager} from "@scalexcore/interfaces/IRangeLiquidityManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";

/// @notice Wrapper to expose internal library functions for testing
contract DistributionHarness {
    function calculateTickPrices(
        uint128 lowerPrice,
        uint128 upperPrice,
        uint16 tickCount,
        uint16 tickSpacing
    ) external pure returns (uint128[] memory) {
        return RangeLiquidityDistribution.calculateTickPrices(lowerPrice, upperPrice, tickCount, tickSpacing);
    }

    function calculateTickPricesLegacy(
        uint128 lowerPrice,
        uint128 upperPrice,
        uint16 tickCount
    ) external pure returns (uint128[] memory) {
        return RangeLiquidityDistribution.calculateTickPrices(lowerPrice, upperPrice, tickCount);
    }

    function calculateDistribution(
        IRangeLiquidityManager.Strategy strategy,
        uint256 totalAmount,
        uint128[] memory tickPrices,
        uint128 currentPrice,
        Currency depositCurrency,
        bool isBaseCurrency
    ) external pure returns (RangeLiquidityDistribution.DistributionResult memory) {
        return RangeLiquidityDistribution.calculateDistribution(
            strategy, totalAmount, tickPrices, currentPrice, depositCurrency, isBaseCurrency
        );
    }

    function calculatePriceDrift(
        uint128 oldPrice,
        uint128 newPrice
    ) external pure returns (uint256) {
        return RangeLiquidityDistribution.calculatePriceDrift(oldPrice, newPrice);
    }

    function calculateNewRange(
        uint128 oldLowerPrice,
        uint128 oldUpperPrice,
        uint128 currentPrice
    ) external pure returns (uint128 newLowerPrice, uint128 newUpperPrice) {
        return RangeLiquidityDistribution.calculateNewRange(oldLowerPrice, oldUpperPrice, currentPrice);
    }

    function convertToQuoteValue(
        uint256 baseAmount,
        uint256 quoteAmount,
        uint128 currentPrice,
        uint8 baseDecimals
    ) external pure returns (uint256) {
        return RangeLiquidityDistribution.convertToQuoteValue(baseAmount, quoteAmount, currentPrice, baseDecimals);
    }
}

contract RangeLiquidityDistributionTest is Test {
    DistributionHarness private harness;
    Currency private dummyCurrency;

    function setUp() public {
        harness = new DistributionHarness();
        dummyCurrency = Currency.wrap(address(0x1));
    }

    // ========== calculateTickPrices ==========

    function test_calculateTickPrices_basicWithSpacing50() public view {
        // Range: 1000 to 2000, 5 ticks, spacing 50
        uint128[] memory ticks = harness.calculateTickPrices(1000, 2000, 5, 50);
        assertEq(ticks.length, 5);

        // Step = (2000 - 1000) / 5 = 200
        // Aligned step = (200 / 50) * 50 = 200
        // Ticks: 1200, 1400, 1600, 1800, 2000
        assertEq(ticks[0], 1200);
        assertEq(ticks[1], 1400);
        assertEq(ticks[2], 1600);
        assertEq(ticks[3], 1800);
        assertEq(ticks[4], 2000);
    }

    function test_calculateTickPrices_withSpacing200() public view {
        // Range: 1000 to 3000, 4 ticks, spacing 200
        uint128[] memory ticks = harness.calculateTickPrices(1000, 3000, 4, 200);
        assertEq(ticks.length, 4);

        // Step = 2000 / 4 = 500, aligned = (500/200)*200 = 400
        // Ticks: 1400, 1800, 2200, 2600
        assertEq(ticks[0], 1400);
        assertEq(ticks[1], 1800);
        assertEq(ticks[2], 2200);
        assertEq(ticks[3], 2600);
    }

    function test_calculateTickPrices_smallRange_clampsToMinSpacing() public view {
        // Range: 100 to 200, 10 ticks, spacing 50
        // Step = 100/10 = 10, aligned = (10/50)*50 = 0 -> clamped to 50
        uint128[] memory ticks = harness.calculateTickPrices(100, 200, 10, 50);
        assertEq(ticks.length, 10);

        assertEq(ticks[0], 150);
        assertEq(ticks[1], 200);
        // Remaining ticks clamped to upper price
        for (uint256 i = 2; i < 10; i++) {
            assertEq(ticks[i], 200);
        }
    }

    function test_calculateTickPrices_singleTick() public view {
        uint128[] memory ticks = harness.calculateTickPrices(1000, 2000, 1, 50);
        assertEq(ticks.length, 1);
        assertEq(ticks[0], 2000);
    }

    function test_calculateTickPricesLegacy_defaultsToSpacing50() public view {
        uint128[] memory ticksLegacy = harness.calculateTickPricesLegacy(1000, 2000, 5);
        uint128[] memory ticksExplicit = harness.calculateTickPrices(1000, 2000, 5, 50);

        assertEq(ticksLegacy.length, ticksExplicit.length);
        for (uint256 i = 0; i < ticksLegacy.length; i++) {
            assertEq(ticksLegacy[i], ticksExplicit[i]);
        }
    }

    function test_calculateTickPrices_neverExceedUpperPrice() public view {
        uint128[] memory ticks = harness.calculateTickPrices(100, 300, 20, 50);
        for (uint256 i = 0; i < ticks.length; i++) {
            assertLe(ticks[i], 300);
        }
    }

    // ========== calculateDistribution ==========

    function test_calculateDistribution_uniform() public view {
        uint128[] memory tickPrices = new uint128[](5);
        tickPrices[0] = 900;
        tickPrices[1] = 950;
        tickPrices[2] = 1000; // at current price
        tickPrices[3] = 1050;
        tickPrices[4] = 1100;

        RangeLiquidityDistribution.DistributionResult memory result =
            harness.calculateDistribution(
                IRangeLiquidityManager.Strategy.UNIFORM,
                10000,
                tickPrices,
                1000,
                dummyCurrency,
                false
            );

        // UNIFORM: 50/50
        assertEq(result.totalBuyBudget, 5000);
        assertEq(result.totalSellBudget, 5000);

        // 2 buy ticks: 5000/2 = 2500 each
        assertEq(result.buyAmounts[0], 2500);
        assertEq(result.buyAmounts[1], 2500);
        assertEq(result.buyAmounts[2], 0); // at current price

        // 2 sell ticks: converted from quote to base
        assertEq(result.sellAmounts[3], uint128((uint256(2500) * 1e8) / 1050));
        assertEq(result.sellAmounts[4], uint128((uint256(2500) * 1e8) / 1100));
    }

    function test_calculateDistribution_bidHeavy() public view {
        uint128[] memory tickPrices = new uint128[](4);
        tickPrices[0] = 900;
        tickPrices[1] = 950;
        tickPrices[2] = 1050;
        tickPrices[3] = 1100;

        RangeLiquidityDistribution.DistributionResult memory result =
            harness.calculateDistribution(
                IRangeLiquidityManager.Strategy.BID_HEAVY,
                10000,
                tickPrices,
                1000,
                dummyCurrency,
                false
            );

        // BID_HEAVY: 70% buy / 30% sell
        assertEq(result.totalBuyBudget, 7000);
        assertEq(result.totalSellBudget, 3000);

        // 2 buy ticks: 7000/2 = 3500
        assertEq(result.buyAmounts[0], 3500);
        assertEq(result.buyAmounts[1], 3500);
    }

    function test_calculateDistribution_askHeavy() public view {
        uint128[] memory tickPrices = new uint128[](4);
        tickPrices[0] = 900;
        tickPrices[1] = 950;
        tickPrices[2] = 1050;
        tickPrices[3] = 1100;

        RangeLiquidityDistribution.DistributionResult memory result =
            harness.calculateDistribution(
                IRangeLiquidityManager.Strategy.ASK_HEAVY,
                10000,
                tickPrices,
                1000,
                dummyCurrency,
                false
            );

        // ASK_HEAVY: 30% buy / 70% sell
        assertEq(result.totalBuyBudget, 3000);
        assertEq(result.totalSellBudget, 7000);

        assertEq(result.buyAmounts[0], 1500);
        assertEq(result.buyAmounts[1], 1500);
    }

    function test_calculateDistribution_baseCurrencyDeposit_noConversion() public view {
        uint128[] memory tickPrices = new uint128[](2);
        tickPrices[0] = 900;
        tickPrices[1] = 1100;

        RangeLiquidityDistribution.DistributionResult memory result =
            harness.calculateDistribution(
                IRangeLiquidityManager.Strategy.UNIFORM,
                10000,
                tickPrices,
                1000,
                dummyCurrency,
                true // base currency
            );

        // isBaseCurrency=true -> sell amounts stay as-is (no conversion)
        assertEq(result.sellAmounts[1], 5000);
    }

    function test_calculateDistribution_allTicksBelowPrice() public view {
        uint128[] memory tickPrices = new uint128[](3);
        tickPrices[0] = 800;
        tickPrices[1] = 900;
        tickPrices[2] = 950;

        RangeLiquidityDistribution.DistributionResult memory result =
            harness.calculateDistribution(
                IRangeLiquidityManager.Strategy.UNIFORM,
                9000,
                tickPrices,
                1000,
                dummyCurrency,
                false
            );

        // All buy side, 3 ticks -> 4500/3 = 1500 each
        assertEq(result.buyAmounts[0], 1500);
        assertEq(result.buyAmounts[1], 1500);
        assertEq(result.buyAmounts[2], 1500);
        assertEq(result.sellAmounts[0], 0);
        assertEq(result.sellAmounts[1], 0);
        assertEq(result.sellAmounts[2], 0);
    }

    function test_calculateDistribution_allTicksAbovePrice() public view {
        uint128[] memory tickPrices = new uint128[](3);
        tickPrices[0] = 1050;
        tickPrices[1] = 1100;
        tickPrices[2] = 1200;

        RangeLiquidityDistribution.DistributionResult memory result =
            harness.calculateDistribution(
                IRangeLiquidityManager.Strategy.UNIFORM,
                9000,
                tickPrices,
                1000,
                dummyCurrency,
                false
            );

        // All sell side
        assertEq(result.buyAmounts[0], 0);
        assertEq(result.buyAmounts[1], 0);
        assertEq(result.buyAmounts[2], 0);
        assertGt(result.sellAmounts[0], 0);
        assertGt(result.sellAmounts[1], 0);
        assertGt(result.sellAmounts[2], 0);
    }

    // ========== calculatePriceDrift ==========

    function test_calculatePriceDrift_noDrift() public view {
        assertEq(harness.calculatePriceDrift(1000, 1000), 0);
    }

    function test_calculatePriceDrift_upward10percent() public view {
        assertEq(harness.calculatePriceDrift(1000, 1100), 1000);
    }

    function test_calculatePriceDrift_downward10percent() public view {
        assertEq(harness.calculatePriceDrift(1000, 900), 1000);
    }

    function test_calculatePriceDrift_small1percent() public view {
        assertEq(harness.calculatePriceDrift(1000, 1010), 100);
    }

    function test_calculatePriceDrift_zeroOldPrice() public view {
        assertEq(harness.calculatePriceDrift(0, 1000), 0);
    }

    function test_calculatePriceDrift_symmetry() public view {
        uint256 driftUp = harness.calculatePriceDrift(1000, 1050);
        uint256 driftDown = harness.calculatePriceDrift(1000, 950);
        assertEq(driftUp, driftDown);
    }

    function test_calculatePriceDrift_50percent() public view {
        assertEq(harness.calculatePriceDrift(1000, 1500), 5000);
    }

    // ========== calculateNewRange ==========

    function test_calculateNewRange_centerAtNewPrice() public view {
        (uint128 newLower, uint128 newUpper) = harness.calculateNewRange(900, 1100, 1200);
        assertEq(newLower, 1100);
        assertEq(newUpper, 1300);
    }

    function test_calculateNewRange_priceDropped() public view {
        (uint128 newLower, uint128 newUpper) = harness.calculateNewRange(900, 1100, 800);
        assertEq(newLower, 700);
        assertEq(newUpper, 900);
    }

    function test_calculateNewRange_priceTooLow() public view {
        (uint128 newLower, uint128 newUpper) = harness.calculateNewRange(900, 1100, 50);
        assertEq(newLower, 0);
        assertEq(newUpper, 200);
    }

    function test_calculateNewRange_preservesRangeSize() public view {
        (uint128 newLower, uint128 newUpper) = harness.calculateNewRange(1000, 2000, 1800);
        assertEq(newUpper - newLower, 1000);
    }

    function test_calculateNewRange_sameCenterPrice() public view {
        (uint128 newLower, uint128 newUpper) = harness.calculateNewRange(900, 1100, 1000);
        assertEq(newLower, 900);
        assertEq(newUpper, 1100);
    }

    // ========== convertToQuoteValue ==========

    function test_convertToQuoteValue_18decimals() public view {
        // 1 ETH at 2000 USDC + 500 USDC
        uint256 total = harness.convertToQuoteValue(1e18, 500e6, 2000e6, 18);
        assertEq(total, 2500e6);
    }

    function test_convertToQuoteValue_zeroBase() public view {
        uint256 total = harness.convertToQuoteValue(0, 1000e6, 2000e6, 18);
        assertEq(total, 1000e6);
    }

    function test_convertToQuoteValue_zeroQuote() public view {
        uint256 total = harness.convertToQuoteValue(2e18, 0, 1500e6, 18);
        assertEq(total, 3000e6);
    }

    function test_convertToQuoteValue_8decimals() public view {
        uint256 total = harness.convertToQuoteValue(1e8, 0, 50000e6, 8);
        assertEq(total, 50000e6);
    }

    function test_convertToQuoteValue_bothZero() public view {
        uint256 total = harness.convertToQuoteValue(0, 0, 2000e6, 18);
        assertEq(total, 0);
    }
}
