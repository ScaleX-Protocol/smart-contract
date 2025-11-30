// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";

contract CheckOrderStatuses is Test {
    IOrderBook constant orderBook = IOrderBook(0x58013521Ba2D0FdfDC4763313Ae4e61A4dD9438e);
    
    function checkSpecificOrders(uint48[] memory orderIds) public view {
        console.log("=== Checking Specific Order IDs ===");
        console.log("OrderBook address:", address(orderBook));
        
        for (uint256 i = 0; i < orderIds.length; i++) {
            uint48 orderId = orderIds[i];
            
            try orderBook.getOrder(orderId) returns (IOrderBook.Order memory order) {
                console.log("\n--- Order", orderId, "---");
                console.log("Price:", order.price, "readable:", order.price / 1e6);
                console.log("Quantity:", order.quantity, "readable:", order.quantity / 1e18);
                console.log("Side:", uint8(order.side) == 0 ? "BUY" : "SELL");
                console.log("User:", order.user);
                console.log("Status:", uint8(order.status));
                
                // Status meanings: 0=OPEN, 1=FILLED, 2=CANCELLED, 3=EXPIRED
                string memory statusStr = "UNKNOWN";
                if (uint8(order.status) == 0) statusStr = "OPEN";
                else if (uint8(order.status) == 1) statusStr = "FILLED";
                else if (uint8(order.status) == 2) statusStr = "CANCELLED";
                else if (uint8(order.status) == 3) statusStr = "EXPIRED";
                console.log("Status decoded:", statusStr);
                
                if (uint8(order.status) == 0) {
                    console.log("*** This order should appear in getBestPrice! ***");
                }
                
            } catch {
                console.log("Order", orderId, ": NOT FOUND");
            }
        }
    }
    
    function checkOrderBookBehavior() public view {
        console.log("\n=== Checking OrderBook Behavior ===");
        
        // Test with known user addresses from indexer
        address[] memory users = new address[](3);
        users[0] = 0x611910e4C4408eE76199CA4a5215FE830210fd55; // trader bot 3
        users[1] = 0x506B6fa189Ada984E1F98473047970f17da15AEc; // trader bot 1  
        users[2] = 0xf38A17f0d365dA9e1Ba6715b16708ACf30153cD7; // trader bot 2
        
        console.log("Known trader addresses from indexer:");
        for (uint256 i = 0; i < users.length; i++) {
            console.log("Trader", i + 1, ":", users[i]);
        }
        
        // Check if any orders exist for these users by checking recent order ranges
        console.log("\nChecking orders 100-130...");
        for (uint48 orderId = 100; orderId <= 130; orderId++) {
            try orderBook.getOrder(orderId) returns (IOrderBook.Order memory order) {
                if (order.user == users[0] || order.user == users[1] || order.user == users[2]) {
                    console.log("Found order", orderId, "for known trader:", order.user);
                    console.log("  Status:", uint8(order.status));
                }
            } catch {
                // Order doesn't exist, continue
            }
        }
    }
    
    function run() external view {
        // Example with default order IDs - including new fixed orders
        uint48[] memory defaultOrderIds = new uint48[](8);
        defaultOrderIds[0] = 721; // New SELL orders
        defaultOrderIds[1] = 720; // New SELL orders  
        defaultOrderIds[2] = 716; // New BUY orders
        defaultOrderIds[3] = 715; // New BUY orders
        defaultOrderIds[4] = 705; // Original test order
        defaultOrderIds[5] = 703; // Old cancelled order
        defaultOrderIds[6] = 702; // Old cancelled order
        defaultOrderIds[7] = 701; // Old cancelled order
        
        checkSpecificOrders(defaultOrderIds);
        checkOrderBookBehavior();
    }
    
    function runWithOrderIds(uint48[] memory orderIds) external view {
        checkSpecificOrders(orderIds);
        checkOrderBookBehavior();
    }
}