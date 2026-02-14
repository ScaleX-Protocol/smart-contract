// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeTier} from "@scalexcore/libraries/FeeTier.sol";

/// @notice Wrapper to expose internal library functions for testing
contract FeeTierHarness {
    function isValidFeeTier(uint24 feeTier) external pure returns (bool) {
        return FeeTier.isValidFeeTier(feeTier);
    }

    function isValidTickSpacing(uint16 tickSpacing) external pure returns (bool) {
        return FeeTier.isValidTickSpacing(tickSpacing);
    }

    function getTickSpacingForFeeTier(uint24 feeTier) external pure returns (uint16) {
        return FeeTier.getTickSpacingForFeeTier(feeTier);
    }

    function getFeeTierForTickSpacing(uint16 tickSpacing) external pure returns (uint24) {
        return FeeTier.getFeeTierForTickSpacing(tickSpacing);
    }

    function calculateLPFee(uint24 feeTier, uint16 protocolFeeBps) external pure returns (uint24) {
        return FeeTier.calculateLPFee(feeTier, protocolFeeBps);
    }

    function calculateFee(uint256 amount, uint24 feeTierBps) external pure returns (uint256) {
        return FeeTier.calculateFee(amount, feeTierBps);
    }

    function splitFee(
        uint256 totalFee,
        uint24 feeTier,
        uint16 protocolFeeBps
    ) external pure returns (uint256 protocolFee, uint256 lpFee) {
        return FeeTier.splitFee(totalFee, feeTier, protocolFeeBps);
    }
}

