// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/core/Oracle.sol";
import "../src/core/SyntheticTokenFactory.sol";

/**
 * @title VerifyOracleFallback
 * @notice Script to verify Oracle's automatic underlying → synthetic token price fallback
 * @dev Tests that querying underlying token prices returns synthetic token prices
 */
contract VerifyOracleFallback is Script {
    function run() external view {
        // Load environment variables
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        address factoryAddress = vm.envAddress("SYNTHETIC_TOKEN_FACTORY_ADDRESS");

        // Test token addresses (Testnet 11155111)
        address sxWETH = 0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6;
        address underlyingWETH = 0x8b732595a59c9a18acA0Aca3221A656Eb38158fC;
        address sxIDRX = 0x0a3eECF8d7d68dD4c943c6e42bab11A3f4F07DB7;
        address underlyingIDRX = 0x80FD9a0F8BCA5255692016D67E0733bf5262C142;

        console.log("=== Verifying Oracle Auto-Fallback ===");
        console.log("Oracle:", oracleAddress);
        console.log("Factory:", factoryAddress);
        console.log("");

        Oracle oracle = Oracle(oracleAddress);
        SyntheticTokenFactory factory = SyntheticTokenFactory(factoryAddress);

        // Verify factory is set
        console.log("1. Factory Configuration:");
        address configuredFactory = address(oracle.syntheticTokenFactory());
        console.log("   Oracle.syntheticTokenFactory():", configuredFactory);
        require(configuredFactory == factoryAddress, "Factory not configured correctly");
        console.log("   [OK] Factory configured correctly");
        console.log("");

        // Test WETH
        console.log("2. Testing WETH:");
        console.log("   Synthetic WETH (sxWETH):", sxWETH);
        console.log("   Underlying WETH:", underlyingWETH);

        // Get synthetic token from factory
        address resolvedSynthetic = factory.getSyntheticToken(uint32(block.chainid), underlyingWETH);
        console.log("   Factory.getSyntheticToken(underlying):", resolvedSynthetic);
        require(resolvedSynthetic == sxWETH, "Factory mapping incorrect");

        // Check if synthetic is active
        bool isActive = factory.isSyntheticTokenActive(sxWETH);
        console.log("   Factory.isSyntheticTokenActive(sxWETH):", isActive);
        require(isActive, "Synthetic token not active");

        // Query prices
        uint256 syntheticPrice = oracle.getSpotPrice(sxWETH);
        console.log("   Oracle.getSpotPrice(sxWETH):", syntheticPrice);

        uint256 underlyingPrice = oracle.getSpotPrice(underlyingWETH);
        console.log("   Oracle.getSpotPrice(underlying):", underlyingPrice);

        require(underlyingPrice == syntheticPrice, "Price fallback not working for WETH");
        console.log("   [OK] Underlying query returns synthetic price ($", syntheticPrice / 1e8, ")");
        console.log("");

        // Test IDRX
        console.log("3. Testing IDRX:");
        console.log("   Synthetic IDRX (sxIDRX):", sxIDRX);
        console.log("   Underlying IDRX:", underlyingIDRX);

        resolvedSynthetic = factory.getSyntheticToken(uint32(block.chainid), underlyingIDRX);
        console.log("   Factory.getSyntheticToken(underlying):", resolvedSynthetic);
        require(resolvedSynthetic == sxIDRX, "Factory mapping incorrect");

        isActive = factory.isSyntheticTokenActive(sxIDRX);
        console.log("   Factory.isSyntheticTokenActive(sxIDRX):", isActive);
        require(isActive, "Synthetic token not active");

        syntheticPrice = oracle.getSpotPrice(sxIDRX);
        console.log("   Oracle.getSpotPrice(sxIDRX):", syntheticPrice);

        underlyingPrice = oracle.getSpotPrice(underlyingIDRX);
        console.log("   Oracle.getSpotPrice(underlying):", underlyingPrice);

        require(underlyingPrice == syntheticPrice, "Price fallback not working for IDRX");
        console.log("   [OK] Underlying query returns synthetic price ($", syntheticPrice / 1e8, ")");
        console.log("");

        console.log("=== All Tests Passed ===");
        console.log("Oracle auto-fallback is working correctly!");
    }
}
