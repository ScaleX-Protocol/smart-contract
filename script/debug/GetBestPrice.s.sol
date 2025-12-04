// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IScaleXRouter} from "@scalexcore/interfaces/IScaleXRouter.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";

contract TestBestPrice is Script {
    // Contract addresses
    IScaleXRouter constant router = IScaleXRouter(0xd81F05627eC398719B58F034a0E806D2971958f1);
    
    // From your log parameters
    Currency constant baseCurrency = Currency.wrap(address(0x835c8aa033972E372865FcC933c9de0A48B6Ae23)); // gsWETH
    Currency constant quoteCurrency = Currency.wrap(address(0x22F9a3898C3DB2a0008fe9a7524a4A41D8A789Df)); // gsUSDC
    
    // Market maker account and private key (using trader bot key 1)
    uint256 constant MM_PRIVATE_KEY = 0x1baeb251ed376027e40d3f5c2315307b9a3ba3c13c5f6e80070618a7ad6781f8;
    address mmAccount = vm.addr(MM_PRIVATE_KEY);
    
    function testGetBestAskPrice() public {
        console.log("=== Testing getBestPrice function ===");
        console.log("Getting best ask price");
        console.log("[getBestPrice] Function called with side: SELL");
        console.log("[getBestPrice] Contract address:", address(router));
        console.log("[getBestPrice] Pool key base currency:", Currency.unwrap(baseCurrency));
        console.log("[getBestPrice] Pool key quote currency:", Currency.unwrap(quoteCurrency));
        
        // Function arguments as shown in log: [baseCurrency, quoteCurrency, side]
        // Side: 1 = SELL (getting best ask price)
        console.log("[getBestPrice] Function arguments: [baseCurrency, quoteCurrency, side=1]");
        
        try router.getBestPrice(baseCurrency, quoteCurrency, IOrderBook.Side.SELL) returns (IOrderBook.PriceVolume memory priceVolume) {
            console.log("[SUCCESS] Best ask price:", priceVolume.price);
            console.log("[SUCCESS] Best ask price (readable):", priceVolume.price / 1e6);
            console.log("[SUCCESS] Best ask volume:", priceVolume.volume);
            
            if (priceVolume.price == 0) {
                console.log("No ask orders available (empty orderbook)");
            } else {
                console.log("Ask price found successfully");
            }
        } catch Error(string memory reason) {
            console.log("[ERROR] getBestPrice failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("[ERROR] getBestPrice failed with low-level error:");
            console.logBytes(lowLevelData);
        }
    }
    
    function testGetBestBidPrice() public {
        console.log("\n=== Testing getBestPrice for BID ===");
        console.log("Getting best bid price");
        console.log("[getBestPrice] Function called with side: BUY");
        console.log("[getBestPrice] Contract address:", address(router));
        console.log("[getBestPrice] Pool key base currency:", Currency.unwrap(baseCurrency));
        console.log("[getBestPrice] Pool key quote currency:", Currency.unwrap(quoteCurrency));
        
        // Function arguments: [baseCurrency, quoteCurrency, side]
        // Side: 0 = BUY (getting best bid price)
        console.log("[getBestPrice] Function arguments: [baseCurrency, quoteCurrency, side=0]");
        
        try router.getBestPrice(baseCurrency, quoteCurrency, IOrderBook.Side.BUY) returns (IOrderBook.PriceVolume memory priceVolume) {
            console.log("[SUCCESS] Best bid price:", priceVolume.price);
            console.log("[SUCCESS] Best bid price (readable):", priceVolume.price / 1e6);
            console.log("[SUCCESS] Best bid volume:", priceVolume.volume);
            
            if (priceVolume.price == 0) {
                console.log("No bid orders available (empty orderbook)");
            } else {
                console.log("Bid price found successfully");
            }
        } catch Error(string memory reason) {
            console.log("getBestPrice failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("[ERROR] getBestPrice failed with low-level error:");
            console.logBytes(lowLevelData);
        }
    }
    
    function testBothPrices() public {
        console.log("\n=== Testing Both Best Prices ===");
        
        uint256 bestAsk = 0;
        uint256 bestBid = 0;
        
        // Get best ask (SELL side)
        try router.getBestPrice(baseCurrency, quoteCurrency, IOrderBook.Side.SELL) returns (IOrderBook.PriceVolume memory askPriceVolume) {
            bestAsk = askPriceVolume.price;
            console.log("Best Ask (SELL side):", askPriceVolume.price, "readable:", askPriceVolume.price / 1e6);
        } catch {
            console.log("No ask price available");
        }
        
        // Get best bid (BUY side) 
        try router.getBestPrice(baseCurrency, quoteCurrency, IOrderBook.Side.BUY) returns (IOrderBook.PriceVolume memory bidPriceVolume) {
            bestBid = bidPriceVolume.price;
            console.log("Best Bid (BUY side):", bidPriceVolume.price, "readable:", bidPriceVolume.price / 1e6);
        } catch {
            console.log("No bid price available");
        }
        
        // Calculate spread
        if (bestAsk > 0 && bestBid > 0) {
            uint256 spread = bestAsk - bestBid;
            uint256 spreadBps = (spread * 10000) / bestBid;
            console.log("Spread:", spread, "readable:", spread / 1e6);
            console.log("Spread (bps):", spreadBps);
        } else {
            console.log("Cannot calculate spread - missing bid or ask");
        }
    }
    
    function run() external {
        // Test the exact function call from your MM bot log
        testGetBestAskPrice();
        
        console.log("\n==================================================");
        
        // Test bid price as well
        testGetBestBidPrice();
        
        console.log("\n==================================================");
        
        // Test both and show spread
        testBothPrices();
    }
}