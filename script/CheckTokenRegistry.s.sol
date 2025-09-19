// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface ITokenRegistry {
    function getSyntheticToken(uint32 sourceChainId, address sourceToken, uint32 targetChainId) external view returns (address);
    function isTokenMappingActive(uint32 sourceChainId, address sourceToken, uint32 targetChainId) external view returns (bool);
    function getChainTokens(uint32 sourceChainId) external view returns (address[] memory);
}

interface IBalanceManager {
    function getTokenRegistry() external view returns (address);
}

contract CheckTokenRegistry is Script {
    // From deployments/rari.json
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    address constant TOKEN_REGISTRY = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;
    
    // Chain IDs
    uint32 constant RARI_CHAIN_ID = 1918988905;
    uint32 constant RISE_CHAIN_ID = 11155931;
    uint32 constant ARBITRUM_CHAIN_ID = 421614;
    uint32 constant APPCHAIN_ID = 4661;
    
    // Rise token addresses
    address constant RISE_USDT = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;
    address constant RISE_WETH = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
    address constant RISE_WBTC = 0xc6b3109e45F7A479Ac324e014b6a272e4a25bF0E;
    
    // Arbitrum token addresses  
    address constant ARB_USDT = 0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a;
    address constant ARB_WETH = 0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7;
    address constant ARB_WBTC = 0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A;

    function run() external view {
        console.log("=== TokenRegistry Configuration Check ===");
        console.log("TokenRegistry Address:", TOKEN_REGISTRY);
        console.log("");

        IBalanceManager bm = IBalanceManager(BALANCE_MANAGER);
        ITokenRegistry tr = ITokenRegistry(TOKEN_REGISTRY);
        
        // Verify BalanceManager is using correct TokenRegistry
        address bmTokenRegistry = bm.getTokenRegistry();
        console.log("BalanceManager TokenRegistry:", bmTokenRegistry);
        console.log("Expected TokenRegistry:", TOKEN_REGISTRY);
        if (bmTokenRegistry == TOKEN_REGISTRY) {
            console.log("Status: CORRECT");
        } else {
            console.log("Status: MISMATCH - This could be the issue!");
        }
        console.log("");
        
        // Check Appchain mappings (should work)
        console.log("=== Appchain Token Mappings (Should Work) ===");
        address[] memory appchainTokens = tr.getChainTokens(APPCHAIN_ID);
        console.log("Registered tokens for Appchain:", appchainTokens.length);
        for (uint i = 0; i < appchainTokens.length; i++) {
            console.log("  Token:", appchainTokens[i]);
        }
        console.log("");
        
        // Check Rise mappings (likely missing)
        console.log("=== Rise Sepolia Token Mappings (Problem Area) ===");
        address[] memory riseTokens = tr.getChainTokens(RISE_CHAIN_ID);
        console.log("Registered tokens for Rise:", riseTokens.length);
        
        if (riseTokens.length == 0) {
            console.log("ERROR: No token mappings registered for Rise Sepolia!");
            console.log("This explains why Rise deposits fail");
        } else {
            for (uint i = 0; i < riseTokens.length; i++) {
                console.log("  Token:", riseTokens[i]);
            }
        }
        console.log("");
        
        // Test specific Rise token mappings
        console.log("Rise Token Mapping Tests:");
        address riseSyntheticUSDT = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_USDT, RARI_CHAIN_ID);
        console.log("  Rise USDT -> Synthetic:", riseSyntheticUSDT);
        
        address riseSyntheticWETH = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_WETH, RARI_CHAIN_ID);
        console.log("  Rise WETH -> Synthetic:", riseSyntheticWETH);
        
        address riseSyntheticWBTC = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_WBTC, RARI_CHAIN_ID);
        console.log("  Rise WBTC -> Synthetic:", riseSyntheticWBTC);
        console.log("");
        
        // Check Arbitrum mappings  
        console.log("=== Arbitrum Sepolia Token Mappings ===");
        address[] memory arbTokens = tr.getChainTokens(ARBITRUM_CHAIN_ID);
        console.log("Registered tokens for Arbitrum:", arbTokens.length);
        
        if (arbTokens.length == 0) {
            console.log("ERROR: No token mappings registered for Arbitrum Sepolia!");
        } else {
            for (uint i = 0; i < arbTokens.length; i++) {
                console.log("  Token:", arbTokens[i]);
            }
        }
        
        console.log("");
        console.log("=== DIAGNOSIS ===");
        console.log("If Rise/Arbitrum deposits fail to relay:");
        console.log("1. TokenRegistry needs mappings for Rise/Arbitrum tokens");
        console.log("2. Missing mappings prevent synthetic token minting");
        console.log("3. Relayer fails when trying to call BalanceManager.handle()");
    }
}