// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract AnalyzeFailedPrice is Script {
    // Failed transaction details
    uint128 constant FAILED_PRICE = 3063000000; // 3063 USDC per WETH from failed tx
    uint128 constant MIN_PRICE_INCREMENT = 1000000; // 1 USDC from trading rules
    
    function run() external {
        console.log("=== ANALYZING FAILED TRANSACTION PRICE ===");
        console.log("Failed transaction price:", FAILED_PRICE);
        console.log("Min price increment:", MIN_PRICE_INCREMENT);
        console.log("");
        
        // Test price validation
        console.log("=== PRICE INCREMENT VALIDATION ===");
        
        // Check if price is aligned with increment
        uint128 remainder = FAILED_PRICE % MIN_PRICE_INCREMENT;
        console.log("Price remainder when divided by increment:", remainder);
        console.log("Is price aligned with increment?", remainder == 0);
        console.log("");
        
        // Calculate what the correct price should be
        uint128 roundedDown = (FAILED_PRICE / MIN_PRICE_INCREMENT) * MIN_PRICE_INCREMENT;
        uint128 roundedUp = roundedDown + MIN_PRICE_INCREMENT;
        
        console.log("=== PRICE CORRECTION OPTIONS ===");
        console.log("Rounded down to:", roundedDown);
        console.log("Rounded up to:", roundedUp);
        console.log("");
        
        // JavaScript MM bot logic equivalent
        console.log("=== MM BOT PRICE PROCESSING SIMULATION ===");
        console.log("1. Original calculated price:", FAILED_PRICE);
        
        // This is what roundToNearestPriceIncrement() does: (price / increment) * increment
        uint128 mmBotProcessedPrice = (FAILED_PRICE / MIN_PRICE_INCREMENT) * MIN_PRICE_INCREMENT;
        console.log("2. After roundToNearestPriceIncrement():", mmBotProcessedPrice);
        
        // Check if the MM bot processed price matches what failed
        console.log("3. Does MM bot processed price match failed price?", mmBotProcessedPrice == FAILED_PRICE);
        
        if (mmBotProcessedPrice != FAILED_PRICE) {
            console.log("4. Difference:", FAILED_PRICE > mmBotProcessedPrice ? FAILED_PRICE - mmBotProcessedPrice : mmBotProcessedPrice - FAILED_PRICE);
        }
        console.log("");
        
        // Test specific values
        console.log("=== SPECIFIC VALIDATIONS ===");
        testPriceIncrement(3063000000); // Failed price
        testPriceIncrement(3063000000 - 1); // Slightly below
        testPriceIncrement(3064000000); // Next increment up
        testPriceIncrement(1961000000); // Our successful test price
        
        console.log("=== ANALYSIS COMPLETE ===");
    }
    
    function testPriceIncrement(uint128 price) internal view {
        uint128 remainder = price % MIN_PRICE_INCREMENT;
        uint128 rounded = (price / MIN_PRICE_INCREMENT) * MIN_PRICE_INCREMENT;
        console.log("Price:", price);
        console.log("Remainder:", remainder); 
        console.log("Valid:", remainder == 0);
        console.log("Rounded:", rounded);
        console.log("---");
    }
}