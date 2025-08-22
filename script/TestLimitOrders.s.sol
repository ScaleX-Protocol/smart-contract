// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/GTXRouter.sol";
import "../src/core/PoolManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";
import {IPoolManager} from "../src/core/interfaces/IPoolManager.sol";

contract TestLimitOrders is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== TESTING LIMIT ORDERS =========");
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
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        GTXRouter router = GTXRouter(routerAddr);
        PoolManager poolManager = PoolManager(poolManagerAddr);
        
        console.log("Contracts:");
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("Router:", routerAddr);
        console.log("PoolManager:", poolManagerAddr);
        console.log("");
        console.log("Tokens:");
        console.log("gsUSDT:", gsUSDT);
        console.log("gsWETH:", gsWETH);
        
        // Step 1: Check current balances
        console.log("=== STEP 1: CHECKING BALANCES ===");
        
        Currency usdtCurrency = Currency.wrap(gsUSDT);
        Currency wethCurrency = Currency.wrap(gsWETH);
        
        uint256 usdtBalance = balanceManager.getBalance(deployer, usdtCurrency);
        uint256 wethBalance = balanceManager.getBalance(deployer, wethCurrency);
        
        console.log("gsUSDT balance in BalanceManager:", usdtBalance);
        console.log("gsWETH balance in BalanceManager:", wethBalance);
        
        if (usdtBalance == 0 && wethBalance == 0) {
            console.log("No balances found for trading");
            console.log("Cross-chain message may still be processing");
            console.log("Or tokens need to be deposited manually");
            return;
        }
        
        // Step 2: Get pool information
        console.log("=== STEP 2: POOL INFORMATION ===");
        
        // Create pool struct
        IPoolManager.Pool memory pool = IPoolManager.Pool({
            base: usdtCurrency,
            quote: wethCurrency
        });
        
        // Pool ID from deployments (gsWETH/gsUSDT)
        bytes32 poolId = 0x95e33693c8b0e491367d67550606cf78dd5063c7157ebfbc2cf1843b33f88272;
        console.log("Pool ID:", vm.toString(poolId));
        
        // Step 3: Try to place a limit order
        if (usdtBalance > 0) {
            console.log("=== STEP 3: PLACING LIMIT ORDER ===");
            
            vm.startBroadcast(deployerPrivateKey);
            
            uint128 orderAmount = uint128(usdtBalance / 10); // Use 10% of balance
            uint128 orderPrice = 4500e18; // 1 WETH = 4500 USDT (example price)
            
            console.log("Attempting to place limit order:");
            console.log("Amount:", orderAmount);
            console.log("Price:", orderPrice);
            console.log("Side: BUY (buying WETH with USDT)");
            
            try router.placeLimitOrder(
                pool,
                IOrderBook.Side.BUY,
                orderAmount,
                orderPrice
            ) {
                console.log("SUCCESS: Limit order placed!");
            } catch Error(string memory reason) {
                console.log("Failed to place limit order:", reason);
            } catch {
                console.log("Failed to place limit order with unknown error");
            }
            
            vm.stopBroadcast();
        }
        
        // Step 4: Check order book status
        console.log("=== STEP 4: CHECKING ORDER BOOK ===");
        
        try router.getOrderQueue(pool, IOrderBook.Side.BUY, 4500e18) returns (uint48[] memory orderIds) {
            console.log("Buy orders at price 4500:");
            for (uint i = 0; i < orderIds.length && i < 5; i++) {
                console.log("Order ID:", orderIds[i]);
            }
        } catch {
            console.log("Could not fetch buy order queue");
        }
        
        try router.getOrderQueue(pool, IOrderBook.Side.SELL, 4500e18) returns (uint48[] memory orderIds) {
            console.log("Sell orders at price 4500:");
            for (uint i = 0; i < orderIds.length && i < 5; i++) {
                console.log("Order ID:", orderIds[i]);
            }
        } catch {
            console.log("Could not fetch sell order queue");
        }
        
        console.log("========== LIMIT ORDER TEST COMPLETE =========");
        console.log("The CLOB system is ready for trading once tokens are available!");
    }
}