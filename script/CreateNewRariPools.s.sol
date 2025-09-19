// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";
import {PoolId} from "../src/core/libraries/Pool.sol";

contract CreateNewRariPools is Script {
    // Rari testnet addresses
    address constant POOL_MANAGER = 0xA3B22cA94Cc3Eb8f6Bd8F4108D88d085e12d886b;
    
    // New synthetic token addresses (correct decimals)
    address constant gUSDT = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d; // 6 decimals
    address constant gWETH = 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8; // 18 decimals
    address constant gWBTC = 0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748; // 8 decimals

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        PoolManager poolManager = PoolManager(POOL_MANAGER);
        
        console.log("=== Creating New Rari Trading Pools ===");
        console.log("PoolManager:", POOL_MANAGER);
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("");
        
        // Create gWETH/gUSDT Pool
        console.log("=== Creating gWETH/gUSDT Pool ===");
        console.log("Base (gWETH):", gWETH, "(18 decimals)");
        console.log("Quote (gUSDT):", gUSDT, "(6 decimals)");
        
        Currency gWETHCurrency = Currency.wrap(gWETH);
        Currency gUSDTCurrency = Currency.wrap(gUSDT);
        
        // Check if pool already exists
        bool pool1Exists = poolManager.poolExists(gWETHCurrency, gUSDTCurrency);
        if (pool1Exists) {
            console.log("gWETH/gUSDT pool already exists, skipping creation");
        } else {
            console.log("Creating gWETH/gUSDT pool...");
            
            // Define trading rules for gWETH/gUSDT
            IOrderBook.TradingRules memory tradingRules1 = IOrderBook.TradingRules({
                minTradeAmount: 1e15,       // 0.001 WETH minimum trade (18 decimals)
                minAmountMovement: 1e15,    // 0.001 WETH minimum amount movement (18 decimals)
                minPriceMovement: 1e2,      // 0.01 USDT price tick (6 decimals)
                minOrderSize: 1e4           // 0.01 USDT minimum order (6 decimals) 
            });
            
            PoolId poolId1 = poolManager.createPool(gWETHCurrency, gUSDTCurrency, tradingRules1);
            console.log("gWETH/gUSDT Pool created with ID:");
            console.logBytes32(PoolId.unwrap(poolId1));
        }
        
        console.log("");
        
        // Create gWBTC/gUSDT Pool
        console.log("=== Creating gWBTC/gUSDT Pool ===");
        console.log("Base (gWBTC):", gWBTC, "(8 decimals)");
        console.log("Quote (gUSDT):", gUSDT, "(6 decimals)");
        
        Currency gWBTCCurrency = Currency.wrap(gWBTC);
        
        // Check if pool already exists
        bool pool2Exists = poolManager.poolExists(gWBTCCurrency, gUSDTCurrency);
        if (pool2Exists) {
            console.log("gWBTC/gUSDT pool already exists, skipping creation");
        } else {
            console.log("Creating gWBTC/gUSDT pool...");
            
            // Define trading rules for gWBTC/gUSDT
            IOrderBook.TradingRules memory tradingRules2 = IOrderBook.TradingRules({
                minTradeAmount: 1e5,        // 0.001 WBTC minimum trade (8 decimals)
                minAmountMovement: 1e5,     // 0.001 WBTC minimum amount movement (8 decimals)
                minPriceMovement: 1e2,      // 0.01 USDT price tick (6 decimals)
                minOrderSize: 1e4           // 0.01 USDT minimum order (6 decimals)
            });
            
            PoolId poolId2 = poolManager.createPool(gWBTCCurrency, gUSDTCurrency, tradingRules2);
            console.log("gWBTC/gUSDT Pool created with ID:");
            console.logBytes32(PoolId.unwrap(poolId2));
        }

        vm.stopBroadcast();
        
        console.log("");
        console.log("=== Pool Creation Summary ===");
        console.log("SUCCESS: Pools created successfully!");
        console.log("");
        console.log("Trading pairs now available:");
        console.log("1. gWETH/gUSDT - Trade gWETH for gUSDT");
        console.log("2. gWBTC/gUSDT - Trade gWBTC for gUSDT");
        console.log("");
        console.log("Cross-chain flow:");
        console.log("Rise/Arbitrum USDT/WETH/WBTC to Rari gUSDT/gWETH/gWBTC to Trading");
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify pools exist: forge script script/CheckPoolExists.s.sol");
        console.log("2. Test deposits from Rise/Arbitrum chains");
        console.log("3. Begin trading on these new pools");
    }
}