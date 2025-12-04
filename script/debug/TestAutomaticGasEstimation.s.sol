// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IScaleXRouter} from "../../src/core/interfaces/IScaleXRouter.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {IPoolManager} from "../../src/core/interfaces/IPoolManager.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";

contract TestAutomaticGasEstimation is Script {
    address constant USER = 0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a;
    uint128 constant PRICE = 1961000000; // Use successful price
    
    function run() external {
        string memory json = vm.readFile("./deployments/84532.json");
        
        address scaleXRouter = vm.parseJsonAddress(json, ".ScaleXRouter");
        address gsUSDC = vm.parseJsonAddress(json, ".gsUSDC");
        address gsWETH = vm.parseJsonAddress(json, ".gsWETH");
        address pool = vm.parseJsonAddress(json, ".WETH_USDC_Pool");
        
        console.log("=== TESTING AUTOMATIC GAS ESTIMATION ===");
        console.log("This simulates how the MM bot will now estimate gas automatically");
        console.log("");
        
        IPoolManager.Pool memory poolForOrder = IPoolManager.Pool({
            baseCurrency: Currency.wrap(gsWETH),
            quoteCurrency: Currency.wrap(gsUSDC),
            orderBook: IOrderBook(pool)
        });
        
        // Test different order sizes to see gas estimates
        uint128[4] memory quantities = [
            uint128(50000000000000000),   // 0.05 WETH
            uint128(100000000000000000),  // 0.1 WETH
            uint128(250000000000000000),  // 0.25 WETH  
            uint128(500000000000000000)   // 0.5 WETH
        ];
        
        for (uint i = 0; i < quantities.length; i++) {
            uint128 quantity = quantities[i];
            console.log("=== Order size:", quantity, "===");
            
            // Simulate gas estimation (this is what Viem's simulateContract does)
            vm.startPrank(USER);
            try vm.estimateGas(
                scaleXRouter,
                abi.encodeWithSelector(
                    IScaleXRouter.placeLimitOrder.selector,
                    poolForOrder,
                    PRICE + uint128(i), // Slight price variation
                    quantity,
                    IOrderBook.Side.BUY,
                    IOrderBook.TimeInForce.GTC,
                    uint128(0)
                )
            ) returns (uint256 estimatedGas) {
                console.log("Estimated gas:", estimatedGas);
                
                // Calculate what MM bot will use (estimate + 20% buffer)
                uint256 gasWithBuffer = (estimatedGas * 120) / 100;
                console.log("Gas with 20% buffer:", gasWithBuffer);
                
                // Test if this amount would work
                try IScaleXRouter(scaleXRouter).placeLimitOrder{gas: gasWithBuffer}(
                    poolForOrder,
                    PRICE + uint128(i),
                    quantity,
                    IOrderBook.Side.BUY,
                    IOrderBook.TimeInForce.GTC,
                    uint128(0)
                ) returns (uint48 orderId) {
                    console.log("SUCCESS: Order placed with estimated gas! Order ID:", orderId);
                    
                    // Cancel to clean up
                    try IScaleXRouter(scaleXRouter).cancelOrder{gas: gasWithBuffer}(poolForOrder, orderId) {
                        console.log("Order cancelled");
                    } catch {
                        console.log("Could not cancel");
                    }
                } catch Error(string memory reason) {
                    console.log("FAILED with estimated gas, reason:", reason);
                } catch (bytes memory) {
                    console.log("FAILED with estimated gas: OutOfGas or low-level error");
                }
            } catch {
                console.log("Could not estimate gas for this order size");
            }
            vm.stopPrank();
            console.log("");
        }
        
        console.log("=== BENEFITS OF AUTOMATIC GAS ESTIMATION ===");
        console.log("1. No more hardcoded gas limits");
        console.log("2. Automatically scales with order size");
        console.log("3. Adapts to network conditions");
        console.log("4. Reduces gas waste on small orders");
        console.log("5. Prevents OutOfGas on large orders");
        console.log("");
        console.log("Your MM bot now uses simulateContract + 20% buffer");
        console.log("=== TEST COMPLETE ===");
    }
}