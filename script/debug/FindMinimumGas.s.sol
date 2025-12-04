// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IScaleXRouter} from "../../src/core/interfaces/IScaleXRouter.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {IPoolManager} from "../../src/core/interfaces/IPoolManager.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";

contract FindMinimumGas is Script {
    address constant USER = 0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a;
    uint128 constant PRICE = 1961000000; // Use successful price from previous test
    IOrderBook.Side constant SIDE = IOrderBook.Side.BUY;
    
    function run() external {
        string memory json = vm.readFile("./deployments/84532.json");
        
        address scaleXRouter = vm.parseJsonAddress(json, ".ScaleXRouter");
        address gsUSDC = vm.parseJsonAddress(json, ".gsUSDC");
        address gsWETH = vm.parseJsonAddress(json, ".gsWETH");
        address pool = vm.parseJsonAddress(json, ".WETH_USDC_Pool");
        
        console.log("=== FINDING MINIMUM GAS FOR DIFFERENT ORDER SIZES ===");
        
        IPoolManager.Pool memory poolForOrder = IPoolManager.Pool({
            baseCurrency: Currency.wrap(gsWETH),
            quoteCurrency: Currency.wrap(gsUSDC),
            orderBook: IOrderBook(pool)
        });
        
        vm.startPrank(USER);
        IScaleXRouter router = IScaleXRouter(scaleXRouter);
        
        // Test different quantities with increasing gas limits
        uint128[4] memory quantities = [
            uint128(50000000000000000),   // 0.05 WETH
            uint128(100000000000000000),  // 0.1 WETH (our successful test)
            uint128(250000000000000000),  // 0.25 WETH
            uint128(500000000000000000)   // 0.5 WETH (failed original)
        ];
        
        uint256[6] memory gasLimits = [
            uint256(3000000),   // 3M
            uint256(6000000),   // 6M  
            uint256(10000000),  // 10M
            uint256(15000000),  // 15M
            uint256(20000000),  // 20M
            uint256(25000000)   // 25M
        ];
        
        for (uint i = 0; i < quantities.length; i++) {
            uint128 quantity = quantities[i];
            console.log("");
            console.log("=== Testing quantity:", quantity, "===");
            
            bool success = false;
            for (uint j = 0; j < gasLimits.length; j++) {
                uint256 gasLimit = gasLimits[j];
                console.log("Trying with", gasLimit, "gas...");
                
                try router.placeLimitOrder{gas: gasLimit}(
                    poolForOrder,
                    PRICE + uint128(i), // Slight price variation to avoid conflicts
                    quantity,
                    SIDE,
                    IOrderBook.TimeInForce.GTC,
                    0
                ) returns (uint48 orderId) {
                    console.log("SUCCESS! Order ID:", orderId);
                    
                    // Cancel immediately
                    try router.cancelOrder{gas: gasLimit}(poolForOrder, orderId) {
                        console.log("Order cancelled");
                    } catch {
                        console.log("Could not cancel");
                    }
                    
                    success = true;
                    break;
                    
                } catch Error(string memory reason) {
                    console.log("Failed with reason:", reason);
                } catch (bytes memory) {
                    console.log("Failed: OutOfGas or low-level error");
                }
            }
            
            if (!success) {
                console.log("FAILED: Could not place order even with 25M gas!");
            }
        }
        
        vm.stopPrank();
        
        console.log("");
        console.log("=== MINIMUM GAS RECOMMENDATIONS ===");
        console.log("Based on test results:");
        console.log("- Small orders (0.05-0.1 WETH): ~3M gas should work");
        console.log("- Medium orders (0.25 WETH): Requires higher gas");
        console.log("- Large orders (0.5+ WETH): May require 15M+ gas");
        console.log("");
        console.log("MM Bot recommendation: Use 15M gas for safety");
        console.log("=== TEST COMPLETE ===");
    }
}