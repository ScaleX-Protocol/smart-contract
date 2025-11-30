// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IScaleXRouter} from "@scalexcore/interfaces/IScaleXRouter.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";

contract DebugOrderBook is Test {
    // Contract addresses
    IScaleXRouter constant router = IScaleXRouter(0xd81F05627eC398719B58F034a0E806D2971958f1);
    IPoolManager constant poolManager = IPoolManager(0x4c154D2a83B7dC575D186824059851c30965E337);
    IOrderBook constant orderBook = IOrderBook(0x58013521Ba2D0FdfDC4763313Ae4e61A4dD9438e);
    
    // Pool parameters
    Currency constant baseCurrency = Currency.wrap(address(0x835c8aa033972E372865FcC933c9de0A48B6Ae23)); // gsWETH
    Currency constant quoteCurrency = Currency.wrap(address(0x22F9a3898C3DB2a0008fe9a7524a4A41D8A789Df)); // gsUSDC
    
    function debugOrderBookState() public view {
        console.log("=== OrderBook Debug Information ===");
        console.log("OrderBook address:", address(orderBook));
        console.log("Base currency (gsWETH):", Currency.unwrap(baseCurrency));
        console.log("Quote currency (gsUSDC):", Currency.unwrap(quoteCurrency));
        
        // Try to get order count or other orderbook info
        console.log("\n=== OrderBook State ===");
        
        // Check best prices directly on orderbook
        try orderBook.getBestPrice(IOrderBook.Side.SELL) returns (IOrderBook.PriceVolume memory askPrice) {
            console.log("Direct OrderBook - Best Ask:");
            console.log("  Price:", askPrice.price);
            console.log("  Volume:", askPrice.volume);
        } catch {
            console.log("Failed to get best ask price directly from orderbook");
        }
        
        try orderBook.getBestPrice(IOrderBook.Side.BUY) returns (IOrderBook.PriceVolume memory bidPrice) {
            console.log("Direct OrderBook - Best Bid:");
            console.log("  Price:", bidPrice.price);
            console.log("  Volume:", bidPrice.volume);
        } catch {
            console.log("Failed to get best bid price directly from orderbook");
        }
        
        // Check if we can get any order information
        console.log("\n=== Order Investigation ===");
        
        // Try to get order by ID (recent order IDs from your test)
        for (uint48 orderId = 115; orderId <= 125; orderId++) {
            try this.checkOrder(orderId) {
                console.log("Order", orderId, "exists and is accessible");
            } catch {
                // Order doesn't exist or not accessible
            }
        }
        
        console.log("\n=== Pool Information ===");
        try poolManager.getPool(poolManager.createPoolKey(baseCurrency, quoteCurrency)) returns (IPoolManager.Pool memory pool) {
            console.log("Pool found:");
            console.log("  Base currency:", Currency.unwrap(pool.baseCurrency));
            console.log("  Quote currency:", Currency.unwrap(pool.quoteCurrency));
            console.log("  OrderBook:", address(pool.orderBook));
            console.log("  Matches expected:", address(pool.orderBook) == address(orderBook));
        } catch {
            console.log("Failed to get pool information");
        }
    }
    
    // External function to check if an order exists
    function checkOrder(uint48 orderId) external view {
        // Try to get order info - this will revert if order doesn't exist
        orderBook.getOrder(orderId);
    }
    
    function debugSpecificOrder() public view {
        console.log("\n=== Checking Specific Recent Orders ===");
        
        // Check the order that was placed in TestSpecificOrder (Order ID 120)
        uint48 targetOrderId = 120;
        
        try orderBook.getOrder(targetOrderId) returns (IOrderBook.Order memory order) {
            console.log("Order", targetOrderId, "found:");
            console.log("  Price:", order.price, "readable:", order.price / 1e6);
            console.log("  Quantity:", order.quantity, "readable:", order.quantity / 1e18);
            console.log("  Side:", uint8(order.side), uint8(order.side) == 0 ? "(BUY)" : "(SELL)");
            console.log("  User:", order.user);
            console.log("  Expiry:", order.expiry);
            // console.log("  IsMarketOrder:", order.isMarketOrder); // Field might not exist
            console.log("  Status:", uint8(order.status));
            
            // Decode status
            if (uint8(order.status) == 0) console.log("  Status: OPEN");
            else if (uint8(order.status) == 1) console.log("  Status: FILLED");
            else if (uint8(order.status) == 2) console.log("  Status: CANCELLED");
            else if (uint8(order.status) == 3) console.log("  Status: EXPIRED");
            else console.log("  Status: UNKNOWN");
            
        } catch {
            console.log("Order", targetOrderId, "not found or error getting order details");
        }
    }
    
    function debugOrderBookMethods() public view {
        console.log("\n=== Testing OrderBook Methods ===");
        
        // Simplified - just test if we can call basic functions
        try orderBook.getTradingRules() {
            console.log("Trading Rules method exists and is callable");
        } catch {
            console.log("Failed to get trading rules");
        }
        
        console.log("OrderBook basic info gathered");
    }
    
    function run() external view {
        debugOrderBookState();
        debugSpecificOrder();
        debugOrderBookMethods();
    }
}