// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./DeployHelpers.s.sol";
import "../src/core/PoolManager.sol";
import "../src/core/GTXRouter.sol";
import "../src/core/BalanceManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {PoolKey} from "../src/core/libraries/Pool.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";
import {IPoolManager} from "../src/core/interfaces/IPoolManager.sol";

contract TestTradingOrders is DeployHelpers {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Deployed contracts
        address poolManagerAddr = 0xA3B22cA94Cc3Eb8f6Bd8F4108D88d085e12d886b;
        address routerAddr = 0xF38489749c3e65c82a9273c498A8c6614c34754b;
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        
        // Synthetic tokens
        address gsUSDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address gsWBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;
        
        console.log("========== TESTING TRADING ORDERS ==========");
        console.log("User address:", deployer);
        console.log("PoolManager:", poolManagerAddr);
        console.log("Router:", routerAddr);
        
        // Check balances first
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        console.log("=== CURRENT BALANCES ===");
        console.log("gsUSDT balance:", balanceManager.getBalance(deployer, Currency.wrap(gsUSDT)));
        console.log("gsWETH balance:", balanceManager.getBalance(deployer, Currency.wrap(gsWETH)));
        console.log("gsWBTC balance:", balanceManager.getBalance(deployer, Currency.wrap(gsWBTC)));
        
        // Get pool information
        PoolManager poolManager = PoolManager(poolManagerAddr);
        GTXRouter router = GTXRouter(routerAddr);
        
        PoolKey memory wethUsdtPool = PoolKey({
            baseCurrency: Currency.wrap(gsWETH),
            quoteCurrency: Currency.wrap(gsUSDT)
        });
        
        IPoolManager.Pool memory pool;
        try poolManager.getPool(wethUsdtPool) returns (IPoolManager.Pool memory poolData) {
            pool = poolData;
            console.log("=== POOL INFO ===");
            console.log("Pool found - OrderBook:", address(pool.orderBook));
        } catch {
            console.log("ERROR: Could not get pool information");
            return;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Test 1: Place a limit buy order (buy 0.1 WETH at 4000 USDT each)
        console.log("=== TEST 1: LIMIT BUY ORDER ===");
        console.log("Placing buy order: 0.1 WETH at 4000 USDT");
        
        try router.placeLimitOrder(
            pool,
            4000e6,           // price: 4000 USDT (6 decimals)
            1e17,             // quantity: 0.1 WETH (18 decimals)
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            400e6             // depositAmount: 400 USDT for 0.1 WETH
        ) returns (uint48 orderId1) {
            console.log("SUCCESS: Buy order placed, ID:", orderId1);
        } catch Error(string memory reason) {
            console.log("Buy order failed:", reason);
        } catch {
            console.log("Buy order failed with unknown error");
        }
        
        // Test 2: Place a limit sell order (sell 0.05 WETH at 4200 USDT each)
        console.log("=== TEST 2: LIMIT SELL ORDER ===");
        console.log("Placing sell order: 0.05 WETH at 4200 USDT");
        
        try router.placeLimitOrder(
            pool,
            4200e6,           // price: 4200 USDT
            5e16,             // quantity: 0.05 WETH 
            IOrderBook.Side.SELL,
            IOrderBook.TimeInForce.GTC,
            5e16              // depositAmount: 0.05 WETH
        ) returns (uint48 orderId2) {
            console.log("SUCCESS: Sell order placed, ID:", orderId2);
        } catch Error(string memory reason) {
            console.log("Sell order failed:", reason);
        } catch {
            console.log("Sell order failed with unknown error");
        }
        
        // Test 3: Check order book state
        console.log("=== ORDER BOOK STATE ===");
        try pool.orderBook.getBestPrice(IOrderBook.Side.BUY) returns (IOrderBook.PriceVolume memory bestBuy) {
            console.log("Best buy price:", bestBuy.price);
            console.log("Best buy volume:", bestBuy.volume);
        } catch {
            console.log("No buy orders in book");
        }
        
        try pool.orderBook.getBestPrice(IOrderBook.Side.SELL) returns (IOrderBook.PriceVolume memory bestSell) {
            console.log("Best sell price:", bestSell.price);
            console.log("Best sell volume:", bestSell.volume);
        } catch {
            console.log("No sell orders in book");
        }
        
        vm.stopBroadcast();
        
        console.log("=== FINAL BALANCES ===");
        console.log("gsUSDT balance:", balanceManager.getBalance(deployer, Currency.wrap(gsUSDT)));
        console.log("gsWETH balance:", balanceManager.getBalance(deployer, Currency.wrap(gsWETH)));
        
        console.log("========== TRADING TEST COMPLETE ==========");
    }
}