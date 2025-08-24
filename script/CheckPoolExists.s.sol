// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

/**
 * @title CheckPoolExists
 * @dev Script to check if a pool exists for given base and quote currency addresses
 */
contract CheckPoolExists is Script {
    
    function run() external view {
        // Get deployed PoolManager address on Rari
        address poolManagerAddress = 0xA3B22cA94Cc3Eb8f6Bd8F4108D88d085e12d886b;
        
        PoolManager poolManager = PoolManager(poolManagerAddress);
        
        console.log("=== POOL EXISTENCE CHECKER ===");
        console.log("PoolManager:", poolManagerAddress);
        console.log("Chain ID:", block.chainid);
        console.log("");
        
        // gsWETH/gsUSDT indexer version
        // OLD ADDRESSES (commented out):
        // address baseCurrencyAddress = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836; // gsWETH 
        // address quoteCurrencyAddress = 0x6fcf28b801C7116cA8b6460289e259aC8D9131F3; // gsUSDT 
        
        // deployments version
        address baseCurrencyAddress = 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8; // gsWETH 
        address quoteCurrencyAddress = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d; // gsUSDT
        
        Currency baseCurrency = Currency.wrap(baseCurrencyAddress);
        Currency quoteCurrency = Currency.wrap(quoteCurrencyAddress);
        
        console.log("=== VERIFYING gsWETH/gsUSDT POOL ===");
        console.log("Base Currency (gsWETH):", baseCurrencyAddress);
        console.log("Quote Currency (gsUSDT):", quoteCurrencyAddress);
        console.log("Expected OrderBook:", "0x1d355de94dd6236a0818d2a872dfa97b56870da3");
        console.log("Expected Pool ID:", "da83d729dd59a57b10efce4b1a17c369927df643a6e649cc95468d7c0073292f");
        console.log("");
        
        // Check if pool exists using poolExists function
        bool exists = poolManager.poolExists(baseCurrency, quoteCurrency);
        
        if (exists) {
            console.log(">>> POOL EXISTS <<<");
            console.log("Pool is valid for trading");
            
            // Get additional pool information if pool exists
            uint256 liquidityScore = poolManager.getPoolLiquidityScore(baseCurrency, quoteCurrency);
            console.log("Liquidity Score:", liquidityScore);
        } else {
            console.log(">>> POOL DOES NOT EXIST <<<");
            console.log("Pool needs to be created before trading");
            console.log("Use PoolManager.createPool() to create this pool");
        }
        
        console.log("");
        console.log("=== USAGE INSTRUCTIONS ===");
        console.log("1. Update poolManagerAddress with deployed address");
        console.log("2. Update baseCurrencyAddress and quoteCurrencyAddress");
        console.log("3. Run: forge script script/CheckPoolExists.s.sol --rpc-url <RPC_URL>");
    }
    
    /**
     * @dev Helper function to check pool existence with specific addresses
     * @param poolManagerAddress Address of the deployed PoolManager
     * @param baseCurrencyAddress Address of the base currency
     * @param quoteCurrencyAddress Address of the quote currency
     */
    function checkPool(
        address poolManagerAddress,
        address baseCurrencyAddress,
        address quoteCurrencyAddress
    ) external view returns (bool exists, uint256 liquidityScore) {
        PoolManager poolManager = PoolManager(poolManagerAddress);
        
        Currency baseCurrency = Currency.wrap(baseCurrencyAddress);
        Currency quoteCurrency = Currency.wrap(quoteCurrencyAddress);
        
        exists = poolManager.poolExists(baseCurrency, quoteCurrency);
        
        if (exists) {
            liquidityScore = poolManager.getPoolLiquidityScore(baseCurrency, quoteCurrency);
        }
        
        return (exists, liquidityScore);
    }
}