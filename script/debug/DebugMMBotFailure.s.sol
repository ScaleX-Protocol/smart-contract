// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IScaleXRouter} from "../../src/core/interfaces/IScaleXRouter.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {IPoolManager} from "../../src/core/interfaces/IPoolManager.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";

contract DebugMMBotFailure is Script {
    // EXACT parameters from MM bot logs
    address constant USER = 0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a;
    uint128 constant PRICE = 3210000000; // From logs: 3210000000 
    uint128 constant QUANTITY = 500000000000000000; // From logs: 500000000000000000
    IOrderBook.Side constant SIDE = IOrderBook.Side.BUY; // From logs: side=0
    IOrderBook.TimeInForce constant TIF = IOrderBook.TimeInForce.GTC; // From logs: timeInForce=0  
    uint128 constant DEPOSIT_AMOUNT = 0; // From logs: depositAmount=0
    
    function run() external {
        string memory json = vm.readFile("./deployments/84532.json");
        
        address scaleXRouter = vm.parseJsonAddress(json, ".ScaleXRouter");
        address balanceManager = vm.parseJsonAddress(json, ".BalanceManager");
        address gsUSDC = vm.parseJsonAddress(json, ".gsUSDC");
        address gsWETH = vm.parseJsonAddress(json, ".gsWETH");
        address pool = vm.parseJsonAddress(json, ".WETH_USDC_Pool");
        
        console.log("=== DEBUGGING MM BOT SIMULATION FAILURES ===");
        console.log("Reproducing exact parameters that are failing in MM bot:");
        console.log("User:", USER);
        console.log("Price:", PRICE, "(3210 USDC per WETH)");
        console.log("Quantity:", QUANTITY, "(0.5 WETH)");
        console.log("Side: BUY");
        console.log("TimeInForce: GTC");
        console.log("DepositAmount:", DEPOSIT_AMOUNT);
        console.log("");
        
        // Check user balance first
        console.log("=== USER BALANCE CHECK ===");
        IBalanceManager bm = IBalanceManager(balanceManager);
        uint256 bmGsUSDCBalance = bm.getBalance(USER, Currency.wrap(gsUSDC));
        uint256 bmGsWETHBalance = bm.getBalance(USER, Currency.wrap(gsWETH));
        console.log("BalanceManager gsUSDC Balance:", bmGsUSDCBalance);
        console.log("BalanceManager gsWETH Balance:", bmGsWETHBalance);
        
        // Calculate required amount
        uint256 requiredGsUSDC = (uint256(QUANTITY) * uint256(PRICE)) / 1e18;
        console.log("Required gsUSDC for order:", requiredGsUSDC);
        console.log("Has sufficient balance:", bmGsUSDCBalance >= requiredGsUSDC);
        console.log("");
        
        // Build pool struct
        IPoolManager.Pool memory poolForOrder = IPoolManager.Pool({
            baseCurrency: Currency.wrap(gsWETH),
            quoteCurrency: Currency.wrap(gsUSDC),
            orderBook: IOrderBook(pool)
        });
        
        console.log("=== TESTING ORDER PLACEMENT ===");
        vm.startPrank(USER);
        IScaleXRouter router = IScaleXRouter(scaleXRouter);
        
        // Try to place the exact order that's failing in MM bot
        try router.placeLimitOrder{gas: 8000000}(
            poolForOrder,
            PRICE,
            QUANTITY,
            SIDE,
            TIF,
            DEPOSIT_AMOUNT
        ) returns (uint48 orderId) {
            console.log("SUCCESS! Order placed with Order ID:", orderId);
            
            // Cancel to clean up
            try router.cancelOrder{gas: 8000000}(poolForOrder, orderId) {
                console.log("Order cancelled successfully");
            } catch {
                console.log("Could not cancel order");
            }
            
        } catch Error(string memory reason) {
            console.log("FAILED with error reason:", reason);
            
        } catch (bytes memory lowLevelData) {
            console.log("FAILED with low-level error:");
            console.logBytes(lowLevelData);
            
            // Check for common error patterns
            if (lowLevelData.length >= 4) {
                bytes4 errorSelector = bytes4(lowLevelData);
                console.log("Error selector (hex):");
                console.logBytes4(errorSelector);
                
                if (errorSelector == 0x08c379a0) {
                    console.log("Standard Error(string) detected");
                } else {
                    console.log("Custom error or unknown selector");
                }
            }
        }
        
        vm.stopPrank();
        
        console.log("");
        console.log("=== DIAGNOSTIC CHECKS ===");
        
        // Check if trading rules are valid
        console.log("Checking trading rules...");
        try IOrderBook(pool).getTradingRules() returns (IOrderBook.TradingRules memory rules) {
            console.log("Trading rules retrieved:");
            console.log("- Min trade amount:", rules.minTradeAmount);
            console.log("- Min price movement:", rules.minPriceMovement);
            console.log("- Min amount movement:", rules.minAmountMovement);
            
            // Check if order meets requirements
            console.log("Order validation:");
            console.log("- Quantity >= minTradeAmount:", QUANTITY >= rules.minTradeAmount);
            console.log("- Price aligned with increment:", PRICE % rules.minPriceMovement == 0);
            
        } catch {
            console.log("Could not get trading rules");
        }
        
        // Check current order book state
        console.log("");
        console.log("Checking order book state...");
        try IOrderBook(pool).getBestPrice(IOrderBook.Side.BUY) returns (IOrderBook.PriceVolume memory bestBuy) {
            console.log("Best BUY price:", bestBuy.price);
            console.log("Available volume:", bestBuy.volume);
        } catch {
            console.log("Could not get best BUY price");
        }
        
        try IOrderBook(pool).getBestPrice(IOrderBook.Side.SELL) returns (IOrderBook.PriceVolume memory bestSell) {
            console.log("Best SELL price:", bestSell.price);
            console.log("Available volume:", bestSell.volume);
        } catch {
            console.log("Could not get best SELL price");
        }
        
        console.log("");
        console.log("=== ANALYSIS COMPLETE ===");
    }
}