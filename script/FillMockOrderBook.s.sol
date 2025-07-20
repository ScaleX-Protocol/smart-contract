// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../script/DeployHelpers.s.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/GTXRouter.sol";
import "../src/core/PoolManager.sol";

import "../src/mocks/MockToken.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";
import "../src/core/resolvers/PoolManagerResolver.sol";

contract FillMockOrderBook is Script, DeployHelpers {
   // Contract address keys
   string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
   string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
   string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
   string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
   string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";

   // Core contracts
   BalanceManager balanceManager;
   PoolManager poolManager;
   GTXRouter gtxRouter;
   PoolManagerResolver poolManagerResolver;

   // Mock tokens
   MockWETH mockWETH;
   MockUSDC mockUSDC;

   // Track order IDs for verification
   uint48[] buyOrderIds;
   uint48[] sellOrderIds;

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
       gtxRouter = GTXRouter(deployed[GTX_ROUTER_ADDRESS].addr);

       // Load mock tokens
       mockWETH = MockWETH(deployed[WETH_ADDRESS].addr);
       mockUSDC = MockUSDC(deployed[USDC_ADDRESS].addr);
   }

   function run() public {
       uint256 deployerPrivateKey = getDeployerKey();
       vm.startBroadcast(deployerPrivateKey);

       fillETHUSDCOrderBook();

       verifyOrders();
       
       checkOrderBookDepth();

       vm.stopBroadcast();
   }

   function fillETHUSDCOrderBook() private {
       console.log("\n=== Filling ETH/USDC Order Book ===");

       // Get currency objects
       Currency weth = Currency.wrap(address(mockWETH));
       Currency usdc = Currency.wrap(address(mockUSDC));

       // Get the pool using the resolver
       IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, usdc, address(poolManager));

       // Setup sender with funds
       _setupFunds(200e18, 400_000e6); // 200 ETH, 400,000 USDC

       // Place BUY orders (bids) - ascending price from 1900 to 1980
       _placeBuyOrders(pool, 1900e6, 1980e6, 10e6, 10, 5e17);

       // Place SELL orders (asks) - ascending price from 2000 to 2100
    //    _placeSellOrders(pool, 2000e6, 2100e6, 10e6, 10, 4e17);

       // Print summary
       console.log("ETH/USDC order book filled with:");
       console.log("- BUY orders from 1900 USDC to 1980 USDC");
       console.log("- SELL orders from 2000 USDC to 2100 USDC");
   }

   function _setupFunds(uint256 ethAmount, uint256 usdcAmount) private {
       console.log("\n=== Setting up funds ===");
       console.log("Minting ETH amount:", ethAmount, "(raw)");
       console.log("Minting ETH amount:", ethAmount / 1e18, "ETH");
       console.log("Minting USDC amount:", usdcAmount, "(raw)");
       console.log("Minting USDC amount:", usdcAmount / 1e6, "USDC");
       
       // Mint tokens directly to sender
       mockWETH.mint(msg.sender, ethAmount);
       mockUSDC.mint(msg.sender, usdcAmount);
       
       console.log("Tokens minted successfully");
       
       // Approve tokens for balance manager
       bool wethApproval = IERC20(address(mockWETH)).approve(address(balanceManager), ethAmount);
       bool usdcApproval = IERC20(address(mockUSDC)).approve(address(balanceManager), usdcAmount);
       
       console.log("WETH approval result:", wethApproval);
       console.log("USDC approval result:", usdcApproval);
       
       // Verify final balances and allowances
       console.log("Final WETH balance:", mockWETH.balanceOf(msg.sender) / 1e18, "ETH");
       console.log("Final USDC balance:", mockUSDC.balanceOf(msg.sender) / 1e6, "USDC");
       console.log("Final WETH allowance:", IERC20(address(mockWETH)).allowance(msg.sender, address(balanceManager)) / 1e18, "ETH");
       console.log("Final USDC allowance:", IERC20(address(mockUSDC)).allowance(msg.sender, address(balanceManager)) / 1e6, "USDC");
       console.log("Funds setup complete\n");
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
           console.log("Price (USDC):", currentPrice / 1e6);
           console.log("Quantity:", quantity, "(raw)");
           console.log("Quantity (ETH):", quantity / 1e18);
           
           // Calculate required deposit for buy order: price * quantity (in USDC)
           // This should give us the USDC amount needed (in USDC's 6 decimals)
           uint128 requiredDeposit = (currentPrice * quantity) / 1e18;
           
           console.log("Calculated deposit:", requiredDeposit, "(raw)");
           console.log("Calculated deposit (USDC):", requiredDeposit / 1e6);
           
           // Check user balances before placing order
           uint256 usdcBalance = mockUSDC.balanceOf(msg.sender);
           uint256 usdcAllowance = IERC20(address(mockUSDC)).allowance(msg.sender, address(balanceManager));
           
           console.log("User USDC balance:", usdcBalance, "(raw)");
           console.log("User USDC balance:", usdcBalance / 1e6, "USDC");
           console.log("USDC allowance:", usdcAllowance, "(raw)");
           console.log("USDC allowance:", usdcAllowance / 1e6, "USDC");
           
           console.log("Placing limit order...");
           uint48 orderId = gtxRouter.placeLimitOrder(
               pool, currentPrice, quantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, requiredDeposit
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
           console.log("Price (USDC):", currentPrice / 1e6);
           console.log("Quantity:", quantity, "(raw)");
           console.log("Quantity (ETH):", quantity / 1e18);
           
           // For sell orders, deposit the base currency (WETH) quantity
           uint128 requiredDeposit = quantity;
           
           console.log("Required deposit:", requiredDeposit, "(raw)");
           console.log("Required deposit (ETH):", requiredDeposit / 1e18);
           
           // Check user balances before placing order
           uint256 wethBalance = mockWETH.balanceOf(msg.sender);
           uint256 wethAllowance = IERC20(address(mockWETH)).allowance(msg.sender, address(balanceManager));
           
           console.log("User WETH balance:", wethBalance, "(raw)");
           console.log("User WETH balance:", wethBalance / 1e18, "ETH");
           console.log("WETH allowance:", wethAllowance, "(raw)");
           console.log("WETH allowance:", wethAllowance / 1e18, "ETH");
           
           console.log("Placing limit order...");
           uint48 orderId = gtxRouter.placeLimitOrder(
               pool, currentPrice, quantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, requiredDeposit
           );
           
           console.log("Order placed successfully! Order ID:", orderId);
           sellOrderIds.push(orderId);

           currentPrice += priceStep;
           ordersPlaced++;
       }
   }

   function verifyOrders() private {
       console.log("\n=== Verifying Order Book ===");

       // Get currency objects
       Currency weth = Currency.wrap(address(mockWETH));
       Currency usdc = Currency.wrap(address(mockUSDC));

       // Get pool
       IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, usdc, address(poolManager));

       // Check best prices
       IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);
       IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);

       console.log("Best BUY price:", bestBuy.price);
       console.log("USDC with volume:", bestBuy.volume, "ETH\n");

       console.log("Best SELL price:", bestSell.price);
       console.log("USDC with volume:", bestSell.volume, "ETH\n");

       // Check a few specific price levels
       _checkPriceLevel(weth, usdc, IOrderBook.Side.BUY, 1950e6);
       _checkPriceLevel(weth, usdc, IOrderBook.Side.SELL, 2050e6);

       // Check sample orders from both sides
       if (buyOrderIds.length > 0) {
           _checkOrderDetails(weth, usdc, buyOrderIds[0], "First BUY");
           _checkOrderDetails(weth, usdc, buyOrderIds[buyOrderIds.length - 1], "Last BUY");
       }

       if (sellOrderIds.length > 0) {
           _checkOrderDetails(weth, usdc, sellOrderIds[0], "First SELL");
           _checkOrderDetails(weth, usdc, sellOrderIds[sellOrderIds.length - 1], "Last SELL");
       }
   }

   function _checkPriceLevel(Currency base, Currency quote, IOrderBook.Side side, uint128 price) private {
       (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(base, quote, side, price);
       string memory sideStr = side == IOrderBook.Side.BUY ? "BUY" : "SELL";

       console.log("Price level", price, "USDC -", sideStr);
       console.log("orders:", orderCount);
       console.log("with volume:", totalVolume, "ETH");
       console.log("");
   }

   function _checkOrderDetails(Currency base, Currency quote, uint48 orderId, string memory label) private {
       IOrderBook.Order memory order = gtxRouter.getOrder(base, quote, orderId);

       console.log("\nOrder details for", label);
       console.log("order (ID:", orderId, "):");
       console.log("User:", order.user);
       console.log("Order ID:", order.id);
       console.log("Side:", order.side == IOrderBook.Side.BUY ? "BUY" : "SELL");
       console.log("Type:", order.orderType == IOrderBook.OrderType.LIMIT ? "LIMIT" : "MARKET");
       console.log("Price:", order.price, "USDC");
       console.log("Quantity:", order.quantity, "ETH");
       console.log("Filled:", order.filled, "ETH");
       console.log("Next in queue:", order.next);
       console.log("Prev in queue:", order.prev);
       console.log("Status:", uint8(order.status));
       console.log("");
   }

   function checkOrderBookDepth() private {
       console.log("\n=== Verifying OrderBook State ===");
       
       // Get currency objects
       Currency weth = Currency.wrap(address(mockWETH));
       Currency usdc = Currency.wrap(address(mockUSDC));
       
       // Verify BUY orders are correctly placed
       _verifyBuyOrdersPlaced(weth, usdc);
       
       // Verify SELL orders are correctly placed (if any)
       _verifySellOrdersPlaced(weth, usdc);
       
       // Verify orderbook structure is correct
       _verifyOrderBookStructure(weth, usdc);
       
       console.log("All orderbook verifications passed!");
   }
   
   function _verifyBuyOrdersPlaced(Currency base, Currency quote) private {
       console.log("Checking BUY orders...");
       
       // Expected: BUY orders from 1900 to 1980 USDC (if 10 orders with 10 USDC step)
       uint128 expectedStartPrice = 1900e6;
       uint128 expectedEndPrice = 1980e6;
       uint128 expectedQuantity = 5e17; // 0.5 ETH
       
       // Check best BUY price (should be highest = 1980)
       IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(base, quote, IOrderBook.Side.BUY);
       require(bestBuy.price == expectedEndPrice, "Best BUY price incorrect");
       require(bestBuy.volume >= expectedQuantity, "Best BUY volume too low");
       
       // Verify we have the expected number of buy orders
       require(buyOrderIds.length > 0, "No BUY orders were placed");
       
       // Check a few specific price levels
       (uint48 orderCount1980, uint256 volume1980) = gtxRouter.getOrderQueue(base, quote, IOrderBook.Side.BUY, 1980e6);
       (uint48 orderCount1970, uint256 volume1970) = gtxRouter.getOrderQueue(base, quote, IOrderBook.Side.BUY, 1970e6);
       (uint48 orderCount1900, uint256 volume1900) = gtxRouter.getOrderQueue(base, quote, IOrderBook.Side.BUY, 1900e6);
       
       require(orderCount1980 > 0, "No orders at 1980 USDC");
       require(volume1980 == expectedQuantity, "Wrong volume at 1980 USDC");
       require(orderCount1970 > 0, "No orders at 1970 USDC");
       require(orderCount1900 > 0, "No orders at 1900 USDC");
       
       console.log("BUY orders verification passed");
   }
   
   function _verifySellOrdersPlaced(Currency base, Currency quote) private {
       console.log("Checking SELL orders...");
       
       // Check if SELL orders were placed (currently commented out in script)
       IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(base, quote, IOrderBook.Side.SELL);
       
       if (sellOrderIds.length == 0) {
           require(bestSell.price == 0, "Unexpected SELL orders found");
           console.log("No SELL orders (as expected)");
       } else {
           // If SELL orders exist, verify they're correctly placed
           require(bestSell.price > 0, "SELL orders placed but no best price");
           require(bestSell.volume > 0, "SELL orders placed but no volume");
           console.log("SELL orders verification passed");
       }
   }
   
   function _verifyOrderBookStructure(Currency base, Currency quote) private {
       console.log("Checking orderbook structure...");
       
       IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(base, quote, IOrderBook.Side.BUY);
       IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(base, quote, IOrderBook.Side.SELL);
       
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
           IOrderBook.Order memory order = gtxRouter.getOrder(base, quote, buyOrderIds[i]);
           require(order.id == buyOrderIds[i], "Order ID mismatch");
           require(order.user == msg.sender, "Order user mismatch");
           require(order.side == IOrderBook.Side.BUY, "Order side mismatch");
           require(order.quantity > 0, "Invalid order quantity");
       }
       
       console.log("Orderbook structure verification passed");
   }
}
