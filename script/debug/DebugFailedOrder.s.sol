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

contract DebugFailedOrder is Script {
    // Current MM bot failure parameters
    address constant FAILED_TX_USER = 0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a;
    uint128 constant FAILED_PRICE = 3200000000; // 3200 USDC per WETH (from MM bot logs)
    uint128 constant FAILED_QUANTITY = 500000000000000000; // 0.5 WETH
    IOrderBook.Side constant FAILED_SIDE = IOrderBook.Side.BUY;
    
    function run() external {
        // Load deployment addresses
        string memory json = vm.readFile("./deployments/84532.json");
        
        address scaleXRouter = vm.parseJsonAddress(json, ".ScaleXRouter");
        address balanceManager = vm.parseJsonAddress(json, ".BalanceManager");
        address poolManager = vm.parseJsonAddress(json, ".PoolManager");
        address gsUSDC = vm.parseJsonAddress(json, ".gsUSDC");
        address gsWETH = vm.parseJsonAddress(json, ".gsWETH");
        address pool = vm.parseJsonAddress(json, ".WETH_USDC_Pool");
        
        console.log("=== DEBUGGING CURRENT MM BOT FAILURES ===");
        console.log("Using exact parameters from current MM bot simulation failures");
        console.log("User Address:", FAILED_TX_USER);
        console.log("Price: 3200 USDC per WETH");
        console.log("Quantity: 0.5 WETH");
        console.log("");
        
        // Check contract addresses
        console.log("=== CONTRACT ADDRESSES ===");
        console.log("ScaleXRouter:", scaleXRouter);
        console.log("BalanceManager:", balanceManager);
        console.log("PoolManager:", poolManager);
        console.log("gsUSDC (quote):", gsUSDC);
        console.log("gsWETH (base):", gsWETH);
        console.log("Pool:", pool);
        console.log("");
        
        // Check user balances
        console.log("=== USER TOKEN BALANCES ===");
        uint256 gsUSDCBalance = IERC20(gsUSDC).balanceOf(FAILED_TX_USER);
        uint256 gsWETHBalance = IERC20(gsWETH).balanceOf(FAILED_TX_USER);
        console.log("gsUSDC Balance:", gsUSDCBalance);
        console.log("gsWETH Balance:", gsWETHBalance);
        console.log("");
        
        // Check allowances
        console.log("=== USER ALLOWANCES TO SCALEX_ROUTER ===");
        uint256 gsUSDCAllowance = IERC20(gsUSDC).allowance(FAILED_TX_USER, scaleXRouter);
        uint256 gsWETHAllowance = IERC20(gsWETH).allowance(FAILED_TX_USER, scaleXRouter);
        console.log("gsUSDC Allowance:", gsUSDCAllowance);
        console.log("gsWETH Allowance:", gsWETHAllowance);
        console.log("");
        
        // Check allowances to BalanceManager
        console.log("=== USER ALLOWANCES TO BALANCE_MANAGER ===");
        uint256 gsUSDCAllowanceBM = IERC20(gsUSDC).allowance(FAILED_TX_USER, balanceManager);
        uint256 gsWETHAllowanceBM = IERC20(gsWETH).allowance(FAILED_TX_USER, balanceManager);
        console.log("gsUSDC Allowance to BalanceManager:", gsUSDCAllowanceBM);
        console.log("gsWETH Allowance to BalanceManager:", gsWETHAllowanceBM);
        console.log("");
        
        // Check BalanceManager balances
        console.log("=== BALANCE_MANAGER BALANCES ===");
        IBalanceManager bm = IBalanceManager(balanceManager);
        uint256 bmGsUSDCBalance = bm.getBalance(FAILED_TX_USER, Currency.wrap(gsUSDC));
        uint256 bmGsWETHBalance = bm.getBalance(FAILED_TX_USER, Currency.wrap(gsWETH));
        console.log("BalanceManager gsUSDC Balance:", bmGsUSDCBalance);
        console.log("BalanceManager gsWETH Balance:", bmGsWETHBalance);
        console.log("");
        
        // Calculate required amount for the order
        console.log("=== ORDER REQUIREMENTS ===");
        console.log("Order Side: BUY");
        console.log("Price:", FAILED_PRICE, "(3200 USDC per WETH)");
        console.log("Quantity:", FAILED_QUANTITY, "(0.5 WETH)");
        
        // For BUY orders, we need quote currency (gsUSDC)
        uint256 requiredGsUSDC = (uint256(FAILED_QUANTITY) * uint256(FAILED_PRICE)) / 1e18;
        console.log("Required gsUSDC for order:", requiredGsUSDC);
        console.log("Has sufficient gsUSDC balance:", gsUSDCBalance >= requiredGsUSDC);
        console.log("Has sufficient gsUSDC in BalanceManager:", bmGsUSDCBalance >= requiredGsUSDC);
        console.log("");
        
        // Check pool configuration
        console.log("=== POOL CONFIGURATION ===");
        PoolKey memory poolKey = PoolKey({
            baseCurrency: Currency.wrap(gsWETH),
            quoteCurrency: Currency.wrap(gsUSDC)
        });
        try IPoolManager(poolManager).getPool(poolKey) returns (IPoolManager.Pool memory poolData) {
            console.log("Pool exists and is configured");
            console.log("Pool OrderBook address:", address(poolData.orderBook));
            console.log("Pool Base Currency:", Currency.unwrap(poolData.baseCurrency));
            console.log("Pool Quote Currency:", Currency.unwrap(poolData.quoteCurrency));
            
            // Check if OrderBook is accessible
            try poolData.orderBook.getBestPrice(IOrderBook.Side.BUY) returns (IOrderBook.PriceVolume memory bestBuy) {
                console.log("OrderBook is accessible - Best BUY price:", bestBuy.price);
            } catch {
                console.log("ERROR: Cannot access OrderBook getBestPrice");
            }
        } catch {
            console.log("ERROR: Pool not found or not configured properly");
        }
        console.log("");
        
        // Check Router configuration
        console.log("=== ROUTER CONFIGURATION ===");
        IScaleXRouter router = IScaleXRouter(scaleXRouter);
        try router.getBestPrice(
            Currency.wrap(gsWETH),
            Currency.wrap(gsUSDC), 
            IOrderBook.Side.BUY
        ) returns (IOrderBook.PriceVolume memory bestPrice) {
            console.log("Router getBestPrice works - Price:", bestPrice.price, "Volume:", bestPrice.volume);
        } catch {
            console.log("ERROR: Router getBestPrice failed");
        }
        
        // Simulate the failed order parameters
        console.log("");
        console.log("=== SIMULATING ORDER PLACEMENT ===");
        
        // Build the pool struct as it was in the failed transaction
        IPoolManager.Pool memory poolForOrder = IPoolManager.Pool({
            baseCurrency: Currency.wrap(gsWETH),
            quoteCurrency: Currency.wrap(gsUSDC),
            orderBook: IOrderBook(pool) // Using pool address as orderBook
        });
        
        console.log("Attempting to simulate order with parameters:");
        console.log("- Pool base:", Currency.unwrap(poolForOrder.baseCurrency));
        console.log("- Pool quote:", Currency.unwrap(poolForOrder.quoteCurrency));
        console.log("- Price:", FAILED_PRICE);
        console.log("- Quantity:", FAILED_QUANTITY);
        console.log("- Side: BUY (0)");
        console.log("- TimeInForce: GTC (0)");
        console.log("- DepositAmount: 0");
        
        // Test with different gas limits to simulate MM bot constraints
        vm.startPrank(FAILED_TX_USER);
        
        console.log("=== TESTING WITH DIFFERENT GAS LIMITS ===");
        
        // Test 1: MM bot's old simulation gas limit (10M)
        console.log("Test 1: 10M gas limit (MM bot's old setting)");
        try router.placeLimitOrder{gas: 10000000}(
            poolForOrder,
            FAILED_PRICE,
            FAILED_QUANTITY,
            FAILED_SIDE,
            IOrderBook.TimeInForce.GTC,
            0
        ) returns (uint48 orderId1) {
            console.log("SUCCESS with 10M gas! Order ID:", orderId1);
            try router.cancelOrder{gas: 10000000}(poolForOrder, orderId1) {
                console.log("Order cancelled");
            } catch { console.log("Could not cancel"); }
        } catch Error(string memory reason) {
            console.log("FAILED with 10M gas, reason:", reason);
        } catch (bytes memory) {
            console.log("FAILED with 10M gas: OutOfGas");
        }
        console.log("");
        
        // Test 2: MM bot's new simulation gas limit (30M)
        console.log("Test 2: 30M gas limit (MM bot's new setting)");
        try router.placeLimitOrder{gas: 30000000}(
            poolForOrder,
            FAILED_PRICE + 1000000, // Slight price difference to avoid duplicate
            FAILED_QUANTITY,
            FAILED_SIDE,
            IOrderBook.TimeInForce.GTC,
            0
        ) returns (uint48 orderId2) {
            console.log("SUCCESS with 30M gas! Order ID:", orderId2);
            try router.cancelOrder{gas: 30000000}(poolForOrder, orderId2) {
                console.log("Order cancelled");
            } catch { console.log("Could not cancel"); }
        } catch Error(string memory reason) {
            console.log("FAILED with 30M gas, reason:", reason);
        } catch (bytes memory) {
            console.log("FAILED with 30M gas: OutOfGas");
        }
        console.log("");
        
        // Test 3: Unlimited gas (what we saw in previous run)
        console.log("Test 3: Unlimited gas (Forge default)");
        try router.placeLimitOrder(
            poolForOrder,
            FAILED_PRICE + 2000000, // Another price to avoid duplicates
            FAILED_QUANTITY,
            FAILED_SIDE,
            IOrderBook.TimeInForce.GTC,
            0
        ) returns (uint48 orderId3) {
            console.log("SUCCESS with unlimited gas! Order ID:", orderId3);
            try router.cancelOrder(poolForOrder, orderId3) {
                console.log("Order cancelled");
            } catch { console.log("Could not cancel"); }
        } catch Error(string memory reason) {
            console.log("FAILED with unlimited gas, reason:", reason);
        } catch (bytes memory) {
            console.log("FAILED with unlimited gas: Unexpected error");
        }
        
        vm.stopPrank();
        
        console.log("");
        console.log("=== DEBUG COMPLETE ===");
    }
}