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

contract TestExactFailedParams is Script {
    // EXACT parameters from the failed transaction
    address constant FAILED_TX_USER = 0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a;
    uint128 constant EXACT_FAILED_PRICE = 3063000000; // 3063 USDC per WETH
    uint128 constant EXACT_FAILED_QUANTITY = 500000000000000000; // 0.5 WETH  
    IOrderBook.Side constant EXACT_FAILED_SIDE = IOrderBook.Side.BUY;
    IOrderBook.TimeInForce constant EXACT_FAILED_TIF = IOrderBook.TimeInForce.GTC;
    uint128 constant EXACT_FAILED_DEPOSIT = 0; // depositAmount was 0
    
    function run() external {
        string memory json = vm.readFile("./deployments/84532.json");
        
        address scaleXRouter = vm.parseJsonAddress(json, ".ScaleXRouter");
        address balanceManager = vm.parseJsonAddress(json, ".BalanceManager");
        address gsUSDC = vm.parseJsonAddress(json, ".gsUSDC");
        address gsWETH = vm.parseJsonAddress(json, ".gsWETH");
        address pool = vm.parseJsonAddress(json, ".WETH_USDC_Pool");
        
        console.log("=== TESTING EXACT FAILED TRANSACTION PARAMETERS ===");
        console.log("Original failed TX: 0x5bb5c3b7884b7b2ff04955e2e7b885cc41bd236d226b640af528f6a07a09ad65");
        console.log("User:", FAILED_TX_USER);
        console.log("Price:", EXACT_FAILED_PRICE, "(3063 USDC per WETH)");
        console.log("Quantity:", EXACT_FAILED_QUANTITY, "(0.5 WETH)");
        console.log("Side: BUY (0)");
        console.log("TimeInForce: GTC (0)");
        console.log("DepositAmount:", EXACT_FAILED_DEPOSIT);
        console.log("");
        
        // Check user balance first
        console.log("=== USER BALANCE CHECK ===");
        IBalanceManager bm = IBalanceManager(balanceManager);
        uint256 bmGsUSDCBalance = bm.getBalance(FAILED_TX_USER, Currency.wrap(gsUSDC));
        console.log("BalanceManager gsUSDC Balance:", bmGsUSDCBalance);
        
        uint256 requiredGsUSDC = (uint256(EXACT_FAILED_QUANTITY) * uint256(EXACT_FAILED_PRICE)) / 1e18;
        console.log("Required gsUSDC for order:", requiredGsUSDC);
        console.log("Has sufficient balance:", bmGsUSDCBalance >= requiredGsUSDC);
        console.log("");
        
        if (bmGsUSDCBalance < requiredGsUSDC) {
            console.log("ERROR: Insufficient balance - cannot reproduce test");
            return;
        }
        
        // Build the exact same pool struct
        IPoolManager.Pool memory poolForOrder = IPoolManager.Pool({
            baseCurrency: Currency.wrap(gsWETH),
            quoteCurrency: Currency.wrap(gsUSDC),
            orderBook: IOrderBook(pool)
        });
        
        console.log("=== TESTING WITH DIFFERENT GAS LIMITS ===");
        
        vm.startPrank(FAILED_TX_USER);
        IScaleXRouter router = IScaleXRouter(scaleXRouter);
        
        // Test 1: Original failed gas limit (2M)
        console.log("Test 1: Original failed gas limit (2,000,000)");
        try router.placeLimitOrder{gas: 2000000}(
            poolForOrder,
            EXACT_FAILED_PRICE,
            EXACT_FAILED_QUANTITY,
            EXACT_FAILED_SIDE,
            EXACT_FAILED_TIF,
            EXACT_FAILED_DEPOSIT
        ) returns (uint48 orderId1) {
            console.log("UNEXPECTED SUCCESS with 2M gas! Order ID:", orderId1);
            
            // Clean up
            try router.cancelOrder{gas: 2000000}(poolForOrder, orderId1) {
                console.log("Order cancelled");
            } catch {
                console.log("Could not cancel order");
            }
        } catch Error(string memory reason) {
            console.log("FAILED as expected with reason:", reason);
        } catch (bytes memory) {
            console.log("FAILED as expected: OutOfGas or low-level error");
        }
        console.log("");
        
        // Test 2: Updated MM bot gas limit (3M)
        console.log("Test 2: Updated MM bot gas limit (3,000,000)");
        try router.placeLimitOrder{gas: 3000000}(
            poolForOrder,
            EXACT_FAILED_PRICE,
            EXACT_FAILED_QUANTITY,
            EXACT_FAILED_SIDE,
            EXACT_FAILED_TIF,
            EXACT_FAILED_DEPOSIT
        ) returns (uint48 orderId2) {
            console.log("SUCCESS with 3M gas! Order ID:", orderId2);
            
            // Clean up
            try router.cancelOrder{gas: 3000000}(poolForOrder, orderId2) {
                console.log("Order cancelled successfully");
            } catch {
                console.log("Could not cancel order (may have filled)");
            }
        } catch Error(string memory reason) {
            console.log("FAILED with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("FAILED with low-level error");
            console.logBytes(lowLevelData);
        }
        console.log("");
        
        // Test 3: High gas limit for absolute confirmation (6M)
        console.log("Test 3: High gas limit for confirmation (6,000,000)");
        try router.placeLimitOrder{gas: 6000000}(
            poolForOrder,
            EXACT_FAILED_PRICE + 1000000, // Add 1 USDC to avoid duplicate price
            EXACT_FAILED_QUANTITY,
            EXACT_FAILED_SIDE,
            EXACT_FAILED_TIF,
            EXACT_FAILED_DEPOSIT
        ) returns (uint48 orderId3) {
            console.log("SUCCESS with 6M gas! Order ID:", orderId3);
            
            // Clean up
            try router.cancelOrder{gas: 6000000}(poolForOrder, orderId3) {
                console.log("Order cancelled successfully");
            } catch {
                console.log("Could not cancel order (may have filled)");
            }
        } catch Error(string memory reason) {
            console.log("FAILED with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("FAILED with low-level error");
            console.logBytes(lowLevelData);
        }
        console.log("");
        
        vm.stopPrank();
        
        console.log("=== TEST RESULTS SUMMARY ===");
        console.log("Original transaction parameters:");
        console.log("- User: 0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a");
        console.log("- Price: 3,063,000,000 (3063 USDC)"); 
        console.log("- Quantity: 500,000,000,000,000,000 (0.5 WETH)");
        console.log("- Gas limit: 2,000,000 (FAILED)");
        console.log("");
        console.log("Expected results:");
        console.log("- 2M gas: Should fail with OutOfGas");
        console.log("- 3M gas: Should succeed (MM bot fix)");
        console.log("- 6M gas: Should succeed (confirmation)");
        console.log("=== TEST COMPLETE ===");
    }
}