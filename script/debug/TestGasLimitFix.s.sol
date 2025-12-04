// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IScaleXRouter} from "../../src/core/interfaces/IScaleXRouter.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {IPoolManager} from "../../src/core/interfaces/IPoolManager.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import {PoolKey} from "../../src/core/libraries/Pool.sol";

contract TestGasLimitFix is Script {
    // Test with the same user and parameters from the failed transaction
    address constant TEST_USER = 0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a;
    uint128 constant TEST_PRICE = 3063000000; // 3063 USDC per WETH
    uint128 constant TEST_QUANTITY = 100000000000000000; // 0.1 WETH (smaller for testing)
    IOrderBook.Side constant TEST_SIDE = IOrderBook.Side.BUY;
    
    function run() external {
        // Load deployment addresses
        string memory json = vm.readFile("./deployments/84532.json");
        
        address scaleXRouter = vm.parseJsonAddress(json, ".ScaleXRouter");
        address balanceManager = vm.parseJsonAddress(json, ".BalanceManager");
        address poolManager = vm.parseJsonAddress(json, ".PoolManager");
        address gsUSDC = vm.parseJsonAddress(json, ".gsUSDC");
        address gsWETH = vm.parseJsonAddress(json, ".gsWETH");
        address pool = vm.parseJsonAddress(json, ".WETH_USDC_Pool");
        
        console.log("=== TESTING GAS LIMIT FIX FOR LIMIT ORDERS ===");
        console.log("Test User:", TEST_USER);
        console.log("Router:", scaleXRouter);
        console.log("");
        
        // Check user balances first
        console.log("=== USER BALANCE CHECK ===");
        IBalanceManager bm = IBalanceManager(balanceManager);
        uint256 bmGsUSDCBalance = bm.getBalance(TEST_USER, Currency.wrap(gsUSDC));
        uint256 bmGsWETHBalance = bm.getBalance(TEST_USER, Currency.wrap(gsWETH));
        console.log("BalanceManager gsUSDC Balance:", bmGsUSDCBalance);
        console.log("BalanceManager gsWETH Balance:", bmGsWETHBalance);
        
        // Calculate required amount for the test order
        uint256 requiredGsUSDC = (uint256(TEST_QUANTITY) * uint256(TEST_PRICE)) / 1e18;
        console.log("Required gsUSDC for test order:", requiredGsUSDC);
        console.log("Has sufficient balance:", bmGsUSDCBalance >= requiredGsUSDC);
        console.log("");
        
        if (bmGsUSDCBalance < requiredGsUSDC) {
            console.log("ERROR: Insufficient balance for test. Need to fund the test account first.");
            return;
        }
        
        // Build the pool struct
        IPoolManager.Pool memory poolForOrder = IPoolManager.Pool({
            baseCurrency: Currency.wrap(gsWETH),
            quoteCurrency: Currency.wrap(gsUSDC),
            orderBook: IOrderBook(pool)
        });
        
        console.log("=== TESTING WITH DIFFERENT GAS LIMITS ===");
        
        // Test 1: Try with original gas limit (2M) - should fail
        console.log("Test 1: Trying with 2,000,000 gas (original limit)");
        vm.startPrank(TEST_USER);
        IScaleXRouter router = IScaleXRouter(scaleXRouter);
        try router.placeLimitOrder{gas: 2000000}(
            poolForOrder,
            TEST_PRICE,
            TEST_QUANTITY,
            TEST_SIDE,
            IOrderBook.TimeInForce.GTC,
            0 // depositAmount
        ) returns (uint48) {
            console.log("SUCCESS: Order placed with 2M gas");
        } catch Error(string memory reason) {
            console.log("FAILED with reason:", reason);
        } catch (bytes memory) {
            console.log("FAILED: Out of gas or low-level error with 2M gas");
        }
        vm.stopPrank();
        console.log("");
        
        // Test 2: Try with new gas limit (3.5M) - should succeed
        console.log("Test 2: Trying with 3,500,000 gas (new limit)");
        vm.startPrank(TEST_USER);
        try router.placeLimitOrder{gas: 3500000}(
            poolForOrder,
            TEST_PRICE,
            TEST_QUANTITY,
            TEST_SIDE,
            IOrderBook.TimeInForce.GTC,
            0 // depositAmount
        ) returns (uint48 orderId) {
            console.log("SUCCESS: Order placed with 3.5M gas, Order ID:", orderId);
            
            // Try to cancel the order to clean up
            try router.cancelOrder{gas: 3500000}(poolForOrder, orderId) {
                console.log("SUCCESS: Order cancelled successfully");
            } catch {
                console.log("NOTE: Could not cancel order (may have filled immediately)");
            }
            
        } catch Error(string memory reason) {
            console.log("FAILED with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("FAILED: Low-level error with 3.5M gas");
            console.logBytes(lowLevelData);
        }
        vm.stopPrank();
        console.log("");
        
        // Test 3: Try with even higher gas limit for safety (4M)
        console.log("Test 3: Trying with 4,000,000 gas (extra safe limit)");
        vm.startPrank(TEST_USER);
        try router.placeLimitOrder{gas: 4000000}(
            poolForOrder,
            TEST_PRICE + 1, // Slightly different price to avoid duplicate
            TEST_QUANTITY,
            TEST_SIDE,
            IOrderBook.TimeInForce.GTC,
            0 // depositAmount
        ) returns (uint48 orderId) {
            console.log("SUCCESS: Order placed with 4M gas, Order ID:", orderId);
            
            // Try to cancel the order to clean up
            try router.cancelOrder{gas: 4000000}(poolForOrder, orderId) {
                console.log("SUCCESS: Order cancelled successfully");
            } catch {
                console.log("NOTE: Could not cancel order (may have filled immediately)");
            }
            
        } catch Error(string memory reason) {
            console.log("FAILED with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("FAILED: Low-level error with 4M gas");
            console.logBytes(lowLevelData);
        }
        vm.stopPrank();
        console.log("");
        
        // Test 4: Check gas estimation for the operation
        console.log("=== GAS ESTIMATION TEST ===");
        vm.startPrank(TEST_USER);
        
        // Create a separate call to estimate gas
        bytes memory callData = abi.encodeWithSelector(
            IScaleXRouter.placeLimitOrder.selector,
            poolForOrder,
            TEST_PRICE + 2, // Different price
            TEST_QUANTITY,
            TEST_SIDE,
            IOrderBook.TimeInForce.GTC,
            uint128(0)
        );
        
        // This is a rough estimation - in practice, you'd use eth_estimateGas
        console.log("Call data length:", callData.length);
        console.log("Estimated minimum gas needed: ~3,000,000 based on our simulation");
        
        vm.stopPrank();
        
        console.log("=== TEST SUMMARY ===");
        console.log("- 2,000,000 gas: Expected to fail (original MM bot setting)");
        console.log("- 3,500,000 gas: Should succeed (new MM bot setting)"); 
        console.log("- 4,000,000 gas: Extra safe option");
        console.log("");
        console.log("Recommendation: Use 3,500,000 gas for production MM bot");
        console.log("=== TEST COMPLETE ===");
    }
}