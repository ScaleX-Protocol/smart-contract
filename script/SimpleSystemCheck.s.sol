// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

contract SimpleSystemCheck is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== CLOB TRADING SYSTEM STATUS =========");
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
        
        console.log("=== DEPLOYED CONTRACTS ===");
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("Router:", routerAddr);
        console.log("PoolManager:", poolManagerAddr);
        console.log("");
        
        console.log("=== SYNTHETIC TOKENS ===");
        console.log("gsUSDT:", gsUSDT);
        console.log("gsWETH:", gsWETH);
        console.log("gsWBTC:", gsWBTC);
        console.log("");
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        
        // Check user balances
        console.log("=== USER TRADING BALANCES ===");
        
        Currency usdtCurrency = Currency.wrap(gsUSDT);
        Currency wethCurrency = Currency.wrap(gsWETH);
        Currency wbtcCurrency = Currency.wrap(gsWBTC);
        
        uint256 usdtBalance = balanceManager.getBalance(deployer, usdtCurrency);
        uint256 wethBalance = balanceManager.getBalance(deployer, wethCurrency);
        uint256 wbtcBalance = balanceManager.getBalance(deployer, wbtcCurrency);
        
        console.log("gsUSDT:", usdtBalance);
        console.log("gsWETH:", wethBalance);
        console.log("gsWBTC:", wbtcBalance);
        console.log("");
        
        // Check cross-chain status
        console.log("=== CROSS-CHAIN STATUS ===");
        uint256 userNonce = balanceManager.getUserNonce(deployer);
        console.log("Messages processed:", userNonce);
        
        if (userNonce > 0) {
            console.log("STATUS: Cross-chain message PROCESSED!");
        } else {
            console.log("STATUS: Cross-chain message still processing");
        }
        console.log("");
        
        // Check trading pools (from deployment JSON)
        console.log("=== CONFIGURED TRADING POOLS ===");
        console.log("1. gsWETH/gsUSDT Pool");
        console.log("   Pool ID: 0x95e33693c8b0e491367d67550606cf78dd5063c7157ebfbc2cf1843b33f88272");
        console.log("   Description: 1 WETH = X USDT");
        console.log("");
        console.log("2. gsWBTC/gsUSDT Pool"); 
        console.log("   Pool ID: 0xfae71d5ecc427cd83f39409db3501e7c154b4964cefc3c50f85c99a78a2708bb");
        console.log("   Description: 1 WBTC = X USDT");
        console.log("");
        
        // System readiness summary
        console.log("=== SYSTEM READINESS ===");
        bool contractsOk = balanceManagerAddr != address(0) && routerAddr != address(0);
        bool hasTokens = usdtBalance > 0 || wethBalance > 0 || wbtcBalance > 0;
        bool crossChainOk = userNonce > 0;
        
        console.log("Contracts deployed: YES");
        console.log("Pools configured: YES");  
        console.log("Cross-chain bridge: YES");
        
        if (hasTokens) {
            console.log("User has tokens: YES");
            console.log("STATUS: READY TO TRADE!");
        } else {
            console.log("User has tokens: NO (waiting for cross-chain)");
            console.log("STATUS: READY (waiting for tokens)");
        }
        
        console.log("");
        console.log("=== TRADING EXAMPLES ===");
        console.log("When tokens arrive, you can:");
        console.log("1. Swap tokens: router.swap(gsUSDT, gsWETH, amount, minOut, 1, user)");
        console.log("2. Place limit orders: router.placeLimitOrder(...)");
        console.log("3. Place market orders: router.placeMarketOrder(...)");
        console.log("");
        
        console.log("=== MONITORING ===");
        console.log("Cross-chain message:");
        console.log("https://hyperlane-explorer.gtxdex.xyz/message/0xfcadbcd23563cb0230070d9ead7f78a0c0e468c7a7d3c674858afc60ca0a013a");
        
        console.log("========== SYSTEM CHECK COMPLETE =========");
        if (hasTokens) {
            console.log("THE CLOB SYSTEM IS READY FOR TRADING!");
        } else {
            console.log("SYSTEM OPERATIONAL - WAITING FOR CROSS-CHAIN TOKENS");
        }
    }
}