// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Test, console} from "forge-std/Test.sol";
import {IPoolManager} from "../src/core/interfaces/IPoolManager.sol";
import {IGTXRouter} from "../src/core/interfaces/IGTXRouter.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {PoolKey} from "../src/core/libraries/Pool.sol";

contract SimpleLiquidityCheck is Script {
    // Addresses from deployment file
    address constant ROUTER = 0x41995633558cb6c8D539583048DbD0C9C5451F98;
    address constant POOL_MANAGER = 0x192F275A3BB908c0e111B716acd35E9ABb9E70cD;
    address constant WETH = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
    address constant USDC = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;
    
    // Test parameters
    uint256 constant INPUT_AMOUNT = 100000000000000000; // 0.1 ETH
    uint256 constant SLIPPAGE_BPS = 500; // 5%

    function run() external view {
        console.log("=== GTX Router Liquidity Check ===");
        
        // First validate all contract addresses
        if (!validateContracts()) {
            console.log("Contract validation failed. Stopping execution.");
            return;
        }
        
        // Get the pool for WETH/USDC
        PoolKey memory poolKey = createPoolKey();
        console.log("Pool Key created for WETH/USDC pair");
        
        // Get the pool from PoolManager
        IPoolManager.Pool memory pool = getPoolFromManager(poolKey);
        if (address(pool.orderBook) == address(0)) {
            console.log("ERROR: Pool does not exist for WETH/USDC");
            return;
        }
        
        console.log("Pool found - OrderBook:", address(pool.orderBook));
        console.log("");
        
        // Check liquidity using GTXRouter
        checkPoolLiquidityViaRouter(pool);
        
        console.log("");
        console.log("=== Analysis ===");
        console.log("For WETH->USDC swap to work, you need SELL orders");
        console.log("If no liquidity is found, run: forge script script/FillMockOrderBook.s.sol --rpc-url https://testnet.riselabs.xyz --broadcast");
    }
    
    function validateContracts() internal view returns (bool) {
        console.log("=== Contract Validation ===");
        
        bool allValid = true;
        
        // Check ROUTER
        if (!isContract(ROUTER)) {
            console.log("[ERROR] ROUTER address has no code deployed:", ROUTER);
            allValid = false;
        } else {
            console.log("[OK] GTX Router contract exists:", ROUTER);
        }
        
        // Check POOL_MANAGER
        if (!isContract(POOL_MANAGER)) {
            console.log("[ERROR] POOL_MANAGER address has no code deployed:", POOL_MANAGER);
            allValid = false;
        } else {
            console.log("[OK] Pool Manager contract exists:", POOL_MANAGER);
        }
        
        // Check WETH
        if (!isContract(WETH)) {
            console.log("[ERROR] WETH address has no code deployed:", WETH);
            allValid = false;
        } else {
            console.log("[OK] WETH contract exists:", WETH);
        }
        
        // Check USDC
        if (!isContract(USDC)) {
            console.log("[ERROR] USDC address has no code deployed:", USDC);
            allValid = false;
        } else {
            console.log("[OK] USDC contract exists:", USDC);
        }
        
        console.log("");
        return allValid;
    }
    
    function createPoolKey() internal pure returns (PoolKey memory) {
        return PoolKey({
            baseCurrency: Currency.wrap(WETH),
            quoteCurrency: Currency.wrap(USDC)
        });
    }
    
    function getPoolFromManager(PoolKey memory poolKey) internal view returns (IPoolManager.Pool memory) {
        try IPoolManager(POOL_MANAGER).getPool(poolKey) returns (IPoolManager.Pool memory pool) {
            return pool;
        } catch {
            // Return empty pool if call fails
            return IPoolManager.Pool({
                orderBook: IOrderBook(address(0)),
                baseCurrency: Currency.wrap(address(0)),
                quoteCurrency: Currency.wrap(address(0))
            });
        }
    }
    
    function checkPoolLiquidityViaRouter(IPoolManager.Pool memory pool) internal view {
        console.log("=== Checking Liquidity via GTX Router ===");
        
        // Check BUY side liquidity
        console.log("Checking BUY side liquidity:");
        checkRouterPrices(pool, IOrderBook.Side.BUY);
        
        console.log("");
        
        // Check SELL side liquidity  
        console.log("Checking SELL side liquidity:");
        checkRouterPrices(pool, IOrderBook.Side.SELL);
    }
    
    function checkRouterPrices(IPoolManager.Pool memory pool, IOrderBook.Side side) internal view {
        try IGTXRouter(ROUTER).getNextBestPrices(pool, side, 0, 3) returns (IOrderBook.PriceVolume[] memory prices) {
            console.log("  Call successful - Found", prices.length, "price levels");
            
            if (prices.length == 0) {
                console.log("  [EMPTY] No orders available on this side");
            } else {
                for (uint i = 0; i < prices.length; i++) {
                    console.log("    Level", i + 1, ":");
                    console.log("      Price:", prices[i].price);
                    console.log("      Volume:", prices[i].volume);
                    
                    if (prices[i].price > 0 && prices[i].volume > 0) {
                        console.log("      [OK] Valid liquidity found");
                    } else {
                        console.log("      [EMPTY] Invalid price/volume");
                    }
                }
            }
        } catch Error(string memory reason) {
            console.log("  [ERROR] Router call failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("  [ERROR] Router call failed with low-level error");
            if (lowLevelData.length > 0) {
                console.log("  Error data:");
                logBytes32(lowLevelData);
            } else {
                console.log("  Empty revert data");
            }
        }
    }
    
    
    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
    
    
    // Helper function to log bytes data in hex format (for debugging)
    function logBytes32(bytes memory data) internal view {
        if (data.length == 0) {
            console.log("  (empty)");
            return;
        }
        
        // Log in chunks of 32 bytes for readability
        for (uint i = 0; i < data.length; i += 32) {
            bytes32 chunk;
            uint remainingBytes = data.length - i;
            uint chunkSize = remainingBytes > 32 ? 32 : remainingBytes;
            
            assembly {
                chunk := mload(add(add(data, 0x20), i))
            }
            
            if (chunkSize == 32) {
                console.log("  ", vm.toString(chunk));
            } else {
                console.log("  ", vm.toString(chunk));
                console.log("    (partial bytes:", chunkSize, ")");
            }
        }
    }
}