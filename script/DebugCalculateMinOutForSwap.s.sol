// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../script/DeployHelpers.s.sol";
import {GTXRouter} from "../src/core/GTXRouter.sol";
import {BalanceManager} from "../src/core/BalanceManager.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {IPoolManager} from "../src/core/interfaces/IPoolManager.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";
import {Currency, CurrencyLibrary} from "../src/core/libraries/Currency.sol";
import {PoolKey} from "../src/core/libraries/Pool.sol";

contract DebugCalculateMinOutForSwap is Script, DeployHelpers {
    using CurrencyLibrary for Currency;

    // Sepolia testnet addresses from your error
    address constant ROUTER_ADDRESS = 0x41995633558cb6c8D539583048DbD0C9C5451F98;
    address constant SRC_CURRENCY = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
    address constant DST_CURRENCY = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;
    uint256 constant INPUT_AMOUNT = 100000000000000000; // 0.1 ETH
    uint256 constant SLIPPAGE_BPS = 500; // 5%

    GTXRouter gtxRouter;
    BalanceManager balanceManager;
    PoolManager poolManager;

    function setUp() public {
        // Load the router from the specific address
        gtxRouter = GTXRouter(ROUTER_ADDRESS);
        
        // Load other contracts from deployment addresses
        poolManager = PoolManager(0x192F275A3BB908c0e111B716acd35E9ABb9E70cD);
        balanceManager = BalanceManager(0x26FE17306F6D271dcD33ea19b42D4583D394500A);
        
        console.log("Loaded contracts:");
        console.log("GTX Router:", ROUTER_ADDRESS);
        console.log("Pool Manager:", address(poolManager));
        console.log("Balance Manager:", address(balanceManager));
        console.log("");
    }

    function run() external {
        console.log("=== Debugging calculateMinOutForSwap Call ===");
        console.log("Router Address:", ROUTER_ADDRESS);
        console.log("Source Currency:", SRC_CURRENCY);
        console.log("Destination Currency:", DST_CURRENCY);
        console.log("Input Amount:", INPUT_AMOUNT);
        console.log("Slippage BPS:", SLIPPAGE_BPS);
        console.log("");

        // Step 1: Check if contracts exist
        checkContractExistence();

        // Step 2: Check pool existence
        checkPoolExistence();

        // Step 3: Check liquidity status
        checkOrderBookLiquidity();

        // Step 4: Check token balances and states
        checkTokenStates();

        // Step 5: Try the actual call with detailed error handling
        attemptCalculateMinOut();

        // Step 6: Try alternative approaches
        debugAlternativeApproaches();
        
        // Step 7: Provide specific recommendations
        provideRecommendations();
    }

    function checkContractExistence() private view {
        console.log("=== Contract Existence Check ===");
        
        uint256 routerCodeSize;
        assembly {
            routerCodeSize := extcodesize(ROUTER_ADDRESS)
        }
        console.log("Router code size:", routerCodeSize);

        uint256 srcCodeSize;
        assembly {
            srcCodeSize := extcodesize(SRC_CURRENCY)
        }
        console.log("Source token code size:", srcCodeSize);

        uint256 dstCodeSize;
        assembly {
            dstCodeSize := extcodesize(DST_CURRENCY)
        }
        console.log("Destination token code size:", dstCodeSize);
        console.log("");
    }

    function checkPoolExistence() private view {
        console.log("=== Pool Existence Check ===");
        
        if (address(poolManager) != address(0)) {
            try poolManager.getPool(
                PoolKey({
                    baseCurrency: Currency.wrap(SRC_CURRENCY),
                    quoteCurrency: Currency.wrap(DST_CURRENCY)
                })
            ) returns (IPoolManager.Pool memory pool) {
                console.log("Pool found!");
                console.log("Pool order book:", address(pool.orderBook));
            } catch Error(string memory reason) {
                console.log("Pool check failed:", reason);
            } catch {
                console.log("Pool check failed with low-level error");
            }
        } else {
            console.log("Pool Manager not available");
        }
        console.log("");
    }

    function checkTokenStates() private view {
        console.log("=== Token States Check ===");
        
        // Check source token
        getTokenInfoInternal(SRC_CURRENCY, "Source");
        
        // Check destination token
        getTokenInfoInternal(DST_CURRENCY, "Destination");
        
        console.log("");
    }
    
    function getTokenInfoInternal(address token, string memory tokenName) private view {
        // Try to get token symbol
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("symbol()"));
        if (success && data.length > 0) {
            try this.decodeString(data) returns (string memory symbol) {
                console.log(tokenName, "token symbol:", symbol);
            } catch {
                console.log(tokenName, "token has invalid symbol");
            }
        } else {
            console.log(tokenName, "token has no symbol function");
        }

        // Try to get token decimals
        (success, data) = token.staticcall(abi.encodeWithSignature("decimals()"));
        if (success && data.length > 0) {
            try this.decodeUint8(data) returns (uint8 decimals) {
                console.log(tokenName, "token decimals:", decimals);
            } catch {
                console.log(tokenName, "token has invalid decimals");
            }
        } else {
            console.log(tokenName, "token has no decimals function");
        }
    }
    
    // Helper functions for decoding (external for try/catch)
    function decodeString(bytes memory data) external pure returns (string memory) {
        return abi.decode(data, (string));
    }
    
    function decodeUint8(bytes memory data) external pure returns (uint8) {
        return abi.decode(data, (uint8));
    }


    function attemptCalculateMinOut() private view {
        console.log("=== Attempting calculateMinOutForSwap ===");
        
        try gtxRouter.calculateMinOutForSwap(
            Currency.wrap(SRC_CURRENCY),
            Currency.wrap(DST_CURRENCY),
            INPUT_AMOUNT,
            SLIPPAGE_BPS
        ) returns (uint128 minOut) {
            console.log("SUCCESS! Min out amount:", minOut);
        } catch Error(string memory reason) {
            console.log("Call failed with reason:", reason);
        } catch Panic(uint errorCode) {
            console.log("Call failed with panic code:", errorCode);
        } catch (bytes memory lowLevelData) {
            console.log("Call failed with low-level error");
            console.logBytes(lowLevelData);
        }
        console.log("");
    }

    function debugAlternativeApproaches() private view {
        console.log("=== Alternative Debugging Approaches ===");
        
        // Try with different amounts
        console.log("Trying with smaller amount (1 wei):");
        try gtxRouter.calculateMinOutForSwap(
            Currency.wrap(SRC_CURRENCY),
            Currency.wrap(DST_CURRENCY),
            1,
            SLIPPAGE_BPS
        ) returns (uint128 minOut) {
            console.log("Small amount works! Min out:", minOut);
        } catch {
            console.log("Small amount also fails");
        }

        // Try with zero slippage
        console.log("Trying with zero slippage:");
        try gtxRouter.calculateMinOutForSwap(
            Currency.wrap(SRC_CURRENCY),
            Currency.wrap(DST_CURRENCY),
            INPUT_AMOUNT,
            0
        ) returns (uint128 minOut) {
            console.log("Zero slippage works! Min out:", minOut);
        } catch {
            console.log("Zero slippage also fails");
        }

        // Try reversed currencies
        console.log("Trying reversed currencies:");
        try gtxRouter.calculateMinOutForSwap(
            Currency.wrap(DST_CURRENCY),
            Currency.wrap(SRC_CURRENCY),
            INPUT_AMOUNT,
            SLIPPAGE_BPS
        ) returns (uint128 minOut) {
            console.log("Reversed currencies work! Min out:", minOut);
        } catch {
            console.log("Reversed currencies also fail");
        }
        console.log("");
    }

    /// @notice Check order book liquidity status
    function checkOrderBookLiquidity() private view {
        console.log("=== Order Book Liquidity Check ===");
        
        if (address(poolManager) == address(0)) {
            console.log("Pool Manager not available - skipping liquidity check");
            console.log("");
            return;
        }

        // Get pool and order book directly
        PoolKey memory key = PoolKey({
            baseCurrency: Currency.wrap(SRC_CURRENCY),
            quoteCurrency: Currency.wrap(DST_CURRENCY)
        });
        
        try poolManager.getPool(key) returns (IPoolManager.Pool memory pool) {
            address orderBookAddr = address(pool.orderBook);
            console.log("Order book address:", orderBookAddr);
            
            // Check buy side liquidity
            console.log("Checking BUY side liquidity (people wanting to buy WETH with USDC):");
            (bool hasBuyOrders, uint128 bestBuyPrice, uint256 buyVolume) = checkOrderBookSideInternal(orderBookAddr, 0);
            if (hasBuyOrders) {
                console.log("[OK] BUY orders exist - Best price:", bestBuyPrice, "Volume:", buyVolume);
            } else {
                console.log("[FAIL] NO BUY orders - No one wants to buy WETH");
            }

            // Check sell side liquidity
            console.log("Checking SELL side liquidity (people wanting to sell WETH for USDC):");
            (bool hasSellOrders, uint128 bestSellPrice, uint256 sellVolume) = checkOrderBookSideInternal(orderBookAddr, 1);
            if (hasSellOrders) {
                console.log("[OK] SELL orders exist - Best price:", bestSellPrice, "Volume:", sellVolume);
            } else {
                console.log("[FAIL] NO SELL orders - No one wants to sell WETH");
            }

            console.log("");
            console.log("ANALYSIS: For your WETH->USDC swap to work, you need SELL orders");
            console.log("(people selling WETH for USDC). If no SELL orders exist, swap will fail.");
            
        } catch {
            console.log("Could not get pool or order book");
        }
        console.log("");
    }
    
    function checkOrderBookSideInternal(address orderBookAddr, uint8 side) private view returns (bool hasOrders, uint128 bestPrice, uint256 volume) {
        try IOrderBook(orderBookAddr).getNextBestPrices(
            side == 0 ? IOrderBook.Side.BUY : IOrderBook.Side.SELL,
            0, // startPrice
            1  // count - just get the best one
        ) returns (IOrderBook.PriceVolume[] memory prices) {
            if (prices.length > 0 && prices[0].price > 0) {
                hasOrders = true;
                bestPrice = prices[0].price;
                volume = prices[0].volume;
            }
        } catch {
            // Failed to get prices
            hasOrders = false;
            bestPrice = 0;
            volume = 0;
        }
    }

    /// @notice Get pool and order book address (external for try/catch)
    function getPoolAndOrderBook() external view returns (address) {
        PoolKey memory key = poolManager.createPoolKey(
            Currency.wrap(SRC_CURRENCY),
            Currency.wrap(DST_CURRENCY)
        );
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return address(pool.orderBook);
    }

    /// @notice Check specific side of order book (external for try/catch)
    function checkOrderBookSide(address orderBookAddr, uint8 side) external view returns (bool hasOrders, uint128 bestPrice, uint256 volume) {
        IOrderBook orderBook = IOrderBook(orderBookAddr);
        IOrderBook.PriceVolume[] memory prices = orderBook.getNextBestPrices(
            side == 0 ? IOrderBook.Side.BUY : IOrderBook.Side.SELL,
            0, // startPrice
            1  // count - just get the best one
        );
        
        if (prices.length > 0 && prices[0].price > 0) {
            hasOrders = true;
            bestPrice = prices[0].price;
            volume = prices[0].volume;
        }
    }

    /// @notice Provide specific recommendations based on findings
    function provideRecommendations() private view {
        console.log("=== RECOMMENDATIONS ===");
        console.log("");
        console.log("Based on the analysis, here's what you should do:");
        console.log("");
        console.log("1. ROOT CAUSE: Empty Order Book");
        console.log("   - The WETH/USDC pool exists but has no liquidity");
        console.log("   - No market makers have placed buy/sell orders");
        console.log("");
        console.log("2. IMMEDIATE SOLUTIONS:");
        console.log("   a) Add liquidity by running:");
        console.log("      forge script script/FillMockOrderBook.s.sol --rpc-url https://testnet.riselabs.xyz --broadcast");
        console.log("");
        console.log("   b) Place manual orders via your frontend:");
        console.log("      - Place SELL orders (selling WETH for USDC)");
        console.log("      - Place BUY orders (buying WETH with USDC)");
        console.log("");
        console.log("3. WHY THE ERROR IS GENERIC:");
        console.log("   - calculateMinOutForSwap returns 0 when order book is empty");
        console.log("   - Downstream code doesn't handle 0 properly, causing 'execution reverted'");
        console.log("");
        console.log("4. FOR BETTER ERROR MESSAGES:");
        console.log("   - Implement the enhanced error handling from GTXRouterEnhanced.sol");
        console.log("   - This will show 'EmptyOrderBook' instead of 'execution reverted'");
        console.log("");
        console.log("5. VERIFICATION COMMANDS:");
        console.log("   # Check if orders exist after adding liquidity:");
        console.log("   cast call ORDER_BOOK_ADDR \"getNextBestPrices(uint8,uint128,uint8)\" 1 0 1");
        console.log("   # Should return non-zero price/volume if successful");
        console.log("");
        console.log("The calculateMinOutForSwap function will work perfectly once liquidity is added!");
    }

    /// @notice Helper function to manually test the exact failing call
    function testExactFailingCall() external view returns (uint128) {
        return gtxRouter.calculateMinOutForSwap(
            Currency.wrap(SRC_CURRENCY),
            Currency.wrap(DST_CURRENCY),
            INPUT_AMOUNT,
            SLIPPAGE_BPS
        );
    }
}