contract FeeTierTest is Test {
    FeeTierHarness private harness;

    function setUp() public {
        harness = new FeeTierHarness();
    }

    // ========== isValidFeeTier ==========

    function test_isValidFeeTier_low() public view {
        assertTrue(harness.isValidFeeTier(20));
    }

    function test_isValidFeeTier_medium() public view {
        assertTrue(harness.isValidFeeTier(50));
    }

    function test_isValidFeeTier_zero() public view {
        assertFalse(harness.isValidFeeTier(0));
    }

    function test_isValidFeeTier_invalid_10() public view {
        assertFalse(harness.isValidFeeTier(10));
    }

    function test_isValidFeeTier_invalid_100() public view {
        assertFalse(harness.isValidFeeTier(100));
    }

    function test_isValidFeeTier_invalid_30() public view {
        assertFalse(harness.isValidFeeTier(30));
    }

    // ========== isValidTickSpacing ==========

    function test_isValidTickSpacing_low() public view {
        assertTrue(harness.isValidTickSpacing(50));
    }

    function test_isValidTickSpacing_medium() public view {
        assertTrue(harness.isValidTickSpacing(200));
    }

    function test_isValidTickSpacing_zero() public view {
        assertFalse(harness.isValidTickSpacing(0));
    }

    function test_isValidTickSpacing_invalid_100() public view {
        assertFalse(harness.isValidTickSpacing(100));
    }

    function test_isValidTickSpacing_invalid_1() public view {
        assertFalse(harness.isValidTickSpacing(1));
    }

    // ========== getTickSpacingForFeeTier ==========

    function test_getTickSpacingForFeeTier_low() public view {
        assertEq(harness.getTickSpacingForFeeTier(20), 50);
    }

    function test_getTickSpacingForFeeTier_medium() public view {
        assertEq(harness.getTickSpacingForFeeTier(50), 200);
    }

    function test_getTickSpacingForFeeTier_reverts_invalidTier() public {
        vm.expectRevert(abi.encodeWithSelector(FeeTier.InvalidFeeTier.selector, uint24(100)));
        harness.getTickSpacingForFeeTier(100);
    }

    function test_getTickSpacingForFeeTier_reverts_zero() public {
        vm.expectRevert(abi.encodeWithSelector(FeeTier.InvalidFeeTier.selector, uint24(0)));
        harness.getTickSpacingForFeeTier(0);
    }

    // ========== getFeeTierForTickSpacing ==========

    function test_getFeeTierForTickSpacing_low() public view {
        assertEq(harness.getFeeTierForTickSpacing(50), 20);
    }

    function test_getFeeTierForTickSpacing_medium() public view {
        assertEq(harness.getFeeTierForTickSpacing(200), 50);
    }

    function test_getFeeTierForTickSpacing_reverts_invalidSpacing() public {
        vm.expectRevert(abi.encodeWithSelector(FeeTier.InvalidTickSpacing.selector, uint16(100)));
        harness.getFeeTierForTickSpacing(100);
    }

    function test_getFeeTierForTickSpacing_reverts_zero() public {
        vm.expectRevert(abi.encodeWithSelector(FeeTier.InvalidTickSpacing.selector, uint16(0)));
        harness.getFeeTierForTickSpacing(0);
    }

    // ========== calculateLPFee ==========

    function test_calculateLPFee_normalCase() public view {
        // 50 bps fee tier - 10 bps protocol = 40 bps LP
        assertEq(harness.calculateLPFee(50, 10), 40);
    }

    function test_calculateLPFee_lowTier() public view {
        // 20 bps fee tier - 10 bps protocol = 10 bps LP
        assertEq(harness.calculateLPFee(20, 10), 10);
    }

    function test_calculateLPFee_protocolEqualsFee() public view {
        assertEq(harness.calculateLPFee(20, 20), 0);
    }

    function test_calculateLPFee_protocolExceedsFee() public view {
        assertEq(harness.calculateLPFee(20, 30), 0);
    }

    function test_calculateLPFee_zeroProtocol() public view {
        assertEq(harness.calculateLPFee(50, 0), 50);
    }

    // ========== calculateFee ==========

    function test_calculateFee_mediumTier() public view {
        // 1000 * 50 / 10000 = 5
        assertEq(harness.calculateFee(1000, 50), 5);
    }

    function test_calculateFee_lowTier() public view {
        // 10000 * 20 / 10000 = 20
        assertEq(harness.calculateFee(10000, 20), 20);
    }

    function test_calculateFee_zeroAmount() public view {
        assertEq(harness.calculateFee(0, 50), 0);
    }

    function test_calculateFee_zeroFeeTier() public view {
        assertEq(harness.calculateFee(1000, 0), 0);
    }

    function test_calculateFee_largeAmount() public view {
        // 1e18 * 50 / 10000 = 5e15
        assertEq(harness.calculateFee(1e18, 50), 5e15);
    }

    function test_calculateFee_1USDC_mediumTier() public view {
        // 1_000_000 (1 USDC) * 50 / 10000 = 5000 (0.005 USDC)
        assertEq(harness.calculateFee(1_000_000, 50), 5000);
    }

    // ========== splitFee ==========

    function test_splitFee_normalCase() public view {
        // Total fee=100, feeTier=50, protocolFee=10
        // Protocol: 100 * 10 / 50 = 20
        // LP: 100 - 20 = 80
        (uint256 protocolFee, uint256 lpFee) = harness.splitFee(100, 50, 10);
        assertEq(protocolFee, 20);
        assertEq(lpFee, 80);
    }

    function test_splitFee_zeroProtocol() public view {
        (uint256 protocolFee, uint256 lpFee) = harness.splitFee(100, 50, 0);
        assertEq(protocolFee, 0);
        assertEq(lpFee, 100);
    }

    function test_splitFee_zeroTotalFee() public view {
        (uint256 protocolFee, uint256 lpFee) = harness.splitFee(0, 50, 10);
        assertEq(protocolFee, 0);
        assertEq(lpFee, 0);
    }

    function test_splitFee_lowTier() public view {
        // Total fee=200, feeTier=20, protocolFee=5
        // Protocol: 200 * 5 / 20 = 50
        // LP: 200 - 50 = 150
        (uint256 protocolFee, uint256 lpFee) = harness.splitFee(200, 20, 5);
        assertEq(protocolFee, 50);
        assertEq(lpFee, 150);
    }

    function test_splitFee_sumEqualsTotal() public view {
        uint256 totalFee = 12345;
        (uint256 protocolFee, uint256 lpFee) = harness.splitFee(totalFee, 50, 10);
        assertEq(protocolFee + lpFee, totalFee);
    }
}
