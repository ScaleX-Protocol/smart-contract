// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IBalanceManager {
    function setTokenRegistry(address _tokenRegistry) external;
    function getTokenRegistry() external view returns (address);
}

interface ITokenRegistry {
    function registerTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address syntheticToken,
        string memory symbol,
        uint8 sourceDecimals,
        uint8 syntheticDecimals
    ) external;
}

contract FixTokenRegistryIssues is Script {
    // From deployments/rari.json
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    address constant TOKEN_REGISTRY = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;
    
    // Chain IDs
    uint32 constant RARI_CHAIN_ID = 1918988905;
    uint32 constant RISE_CHAIN_ID = 11155931;
    uint32 constant ARBITRUM_CHAIN_ID = 421614;
    
    // Rise source tokens -> Rari synthetic tokens (from deployment files)
    address constant RISE_USDT = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;
    address constant RISE_WETH = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
    address constant RISE_WBTC = 0xc6b3109e45F7A479Ac324e014b6a272e4a25bF0E;
    
    // Current synthetic tokens on Rari (from rari.json)
    address constant RARI_gUSDT = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d;
    address constant RARI_gWETH = 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8;
    address constant RARI_gWBTC = 0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748;
    
    // Arbitrum source tokens -> same Rari synthetic tokens
    address constant ARB_USDT = 0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a;
    address constant ARB_WETH = 0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7;
    address constant ARB_WBTC = 0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Fixing TokenRegistry Issues ===");
        console.log("BalanceManager:", BALANCE_MANAGER);
        console.log("TokenRegistry:", TOKEN_REGISTRY);
        console.log("");

        IBalanceManager bm = IBalanceManager(BALANCE_MANAGER);
        ITokenRegistry tr = ITokenRegistry(TOKEN_REGISTRY);
        
        // Fix 1: Set TokenRegistry in BalanceManager
        console.log("Fix 1: Setting TokenRegistry in BalanceManager...");
        address currentTokenRegistry = bm.getTokenRegistry();
        console.log("  Current TokenRegistry:", currentTokenRegistry);
        
        if (currentTokenRegistry != TOKEN_REGISTRY) {
            bm.setTokenRegistry(TOKEN_REGISTRY);
            console.log("  TokenRegistry updated to:", TOKEN_REGISTRY);
        } else {
            console.log("  TokenRegistry already correct");
        }
        console.log("");
        
        // Fix 2: Register Rise token mappings
        console.log("Fix 2: Registering Rise Sepolia token mappings...");
        
        console.log("  Registering Rise USDT -> gUSDT mapping...");
        tr.registerTokenMapping(
            RISE_CHAIN_ID,     // sourceChainId
            RISE_USDT,         // sourceToken
            RARI_CHAIN_ID,     // targetChainId
            RARI_gUSDT,        // syntheticToken
            "gUSDT",           // symbol
            6,                 // sourceDecimals
            6                  // syntheticDecimals
        );
        
        console.log("  Registering Rise WETH -> gWETH mapping...");
        tr.registerTokenMapping(
            RISE_CHAIN_ID,     // sourceChainId
            RISE_WETH,         // sourceToken
            RARI_CHAIN_ID,     // targetChainId
            RARI_gWETH,        // syntheticToken
            "gWETH",           // symbol
            18,                // sourceDecimals
            18                 // syntheticDecimals
        );
        
        console.log("  Registering Rise WBTC -> gWBTC mapping...");
        tr.registerTokenMapping(
            RISE_CHAIN_ID,     // sourceChainId
            RISE_WBTC,         // sourceToken
            RARI_CHAIN_ID,     // targetChainId
            RARI_gWBTC,        // syntheticToken
            "gWBTC",           // symbol
            8,                 // sourceDecimals
            8                  // syntheticDecimals
        );
        console.log("");
        
        // Fix 3: Register Arbitrum token mappings
        console.log("Fix 3: Registering Arbitrum Sepolia token mappings...");
        
        console.log("  Registering Arbitrum USDT -> gUSDT mapping...");
        tr.registerTokenMapping(
            ARBITRUM_CHAIN_ID, // sourceChainId
            ARB_USDT,          // sourceToken
            RARI_CHAIN_ID,     // targetChainId
            RARI_gUSDT,        // syntheticToken
            "gUSDT",           // symbol
            6,                 // sourceDecimals
            6                  // syntheticDecimals
        );
        
        console.log("  Registering Arbitrum WETH -> gWETH mapping...");
        tr.registerTokenMapping(
            ARBITRUM_CHAIN_ID, // sourceChainId
            ARB_WETH,          // sourceToken
            RARI_CHAIN_ID,     // targetChainId
            RARI_gWETH,        // syntheticToken
            "gWETH",           // symbol
            18,                // sourceDecimals
            18                 // syntheticDecimals
        );
        
        console.log("  Registering Arbitrum WBTC -> gWBTC mapping...");
        tr.registerTokenMapping(
            ARBITRUM_CHAIN_ID, // sourceChainId
            ARB_WBTC,          // sourceToken
            RARI_CHAIN_ID,     // targetChainId
            RARI_gWBTC,        // syntheticToken
            "gWBTC",           // symbol
            8,                 // sourceDecimals
            8                  // syntheticDecimals
        );

        vm.stopBroadcast();
        
        console.log("");
        console.log("=== TokenRegistry Fix Complete ===");
        console.log("Rise and Arbitrum token mappings now registered!");
        console.log("BalanceManager TokenRegistry configured!");
        console.log("Cross-chain deposits should now work properly!");
    }
}