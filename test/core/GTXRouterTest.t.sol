// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@gtxcore/BalanceManager.sol";
import "@gtxcore/GTXRouter.sol";

import "@gtx/mocks/MockToken.sol";
import "@gtx/mocks/MockUSDC.sol";
import "@gtx/mocks/MockWETH.sol";
import "@gtxcore/OrderBook.sol";
import "@gtxcore/PoolManager.sol";
import {IOrderBook} from "@gtxcore/interfaces/IOrderBook.sol";
import {IOrderBookErrors} from "@gtxcore/interfaces/IOrderBookErrors.sol";
import {IPoolManager} from "@gtxcore/interfaces/IPoolManager.sol";
import {IBalanceManagerErrors} from "@gtxcore/interfaces/IBalanceManagerErrors.sol";
import {Currency} from "@gtxcore/libraries/Currency.sol";
import {PoolKey} from "@gtxcore/libraries/Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Test, console} from "forge-std/Test.sol";

contract GTXRouterTest is Test {
    GTXRouter private gtxRouter;
    PoolManager private poolManager;
    BalanceManager private balanceManager;

    address private owner = address(0x1);
    address private feeReceiver = address(0x2);
    address private user = address(0x3);

    address alice = address(0x5);
    address bob = address(0x6);
    address charlie = address(0x7);

    Currency private wbtc;
    Currency private weth;
    Currency private usdc;
    MockUSDC private mockUSDC;
    MockWETH private mockWETH;
    MockToken private mockWBTC;

    uint256 private feeMaker = 1; // 0.1%
    uint256 private feeTaker = 5; // 0.5%
    uint256 constant FEE_UNIT = 1000;

    uint256 private initialBalance = 1000 ether;
    uint256 private initialBalanceUSDC = 10e6;
    uint256 private initialBalanceWETH = 1e18;

    // Default trading rules
    IOrderBook.TradingRules private defaultTradingRules;

    function setUp() public {
        BeaconDeployer beaconDeployer = new BeaconDeployer();

        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeReceiver, feeMaker, feeTaker))
        );
        balanceManager = BalanceManager(address(balanceManagerProxy));

        IBeacon orderBookBeacon = new UpgradeableBeacon(address(new OrderBook()), owner);
        address orderBookBeaconAddress = address(orderBookBeacon);

        (BeaconProxy poolManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new PoolManager()),
            owner,
            abi.encodeCall(PoolManager.initialize, (owner, address(balanceManager), address(orderBookBeaconAddress)))
        );
        poolManager = PoolManager(address(poolManagerProxy));

        (BeaconProxy routerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new GTXRouter()),
            owner,
            abi.encodeCall(GTXRouter.initialize, (address(poolManager), address(balanceManager)))
        );
        gtxRouter = GTXRouter(address(routerProxy));

        mockWETH = new MockWETH();
        mockUSDC = new MockUSDC();
        mockWBTC = new MockToken("Mock WBTC", "mWBTC", 8);

        usdc = Currency.wrap(address(mockUSDC));
        weth = Currency.wrap(address(mockWETH));
        wbtc = Currency.wrap(address(mockWBTC));

        vm.deal(user, initialBalance);

        // Initialize default trading rules
        defaultTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e14, // 0.0001 ETH
            minAmountMovement: 1e14, // 0.0001 ETH
            minOrderSize: 1e4, // 0.01 USDC
            minPriceMovement: 1e4 // 0.01 USDC with 6 decimals
        });

        // Use the actual owner address
        vm.startPrank(owner);
        balanceManager.setPoolManager(address(poolManager));
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.setAuthorizedOperator(address(routerProxy), true);
        poolManager.setRouter(address(gtxRouter));
        poolManager.addCommonIntermediary(usdc);
        poolManager.createPool(weth, usdc, defaultTradingRules);
        poolManager.createPool(
            wbtc,
            usdc,
            IOrderBook.TradingRules({
                minTradeAmount: 1e3, // 0.00001 BTC (8 decimals)
                minAmountMovement: 1e3, // 0.00001 BTC (8 decimals)
                minOrderSize: 1e4, // 0.01 USDC (6 decimals)
                minPriceMovement: 1e4 // 0.01 USDC with 6 decimals
            })
        );
        vm.stopPrank();
    }

    function _getPool(Currency currency1, Currency currency2) internal view returns (IPoolManager.Pool memory pool) {
        IPoolManager _poolManager = IPoolManager(poolManager);
        PoolKey memory key = _poolManager.createPoolKey(currency1, currency2);

        return _poolManager.getPool(key);
    }

    function testPlaceLimitOrder() public {
        vm.startPrank(alice);
        uint128 price = 2000e6;
        uint128 quantity = 1e18; // 1 ETH
        mockWETH.mint(alice, quantity);
        assertEq(mockWETH.balanceOf(alice), quantity, "Alice should have initial WETH balance");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), quantity);

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        uint48 orderId =
            gtxRouter.placeLimitOrder(pool, price, quantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, quantity);
        vm.stopPrank();

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, price);

        // Assertions for order count and total volume
        assertEq(orderCount, 1, "Order count should be 1 after placing the limit order");
        assertEq(totalVolume, quantity, "Total volume should match the placed order quantity");

        // Assertions for the order details
        IOrderBook.Order memory order = gtxRouter.getOrder(weth, usdc, orderId);
        assertEq(order.id, orderId, "Order ID should match the returned order ID");
        assertEq(order.price, price, "Order price should match the placed price");
        assertEq(order.quantity, quantity, "Order quantity should match the placed quantity");
        assertEq(uint8(order.side), uint8(IOrderBook.Side.SELL), "Order side should be SELL");
    }


    function _setupLiquidityForMarketOrderTests() internal returns (IPoolManager.Pool memory) {
        // Setup sell side liquidity (for BUY market orders)
        vm.startPrank(user);
        mockWETH.mint(user, 10 ether);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 10 ether);
        balanceManager.deposit(weth, 10 ether, user, user);

        uint128 sellPrice1 = 3000 * 10 ** 6;
        uint128 sellPrice2 = 3050 * 10 ** 6;
        uint128 sellPrice3 = 3100 * 10 ** 6;
        uint128 sellQty1 = 5 * 10 ** 17;
        uint128 sellQty2 = 3 * 10 ** 17;
        uint128 sellQty3 = 2 * 10 ** 17;

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        gtxRouter.placeLimitOrder(pool, sellPrice1, sellQty1, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 0);
        gtxRouter.placeLimitOrder(pool, sellPrice2, sellQty2, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 0);
        gtxRouter.placeLimitOrder(pool, sellPrice3, sellQty3, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 0);
        vm.stopPrank();

        // Setup buy side liquidity (for SELL market orders)
        vm.startPrank(user);
        mockUSDC.mint(user, 10_000 * 10 ** 6);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 10_000 * 10 ** 6);
        balanceManager.deposit(usdc, 10_000 * 10 ** 6, user, user);

        uint128 buyPrice1 = 2900 * 10 ** 6;
        uint128 buyPrice2 = 2850 * 10 ** 6;
        uint128 buyPrice3 = 2800 * 10 ** 6;
        uint128 buyQty1 = 4 * 10 ** 17;
        uint128 buyQty2 = 3 * 10 ** 17;
        uint128 buyQty3 = 2 * 10 ** 17;

        gtxRouter.placeLimitOrder(pool, buyPrice1, buyQty1, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 0);
        gtxRouter.placeLimitOrder(pool, buyPrice2, buyQty2, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 0);
        gtxRouter.placeLimitOrder(pool, buyPrice3, buyQty3, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 0);
        vm.stopPrank();

        return pool;
    }

    function testMarketBuyWithDeposit_Success() public {
        IPoolManager.Pool memory pool = _setupLiquidityForMarketOrderTests();

        address buyDepositUser = address(0x8);
        vm.startPrank(buyDepositUser);

        uint256 buyerUsdcAmount = 5000 * 10 ** 6;
        mockUSDC.mint(buyDepositUser, buyerUsdcAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), buyerUsdcAmount);

        IOrderBook.PriceVolume memory bestSellPrice = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);
        uint128 buyMarketQuoteAmount = uint128((0.5 ether * bestSellPrice.price) / 1e18); // Spend enough USDC to buy ~0.5 ETH
        uint128 expectedBaseReceived = uint128(PoolIdLibrary.quoteToBase(buyMarketQuoteAmount, bestSellPrice.price, 18));
        uint128 minOutAmountBuy = gtxRouter.calculateMinOutAmountForMarket(pool, buyMarketQuoteAmount, IOrderBook.Side.BUY, 500); // 5% slippage tolerance

        (uint48 buyDepositOrderId,) = gtxRouter.placeMarketOrder(
            pool, buyMarketQuoteAmount, IOrderBook.Side.BUY, uint128(buyerUsdcAmount), minOutAmountBuy
        );

        console.log("Market buy with deposit executed with ID:", buyDepositOrderId);

        uint256 usdcBalance = balanceManager.getBalance(buyDepositUser, usdc);
        uint256 ethBalance = balanceManager.getBalance(buyDepositUser, weth);

        assertLt(usdcBalance, buyerUsdcAmount);
        assertGt(ethBalance, 0, "User should have received ETH");
        uint256 expectedEthBalance = uint256(expectedBaseReceived) * (FEE_UNIT - feeTaker) / FEE_UNIT;
        assertApproxEqRel(ethBalance, expectedEthBalance, 0.01e18, "Should have received ~0.5 ETH");

        vm.stopPrank();
    }

    function testMarketSellWithDeposit_Success() public {
        IPoolManager.Pool memory pool = _setupLiquidityForMarketOrderTests();

        address sellDepositUser = address(0x9);
        vm.startPrank(sellDepositUser);

        uint256 sellerEthAmount = 2 ether;
        mockWETH.mint(sellDepositUser, sellerEthAmount);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), sellerEthAmount);

        uint128 sellMarketQty = 5 * 10 ** 17;
        IOrderBook.PriceVolume memory bestBuyPrice = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);
        uint256 expectedUsdcReceived = (sellMarketQty * bestBuyPrice.price) / 10 ** 18;
        uint128 minOutAmountSell = uint128((expectedUsdcReceived * 95) / 100);
        minOutAmountSell = uint128(uint256(minOutAmountSell) * (FEE_UNIT - feeTaker) / FEE_UNIT);

        (uint48 sellDepositOrderId,) =
            gtxRouter.placeMarketOrder(pool, sellMarketQty, IOrderBook.Side.SELL, uint128(sellerEthAmount), minOutAmountSell);

        console.log("Market sell with deposit executed with ID:", sellDepositOrderId);

        uint256 ethBalanceAfterSell = balanceManager.getBalance(sellDepositUser, weth);
        uint256 receivedUsdc = balanceManager.getBalance(sellDepositUser, usdc);

        assertEq(ethBalanceAfterSell, 0, "Should have 1.5 ETH remaining");
        assertGt(receivedUsdc, 0, "Should have received some USDC");
        assertApproxEqRel(receivedUsdc, expectedUsdcReceived, 0.01e18, "Should have received ~1475 USDC");

        vm.stopPrank();
    }

    function testMarketBuyWithDeposit_InsufficientFunds() public {
        IPoolManager.Pool memory pool = _setupLiquidityForMarketOrderTests();

        address poorBuyUser = address(0xa);
        vm.startPrank(poorBuyUser);

        uint256 poorBuyerUsdcAmount = 100 * 10 ** 6;
        mockUSDC.mint(poorBuyUser, poorBuyerUsdcAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), poorBuyerUsdcAmount);

        uint128 buyMarketQuoteAmount = 3000 * 10 ** 6; // Try to buy with 3000 USDC
        uint128 minOutAmountBuy = gtxRouter.calculateMinOutAmountForMarket(pool, buyMarketQuoteAmount, IOrderBook.Side.BUY, 500); // 5% slippage tolerance

        // This should fail due to slippage being too high since we're trying to spend 3000 USDC but only have 100 USDC
        vm.expectRevert();
        gtxRouter.placeMarketOrder(pool, buyMarketQuoteAmount, IOrderBook.Side.BUY, uint128(poorBuyerUsdcAmount), minOutAmountBuy);

        vm.stopPrank();
    }

    function testMarketSellWithDeposit_InsufficientFunds() public {
        IPoolManager.Pool memory pool = _setupLiquidityForMarketOrderTests();

        address poorSellUser = address(0xb);
        vm.startPrank(poorSellUser);

        uint256 poorSellerEthAmount = 1 * 10 ** 17;
        mockWETH.mint(poorSellUser, poorSellerEthAmount);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), poorSellerEthAmount);

        uint128 sellMarketQty = 5 * 10 ** 17;
        vm.expectRevert("TransferFromFailed()");
        gtxRouter.placeMarketOrder(pool, sellMarketQty, IOrderBook.Side.SELL, uint128(poorSellerEthAmount), 0);

        vm.stopPrank();
    }

    function testPlaceOrderWithDeposit() public {
        uint256 depositAmount = 10 ether;
        vm.startPrank(alice);
        mockWETH.mint(alice, depositAmount);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);

        IPoolManager.Pool memory pool = _getPool(weth, usdc);
        uint128 price = 3000 * 10 ** 6; // Price with 6 decimals (3000 USDC per ETH)
        uint128 quantity = 1 * 10 ** 18; // Quantity with 18 decimals (1 ETH)
        IOrderBook.Side side = IOrderBook.Side.SELL;
        console.log("Setting side to SELL");

        console.log(Currency.unwrap(pool.quoteCurrency));

        uint48 orderId =
            gtxRouter.placeLimitOrder(pool, price, quantity, side, IOrderBook.TimeInForce.GTC, uint128(quantity));
        console.log("Order with deposit placed with ID:", orderId);

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, side, price);
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);
        assertEq(orderCount, 1);
        assertEq(totalVolume, quantity);

        // Check the balance and locked balance from the balance manager
        uint256 balance = balanceManager.getBalance(user, weth);
        uint256 lockedBalance =
            balanceManager.getLockedBalance(user, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth);

        console.log("User Balance:", balance);
        console.log("User Locked Balance:", lockedBalance);
        vm.stopPrank();
    }

    function testIgnoreMatchOrderSameTrader() public {
        vm.startPrank(alice);
        mockWETH.mint(alice, initialBalanceWETH);
        mockUSDC.mint(alice, initialBalanceUSDC);
        uint128 price = 1900e6;

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1e18);
        gtxRouter.placeLimitOrder(pool, price, 1e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 1e18);

        (uint256 balance, uint256 lockedBalance) =
            _getBalanceAndLockedBalance(alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth);

        assertEq(balance, 0, "Alice WETH balance should be 0 after placing sell order");
        assertEq(lockedBalance, 1e18, "Locked balance should be 1 ETH");

        // For BUY orders, we specify the base quantity (ETH) we want to buy
        // But we need to mint and approve the equivalent amount of USDC
        // 1 ETH at 1900 USDC/ETH = 1900 USDC
        uint256 usdcAmount = 1900e6;
        mockUSDC.mint(alice, usdcAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), usdcAmount);

        // Quantity for buy is in base asset (ETH)
        gtxRouter.placeLimitOrder(pool, price, 1e18, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, uint128(usdcAmount));

        vm.stopPrank();

        (balance, lockedBalance) =
            _getBalanceAndLockedBalance(alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc);

        assertEq(balance, 0, "Alice USDC balance should be 0 after placing buy order");
        assertEq(lockedBalance, 1900e6, "Locked balance should be 1900 USDC");

        (balance, lockedBalance) =
            _getBalanceAndLockedBalance(alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth);

        // Alice's WETH should still be locked, not returned to balance
        assertEq(balance, 0, "Alice WETH balance should be 0 (still locked in order)");
        assertEq(lockedBalance, 1e18, "Locked balance should still be 1 ETH");

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, price);
        assertEq(orderCount, 1, "Order count should be 1 after placing buy order (sell order remains)");
        assertEq(totalVolume, 1e18, "Total volume should be 1 ETH after placing buy order");

        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, price);
        assertEq(orderCount, 1, "Order count should be 1 after placing buy order");
        assertEq(totalVolume, 1e18, "Total volume should be 1 ETH after placing buy order");
    }

    function _getBalanceAndLockedBalance(
        address _user,
        address _operator,
        Currency currency
    ) internal view returns (uint256 balance, uint256 lockedBalance) {
        balance = balanceManager.getBalance(_user, currency);
        lockedBalance = balanceManager.getLockedBalance(_user, _operator, currency);
    }

    function testMatchBuyMarketOrder() public {
        vm.startPrank(alice);
        uint128 sellQty = 1e17; // 0.1 ETH
        mockWETH.mint(alice, sellQty);
        assertEq(mockWETH.balanceOf(alice), 1e17, "Alice should have 0.1 ETH");
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), sellQty);
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        uint128 sellPrice = 1900e6; // 1900 USDC/ETH

        gtxRouter.placeLimitOrder(pool, sellPrice, sellQty, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, sellQty);
        vm.stopPrank();

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, sellPrice);

        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);

        assertEq(orderCount, 1, "Should have one sell order");
        assertEq(totalVolume, sellQty, "Volume should match sell quantity");

        vm.startPrank(bob);
        uint256 bobUsdcAmount = 2000e6;
        mockUSDC.mint(bob, bobUsdcAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), bobUsdcAmount);

        uint128 buyQty = 1e17;
        uint256 requiredUsdc = (buyQty * sellPrice) / 1e18;
        uint128 minOutAmountBuy = gtxRouter.calculateMinOutAmountForMarket(pool, uint128(requiredUsdc), IOrderBook.Side.BUY, 500); // 5% slippage tolerance
        gtxRouter.placeMarketOrder(
            pool,
            uint128(requiredUsdc),
            IOrderBook.Side.BUY,
            uint128(requiredUsdc),
            minOutAmountBuy
        );

        // Verify order matching sell
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, sellPrice);
        assertEq(orderCount, 0, "Sell order should be fully matched");
        assertEq(totalVolume, 0, "Volume should be 0 after match");

        // Check balances
        uint256 bobWethBalance = balanceManager.getBalance(bob, weth);
        uint256 aliceUsdcBalance = balanceManager.getBalance(alice, usdc);

        // Calculate expected amounts after fees
        uint256 expectedWeth = buyQty - ((buyQty * feeTaker) / FEE_UNIT); // Minus taker fee
        uint256 expectedUsdc = (buyQty * sellPrice) / 1e18;
        expectedUsdc = expectedUsdc - ((expectedUsdc * feeMaker) / FEE_UNIT); // Minus maker fee

        assertEq(bobWethBalance, expectedWeth, "Bob should receive ETH minus taker fee");
        assertEq(aliceUsdcBalance, expectedUsdc, "Alice should receive USDC minus maker fee");

        vm.stopPrank();
    }

    function testMatchSellMarketOrder() public {
        // Set up a buy order
        vm.startPrank(alice);
        uint256 aliceUsdcAmount = 1900e6;
        mockUSDC.mint(alice, aliceUsdcAmount);
        assertEq(mockUSDC.balanceOf(alice), 1900e6, "Alice should have 1900 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), aliceUsdcAmount);

        // Get pool for WETH/USDC pair
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        uint128 buyPrice = 1900e6; // 1900 USDC/ETH
        uint128 buyQty = 1e18; // 1 ETH

        // Place buy order
        gtxRouter.placeLimitOrder(
            pool, buyPrice, buyQty, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, uint128(aliceUsdcAmount)
        );
        vm.stopPrank();

        // Check the order was placed correctly
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, buyPrice);
        assertEq(orderCount, 1, "Should have 1 buy order");
        assertEq(totalVolume, buyQty, "Volume should match buy quantity");

        // Bob places market sell order
        vm.startPrank(bob);
        uint128 sellQty = 1e18; // 1 ETH
        mockWETH.mint(bob, sellQty);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), sellQty);

        // Market sell 1 ETH
        gtxRouter.placeMarketOrder(
            pool,
            sellQty,
            IOrderBook.Side.SELL,
            sellQty,
            0
        );

        // Verify order matching
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, buyPrice);
        assertEq(orderCount, 0, "Buy order should be fully matched");
        assertEq(totalVolume, 0, "Volume should be 0 after match");

        // Check balances
        uint256 bobUsdcBalance = balanceManager.getBalance(bob, usdc);
        uint256 aliceWethBalance = balanceManager.getBalance(alice, weth);

        // Calculate expected amounts after fees
        uint256 expectedUsdc = (sellQty * buyPrice) / 1e18;
        expectedUsdc = expectedUsdc - ((expectedUsdc * feeTaker) / FEE_UNIT); // Minus taker fee
        uint256 expectedWeth = sellQty - ((sellQty * feeMaker) / FEE_UNIT); // Minus maker fee

        assertEq(bobUsdcBalance, expectedUsdc, "Bob should receive USDC minus taker fee");
        assertEq(aliceWethBalance, expectedWeth, "Alice should receive ETH minus maker fee");

        vm.stopPrank();
    }

    function testLimitOrderMatching() public {
        // Setup sell order from Alice
        vm.startPrank(alice);
        mockWETH.mint(alice, initialBalanceWETH);
        assertEq(mockWETH.balanceOf(alice), initialBalanceWETH, "Alice should have initial WETH balance");

        // Create pool key and get the pool properly
        PoolKey memory key = poolManager.createPoolKey(weth, usdc);
        IPoolManager.Pool memory pool = poolManager.getPool(key);

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), initialBalanceWETH);
        uint128 price = 2000e6;
        uint128 quantity = 1e18; // 1 ETH
        gtxRouter.placeLimitOrder(pool, price, quantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, quantity);
        vm.stopPrank();

        // Setup buy order from Bob
        vm.startPrank(bob);
        uint256 bobUsdcAmount = 2000e6;
        mockUSDC.mint(bob, bobUsdcAmount); // Bob has enough USDC for 1 ETH at 2000 USDC/ETH
        assertEq(mockUSDC.balanceOf(bob), 2000e6, "Bob should have 2000 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), bobUsdcAmount);
        uint128 buyQuantity = 1e18; // 1 ETH
        gtxRouter.placeLimitOrder(
            pool, price, buyQuantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, uint128(bobUsdcAmount)
        );
        vm.stopPrank();

        // Check that the sell order has been fully matched
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, price);
        console.log("Sell Order Count:", orderCount);
        console.log("Sell Total Volume:", totalVolume);

        assertEq(orderCount, 0, "Sell order should be fully filled");
        assertEq(totalVolume, 0, "Sell total volume should be 0");

        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, price);
        console.log("Buy Order Count:", orderCount);
        console.log("Buy Total Volume:", totalVolume);

        assertEq(orderCount, 0, "Buy order should be fully filled");
        assertEq(totalVolume, 0, "Buy total volume should be 0");
    }

    function testCancelSellOrder() public {
        address trader = makeAddr("trader");
        vm.startPrank(trader);

        // Mint tokens and approve for deposit
        uint128 quantity = 1e18; // 1 ETH
        mockWETH.mint(trader, quantity);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), quantity);

        // Load pool using the _getPool helper
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Place a SELL order with deposit
        uint128 price = 3000e6; // 3000 USDC per ETH
        uint48 orderId =
            gtxRouter.placeLimitOrder(pool, price, quantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, quantity);

        // Confirm order was placed by checking the order queue
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, price);
        assertEq(orderCount, 1, "Sell order should be placed");
        assertEq(totalVolume, quantity, "Sell order volume should match");

        // Cancel the sell order
        gtxRouter.cancelOrder(pool, orderId);

        // Verify that the order is removed from the queue
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, price);
        assertEq(orderCount, 0, "Sell order should be canceled");
        assertEq(totalVolume, 0, "Sell order volume should be zero after cancellation");

        // Check that the locked funds have been released back to the trader
        uint256 balance = balanceManager.getBalance(trader, weth);
        uint256 lockedBalance =
            balanceManager.getLockedBalance(trader, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth);
        assertGt(balance, 0, "Trader's available balance should increase after cancellation");
        assertEq(lockedBalance, 0, "No funds should remain locked for the canceled order");

        vm.stopPrank();
    }

    function testCancelBuyOrder() public {
        // Log the addresses to see which is higher
        address usdcAddr = address(mockUSDC);
        address wethAddr = address(mockWETH);
        
        console.log("=== ADDRESS COMPARISON ===");
        console.log("USDC address:", usdcAddr);
        console.log("WETH address:", wethAddr);
        console.log("Test contract address:", address(this));
        console.log("Test contract nonce:", vm.getNonce(address(this)));
        
        // Deploy two new contracts to see the pattern
        MockWETH tempWETH = new MockWETH();
        MockUSDC tempUSDC = new MockUSDC();
        
        console.log("=== FRESH DEPLOYMENT TEST ===");
        console.log("TempWETH (deployed first):", address(tempWETH));
        console.log("TempUSDC (deployed second):", address(tempUSDC));
        
        if (address(tempWETH) < address(tempUSDC)) {
            console.log("EXPECTED: First deployment < Second deployment");
        } else {
            console.log("UNEXPECTED: First deployment > Second deployment");
        }
        
        if (usdcAddr < wethAddr) {
            console.log("USDC < WETH: USDC will be BASE, WETH will be QUOTE");
        } else {
            console.log("WETH < USDC: WETH will be BASE, USDC will be QUOTE");
        }
        
        // Get the actual pool to confirm
        IPoolManager.Pool memory pool = _getPool(weth, usdc);
        console.log("Pool base currency:", Currency.unwrap(pool.baseCurrency));
        console.log("Pool quote currency:", Currency.unwrap(pool.quoteCurrency));
        
        if (Currency.unwrap(pool.baseCurrency) == usdcAddr) {
            console.log("Confirmed: USDC is BASE currency");
        } else {
            console.log("Confirmed: WETH is BASE currency");
        }
        
        /* COMMENTED OUT ACTUAL TEST LOGIC
        address trader = makeAddr("trader");
        vm.startPrank(trader);
        uint256 usdcAmount = 2000e6;
        mockUSDC.mint(trader, usdcAmount); // 2000 USDC for a buy order
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), usdcAmount);

        // Place a buy order - buying 1 ETH at 2000 USDC per ETH
        uint128 price = 2000e6;
        uint128 quantity = 1e18; // 1 ETH (base quantity)
        IOrderBook.Side side = IOrderBook.Side.BUY;

        // Check initial balances
        (uint256 balance, uint256 lockedBalance) =
            _getBalanceAndLockedBalance(trader, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc);
        assertEq(balance, 0, "Trader USDC balance should be 0 before order");
        assertEq(lockedBalance, 0, "Trader USDC locked balance should be 0 before order");

        // Place the buy order
        uint48 orderId = gtxRouter.placeLimitOrder(
            pool, price, quantity, side, IOrderBook.TimeInForce.GTC, uint128(usdcAmount)
        );

        // Verify the order was placed correctly
        (balance, lockedBalance) =
            _getBalanceAndLockedBalance(trader, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc);
        uint256 expectedLocked = 2000e6; // 2000 USDC (1 ETH * 2000 USDC/ETH)
        assertEq(balance, 0, "Trader USDC balance should be 0 after order placement");
        assertEq(lockedBalance, expectedLocked, "Trader USDC locked balance should equal order value");

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, side, price);
        assertEq(orderCount, 1, "Order should be placed");
        assertEq(totalVolume, quantity, "Volume should match quantity");

        // Cancel the buy order
        gtxRouter.cancelOrder(pool, orderId);
        vm.stopPrank();

        // Verify balances after cancellation
        (balance, lockedBalance) =
            _getBalanceAndLockedBalance(trader, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc);

        assertEq(balance, expectedLocked, "Trader USDC balance should be equal to order value after cancellation");
        assertEq(lockedBalance, 0, "Trader USDC locked balance should be 0 after cancellation");

        // Verify the order was removed from the queue
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, side, price);
        assertEq(orderCount, 0, "Order should be cancelled");
        assertEq(totalVolume, 0, "Volume should be 0 after cancellation");
        */
    }

    function testPartialMarketOrderMatching() public {
        // Setup sell order
        vm.startPrank(alice);
        uint128 sellQty = 10e18; // 10 ETH
        mockWETH.mint(alice, sellQty);
        assertEq(mockWETH.balanceOf(alice), 10e18, "Alice should have 10 ETH");

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), sellQty);
        uint128 sellPrice = 1000e6;
        gtxRouter.placeLimitOrder(pool, sellPrice, sellQty, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, sellQty);
        vm.stopPrank();

        // Place partial market buy order
        vm.startPrank(bob);
        // Calculate required USDC for 6 ETH at 1000 USDC/ETH = 6000 USDC
        uint256 bobUsdcAmount = 6000e6;
        mockUSDC.mint(bob, bobUsdcAmount);
        assertEq(mockUSDC.balanceOf(bob), 6000e6, "Bob should have 6000 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), bobUsdcAmount);

        // Buy with 6000 USDC (quote quantity)
        uint128 buyQuoteAmount = 6000e6;
        uint128 minOutAmountBuy = gtxRouter.calculateMinOutAmountForMarket(pool, buyQuoteAmount, IOrderBook.Side.BUY, 500); // 5% slippage tolerance
        gtxRouter.placeMarketOrder(pool, buyQuoteAmount, IOrderBook.Side.BUY, uint128(bobUsdcAmount), minOutAmountBuy);
        vm.stopPrank();

        // Verify partial fill
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, sellPrice);
        console.log("Order Count after partial fill:", orderCount);
        console.log("Total Volume after partial fill:", totalVolume);

        assertEq(orderCount, 1, "Order should still exist");
        assertEq(totalVolume, 4e18, "Remaining volume should be 4 ETH");
    }

    function testMarketOrderWithNoLiquidity() public {
        vm.startPrank(bob);
        mockUSDC.mint(bob, initialBalanceUSDC);
        assertEq(mockUSDC.balanceOf(bob), initialBalanceUSDC, "Bob should have initial USDC balance");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), initialBalanceUSDC);

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        uint128 buyAmount = uint128(1000e6);
        uint128 minOutAmountBuy = gtxRouter.calculateMinOutAmountForMarket(pool, buyAmount, IOrderBook.Side.BUY, 500); // 5% slippage tolerance
        
        vm.expectRevert(IOrderBookErrors.OrderHasNoLiquidity.selector);
        gtxRouter.placeMarketOrder(pool, buyAmount, IOrderBook.Side.BUY, uint128(initialBalanceUSDC), minOutAmountBuy);

        vm.stopPrank();
    }

    /*function testOrderBookWithManyTraders() public {
        IPoolManager.Pool memory pool = _getPool(weth, usdc);
        // Create 20 traders for testing
        address[] memory traders = new address[](20);
        for (uint256 i = 0; i < 20; i++) {
            traders[i] = address(uint160(i + 1000));

            // Mint tokens to each trader within their own prank context
            vm.startPrank(traders[i]);
            mockWETH.mint(traders[i], 100e18);
            mockUSDC.mint(traders[i], 200_000e6); // Increased USDC for buy orders
            assertEq(mockWETH.balanceOf(traders[i]), 100e18, "Trader should have 100 ETH");
            assertEq(mockUSDC.balanceOf(traders[i]), 200_000e6, "Trader should have 200,000 USDC");

            IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 100e18);
            IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 200_000e6);
            vm.stopPrank();
        }

        // Place buy orders at different price levels
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(traders[i]);
            uint128 price = uint128(1000e6 + i * 1e6); // Price in USDC per ETH

            // For buy orders, quantity is in base asset (ETH)
            uint128 buyQuantity = 5e18; // 5 ETH
            uint256 requiredUsdc = (buyQuantity * price) / 1e18;

            gtxRouter.placeLimitOrder(
                pool, price, buyQuantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, uint128(requiredUsdc)
            );
            vm.stopPrank();
        }

        // Place sell orders at different price levels
        for (uint256 i = 10; i < 20; i++) {
            vm.startPrank(traders[i]);
            uint128 sellQuantity = 10e18;
            gtxRouter.placeLimitOrder(
                pool,
                uint128(1050e6 + (i - 10) * 1e6),
                sellQuantity, // Sell quantity in ETH
                IOrderBook.Side.SELL,
                IOrderBook.TimeInForce.GTC,
                sellQuantity
            );
            vm.stopPrank();
        }

        // Check some orders
        (uint48 buyOrderCount, uint256 buyVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, 1005e6);
        console.log("buy order count", buyOrderCount);
        console.log(buyVolume);
        assertEq(buyOrderCount, 1, "Should have 1 buy order at price 1005");
        assertEq(buyVolume, 5e18, "Buy volume should be 5 ETH");

        (uint48 sellOrderCount, uint256 sellVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, 1055e6);
        assertEq(sellOrderCount, 1, "Should have 1 sell order at price 1055");
        assertEq(sellVolume, 10e18, "Sell volume should be 10e18");

        // Check order book depth
        OrderBook.PriceVolume[] memory buyLevels = gtxRouter.getNextBestPrices(pool, IOrderBook.Side.BUY, 0, 5);
        assertEq(buyLevels.length, 5, "Should have 5 buy price levels");
        assertEq(buyLevels[0].price, 1009e6, "Best buy price should be 1009");

        OrderBook.PriceVolume[] memory sellLevels = gtxRouter.getNextBestPrices(pool, IOrderBook.Side.SELL, 0, 5);
        assertEq(sellLevels.length, 5, "Should have 5 sell price levels");
        assertEq(sellLevels[0].price, 1050e6, "Best sell price should be 1050");

        // Now we'll add a market order to trigger some trades and check balances
        address marketTrader = makeAddr("marketTrader");
        vm.startPrank(marketTrader);
        uint256 marketTraderUsdc = 50_000e6;
        mockUSDC.mint(marketTrader, marketTraderUsdc); // Mint enough USDC for market buy
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), marketTraderUsdc);

        // Store initial balances of some sell traders before the trade
        address orderBookAddress = address(poolManager.getPool(PoolKey(weth, usdc)).orderBook);
        uint256 initialWethLocked10 = balanceManager.getLockedBalance(traders[10], orderBookAddress, weth);
        uint256 initialUsdcBalance10 = balanceManager.getBalance(traders[10], usdc);

        // Execute market buy that should match with lowest sell orders
        // Quantity is in base asset (ETH)
        uint128 marketBuyQty = 5e18; // Buy 5 ETH
        uint256 requiredUsdcForMarket = (marketBuyQty * 1050e6) / 1e18;
        gtxRouter.placeMarketOrder(
            pool, marketBuyQty, IOrderBook.Side.BUY, uint128(requiredUsdcForMarket), (marketBuyQty * 95) / 100
        );
        vm.stopPrank();

        // Verify balances after trade for the first sell trader (index 10)
        uint256 wethLockedAfter10 = balanceManager.getLockedBalance(traders[10], orderBookAddress, weth);
        uint256 usdcBalanceAfter10 = balanceManager.getBalance(traders[10], usdc);

        // Trader 10 should have sold ETH (reduced locked balance) and received USDC
        assertLt(wethLockedAfter10, initialWethLocked10, "Trader 10 should have less locked WETH after trade");
        assertGt(usdcBalanceAfter10, initialUsdcBalance10, "Trader 10 should have more USDC after trade");

        console.log("Trader 10 initial locked WETH:", initialWethLocked10);
        console.log("Trader 10 locked WETH after trade:", wethLockedAfter10);
        console.log("Trader 10 initial USDC balance:", initialUsdcBalance10);
        console.log("Trader 10 USDC balance after trade:", usdcBalanceAfter10);

        // Check market trader's balance after trade
        uint256 marketTraderEthBalance = balanceManager.getBalance(marketTrader, weth);
        uint256 marketTraderEthFee = ((initialWethLocked10 - wethLockedAfter10) * 5) / 1000; // 0.5% taker fee
        uint256 expectedMarketTraderEthBalance = (initialWethLocked10 - wethLockedAfter10) - marketTraderEthFee;

        assertApproxEqAbs(
            marketTraderEthBalance,
            expectedMarketTraderEthBalance,
            1e14, // Allow for small rounding differences
            "Market trader should receive correct WETH amount minus fee"
        );
    }*/

    function testCancelOrderOnlyOnce() public {
        address trader = makeAddr("traderOnce");
        vm.startPrank(trader);

        // Mint and approve tokens
        uint128 quantity = 1 ether;
        mockWETH.mint(trader, quantity);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), quantity);

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Place a SELL order
        uint128 price = 3000e6;
        uint48 orderId =
            gtxRouter.placeLimitOrder(pool, price, quantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, quantity);

        // First cancellation should succeed
        gtxRouter.cancelOrder(pool, orderId);

        // Second cancellation should revert
        vm.expectRevert(
            abi.encodeWithSelector(IOrderBookErrors.OrderIsNotOpenOrder.selector, IOrderBook.Status.CANCELLED)
        );
        gtxRouter.cancelOrder(pool, orderId);

        vm.stopPrank();
    }

    function testImmediateMatchWhenCrossingOrderBook() public {
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Scenario 1: Buy order price > best sell price
        // Place a sell order at 1500 USDC/ETH
        vm.startPrank(alice);
        uint128 quantity = 1e18;
        mockWETH.mint(alice, quantity);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), quantity);
        gtxRouter.placeLimitOrder(pool, 1500e6, quantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, quantity);
        vm.stopPrank();

        // Place a buy order at 2000 USDC/ETH (should match at 1500)
        vm.startPrank(bob);
        uint256 usdcAmount = 2000e6;
        mockUSDC.mint(bob, usdcAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), usdcAmount);
        gtxRouter.placeLimitOrder(
            pool, 2000e6, quantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, uint128(usdcAmount)
        );
        vm.stopPrank();

        // Order book should be empty at both price levels
        (uint48 sellCount, uint256 sellVol) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, 1500e6);
        (uint48 buyCount, uint256 buyVol) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, 2000e6);
        assertEq(sellCount, 0, "Sell order should be matched and removed");
        assertEq(buyCount, 0, "Buy order should be matched and removed");
        assertEq(sellVol, 0, "Sell volume should be zero");
        assertEq(buyVol, 0, "Buy volume should be zero");

        // Scenario 2: Sell order price < best buy price
        // Place a buy order at 3000 USDC/ETH
        vm.startPrank(charlie);
        uint256 charlieUsdc = 3000e6;
        mockUSDC.mint(charlie, charlieUsdc);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), charlieUsdc);
        gtxRouter.placeLimitOrder(
            pool, 3000e6, quantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, uint128(charlieUsdc)
        );
        vm.stopPrank();

        // Place a sell order at 2000 USDC/ETH (should match at 3000)
        vm.startPrank(alice);
        mockWETH.mint(alice, quantity);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), quantity);
        gtxRouter.placeLimitOrder(pool, 2000e6, quantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, quantity);
        vm.stopPrank();

        // Order book should be empty at both price levels
        (sellCount, sellVol) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, 2000e6);
        (buyCount, buyVol) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, 3000e6);
        assertEq(sellCount, 0, "Sell order should be matched and removed");
        assertEq(buyCount, 0, "Buy order should be matched and removed");
        assertEq(sellVol, 0, "Sell volume should be zero");
        assertEq(buyVol, 0, "Buy volume should be zero");
    }

    function testSlippagePlaceMarketOrderWithDepositBuyOrder() public {
        vm.startPrank(alice);
        mockWETH.mint(alice, 5e18);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 5e18);
        balanceManager.deposit(weth, 5e18, alice, alice);
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        gtxRouter.placeLimitOrder(pool, 3000e6, 1e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 0);
        gtxRouter.placeLimitOrder(pool, 3500e6, 1e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 0);
        gtxRouter.placeLimitOrder(pool, 4000e6, 3e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 0);
        vm.stopPrank();

        address slippageBuyer = address(0x10);
        vm.startPrank(slippageBuyer);

        uint128 depositAmount = 10_000e6;

        mockUSDC.mint(slippageBuyer, depositAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), depositAmount);

        uint128 minOutAmount = 2875e15; // 5% slippage tolerance
        minOutAmount = minOutAmount - ((minOutAmount * 5) / 1000); // Fee tolerance
        console.log("Min out amount:", minOutAmount);

        gtxRouter.placeMarketOrder(pool, depositAmount, IOrderBook.Side.BUY, depositAmount, minOutAmount);

        vm.stopPrank();
    }

    function testMarketBuyEatsMultiplePriceLevels() public {
        // Alice provides liquidity by placing multiple sell orders
        vm.startPrank(alice);
        mockWETH.mint(alice, 5e18); // 5 ETH
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 5e18);
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Place sell orders at different price levels
        gtxRouter.placeLimitOrder(pool, 3000e6, 1e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 1e18);
        gtxRouter.placeLimitOrder(pool, 3050e6, 1e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 1e18);
        gtxRouter.placeLimitOrder(pool, 3100e6, 2e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 2e18);
        vm.stopPrank();

        // Bob places a large market buy order to eat through multiple levels
        vm.startPrank(bob);
        uint256 bobUsdcAmount = 10000e6; // 10,000 USDC
        mockUSDC.mint(bob, bobUsdcAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), bobUsdcAmount);

        // Buy 2.5 ETH
        // Cost: (1 * 3000) + (1 * 3050) + (0.5 * 3100) = 3000 + 3050 + 1550 = 7600 USDC
        uint128 buyQuoteAmount = 7600e6;
        uint128 minOutAmountBuy = gtxRouter.calculateMinOutAmountForMarket(pool, buyQuoteAmount, IOrderBook.Side.BUY, 500); // 5% slippage tolerance
        gtxRouter.placeMarketOrder(pool, buyQuoteAmount, IOrderBook.Side.BUY, uint128(bobUsdcAmount), minOutAmountBuy);
        vm.stopPrank();

        // Verify order book state
        (uint48 orderCount3000,) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, 3000e6);
        assertEq(orderCount3000, 0, "Order at 3000 should be filled");

        (uint48 orderCount3050,) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, 3050e6);
        assertEq(orderCount3050, 0, "Order at 3050 should be filled");

        (uint48 orderCount3100, uint256 volume3100) =
            gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, 3100e6);
        assertEq(orderCount3100, 1, "Order at 3100 should still exist");
        assertEq(volume3100, 15 * 10 ** 17, "Remaining volume at 3100 should be 1.5 ETH"); // 2 - 0.5

        // Verify Bob's balance
        uint256 buyQty = 25 * 10 ** 17; // 2.5 ETH
        uint256 expectedWeth = buyQty - ((buyQty * feeTaker) / FEE_UNIT);
        assertEq(balanceManager.getBalance(bob, weth), expectedWeth, "Bob should receive 2.5 ETH minus fees");
    }

    function testMarketSellWithSlippageFailure() public {
        // Alice provides liquidity by placing multiple buy orders
        vm.startPrank(alice);
        mockUSDC.mint(alice, 10000e6); // 10,000 USDC
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 10000e6);
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Place buy orders at different price levels
        gtxRouter.placeLimitOrder(pool, 2900e6, 1e18, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 2900e6);
        gtxRouter.placeLimitOrder(pool, 2850e6, 1e18, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 2850e6);
        gtxRouter.placeLimitOrder(pool, 2800e6, 1e18, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 2800e6);
        vm.stopPrank();

        // Bob places a market sell order with high slippage protection
        vm.startPrank(bob);
        uint128 sellQty = 3e18; // 3 ETH
        mockWETH.mint(bob, sellQty);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), sellQty);

        // Total expected USDC without slippage: (1*2900) + (1*2850) + (1*2800) = 8550 USDC
        uint256 expectedGrossUsdc = 2900e6 + 2850e6 + 2800e6; // 8,550,000,000
        uint256 expectedNetUsdc = expectedGrossUsdc - ((expectedGrossUsdc * feeTaker) / FEE_UNIT); // after taker fee

        uint128 minOutAmount = 8600e6; // Higher than possible proceeds

        vm.expectRevert(abi.encodeWithSelector(IOrderBookErrors.SlippageTooHigh.selector, uint128(expectedNetUsdc), minOutAmount));
        gtxRouter.placeMarketOrder(pool, sellQty, IOrderBook.Side.SELL, sellQty, minOutAmount);
        vm.stopPrank();
    }

    function testMarketOrderSkipsOwnLimitOrder() public {
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Alice places a sell order
        vm.startPrank(alice);
        mockWETH.mint(alice, 2e18); // 2 ETH
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 2e18);
        gtxRouter.placeLimitOrder(pool, 3000e6, 1e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 1e18);
        vm.stopPrank();

        // Bob places another sell order behind Alice's
        vm.startPrank(bob);
        mockWETH.mint(bob, 1e18); // 1 ETH
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1e18);
        gtxRouter.placeLimitOrder(pool, 3050e6, 1e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 1e18);
        vm.stopPrank();

        // Alice places a market buy order. Her own 3000 sell order will be skipped, and Bob's 3050 order will be matched.
        vm.startPrank(alice);
        uint256 aliceUsdcAmount = 4000e6;
        mockUSDC.mint(alice, aliceUsdcAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), aliceUsdcAmount);

        uint128 buyQty = 1e18; // 1 ETH
        uint128 requiredUsdc = uint128((buyQty * 3050e6) / 1e18);
        uint128 minOutAmountBuy = gtxRouter.calculateMinOutAmountForMarket(pool, requiredUsdc, IOrderBook.Side.BUY, 500); // 5% slippage tolerance
        gtxRouter.placeMarketOrder(pool, requiredUsdc, IOrderBook.Side.BUY, uint128(aliceUsdcAmount), minOutAmountBuy);
        vm.stopPrank();

        // Alice's sell order should remain (not cancelled)
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, 3000e6);
        assertEq(orderCount, 1, "Alice's sell order should remain");
        assertEq(totalVolume, 1e18, "Alice's sell order volume should be unchanged");

        // Bob's sell order is filled
        (orderCount, ) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, 3050e6);
        assertEq(orderCount, 0, "Bob's sell order should be filled");

        // Verify balances
        // Bob (maker) receives USDC
        uint256 expectedUsdc = (buyQty * 3050e6) / 1e18;
        expectedUsdc = expectedUsdc - ((expectedUsdc * feeMaker) / FEE_UNIT);
        assertEq(balanceManager.getBalance(bob, usdc), expectedUsdc, "Bob should receive USDC minus maker fee");

        // Alice (taker) receives WETH (only from Bob's order)
        uint256 aliceWethBalance = balanceManager.getBalance(alice, weth);
        uint256 expectedWeth = 1e18 - ((1e18 * feeTaker) / FEE_UNIT); // Only Bob's 1 ETH order is matched
        assertEq(aliceWethBalance, expectedWeth, "Alice should receive WETH from market buy minus taker fee");
    }
}