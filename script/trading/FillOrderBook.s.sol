// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/libraries/Pool.sol";

import "../../src/core/resolvers/PoolManagerResolver.sol";
import "../../src/mocks/MockToken.sol";



contract FillMockOrderBook is Script, DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "BalanceManager";
    string constant POOL_MANAGER_ADDRESS = "PoolManager";
    string constant ScaleX_ROUTER_ADDRESS = "ScaleXRouter";
    string constant WETH_ADDRESS = "sxWETH";

    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    ScaleXRouter scalexRouter;
    PoolManagerResolver poolManagerResolver;

    // Tokens
    IERC20 tokenWETH;
    IERC20 tokenQuote;

    // Quote currency info
    string quoteCurrency;
    string sxQuoteKey;
    uint8 quoteDecimals;

    // Track order IDs for verification
    uint48[] buyOrderIds;
    uint48[] sellOrderIds;
    
    // Store the actual deployer address for verification
    address deployerAddress;

    function setUp() public {
        loadDeployments();
        loadContracts();

        // Deploy the resolver
        poolManagerResolver = new PoolManagerResolver();
    }

    function loadContracts() private {
        // Load core contracts - try new naming first, fallback to old naming
        address bmAddr = deployed["PROXY_BALANCEMANAGER"].isSet ? deployed["PROXY_BALANCEMANAGER"].addr : deployed[BALANCE_MANAGER_ADDRESS].addr;
        address pmAddr = deployed["PROXY_POOLMANAGER"].isSet ? deployed["PROXY_POOLMANAGER"].addr : deployed[POOL_MANAGER_ADDRESS].addr;
        address routerAddr = deployed["PROXY_ROUTER"].isSet ? deployed["PROXY_ROUTER"].addr : deployed[ScaleX_ROUTER_ADDRESS].addr;

        balanceManager = BalanceManager(bmAddr);
        poolManager = PoolManager(pmAddr);
        scalexRouter = ScaleXRouter(routerAddr);

        // Get quote currency from environment
        quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        quoteDecimals = uint8(vm.envOr("QUOTE_DECIMALS", uint256(6)));
        sxQuoteKey = string.concat("sx", quoteCurrency);

        // Load regular tokens for funding (will be converted to synthetic)
        if (deployed["WETH"].isSet) {
            tokenWETH = IERC20(deployed["WETH"].addr);
        } else if (deployed[WETH_ADDRESS].isSet) {
            tokenWETH = IERC20(deployed[WETH_ADDRESS].addr);
        } else {
            revert("WETH token not found in deployments");
        }

        if (deployed[quoteCurrency].isSet) {
            tokenQuote = IERC20(deployed[quoteCurrency].addr);
        } else {
            revert(string.concat(quoteCurrency, " token not found in deployments"));
        }
    }

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        fillETHUSDCOrderBook();

        verifyOrders();

        checkOrderBookDepth();

        vm.stopBroadcast();
    }

    function runConfigurable(
        uint128 buyStartPrice,
        uint128 buyEndPrice,
        uint128 sellStartPrice,
        uint128 sellEndPrice,
        uint128 priceStep,
        uint8 numOrders,
        uint128 buyQuantity,
        uint128 sellQuantity,
        uint256 ethAmount,
        uint256 usdcAmount
    ) public {
        uint256 deployerPrivateKey = getDeployerKey();
        deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        fillETHUSDCOrderBookConfigurable(
            buyStartPrice,
            buyEndPrice,
            sellStartPrice,
            sellEndPrice,
            priceStep,
            numOrders,
            buyQuantity,
            sellQuantity,
            ethAmount,
            usdcAmount
        );

        verifyOrders();

        checkOrderBookDepth();

        vm.stopBroadcast();
    }

    function fillETHUSDCOrderBook() private {
        console.log(string.concat("\n=== Filling ETH/", quoteCurrency, " Order Book ==="));

        // Get deployed synthetic tokens for trading
        address wethAddr = deployed["sxWETH"].addr;
        address quoteAddr = deployed[sxQuoteKey].addr;

        Currency weth = Currency.wrap(wethAddr);
        Currency quote = Currency.wrap(quoteAddr);

        console.log(string.concat("Looking for existing WETH/", quoteCurrency, " pool..."));
        
        // Try to get existing pool - don't try to create one
        PoolKey memory poolKey = poolManager.createPoolKey(weth, quote);
        IPoolManager.Pool memory pool;

        try poolManager.getPool(poolKey) returns (IPoolManager.Pool memory retrievedPool) {
            pool = retrievedPool;
            console.log(string.concat("[OK] Found existing WETH/", quoteCurrency, " pool successfully"));
        } catch {
            console.log(string.concat("[WARNING] No WETH/", quoteCurrency, " pool found"));
            console.log("[INFO] Pool creation requires special permissions");
            console.log("[INFO] Try running 'make create-trading-pools' first");
            console.log("[INFO] Continuing with basic token setup for demonstration...");
            return;
        }
        
        // Verify pool has valid addresses
        if (Currency.unwrap(pool.baseCurrency) == address(0) || Currency.unwrap(pool.quoteCurrency) == address(0)) {
            console.log("[ERROR] Pool has invalid currency addresses");
            console.log("Base currency:", Currency.unwrap(pool.baseCurrency));
            console.log("Quote currency:", Currency.unwrap(pool.quoteCurrency));
            return;
        }
        
        console.log("Pool baseCurrency:", Currency.unwrap(pool.baseCurrency));
        console.log("Pool quoteCurrency:", Currency.unwrap(pool.quoteCurrency));
        console.log("Pool orderBook:", address(pool.orderBook));

        // Calculate amounts based on quote currency decimals
        uint256 quoteFundAmount = 10_000 * (10 ** quoteDecimals); // 10,000 quote currency
        uint128 buyStartPrice = uint128(1900 * (10 ** quoteDecimals));
        uint128 buyEndPrice = uint128(1980 * (10 ** quoteDecimals));
        uint128 sellStartPrice = uint128(2000 * (10 ** quoteDecimals));
        uint128 sellEndPrice = uint128(2100 * (10 ** quoteDecimals));
        uint128 priceStep = uint128(10 * (10 ** quoteDecimals));

        // Setup sender with regular tokens (will be converted to synthetic via deposits)
        _setupFunds(5e18, quoteFundAmount); // 5 ETH, 10,000 quote currency (reduced amounts)
        // Convert regular tokens to synthetic tokens via BalanceManager deposits
        _makeLocalDeposits(5e18, quoteFundAmount); // Deposit to get synthetic tokens

        // Place BUY orders (bids) - ascending price from 1900 to 1980
        // Use smaller order size (0.005 ETH) so trading bots can consume with larger orders
        _placeBuyOrders(pool, buyStartPrice, buyEndPrice, priceStep, 10, 5e15);

        // Place SELL orders (asks) - ascending price from 2000 to 2100
        // Use smaller order size (0.005 ETH) so trading bots can consume with larger orders
        _placeSellOrders(pool, sellStartPrice, sellEndPrice, priceStep, 10, 5e15);

        // Print summary
        console.log(string.concat("ETH/", quoteCurrency, " order book filled with:"));
        console.log(string.concat("- BUY orders from 1900 ", quoteCurrency, " to 1980 ", quoteCurrency));
        console.log(string.concat("- SELL orders from 2000 ", quoteCurrency, " to 2100 ", quoteCurrency));
    }

    function fillETHUSDCOrderBookConfigurable(
        uint128 buyStartPrice,
        uint128 buyEndPrice,
        uint128 sellStartPrice,
        uint128 sellEndPrice,
        uint128 priceStep,
        uint8 numOrders,
        uint128 buyQuantity,
        uint128 sellQuantity,
        uint256 ethAmount,
        uint256 usdcAmount
    ) private {
        console.log("\n=== Filling ETH/USDC Order Book (Configurable) ===");

        // Get currency objects
        Currency weth = Currency.wrap(address(tokenWETH));
        Currency quote = Currency.wrap(address(tokenQuote));

        // Create PoolKey and get the pool (matching deployment order)
        PoolKey memory poolKey = poolManager.createPoolKey(weth, quote);
        IPoolManager.Pool memory pool = poolManager.getPool(poolKey);

        // Setup sender with configurable funds
        _setupFunds(ethAmount, usdcAmount);

        // Place BUY orders (bids) with configurable parameters
        _placeBuyOrders(pool, buyStartPrice, buyEndPrice, priceStep, numOrders, buyQuantity);

        // Place SELL orders (asks) with configurable parameters
        _placeSellOrders(pool, sellStartPrice, sellEndPrice, priceStep, numOrders, sellQuantity);

        // Print summary
        console.log("ETH/USDC order book filled with:");
        console.log("- BUY orders from %s to %s USDC", buyStartPrice, buyEndPrice);
        console.log("- SELL orders from %s to %s USDC", sellStartPrice, sellEndPrice);
    }

    function runWithTokens(string memory token0Key, string memory token1Key) public {
        loadDeployments();

        // Load token addresses from deployment file
        address token0Address = deployed[token0Key].addr;
        address token1Address = deployed[token1Key].addr;

        require(token0Address != address(0), string(abi.encodePacked("Token not found: ", token0Key)));
        require(token1Address != address(0), string(abi.encodePacked("Token not found: ", token1Key)));

        console.log("Using tokens:");
        console.log("Token0 (%s):", token0Key, token0Address);
        console.log("Token1 (%s):", token1Key, token1Address);

        // Load core contracts
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
        scalexRouter = ScaleXRouter(deployed[ScaleX_ROUTER_ADDRESS].addr);

        // Use the provided tokens instead of hardcoded ones
        tokenWETH = IERC20(token0Address);
        tokenQuote = IERC20(token1Address);

        // Deploy the resolver
        poolManagerResolver = new PoolManagerResolver();

        // Get currency objects
        Currency weth = Currency.wrap(address(tokenWETH));
        Currency quote = Currency.wrap(address(tokenQuote));

        // Create PoolKey and get the pool (matching deployment order)
        PoolKey memory poolKey = poolManager.createPoolKey(weth, quote);
        IPoolManager.Pool memory pool = poolManager.getPool(poolKey);

        // Calculate amounts based on quote currency decimals
        uint128 buyStartPrice = uint128(1900 * (10 ** quoteDecimals));
        uint128 buyEndPrice = uint128(1980 * (10 ** quoteDecimals));
        uint128 sellStartPrice = uint128(2000 * (10 ** quoteDecimals));
        uint128 sellEndPrice = uint128(2100 * (10 ** quoteDecimals));
        uint128 priceStep = uint128(10 * (10 ** quoteDecimals));

        // Place BUY orders (bids) - ascending price from 1900 to 1980
        // Use smaller order size (0.005 ETH) so trading bots can consume with larger orders
        _placeBuyOrders(pool, buyStartPrice, buyEndPrice, priceStep, 10, 5e15);

        // Place SELL orders (asks) - ascending price from 2000 to 2100
        // Use smaller order size (0.005 ETH) so trading bots can consume with larger orders
        _placeSellOrders(pool, sellStartPrice, sellEndPrice, priceStep, 10, 5e15);

        console.log("Order book filled with custom tokens:");
        console.log("Token0 (%s):", token0Key, token0Address);
        console.log("Token1 (%s):", token1Key, token1Address);
    }

    function _setupFunds(uint256 ethAmount, uint256 quoteAmount) private {
        console.log("\n=== Setting up funds ===");
        console.log("Minting ETH amount:", ethAmount, "(raw)");
        console.log("Minting ETH amount:", ethAmount / 1e18, "ETH");
        console.log(string.concat("Minting ", quoteCurrency, " amount:"), quoteAmount, "(raw)");
        console.log(string.concat("Minting ", quoteCurrency, " amount:"), quoteAmount / 1e6, quoteCurrency);

        // Check if tokens support minting (have mint function)
        try MockToken(address(tokenWETH)).mint(msg.sender, ethAmount) {
            console.log("Minted WETH successfully");
        } catch {
            console.log("WETH minting failed - using existing supply");
        }

        try MockToken(address(tokenQuote)).mint(msg.sender, quoteAmount) {
            console.log(string.concat("Minted ", quoteCurrency, " successfully"));
        } catch {
            console.log(string.concat(quoteCurrency, " minting failed - using existing supply"));
        }

        // Approve tokens for both ScaleX router and BalanceManager (higher amounts for multiple orders)
        bool wethApprovalRouter = IERC20(address(tokenWETH)).approve(address(scalexRouter), ethAmount * 2);
        bool quoteApprovalRouter = IERC20(address(tokenQuote)).approve(address(scalexRouter), quoteAmount * 2);
        bool wethApprovalBM = IERC20(address(tokenWETH)).approve(address(balanceManager), ethAmount * 2);
        bool quoteApprovalBM = IERC20(address(tokenQuote)).approve(address(balanceManager), quoteAmount * 2);

        console.log("WETH approval (router):", wethApprovalRouter);
        console.log(string.concat(quoteCurrency, " approval (router):"), quoteApprovalRouter);
        console.log("WETH approval (BalanceManager):", wethApprovalBM);
        console.log(string.concat(quoteCurrency, " approval (BalanceManager):"), quoteApprovalBM);

        // Verify final balances and allowances
        console.log("Final WETH balance:", tokenWETH.balanceOf(msg.sender) / 1e18, "ETH");
        console.log(string.concat("Final ", quoteCurrency, " balance:"), tokenQuote.balanceOf(msg.sender) / 1e6, quoteCurrency);
        console.log(
            "Final WETH allowance:",
            IERC20(address(tokenWETH)).allowance(msg.sender, address(scalexRouter)) / 1e18,
            "ETH"
        );
        console.log(
            string.concat("Final ", quoteCurrency, " allowance:"),
            IERC20(address(tokenQuote)).allowance(msg.sender, address(scalexRouter)) / 1e6,
            quoteCurrency
        );
        console.log("Funds setup complete\n");
    }

    function _makeLocalDeposits(uint256 ethAmount, uint256 quoteAmount) private {
        console.log("\n=== Making Local Deposits to BalanceManager ===");
        console.log("Depositing ETH amount:", ethAmount / 1e18, "ETH");
        console.log(string.concat("Depositing ", quoteCurrency, " amount:"), quoteAmount / 1e6, quoteCurrency);

        // Deposit real WETH to BalanceManager (will receive synthetic balance)
        balanceManager.depositLocal(address(tokenWETH), ethAmount, msg.sender);
        console.log("[SUCCESS] WETH deposited to BalanceManager");

        // Deposit real quote currency to BalanceManager (will receive synthetic balance)
        balanceManager.depositLocal(address(tokenQuote), quoteAmount, msg.sender);
        console.log(string.concat("[SUCCESS] ", quoteCurrency, " deposited to BalanceManager"));

        // Verify BalanceManager balances for the deposited tokens
        uint256 wethBalance = balanceManager.getBalance(msg.sender, Currency.wrap(address(tokenWETH)));
        uint256 quoteBalance = balanceManager.getBalance(msg.sender, Currency.wrap(address(tokenQuote)));

        console.log("BalanceManager WETH balance:", wethBalance / 1e18, "ETH");
        console.log(string.concat("BalanceManager ", quoteCurrency, " balance:"), quoteBalance / 1e6, quoteCurrency);

        // Check token balances in BalanceManager
        uint256 bmWethBalance = balanceManager.getBalance(msg.sender, Currency.wrap(address(tokenWETH)));
        uint256 bmQuoteBalance = balanceManager.getBalance(msg.sender, Currency.wrap(address(tokenQuote)));

        console.log("BalanceManager WETH balance:", bmWethBalance / 1e18, "ETH");
        console.log(string.concat("BalanceManager ", quoteCurrency, " balance:"), bmQuoteBalance / 1e6, quoteCurrency);
        console.log("Local deposits complete\n");
    }

    function _placeBuyOrders(
        IPoolManager.Pool memory pool,
        uint128 startPrice,
        uint128 endPrice,
        uint128 priceStep,
        uint8 numOrders,
        uint128 quantity
    ) private {
        uint128 currentPrice = startPrice;
        uint8 ordersPlaced = 0;

        while (currentPrice <= endPrice && ordersPlaced < numOrders) {
            console.log("\n--- Placing BUY Order #", ordersPlaced + 1, "---");
            console.log("Price:", currentPrice, "(raw)");
            console.log(string.concat("Price (", quoteCurrency, "):"), currentPrice / 1e6);
            console.log("Quantity:", quantity, "(raw)");
            console.log("Quantity (ETH):", quantity / 1e18);

            // Calculate required deposit for buy order: price * quantity (in quote currency)
            // This should give us the quote currency amount needed (in quote currency's 6 decimals)
            uint128 requiredDeposit = (currentPrice * quantity) / 1e18;

            console.log("Calculated deposit:", requiredDeposit, "(raw)");
            console.log(string.concat("Calculated deposit (", quoteCurrency, "):"), requiredDeposit / 1e6);

            // Check user balances before placing order
            uint256 quoteBalance = tokenQuote.balanceOf(msg.sender);
            uint256 quoteAllowance = IERC20(address(tokenQuote)).allowance(msg.sender, address(scalexRouter));

            console.log(string.concat("User ", quoteCurrency, " balance:"), quoteBalance, "(raw)");
            console.log(string.concat("User ", quoteCurrency, " balance:"), quoteBalance / 1e6, quoteCurrency);
            console.log(string.concat(quoteCurrency, " allowance:"), quoteAllowance, "(raw)");
            console.log(string.concat(quoteCurrency, " allowance:"), quoteAllowance / 1e6, quoteCurrency);

            console.log("Placing limit order...");
            uint48 orderId = scalexRouter.placeLimitOrder(
                pool, currentPrice, quantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 0
            );

            console.log("Order placed successfully! Order ID:", orderId);
            buyOrderIds.push(orderId);

            currentPrice += priceStep;
            ordersPlaced++;
        }
    }

    function _placeSellOrders(
        IPoolManager.Pool memory pool,
        uint128 startPrice,
        uint128 endPrice,
        uint128 priceStep,
        uint8 numOrders,
        uint128 quantity
    ) private {
        uint128 currentPrice = startPrice;
        uint8 ordersPlaced = 0;

        while (currentPrice <= endPrice && ordersPlaced < numOrders) {
            console.log("\n--- Placing SELL Order #", ordersPlaced + 1, "---");
            console.log("Price:", currentPrice, "(raw)");
            console.log(string.concat("Price (", quoteCurrency, "):"), currentPrice / 1e6);
            console.log("Quantity:", quantity, "(raw)");
            console.log("Quantity (ETH):", quantity / 1e18);

            // For sell orders, deposit the base currency (WETH) quantity
            uint128 requiredDeposit = quantity;

            console.log("Required deposit:", requiredDeposit, "(raw)");
            console.log("Required deposit (ETH):", requiredDeposit / 1e18);

            // Check user balances before placing order
            uint256 wethBalance = tokenWETH.balanceOf(msg.sender);
            uint256 wethAllowance = IERC20(address(tokenWETH)).allowance(msg.sender, address(scalexRouter));

            console.log("User WETH balance:", wethBalance, "(raw)");
            console.log("User WETH balance:", wethBalance / 1e18, "ETH");
            console.log("WETH allowance:", wethAllowance, "(raw)");
            console.log("WETH allowance:", wethAllowance / 1e18, "ETH");

            console.log("Placing limit order...");
            uint48 orderId = scalexRouter.placeLimitOrder(
                pool, currentPrice, quantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 0
            );

            console.log("Order placed successfully! Order ID:", orderId);
            sellOrderIds.push(orderId);

            currentPrice += priceStep;
            ordersPlaced++;
        }
    }

    function verifyOrders() private {
        console.log("\n=== Verifying Order Book ===");

        // Get synthetic currency objects for verification (pools use synthetic tokens)
        address sxWETHAddr = deployed["sxWETH"].addr;
        address sxQuoteAddr = deployed[sxQuoteKey].addr;
        Currency weth = Currency.wrap(sxWETHAddr);
        Currency quote = Currency.wrap(sxQuoteAddr);

        // Get pool
        IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, quote, address(poolManager));

        // Check best prices
        IOrderBook.PriceVolume memory bestBuy = scalexRouter.getBestPrice(weth, quote, IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestSell = scalexRouter.getBestPrice(weth, quote, IOrderBook.Side.SELL);

        console.log("Best BUY price:", bestBuy.price);
        console.log(string.concat(quoteCurrency, " with volume:"), bestBuy.volume, "ETH\n");

        console.log("Best SELL price:", bestSell.price);
        console.log(string.concat(quoteCurrency, " with volume:"), bestSell.volume, "ETH\n");

        // Check a few specific price levels
        _checkPriceLevel(weth, quote, IOrderBook.Side.BUY, 1950e6);
        _checkPriceLevel(weth, quote, IOrderBook.Side.SELL, 2050e6);

        // Check sample orders from both sides
        if (buyOrderIds.length > 0) {
            _checkOrderDetails(weth, quote, buyOrderIds[0], "First BUY");
            _checkOrderDetails(weth, quote, buyOrderIds[buyOrderIds.length - 1], "Last BUY");
        }

        if (sellOrderIds.length > 0) {
            _checkOrderDetails(weth, quote, sellOrderIds[0], "First SELL");
            _checkOrderDetails(weth, quote, sellOrderIds[sellOrderIds.length - 1], "Last SELL");
        }
    }

    function _checkPriceLevel(Currency base, Currency quote, IOrderBook.Side side, uint128 price) private {
        (uint48 orderCount, uint256 totalVolume) = scalexRouter.getOrderQueue(base, quote, side, price);
        string memory sideStr = side == IOrderBook.Side.BUY ? "BUY" : "SELL";

        console.log(string.concat("Price level ", vm.toString(price), " ", quoteCurrency, " - ", sideStr));
        console.log("orders:", orderCount);
        console.log("with volume:", totalVolume, "ETH");
        console.log("");
    }

    function _checkOrderDetails(Currency base, Currency quote, uint48 orderId, string memory label) private {
        IOrderBook.Order memory order = scalexRouter.getOrder(base, quote, orderId);

        console.log("\nOrder details for", label);
        console.log("order (ID:", orderId, "):");
        console.log("User:", order.user);
        console.log("Order ID:", order.id);
        console.log("Side:", order.side == IOrderBook.Side.BUY ? "BUY" : "SELL");
        console.log("Type:", order.orderType == IOrderBook.OrderType.LIMIT ? "LIMIT" : "MARKET");
        console.log("Price:", order.price, quoteCurrency);
        console.log("Quantity:", order.quantity, "ETH");
        console.log("Filled:", order.filled, "ETH");
        console.log("Next in queue:", order.next);
        console.log("Prev in queue:", order.prev);
        console.log("Status:", uint8(order.status));
        console.log("");
    }

    function checkOrderBookDepth() private {
        console.log("\n=== Verifying OrderBook State ===");

        // Get synthetic currency objects for verification (pools use synthetic tokens)
        address sxWETHAddr = deployed["sxWETH"].addr;
        address sxQuoteAddr = deployed[sxQuoteKey].addr;
        Currency weth = Currency.wrap(sxWETHAddr);
        Currency quote = Currency.wrap(sxQuoteAddr);

        // Verify BUY orders are correctly placed
        _verifyBuyOrdersPlaced(weth, quote);

        // Verify SELL orders are correctly placed (if any)
        _verifySellOrdersPlaced(weth, quote);

        // Verify orderbook structure is correct
        _verifyOrderBookStructure(weth, quote);

        console.log("All orderbook verifications passed!");
    }

    function _verifyBuyOrdersPlaced(Currency base, Currency quote) private {
        console.log("Checking BUY orders...");

        // Verify we have buy orders placed
        require(buyOrderIds.length > 0, "No BUY orders were placed");

        // Check best BUY price exists
        IOrderBook.PriceVolume memory bestBuy = scalexRouter.getBestPrice(base, quote, IOrderBook.Side.BUY);
        require(bestBuy.price > 0, "No best BUY price found");
        require(bestBuy.volume > 0, "No volume at best BUY price");

        // Verify each placed order exists and has valid data
        for (uint256 i = 0; i < buyOrderIds.length; i++) {
            IOrderBook.Order memory order = scalexRouter.getOrder(base, quote, buyOrderIds[i]);
            require(order.id == buyOrderIds[i], "Order ID mismatch");
            require(order.user == deployerAddress, "Order user mismatch");
            require(order.side == IOrderBook.Side.BUY, "Order side mismatch");
            require(order.price > 0, "Invalid order price");

            // Check that there's still some volume at this price level (may be partially filled)
            (uint48 orderCount, uint256 totalVolume) =
                scalexRouter.getOrderQueue(base, quote, IOrderBook.Side.BUY, order.price);
            require(orderCount > 0, string(abi.encodePacked("No orders at price ", uint2str(order.price))));
            require(totalVolume > 0, string(abi.encodePacked("No volume at price ", uint2str(order.price))));
        }

        console.log("BUY orders verification passed");
    }

    function _verifySellOrdersPlaced(Currency base, Currency quote) private {
        console.log("Checking SELL orders...");

        IOrderBook.PriceVolume memory bestSell = scalexRouter.getBestPrice(base, quote, IOrderBook.Side.SELL);

        if (sellOrderIds.length == 0) {
            console.log("No SELL orders placed");
        } else {
            // If SELL orders exist, verify they're correctly placed
            require(bestSell.price > 0, "SELL orders placed but no best price");
            require(bestSell.volume > 0, "SELL orders placed but no volume");

            // Verify each placed sell order exists and has valid data
            for (uint256 i = 0; i < sellOrderIds.length; i++) {
                IOrderBook.Order memory order = scalexRouter.getOrder(base, quote, sellOrderIds[i]);
                require(order.id == sellOrderIds[i], "SELL order ID mismatch");
                require(order.user == deployerAddress, "SELL order user mismatch");
                require(order.side == IOrderBook.Side.SELL, "SELL order side mismatch");
                require(order.price > 0, "Invalid SELL order price");

                // Check that there's still some volume at this price level (may be partially filled)
                (uint48 orderCount, uint256 totalVolume) =
                    scalexRouter.getOrderQueue(base, quote, IOrderBook.Side.SELL, order.price);
                require(orderCount > 0, string(abi.encodePacked("No SELL orders at price ", uint2str(order.price))));
                require(totalVolume > 0, string(abi.encodePacked("No SELL volume at price ", uint2str(order.price))));
            }

            console.log("SELL orders verification passed");
        }
    }

    function _verifyOrderBookStructure(Currency base, Currency quote) private {
        console.log("Checking orderbook structure...");

        IOrderBook.PriceVolume memory bestBuy = scalexRouter.getBestPrice(base, quote, IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestSell = scalexRouter.getBestPrice(base, quote, IOrderBook.Side.SELL);

        // Verify BUY side exists
        require(bestBuy.price > 0, "No BUY orders in orderbook");
        require(bestBuy.volume > 0, "No BUY volume in orderbook");

        // If both sides exist, verify spread is positive
        if (bestSell.price > 0) {
            require(bestSell.price > bestBuy.price, "Invalid spread: ask <= bid");
            console.log("Valid bid-ask spread");
        }

        // Verify order IDs are valid and orders exist
        for (uint256 i = 0; i < buyOrderIds.length; i++) {
            IOrderBook.Order memory order = scalexRouter.getOrder(base, quote, buyOrderIds[i]);
            require(order.id == buyOrderIds[i], "Order ID mismatch");
            require(order.user == deployerAddress, "Order user mismatch");
            require(order.side == IOrderBook.Side.BUY, "Order side mismatch");
            require(order.quantity > 0, "Invalid order quantity");
        }

        console.log("Orderbook structure verification passed");
    }

    // Utility function to convert uint to string
    function uint2str(
        uint256 _i
    ) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
}
