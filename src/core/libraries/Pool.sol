// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "./Currency.sol";

struct PoolKey {
    Currency baseCurrency;
    Currency quoteCurrency;
    uint24 feeTier;  // Fee tier in basis points (e.g., 20 = 0.2%, 50 = 0.5%)
}

type PoolId is bytes32;

library PoolIdLibrary {
    // Fee tier constants (in basis points, 1 bp = 0.01%)
    uint24 public constant FEE_TIER_LOW = 20;      // 0.2%
    uint24 public constant FEE_TIER_MEDIUM = 50;   // 0.5%

    // Tick spacing constants
    uint16 public constant TICK_SPACING_LOW = 50;     // For 0.2% fee tier
    uint16 public constant TICK_SPACING_MEDIUM = 200; // For 0.5% fee tier

    function toId(
        PoolKey memory poolKey
    ) internal pure returns (PoolId poolId) {
        assembly {
            poolId := keccak256(poolKey, 0x60)  // Updated to include feeTier (3 words: 0x40 + 0x20)
        }
    }

    /// @notice Get tick spacing for a given fee tier
    function getTickSpacing(uint24 feeTier) internal pure returns (uint16) {
        if (feeTier == FEE_TIER_LOW) {
            return TICK_SPACING_LOW;
        } else if (feeTier == FEE_TIER_MEDIUM) {
            return TICK_SPACING_MEDIUM;
        }
        revert("Invalid fee tier");
    }

    function baseToQuote(
        uint256 baseAmount,
        uint256 price,
        uint8 baseDecimals
    ) internal pure returns (uint256 quoteAmount) {
        assembly ("memory-safe") {
            quoteAmount := div(mul(baseAmount, price), exp(10, baseDecimals))
        }
    }

    function quoteToBase(
        uint256 quoteAmount,
        uint256 price,
        uint8 quoteDecimals
    ) internal pure returns (uint256 baseAmount) {
        assembly ("memory-safe") {
            baseAmount := div(mul(quoteAmount, exp(10, quoteDecimals)), price)
        }
    }
}

using PoolIdLibrary for PoolKey global;
