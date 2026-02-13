// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IRangeLiquidityManager} from "../interfaces/IRangeLiquidityManager.sol";
import {Currency} from "./Currency.sol";

library RangeLiquidityDistribution {
    error InvalidDistribution();

    struct DistributionResult {
        uint128[] buyAmounts;    // Amount in quote currency for each buy order
        uint128[] sellAmounts;   // Amount in base currency for each sell order
        uint256 totalBuyBudget;
        uint256 totalSellBudget;
    }

    /// @notice Calculate tick prices using tick spacing (similar to Uniswap v3)
    /// @param lowerPrice Lower bound price
    /// @param upperPrice Upper bound price
    /// @param tickCount Number of ticks
    /// @param tickSpacing Spacing between ticks (50 or 200)
    function calculateTickPrices(
        uint128 lowerPrice,
        uint128 upperPrice,
        uint16 tickCount,
        uint16 tickSpacing
    ) internal pure returns (uint128[] memory) {
        uint128[] memory ticks = new uint128[](tickCount);

        // Calculate price range per tick using tick spacing
        // tickSpacing determines the granularity of price levels
        uint128 priceRange = upperPrice - lowerPrice;
        uint128 step = priceRange / tickCount;

        // Ensure step is aligned to tick spacing for consistency
        // This creates evenly distributed ticks within the range
        uint128 alignedStep = (step / tickSpacing) * tickSpacing;
        if (alignedStep == 0) alignedStep = tickSpacing;

        for (uint16 i = 0; i < tickCount; i++) {
            uint128 tickPrice = lowerPrice + (alignedStep * (i + 1));
            // Ensure we don't exceed upper price
            if (tickPrice > upperPrice) tickPrice = upperPrice;
            ticks[i] = tickPrice;
        }

        return ticks;
    }

    /// @notice Calculate tick prices evenly distributed across range (legacy - backward compatibility)
    function calculateTickPrices(
        uint128 lowerPrice,
        uint128 upperPrice,
        uint16 tickCount
    ) internal pure returns (uint128[] memory) {
        // Default to tick spacing of 50 for backward compatibility
        return calculateTickPrices(lowerPrice, upperPrice, tickCount, 50);
    }

    /// @notice Calculate distribution based on strategy
    function calculateDistribution(
        IRangeLiquidityManager.Strategy strategy,
        uint256 totalAmount,
        uint128[] memory tickPrices,
        uint128 currentPrice,
        Currency depositCurrency,
        bool isBaseCurrency
    ) internal pure returns (DistributionResult memory result) {
        // Determine budget split based on strategy
        uint256 buyBudget;
        uint256 sellBudget;

        if (strategy == IRangeLiquidityManager.Strategy.UNIFORM) {
            buyBudget = totalAmount / 2;
            sellBudget = totalAmount / 2;
        } else if (strategy == IRangeLiquidityManager.Strategy.BID_HEAVY) {
            buyBudget = (totalAmount * 70) / 100;
            sellBudget = (totalAmount * 30) / 100;
        } else if (strategy == IRangeLiquidityManager.Strategy.ASK_HEAVY) {
            buyBudget = (totalAmount * 30) / 100;
            sellBudget = (totalAmount * 70) / 100;
        } else {
            revert InvalidDistribution();
        }

        result.totalBuyBudget = buyBudget;
        result.totalSellBudget = sellBudget;

        // Count ticks on each side of current price
        uint256 buyTickCount = 0;
        uint256 sellTickCount = 0;

        for (uint256 i = 0; i < tickPrices.length; i++) {
            if (tickPrices[i] < currentPrice) {
                buyTickCount++;
            } else if (tickPrices[i] > currentPrice) {
                sellTickCount++;
            }
        }

        // Initialize arrays
        result.buyAmounts = new uint128[](tickPrices.length);
        result.sellAmounts = new uint128[](tickPrices.length);

        // Distribute amounts uniformly within each side
        uint256 buyAmountPerTick = buyTickCount > 0 ? buyBudget / buyTickCount : 0;
        uint256 sellAmountPerTick = sellTickCount > 0 ? sellBudget / sellTickCount : 0;

        for (uint256 i = 0; i < tickPrices.length; i++) {
            if (tickPrices[i] < currentPrice && buyAmountPerTick > 0) {
                // Buy order - amount in quote currency
                result.buyAmounts[i] = uint128(buyAmountPerTick);
            } else if (tickPrices[i] > currentPrice && sellAmountPerTick > 0) {
                // Sell order - amount in base currency
                // Need to convert from quote to base if deposited in quote
                if (isBaseCurrency) {
                    result.sellAmounts[i] = uint128(sellAmountPerTick);
                } else {
                    // Convert quote amount to base amount at this tick price
                    uint256 baseAmount = (sellAmountPerTick * 1e8) / tickPrices[i];
                    result.sellAmounts[i] = uint128(baseAmount);
                }
            }
        }

        return result;
    }

    /// @notice Calculate price drift in basis points
    function calculatePriceDrift(
        uint128 oldPrice,
        uint128 newPrice
    ) internal pure returns (uint256 driftBps) {
        if (oldPrice == 0) return 0;

        uint256 diff;
        if (newPrice > oldPrice) {
            diff = newPrice - oldPrice;
        } else {
            diff = oldPrice - newPrice;
        }

        // drift = (diff / oldPrice) * 10000
        driftBps = (diff * 10000) / oldPrice;
    }

    /// @notice Calculate new price range centered around current price
    function calculateNewRange(
        uint128 oldLowerPrice,
        uint128 oldUpperPrice,
        uint128 currentPrice
    ) internal pure returns (uint128 newLowerPrice, uint128 newUpperPrice) {
        uint128 rangeSize = oldUpperPrice - oldLowerPrice;
        uint128 halfRange = rangeSize / 2;

        // Center around current price
        if (currentPrice > halfRange) {
            newLowerPrice = currentPrice - halfRange;
            newUpperPrice = currentPrice + halfRange;
        } else {
            // Price too low, start from 0
            newLowerPrice = 0;
            newUpperPrice = rangeSize;
        }
    }

    /// @notice Convert base amount to quote value
    function convertToQuoteValue(
        uint256 baseAmount,
        uint256 quoteAmount,
        uint128 currentPrice,
        uint8 baseDecimals
    ) internal pure returns (uint256 totalQuoteValue) {
        // Convert base to quote: (baseAmount * price) / 10^baseDecimals
        uint256 baseInQuote = (baseAmount * currentPrice) / (10 ** baseDecimals);
        totalQuoteValue = baseInQuote + quoteAmount;
    }
}
