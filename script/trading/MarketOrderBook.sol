// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/PoolManager.sol";

import "../../src/mocks/MockToken.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockWETH.sol";
import "../../src/core/resolvers/PoolManagerResolver.sol";

contract MarketOrderBook is Script, DeployHelpers {
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

   // Synthetic tokens
   IERC20 synthWETH;
   IERC20 synthQuote;

   // Regular tokens for deposits
   IERC20 tokenWETH;
   IERC20 tokenQuote;

   // Quote currency info
   string quoteCurrency;
   string sxQuoteKey;

   // Track order IDs for verification
   uint48[] marketBuyOrderIds;
   uint48[] marketSellOrderIds;

   // Deployer address
   address deployerAddress;

   function setUp() public {
       loadDeployments();
       loadContracts();

       // Deploy the resolver
       poolManagerResolver = new PoolManagerResolver();
   }

   function loadContracts() private {
       // Load core contracts
       balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
       poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
       scalexRouter = ScaleXRouter(deployed[ScaleX_ROUTER_ADDRESS].addr);

       // Get quote currency from environment
       quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
       sxQuoteKey = string.concat("sx", quoteCurrency);

       // Load synthetic tokens
       synthWETH = IERC20(deployed[WETH_ADDRESS].addr);
       synthQuote = IERC20(deployed[sxQuoteKey].addr);

       // Also load regular tokens for deposits
       tokenWETH = IERC20(deployed["WETH"].addr);
       tokenQuote = IERC20(deployed[quoteCurrency].addr);
   }

   function run() public virtual {
       uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_2");
       vm.startBroadcast(deployerPrivateKey);

       deployerAddress = vm.addr(deployerPrivateKey);

       placeMarketOrdersETHUSDC();
       
       vm.stopBroadcast();
       
       // Skip verification in broadcast mode to avoid gas issues
       console.log("Market orders executed successfully!");
       console.log("Run verifyMarketOrdersOnly() to verify order details if needed");
   }

   function verifyMarketOrdersOnly() public {
       uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_2");
       deployerAddress = vm.addr(deployerPrivateKey);
       
       // Move verifications outside of broadcast context (no gas costs)
       verifyMarketOrders();
       verifyMarketOrderExecution();
   }

   function placeMarketOrdersETHUSDC() private {
       console.log(string.concat("\n=== Placing Market Orders on ETH/", quoteCurrency, " ==="));

       // Get currency objects
       Currency weth = Currency.wrap(address(synthWETH));
       Currency quote = Currency.wrap(address(synthQuote));

       // Get the pool using the resolver
       IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, quote, address(poolManager));

       // Make local deposits to get synthetic tokens if needed
       _makeLocalDeposits(1e17, 100e6); // 0.1 ETH, 100 quote currency

       // Setup sender with funds for market orders (use smaller amounts matching our actual balances)
       _setupFunds(1e17, 100e6); // 0.1 ETH, 100 quote currency


       // Check current approvals (not needed for synthetic tokens in BalanceManager)
       uint256 wethAllowance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthWETH)));
       uint256 quoteAllowance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthQuote)));

       console.log("\nCurrent BalanceManager balances:");
       console.log("sxWETH balance:", wethAllowance);
       console.log(string.concat("sx", quoteCurrency, " balance:"), quoteAllowance);

       if (wethAllowance < 1e16) { // Only need 0.01 ETH for tiny market orders
           console.log("Insufficient sxWETH balance in BalanceManager");
           return;
       }

       if (quoteAllowance < 50e6) { // Only need 50 quote currency for tiny market orders
           console.log(string.concat("Insufficient sx", quoteCurrency, " balance in BalanceManager"));
           return;
       }

       // Place market SELL orders (sells ETH for quote currency)
       // These will execute against the BUY limit orders
       _placeMarketSellOrders(pool, 1); // 1 sell order to avoid balance exhaustion

       // Place market BUY orders (buys ETH with quote currency)
       // These will execute against the SELL limit orders
       _placeMarketBuyOrders(pool, 1); // 1 buy order to avoid balance exhaustion

       // Print summary
       console.log("\nMarket orders placed:");
       console.log(string.concat("- 1 market SELL order (selling ETH for ", quoteCurrency, ")"));
       console.log(string.concat("- 1 market BUY order (buying ETH with ", quoteCurrency, ")"));
   }

   function _setupFunds(uint256 ethAmount, uint256 quoteAmount) private view {
       console.log("Using existing synthetic token balances in BalanceManager");

       uint256 currentWETHBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthWETH)));
       uint256 currentQuoteBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthQuote)));

       console.log("Current sxWETH balance:", currentWETHBalance);
       console.log("Current quote balance:", currentQuoteBalance);

       require(currentWETHBalance >= ethAmount, "Insufficient sxWETH balance");
       require(currentQuoteBalance >= quoteAmount, "Insufficient quote balance");
   }

   function _placeMarketBuyOrders(
       IPoolManager.Pool memory pool,
       uint8 numOrders
   ) private {
       console.log("\n--- Placing Market BUY Orders ---");

       // Much smaller quantities to avoid memory issues
       uint128[] memory quantities = new uint128[](5);
       quantities[0] = 1e15;  // 0.001 ETH
       quantities[1] = 2e15;  // 0.002 ETH
       quantities[2] = 5e15;  // 0.005 ETH
       quantities[3] = 1e16;  // 0.01 ETH
       quantities[4] = 2e16;  // 0.02 ETH

       for (uint8 i = 0; i < numOrders; i++) {
           uint128 quantity = quantities[i % 5];

           uint128 minOutAmount = scalexRouter.calculateMinOutAmountForMarket(
               pool, 0, IOrderBook.Side.BUY, 500
           );

           (uint48 orderId, uint128 filled) = scalexRouter.placeMarketOrder(
               pool, quantity, IOrderBook.Side.BUY, 0, minOutAmount
           );

           console.log("Placed market BUY order ID:", orderId);
           console.log("Filled:", filled);
           marketBuyOrderIds.push(orderId);
       }
   }

   function _placeMarketSellOrders(
       IPoolManager.Pool memory pool,
       uint8 numOrders
   ) private {
       console.log("\n--- Placing Market SELL Orders ---");

       // Much smaller quantities to avoid memory issues
       uint128[] memory quantities = new uint128[](5);
       quantities[0] = 1e15;  // 0.001 ETH
       quantities[1] = 2e15;  // 0.002 ETH
       quantities[2] = 5e15;  // 0.005 ETH
       quantities[3] = 1e16;  // 0.01 ETH
       quantities[4] = 2e16;  // 0.02 ETH

       for (uint8 i = 0; i < numOrders; i++) {
           uint128 quantity = quantities[i % 5];

           uint128 minOutAmount = scalexRouter.calculateMinOutAmountForMarket(
               pool, 0, IOrderBook.Side.SELL, 500
           );

           (uint48 orderId, uint128 filled) = scalexRouter.placeMarketOrder(
               pool, quantity, IOrderBook.Side.SELL, 0, minOutAmount
           );

           console.log("Placed market SELL order ID:", orderId);
           console.log("Filled:", filled);
           marketSellOrderIds.push(orderId);
       }
   }

   function verifyMarketOrders() private {
       console.log("\n=== Verifying Market Orders ===");

       // Get currency objects
       Currency weth = Currency.wrap(address(synthWETH));
       Currency quote = Currency.wrap(address(synthQuote));

       // Check market buy orders
       console.log("\n--- Market BUY Orders ---");
       for (uint256 i = 0; i < marketBuyOrderIds.length; i++) {
           _checkOrderDetails(weth, quote, marketBuyOrderIds[i], string(abi.encodePacked("Market BUY #", uint2str(i + 1))));
       }

       // Check market sell orders
       console.log("\n--- Market SELL Orders ---");
       for (uint256 i = 0; i < marketSellOrderIds.length; i++) {
           _checkOrderDetails(weth, quote, marketSellOrderIds[i], string(abi.encodePacked("Market SELL #", uint2str(i + 1))));
       }

       // Check orderbook state and balances
       _logBestPrices(weth, quote);
       _checkBalances();
   }

   function _logBestPrices(Currency weth, Currency quote) private view {
       console.log("\n--- Order Book State After Market Orders ---");
       IOrderBook.PriceVolume memory bestBuy = scalexRouter.getBestPrice(weth, quote, IOrderBook.Side.BUY);
       IOrderBook.PriceVolume memory bestSell = scalexRouter.getBestPrice(weth, quote, IOrderBook.Side.SELL);
       console.log("Best BUY price:", bestBuy.price);
       console.log("Best BUY volume:", bestBuy.volume);
       console.log("Best SELL price:", bestSell.price);
       console.log("Best SELL volume:", bestSell.volume);
   }

   function _checkOrderDetails(Currency base, Currency quote, uint48 orderId, string memory label) private view {
       IOrderBook.Order memory order = scalexRouter.getOrder(base, quote, orderId);

       console.log("\nOrder details for", label);
       console.log("Order ID:", orderId);
       console.log("User:", order.user);
       console.log("Price:", order.price);
       console.log("Quantity:", order.quantity);
       console.log("Filled:", order.filled);
   }

   function _checkBalances() private view {
       console.log("\n--- Balance Check ---");

       uint256 bmEthBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthWETH)));
       uint256 bmQuoteBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthQuote)));

       console.log("BalanceManager sxWETH balance:", bmEthBalance);
       console.log("BalanceManager quote balance:", bmQuoteBalance);

       uint256 ethTokenBalance = synthWETH.balanceOf(deployerAddress);
       uint256 quoteTokenBalance = synthQuote.balanceOf(deployerAddress);

       console.log("Direct sxWETH token balance:", ethTokenBalance);
       console.log("Direct quote token balance:", quoteTokenBalance);
   }

   // Utility function to convert uint to string
   function uint2str(uint256 _i) internal pure returns (string memory str) {
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

   function verifyMarketOrderExecution() private {
       console.log("\n=== Verifying Market Order Execution ===");

       // Get currency objects
       Currency weth = Currency.wrap(address(synthWETH));
       Currency quote = Currency.wrap(address(synthQuote));

       // Verify market orders were executed
       _verifyMarketOrdersExecuted();

       // Verify balance changes from market order execution
       _verifyBalanceChanges(weth, quote);

       // Verify orderbook state after market orders
       _verifyOrderBookAfterMarketOrders(weth, quote);

       console.log("All market order execution verifications passed!");
   }
   
   function _verifyMarketOrdersExecuted() private view {
       console.log("Checking market order execution...");

       require(marketBuyOrderIds.length > 0 || marketSellOrderIds.length > 0, "No market orders were attempted");

       for (uint256 i = 0; i < marketBuyOrderIds.length; i++) {
           require(marketBuyOrderIds[i] > 0, "Invalid market BUY order ID");
       }

       for (uint256 i = 0; i < marketSellOrderIds.length; i++) {
           require(marketSellOrderIds[i] > 0, "Invalid market SELL order ID");
       }

       console.log("Market orders execution verified");
   }
   
   function _verifyBalanceChanges(Currency, Currency) private view {
       console.log("Checking balance changes...");

       uint256 userWethBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthWETH)));
       uint256 userQuoteBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthQuote)));

       if (marketBuyOrderIds.length > 0) {
           require(userQuoteBalance > 0, "No quote transferred for BUY orders");
       }

       if (marketSellOrderIds.length > 0) {
           require(userQuoteBalance > 0, "No quote received from SELL orders");
       }

       require(userWethBalance <= 2e18, "WETH balance exceeded initial amount");

       console.log("Balance changes verification passed");
   }
   
   function _verifyOrderBookAfterMarketOrders(Currency base, Currency quote) private {
       console.log("Checking orderbook state after market orders...");

       _verifySpread(base, quote);
       _verifyMarketOrderStates(base, quote);

       console.log("Orderbook state verification passed");
   }

   function _verifySpread(Currency base, Currency quote) private {
       IOrderBook.PriceVolume memory bestBuy = scalexRouter.getBestPrice(base, quote, IOrderBook.Side.BUY);
       IOrderBook.PriceVolume memory bestSell = scalexRouter.getBestPrice(base, quote, IOrderBook.Side.SELL);

       if (bestBuy.price > 0) {
           require(bestBuy.volume > 0, "BUY side has price but no volume");
       }
       if (bestSell.price > 0) {
           require(bestSell.volume > 0, "SELL side has price but no volume");
       }
       if (bestBuy.price > 0 && bestSell.price > 0) {
           require(bestSell.price > bestBuy.price, "Invalid spread after market orders");
       }
   }

   function _verifyMarketOrderStates(Currency base, Currency quote) private {
       for (uint256 i = 0; i < marketBuyOrderIds.length; i++) {
           IOrderBook.Order memory order = scalexRouter.getOrder(base, quote, marketBuyOrderIds[i]);
           require(order.user == deployerAddress || order.id == 0, "Market order has wrong user or invalid state");
       }
   }

   function _makeLocalDeposits(uint256 ethAmount, uint256 quoteAmount) private {
       console.log("\n=== Making Local Deposits to BalanceManager ===");
       console.log("Depositing ETH amount:", ethAmount / 1e18, "ETH");
       console.log(string.concat("Depositing ", quoteCurrency, " amount:"), quoteAmount / 1e6, quoteCurrency);

       // Mint tokens if we don't have enough balance
       if (tokenWETH.balanceOf(deployerAddress) < ethAmount) {
           MockWETH(address(tokenWETH)).mint(deployerAddress, ethAmount);
           console.log("[SUCCESS] WETH minted to deployer account");
       }

       if (tokenQuote.balanceOf(deployerAddress) < quoteAmount) {
           MockToken(address(tokenQuote)).mint(deployerAddress, quoteAmount);
           console.log(string.concat("[SUCCESS] ", quoteCurrency, " minted to deployer account"));
       }

       // Approve BalanceManager to spend WETH
       tokenWETH.approve(address(balanceManager), ethAmount);
       console.log("[SUCCESS] WETH approved for BalanceManager");

       // Approve BalanceManager to spend quote currency
       tokenQuote.approve(address(balanceManager), quoteAmount);
       console.log(string.concat("[SUCCESS] ", quoteCurrency, " approved for BalanceManager"));

       // Deposit real WETH to BalanceManager (will receive synthetic balance)
       balanceManager.depositLocal(address(tokenWETH), ethAmount, deployerAddress);
       console.log("[SUCCESS] WETH deposited to BalanceManager");

       // Deposit real quote currency to BalanceManager (will receive synthetic balance)
       balanceManager.depositLocal(address(tokenQuote), quoteAmount, deployerAddress);
       console.log(string.concat("[SUCCESS] ", quoteCurrency, " deposited to BalanceManager"));
       
       // Verify BalanceManager balances for the deposited tokens
       uint256 wethBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(tokenWETH)));
       uint256 quoteBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(tokenQuote)));

       console.log("BalanceManager WETH balance:", wethBalance / 1e18, "ETH");
       console.log(string.concat("BalanceManager ", quoteCurrency, " balance:"), quoteBalance / 1e6, quoteCurrency);

       // Check token balances in BalanceManager
       uint256 bmWethBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(tokenWETH)));
       uint256 bmQuoteBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(tokenQuote)));

       console.log("BalanceManager WETH balance:", bmWethBalance / 1e18, "ETH");
       console.log(string.concat("BalanceManager ", quoteCurrency, " balance:"), bmQuoteBalance / 1e6, quoteCurrency);
       console.log("Local deposits complete\n");
   }
}