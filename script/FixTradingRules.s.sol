// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";
import {IPoolManager} from "../src/core/interfaces/IPoolManager.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {PoolKey, PoolId} from "../src/core/libraries/Pool.sol";

contract FixTradingRules is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address poolManager = 0xE3D7C79608eBd053f082973f4edE2c817bF864D5;
        address sxWETH = 0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6;
        address sxIDRX = 0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624;

        console.log("=== FIXING TRADING RULES ===");
        console.log("");

        // Get pool
        PoolKey memory poolKey = PoolKey({
            baseCurrency: Currency.wrap(sxWETH),
            quoteCurrency: Currency.wrap(sxIDRX),
            feeTier: 20
        });

        IPoolManager.Pool memory pool = IPoolManager(poolManager).getPool(poolKey);
        address orderBook = address(pool.orderBook);

        console.log("OrderBook:", orderBook);

        // Get current rules
        IOrderBook.TradingRules memory currentRules = IOrderBook(orderBook).getTradingRules();
        console.log("Current minPriceMovement:", currentRules.minPriceMovement);

        // Update rules:
        // - minPriceMovement: 100 (= 1.00 IDRX, since IDRX has 2 decimals)
        //   This allows price increments of 1 IDRX (e.g., 1894, 1895, 1896...)
        // - minOrderSize: 1000 (= 10.00 IDRX minimum order value in quote currency)
        // - minTradeAmount: 1e15 (= 0.001 WETH minimum in base currency)
        IOrderBook.TradingRules memory newRules = IOrderBook.TradingRules({
            minTradeAmount: 1e15,   // 0.001 WETH minimum base currency amount
            minAmountMovement: currentRules.minAmountMovement,
            minPriceMovement: 100,  // 1.00 IDRX minimum price movement
            minOrderSize: 1000      // 10.00 IDRX minimum order value (quote currency)
        });

        console.log("New minPriceMovement:", newRules.minPriceMovement);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Update trading rules through PoolManager (which owns the OrderBook)
        PoolId poolId = poolKey.toId();
        PoolManager(poolManager).updatePoolTradingRules(poolId, newRules);

        console.log("Trading rules updated!");

        vm.stopBroadcast();

        console.log("");
        console.log("=== FIX COMPLETE ===");
    }
}
