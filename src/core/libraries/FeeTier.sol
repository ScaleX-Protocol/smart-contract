// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title FeeTier
/// @notice Library for managing fee tiers similar to Uniswap v3 CLMM
library FeeTier {
    /// @notice Fee tier constants (in basis points, 1 bp = 0.01%)
    uint24 public constant FEE_TIER_LOW = 20;      // 0.2%
    uint24 public constant FEE_TIER_MEDIUM = 50;   // 0.5%

    /// @notice Tick spacing constants
    uint16 public constant TICK_SPACING_LOW = 50;     // For 0.2% fee tier
    uint16 public constant TICK_SPACING_MEDIUM = 200; // For 0.5% fee tier

    error InvalidFeeTier(uint24 feeTier);
    error InvalidTickSpacing(uint16 tickSpacing);

    /// @notice Validate fee tier
    /// @param feeTier Fee tier to validate
    /// @return valid True if fee tier is valid
    function isValidFeeTier(uint24 feeTier) internal pure returns (bool valid) {
        return feeTier == FEE_TIER_LOW || feeTier == FEE_TIER_MEDIUM;
    }

    /// @notice Validate tick spacing
    /// @param tickSpacing Tick spacing to validate
    /// @return valid True if tick spacing is valid
    function isValidTickSpacing(uint16 tickSpacing) internal pure returns (bool valid) {
        return tickSpacing == TICK_SPACING_LOW || tickSpacing == TICK_SPACING_MEDIUM;
    }

    /// @notice Get tick spacing for a given fee tier
    /// @param feeTier Fee tier
    /// @return tickSpacing Corresponding tick spacing
    function getTickSpacingForFeeTier(uint24 feeTier) internal pure returns (uint16 tickSpacing) {
        if (feeTier == FEE_TIER_LOW) {
            return TICK_SPACING_LOW;
        } else if (feeTier == FEE_TIER_MEDIUM) {
            return TICK_SPACING_MEDIUM;
        }
        revert InvalidFeeTier(feeTier);
    }

    /// @notice Get fee tier for a given tick spacing
    /// @param tickSpacing Tick spacing
    /// @return feeTier Corresponding fee tier
    function getFeeTierForTickSpacing(uint16 tickSpacing) internal pure returns (uint24 feeTier) {
        if (tickSpacing == TICK_SPACING_LOW) {
            return FEE_TIER_LOW;
        } else if (tickSpacing == TICK_SPACING_MEDIUM) {
            return FEE_TIER_MEDIUM;
        }
        revert InvalidTickSpacing(tickSpacing);
    }

    /// @notice Calculate LP fee from total fee tier
    /// @param feeTier Total fee tier in basis points
    /// @param protocolFeeBps Protocol fee in basis points
    /// @return lpFeeBps LP fee in basis points
    function calculateLPFee(uint24 feeTier, uint16 protocolFeeBps) internal pure returns (uint24 lpFeeBps) {
        // LP gets the spread between fee tier and protocol fee
        // Example: 0.5% fee tier - 0.1% protocol fee = 0.4% for LP
        if (protocolFeeBps >= feeTier) {
            return 0;
        }
        return feeTier - protocolFeeBps;
    }

    /// @notice Calculate fee amount
    /// @param amount Transaction amount
    /// @param feeTierBps Fee tier in basis points
    /// @return feeAmount Fee amount
    function calculateFee(uint256 amount, uint24 feeTierBps) internal pure returns (uint256 feeAmount) {
        // Fee = amount * feeTierBps / 10000
        return (amount * feeTierBps) / 10000;
    }

    /// @notice Split fee between protocol and LP
    /// @param totalFee Total fee collected
    /// @param feeTier Fee tier
    /// @param protocolFeeBps Protocol fee in basis points
    /// @return protocolFee Fee for protocol
    /// @return lpFee Fee for LP
    function splitFee(
        uint256 totalFee,
        uint24 feeTier,
        uint16 protocolFeeBps
    ) internal pure returns (uint256 protocolFee, uint256 lpFee) {
        // Calculate protocol fee portion
        protocolFee = (totalFee * protocolFeeBps) / feeTier;
        // Remaining goes to LP
        lpFee = totalFee - protocolFee;
    }
}
