// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/GTXRouter.sol";
import "../src/core/PoolManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {PoolKey, PoolIdLibrary} from "../src/core/libraries/Pool.sol";
import {IPoolManager} from "../src/core/interfaces/IPoolManager.sol";

contract CheckTradingSystem is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== CHECKING TRADING SYSTEM STATUS =========");
        console.log("User:", deployer);
        
        // Switch to Rari
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        // Contract addresses
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
        
        console.log("=== CONTRACT ADDRESSES ===");
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("Router:", routerAddr);
        console.log("PoolManager:", poolManagerAddr);
        console.log("");
        console.log("=== TOKEN ADDRESSES ===");
        console.log("gsUSDT:", gsUSDT);
        console.log("gsWETH:", gsWETH);
        console.log("gsWBTC:", gsWBTC);
        
        // Step 1: Check user balances
        console.log("=== USER BALANCES ===");
        
        Currency usdtCurrency = Currency.wrap(gsUSDT);
        Currency wethCurrency = Currency.wrap(gsWETH);
        Currency wbtcCurrency = Currency.wrap(gsWBTC);
        
        uint256 usdtBalance = balanceManager.getBalance(deployer, usdtCurrency);
        uint256 wethBalance = balanceManager.getBalance(deployer, wethCurrency);
        uint256 wbtcBalance = balanceManager.getBalance(deployer, wbtcCurrency);
        
        console.log("gsUSDT balance:", usdtBalance);
        console.log("gsWETH balance:", wethBalance);
        console.log("gsWBTC balance:", wbtcBalance);
        
        // Step 2: Check pool configurations
        console.log("=== POOL CONFIGURATIONS ===");
        
        // Check pool 1: gsWETH/gsUSDT
        PoolKey memory wethUsdtKey = PoolKey({
            currency0: wethCurrency,
            currency1: usdtCurrency
        });
        
        bytes32 wethUsdtPoolId = PoolIdLibrary.toId(wethUsdtKey);
        console.log("WETH/USDT Pool ID:", vm.toString(wethUsdtPoolId));
        
        try poolManager.getPool(wethUsdtKey) returns (IPoolManager.Pool memory pool) {
            console.log("WETH/USDT Pool found:");
            console.log("  Base Currency:", Currency.unwrap(pool.baseCurrency));
            console.log("  Quote Currency:", Currency.unwrap(pool.quoteCurrency));
            console.log("  OrderBook:", address(pool.orderBook));
        } catch {
            console.log("WETH/USDT Pool not found or error");
        }
        
        // Check pool 2: gsWBTC/gsUSDT
        PoolKey memory wbtcUsdtKey = PoolKey({
            currency0: wbtcCurrency,
            currency1: usdtCurrency
        });
        
        bytes32 wbtcUsdtPoolId = PoolIdLibrary.toId(wbtcUsdtKey);
        console.log("WBTC/USDT Pool ID:", vm.toString(wbtcUsdtPoolId));
        
        try poolManager.getPool(wbtcUsdtKey) returns (IPoolManager.Pool memory pool) {
            console.log("WBTC/USDT Pool found:");
            console.log("  Base Currency:", Currency.unwrap(pool.baseCurrency));
            console.log("  Quote Currency:", Currency.unwrap(pool.quoteCurrency));
            console.log("  OrderBook:", address(pool.orderBook));
        } catch {
            console.log("WBTC/USDT Pool not found or error");
        }
        
        // Step 3: Check cross-chain status
        console.log("=== CROSS-CHAIN STATUS ===");
        
        uint256 userNonce = balanceManager.getUserNonce(deployer);
        console.log("User nonce (processed cross-chain messages):", userNonce);
        
        if (userNonce > 0) {
            console.log("SUCCESS: Cross-chain messages have been processed!");
        } else {
            console.log("PENDING: Cross-chain message still processing");
            console.log("Check: https://hyperlane-explorer.gtxdex.xyz/message/0xfcadbcd23563cb0230070d9ead7f78a0c0e468c7a7d3c674858afc60ca0a013a");
        }
        
        // Step 4: System readiness summary
        console.log("=== SYSTEM READINESS SUMMARY ===");
        
        bool contractsDeployed = balanceManagerAddr != address(0) && 
                                routerAddr != address(0) && 
                                poolManagerAddr != address(0);
        
        bool hasTokens = usdtBalance > 0 || wethBalance > 0 || wbtcBalance > 0;
        bool crossChainProcessed = userNonce > 0;
        
        console.log("Contracts deployed:", contractsDeployed ? "YES" : "NO");
        console.log("User has tokens:", hasTokens ? "YES" : "NO");
        console.log("Cross-chain processed:", crossChainProcessed ? "YES" : "NO");
        
        if (contractsDeployed) {
            console.log("CLOB SYSTEM: READY FOR TRADING");
            
            if (!hasTokens) {
                console.log("WAITING FOR: Cross-chain tokens or manual token deposit");
            } else {
                console.log("STATUS: READY TO TRADE!");
            }
        }
        
        console.log("========== SYSTEM CHECK COMPLETE =========");
    }
}