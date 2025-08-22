// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/GTXRouter.sol";
import "../src/core/PoolManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

contract TestCLOBTrading is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== TESTING CLOB TRADING =========");
        console.log("User:", deployer);
        
        // Switch to Rari
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        // Contract addresses from deployments
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address routerAddr = 0xF38489749c3e65c82a9273c498A8c6614c34754b;
        address poolManagerAddr = 0xA3B22cA94Cc3Eb8f6Bd8F4108D88d085e12d886b;
        
        // Token addresses
        address gsUSDT = 0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address gsWBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        GTXRouter router = GTXRouter(routerAddr);
        PoolManager poolManager = PoolManager(poolManagerAddr);
        
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("Router:", routerAddr);
        console.log("PoolManager:", poolManagerAddr);
        console.log("");
        console.log("Token addresses:");
        console.log("gsUSDT:", gsUSDT);
        console.log("gsWETH:", gsWETH);
        console.log("gsWBTC:", gsWBTC);
        
        // Step 1: Check user's current balances
        console.log("=== STEP 1: CHECKING BALANCES ===");
        
        Currency usdtCurrency = Currency.wrap(gsUSDT);
        Currency wethCurrency = Currency.wrap(gsWETH);
        Currency wbtcCurrency = Currency.wrap(gsWBTC);
        
        uint256 usdtBalance = balanceManager.getBalance(deployer, usdtCurrency);
        uint256 wethBalance = balanceManager.getBalance(deployer, wethCurrency);
        uint256 wbtcBalance = balanceManager.getBalance(deployer, wbtcCurrency);
        
        console.log("User's gsUSDT balance:", usdtBalance);
        console.log("User's gsWETH balance:", wethBalance);
        console.log("User's gsWBTC balance:", wbtcBalance);
        
        if (usdtBalance == 0) {
            console.log("ERROR: No gsUSDT balance found!");
            console.log("Cross-chain message may still be processing.");
            console.log("Check Hyperlane explorer and try again in a few minutes.");
            return;
        }
        
        console.log("SUCCESS: User has", usdtBalance, "gsUSDT tokens!");
        
        // Step 2: Check pool information
        console.log("=== STEP 2: CHECKING POOL INFORMATION ===");
        
        // Pool IDs from deployments
        bytes32 wethUsdtPoolId = 0x95e33693c8b0e491367d67550606cf78dd5063c7157ebfbc2cf1843b33f88272;
        bytes32 wbtcUsdtPoolId = 0xfae71d5ecc427cd83f39409db3501e7c154b4964cefc3c50f85c99a78a2708bb;
        
        console.log("WETH/USDT Pool ID:", vm.toString(wethUsdtPoolId));
        console.log("WBTC/USDT Pool ID:", vm.toString(wbtcUsdtPoolId));
        
        // Step 3: Test trading (if we have balance)
        if (usdtBalance > 100e6) { // If we have more than 100 USDT
            console.log("=== STEP 3: TESTING TRADES ===");
            
            vm.startBroadcast(deployerPrivateKey);
            
            // Try a small trade: 50 USDT for WETH
            uint256 tradeAmount = 50e6; // 50 USDT (6 decimals)
            console.log("Attempting to trade", tradeAmount, "gsUSDT for gsWETH");
            
            try router.swap(
                usdtCurrency,    // Source currency (gsUSDT)
                wethCurrency,    // Destination currency (gsWETH)
                tradeAmount,     // Source amount
                0,              // Min destination amount (0 for testing)
                1,              // Max hops
                deployer        // User
            ) {
                console.log("SUCCESS: Trade executed!");
                
                // Check balances after trade
                uint256 newUsdtBalance = balanceManager.getBalance(deployer, usdtCurrency);
                uint256 newWethBalance = balanceManager.getBalance(deployer, wethCurrency);
                
                console.log("New gsUSDT balance:", newUsdtBalance);
                console.log("New gsWETH balance:", newWethBalance);
                console.log("gsUSDT used:", usdtBalance - newUsdtBalance);
                console.log("gsWETH received:", newWethBalance - wethBalance);
                
            } catch Error(string memory reason) {
                console.log("Trade failed:", reason);
            } catch {
                console.log("Trade failed with unknown error");
            }
            
            vm.stopBroadcast();
            
        } else {
            console.log("Not enough gsUSDT balance for trading test");
            console.log("Need at least 100 USDT, have:", usdtBalance);
        }
        
        // Step 4: Check if we need to deposit some test tokens manually
        if (usdtBalance == 0) {
            console.log("=== STEP 4: MANUAL TOKEN DEPOSIT (FOR TESTING) ===");
            console.log("Since cross-chain message might still be processing,");
            console.log("you can manually deposit some test tokens:");
            console.log("");
            console.log("Option 1: Wait for cross-chain message to process");
            console.log("Option 2: Directly mint gsUSDT for testing (if minter role available)");
            console.log("Option 3: Deposit directly to BalanceManager (if you have gsUSDT)");
        }
        
        console.log("========== TRADING TEST COMPLETE =========");
    }
}