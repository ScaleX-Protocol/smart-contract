// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {BalanceManager} from "../BalanceManager.sol";
import {GTXRouter} from "../GTXRouter.sol";
import {OrderBook} from "../OrderBook.sol";
import {PoolManager} from "../PoolManager.sol";
import {IOrderBook} from "../interfaces/IOrderBook.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";

import {Currency} from "../libraries/Currency.sol";
import {PoolKey} from "../libraries/Pool.sol";
import {MockToken} from "../../mocks/MockToken.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Test, console} from "forge-std/Test.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";

import {PoolHelper} from "./helpers/PoolHelper.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract BalanceAndFeeTest is Test, PoolHelper {
    IPoolManager.Pool public pool;
    OrderBook public orderBook;
    PoolKey public key;

    IOrderBook.TradingRules rules;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address david = address(0x4);

    address owner = address(0x5);
    address feeCollector = address(0x6);

    address baseTokenAddress;
    address quoteTokenAddress;

    uint256 baseDecimals;
    uint256 quoteDecimals;

    Currency baseCurrency;
    Currency quoteCurrency;

    // Define fee structure - modifiable for different test scenarios
    uint256 feeMaker = 10; // 0.1% as basis points (10/10000)
    uint256 feeTaker = 20; // 0.2% as basis points (20/10000)
    uint256 lotSize = 1e18;
    uint256 maxOrderAmount = 500e18;

    GTXRouter router;
    PoolManager poolManager;
    BalanceManager balanceManager;
    MockToken baseToken;
    MockToken quoteToken;

    function setUp() public {
        // Set up tokens
        quoteToken = new MockToken("USDC", "USDC", 6);
        baseToken = new MockToken("WETH", "WETH", 18);

        rules = IOrderBook.TradingRules({
            minTradeAmount: 1e14, // 0.0001 ETH (18 decimals)
            minAmountMovement: 1e13, // 0.00001 ETH (18 decimals)
            minOrderSize: 1e4, // 0.01 USDC (6 decimals)
            minPriceMovement: 1e4 // 0.01 USDC (6 decimals)
        });

        // Mint tokens to users
        uint256 initialAmount = 1_000_000_000e18;
        baseToken.mint(alice, initialAmount);
        baseToken.mint(bob, initialAmount);
        baseToken.mint(charlie, initialAmount);
        baseToken.mint(david, initialAmount);
        quoteToken.mint(alice, initialAmount);
        quoteToken.mint(bob, initialAmount);
        quoteToken.mint(charlie, initialAmount);
        quoteToken.mint(david, initialAmount);

        BeaconDeployer beaconDeployer = new BeaconDeployer();

        (BeaconProxy balanceManagerProxy,
address balanceManagerBeacon
 ) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeCollector, feeMaker, feeTaker))
        );
        balanceManager = BalanceManager(address(balanceManagerProxy));

        IBeacon orderBookBeacon = new UpgradeableBeacon(address(new OrderBook()), owner);
        address orderBookBeaconAddress = address(orderBookBeacon);

        (BeaconProxy poolManagerProxy,
address poolManagerBeacon
 ) = beaconDeployer.deployUpgradeableContract(
            address(new PoolManager()),
            owner,
            abi.encodeCall(PoolManager.initialize, (owner, address(balanceManager), address(orderBookBeaconAddress)))
        );
        poolManager = PoolManager(address(poolManagerProxy));

        Currency weth = Currency.wrap(address(quoteToken));
        Currency usdc = Currency.wrap(address(baseToken));

        PoolKey memory key = poolManager.createPoolKey(weth, usdc);

        console.log("Pool key created with base currency:", address(Currency.unwrap(key.baseCurrency)));
        console.log("Pool key created with quote currency:", address(Currency.unwrap(key.quoteCurrency)));

        baseCurrency = key.baseCurrency;
        quoteCurrency = key.quoteCurrency;

        baseToken = MockToken(address(Currency.unwrap(baseCurrency)));
        quoteToken = MockToken(address(Currency.unwrap(quoteCurrency)));

        baseTokenAddress = address(baseToken);
        quoteTokenAddress = address(quoteToken);

        baseDecimals = MockToken(baseTokenAddress).decimals();
        quoteDecimals = MockToken(quoteTokenAddress).decimals();

        console.log("Base decimals:", baseDecimals);
        console.log("Quote decimals:", quoteDecimals);

        (BeaconProxy routerProxy,
address gtxRouterBeacon
 ) = beaconDeployer.deployUpgradeableContract(
            address(new GTXRouter()),
            owner,
            abi.encodeCall(GTXRouter.initialize, (address(poolManager), address(balanceManager)))
        );
        router = GTXRouter(address(routerProxy));

        // Set up permissions and connections
        vm.startPrank(owner);
        balanceManager.setPoolManager(address(poolManagerProxy));
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.setAuthorizedOperator(address(router), true);
        poolManager.setRouter(address(router));
        vm.stopPrank();

        // Approve token usage for all users
        address[] memory users = new address[](4);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;

        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            baseToken.approve(address(balanceManager), type(uint256).max);
            quoteToken.approve(address(balanceManager), type(uint256).max);
            vm.stopPrank();
        }

        // Create the pool
        poolManager.createPool(baseCurrency, quoteCurrency, rules);

        key = poolManager.createPoolKey(baseCurrency, quoteCurrency);
        pool = poolManager.getPool(key);
        orderBook = OrderBook(address(pool.orderBook));
    }

    function testMultipleMakersSingleTakerFullOrderMatching() public {
        console.log("\n=== MULTIPLE MAKERS FULL ORDER MATCHING TEST ===");

        // Get initial balances for all participants
        uint256 aliceInitialBaseBalance = baseToken.balanceOf(alice);
        uint256 aliceInitialQuoteBalance = quoteToken.balanceOf(alice);
        uint256 bobInitialBaseBalance = baseToken.balanceOf(bob);
        uint256 bobInitialQuoteBalance = quoteToken.balanceOf(bob);
        uint256 charlieInitialBaseBalance = baseToken.balanceOf(charlie);
        uint256 charlieInitialQuoteBalance = quoteToken.balanceOf(charlie);
        uint256 davidInitialBaseBalance = baseToken.balanceOf(david);
        uint256 davidInitialQuoteBalance = quoteToken.balanceOf(david);

        uint256 feeCollectorInitialBaseBalance = balanceManager.getBalance(feeCollector, baseCurrency);
        uint256 feeCollectorInitialQuoteBalance = balanceManager.getBalance(feeCollector, quoteCurrency);

        // Define order parameters
        uint128 alicePrice = uint128(2505 * (10 ** quoteDecimals)); // Best price
        uint128 charliePrice = uint128(2502 * (10 ** quoteDecimals)); // Middle price
        uint128 davidPrice = uint128(2500 * (10 ** quoteDecimals)); // Lowest price

        uint128 aliceQuantity = uint128(2505 * (10 ** baseDecimals)) / 2505; // 3000 USDC
        uint128 bobQuantity = uint128(3 * (10 ** baseDecimals)); // 4500 USDC
        uint128 charlieQuantity = uint128(2502 * (10 ** baseDecimals)) / 2502; // 4500 USDC
        uint128 davidQuantity = uint128(2500 * (10 ** baseDecimals)) / 2500; // 5000 USDC

        // Calculate expected locked amounts
        uint256 aliceExpectedLocked = 2505 * (10 ** quoteDecimals);
        uint256 charlieExpectedLocked = 2502 * (10 ** quoteDecimals);
        uint256 davidExpectedLocked = 2500 * (10 ** quoteDecimals);

        // Create a series of buy orders at different price levels from multiple users
        vm.startPrank(alice);
        console.log("--- Alice places buy order at 2505 USDC per WETH (2505 USDC) ---");
        router.placeOrderWithDeposit(pool, alicePrice, aliceQuantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC);
        vm.stopPrank();

        // Verify Alice's quote token was locked
        uint256 aliceLockedAfterOrder = balanceManager.getLockedBalance(alice, address(orderBook), quoteCurrency);
        assertEq(aliceLockedAfterOrder, aliceExpectedLocked, "Alice's locked amount incorrect");

        // Verify Alice's wallet balance decreased
        uint256 aliceQuoteBalanceAfter = quoteToken.balanceOf(alice);
        assertApproxEqAbs(
            aliceInitialQuoteBalance - aliceQuoteBalanceAfter,
            aliceExpectedLocked,
            100,
            "Alice's wallet balance should have decreased by locked amount"
        );

        vm.startPrank(charlie);
        console.log("--- Charlie places buy order at 2502 USDC per WETH (2502 USDC) ---");
        router.placeOrderWithDeposit(
            pool, charliePrice, charlieQuantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC
        );
        vm.stopPrank();

        // Verify Charlie's quote token was locked
        uint256 charlieLockedAfterOrder = balanceManager.getLockedBalance(charlie, address(orderBook), quoteCurrency);
        assertEq(charlieLockedAfterOrder, charlieExpectedLocked, "Charlie's locked amount incorrect");

        vm.startPrank(david);
        console.log("--- David places buy order at 2500 USDC per WETH (2500 USDC) ---");
        router.placeOrderWithDeposit(pool, davidPrice, davidQuantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC);
        vm.stopPrank();

        // Verify David's quote token was locked
        uint256 davidLockedAfterOrder = balanceManager.getLockedBalance(david, address(orderBook), quoteCurrency);
        assertEq(davidLockedAfterOrder, davidExpectedLocked, "David's locked amount incorrect");

        // Log balances after buy orders from multiple users
        console.log("--- Balances After Multiple Users Place Buy Orders ---");
        logBalance("Alice", alice);
        logBalance("Charlie", charlie);
        logBalance("David", david);
        logBalance("Fee Collector", feeCollector);

        // Calculate expected values - should match against all buy orders from best price first
        uint256 expectedMatchVolumeInBase = aliceQuantity + charlieQuantity + davidQuantity;
        uint256 expectedMatchVolumeInQuote = (
            (aliceQuantity * alicePrice) + (charlieQuantity * charliePrice) + (davidQuantity * davidPrice)
        ) / (10 ** baseDecimals);

        uint256 aliceQuantityUnwrapped = aliceQuantity;
        uint256 alicePriceUnwrapped = alicePrice;
        uint256 aliceTradeValue = (alicePriceUnwrapped * aliceQuantityUnwrapped) / (10 ** baseDecimals);

        uint256 charlieQuantityUnwrapped = charlieQuantity;
        uint256 charliePriceUnwrapped = charliePrice;
        uint256 charlieTradeValue = (charliePriceUnwrapped * charlieQuantityUnwrapped) / (10 ** baseDecimals);

        uint256 davidQuantityUnwrapped = davidQuantity;
        uint256 davidPriceUnwrapped = davidPrice;
        uint256 davidTradeValue = (davidPriceUnwrapped * davidQuantityUnwrapped) / (10 ** baseDecimals);

        uint256 totalTradeValue = aliceTradeValue + charlieTradeValue + davidTradeValue;

        // Calculate expected fees - breaking down calculations
        uint256 feeUnit = 10_000; // Use the actual fee unit value instead of 1
        uint256 aliceTakerFee = (aliceTradeValue * feeTaker) / feeUnit;
        uint256 charlieTakerFee = (charlieTradeValue * feeTaker) / feeUnit;
        uint256 davidTakerFee = (davidTradeValue * feeTaker) / feeUnit;
        uint256 bobTakerFee = aliceTakerFee + charlieTakerFee + davidTakerFee;
        uint256 totalTakerFee = bobTakerFee;

        uint256 aliceMakerFee = (aliceQuantity * feeMaker) / feeUnit;
        uint256 charlieMakerFee = (charlieQuantity * feeMaker) / feeUnit;
        uint256 davidMakerFee = (davidQuantity) * feeMaker / feeUnit;
        uint256 totalMakerFee = aliceMakerFee + charlieMakerFee + davidMakerFee;

        uint256 bobQuantityUnwrapped = bobQuantity;
        uint256 bobMakerFee = (bobQuantityUnwrapped * feeMaker) / feeUnit;

        // Verify order book has correct orders
        (uint48 orderCountAlice, uint256 volumeAlice) = orderBook.getOrderQueue(IOrderBook.Side.BUY, alicePrice);
        (uint48 orderCountCharlie, uint256 volumeCharlie) = orderBook.getOrderQueue(IOrderBook.Side.BUY, charliePrice);
        (uint48 orderCountDavid, uint256 volumeDavid) = orderBook.getOrderQueue(IOrderBook.Side.BUY, davidPrice);

        assertEq(orderCountAlice, 1, "Should be 1 order at Alice's price");
        assertEq(orderCountCharlie, 1, "Should be 1 order at Charlie's price");
        assertEq(orderCountDavid, 1, "Should be 1 order at David's price");

        assertEq(volumeAlice, aliceQuantityUnwrapped, "Volume at Alice's price incorrect");
        assertEq(volumeCharlie, charlieQuantityUnwrapped, "Volume at Charlie's price incorrect");
        assertEq(volumeDavid, davidQuantityUnwrapped, "Volume at David's price incorrect");

        // Bob places a market sell order that should match against all orders
        vm.startPrank(bob);
        console.log("\n--- Bob places market sell order for 3 WETH ---");
        bool success = true;
        try router.placeMarketOrderWithDeposit(
            pool, bobQuantity, IOrderBook.Side.SELL, (bobQuantity * 95) / 100, 0, (bobQuantity * 95) / 100
        ) {
            // Order placed successfully
        } catch {
            success = false;
        }
        vm.stopPrank();

        // Log final balances for all users
        console.log("\n--- Final Balances After Multiple Matching ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);
        logBalance("David", david);
        logBalance("Fee Collector", feeCollector);

        // VERIFY BALANCES AFTER MATCHING

        // 1. Verify fee collector received correct fees
        uint256 feeCollectorBaseBalance = balanceManager.getBalance(feeCollector, baseCurrency);
        uint256 feeCollectorQuoteBalance = balanceManager.getBalance(feeCollector, quoteCurrency);

        uint256 baseBalanceDiff = feeCollectorBaseBalance - feeCollectorInitialBaseBalance;
        uint256 quoteBalanceDiff = feeCollectorQuoteBalance - feeCollectorInitialQuoteBalance;

        assertApproxEqAbs(baseBalanceDiff, bobMakerFee, 100, "Fee collector base balance incorrect");
        assertApproxEqAbs(quoteBalanceDiff, bobTakerFee, 100, "Fee collector quote balance incorrect");

        // 2. Verify Bob's balances
        // Bob should have:
        // - Decreased base token (WETH) by 3 ETH
        // - Increased quote token (USDC) by expectedBaseValue - takerFee
        uint256 bobCurrentBaseBalance = baseToken.balanceOf(bob) + balanceManager.getBalance(bob, baseCurrency);
        uint256 bobCurrentQuoteBalance = quoteToken.balanceOf(bob) + balanceManager.getBalance(bob, quoteCurrency);

        uint256 bobBaseDecrease = bobInitialBaseBalance - bobCurrentBaseBalance;
        uint256 bobQuoteIncrease = bobCurrentQuoteBalance - bobInitialQuoteBalance;

        assertApproxEqAbs(bobBaseDecrease, expectedMatchVolumeInBase, 100, "Bob's base token decrease incorrect");

        assertApproxEqAbs(
            bobQuoteIncrease, expectedMatchVolumeInQuote - bobTakerFee, 100, "Bob's quote token increase incorrect"
        );

        // 3. Verify Alice received her base tokens
        uint256 aliceCurrentBaseBalance = baseToken.balanceOf(alice) + balanceManager.getBalance(alice, baseCurrency);
        uint256 aliceCurrentQuoteBalance = quoteToken.balanceOf(alice) + balanceManager.getBalance(alice, quoteCurrency);

        uint256 aliceBaseIncrease = aliceCurrentBaseBalance - aliceInitialBaseBalance;
        uint256 aliceQuoteDecrease = aliceInitialQuoteBalance - aliceCurrentQuoteBalance;

        assertApproxEqAbs(
            aliceBaseIncrease, aliceQuantityUnwrapped - aliceMakerFee, 100, "Alice didn't receive correct base tokens"
        );

        assertApproxEqAbs(aliceQuoteDecrease, aliceExpectedLocked, 100, "Alice's quote token decrease incorrect");

        // 4. Verify Alice's locked quote tokens were spent
        uint256 aliceRemainingLocked = balanceManager.getLockedBalance(alice, address(orderBook), quoteCurrency);
        assertEq(aliceRemainingLocked, 0, "Alice should have no remaining locked balance");

        // 5. Verify Charlie received his base tokens
        uint256 charlieCurrentBaseBalance =
            baseToken.balanceOf(charlie) + balanceManager.getBalance(charlie, baseCurrency);
        uint256 charlieCurrentQuoteBalance =
            quoteToken.balanceOf(charlie) + balanceManager.getBalance(charlie, quoteCurrency);

        uint256 charlieBaseIncrease = charlieCurrentBaseBalance - charlieInitialBaseBalance;
        uint256 charlieQuoteDecrease = charlieInitialQuoteBalance - charlieCurrentQuoteBalance;

        console.log("charlie base increase", charlieBaseIncrease);
        console.log("charlie maker fee", charlieMakerFee);
        console.log("charlie base increase", charlieQuantityUnwrapped - charlieMakerFee);

        assertApproxEqAbs(
            charlieBaseIncrease,
            charlieQuantityUnwrapped - charlieMakerFee,
            100,
            "Charlie didn't receive correct base tokens"
        );

        assertApproxEqAbs(charlieQuoteDecrease, charlieExpectedLocked, 100, "Charlie's quote token decrease incorrect");

        // 6. Verify David received his base tokens
        uint256 davidCurrentBaseBalance = baseToken.balanceOf(david) + balanceManager.getBalance(david, baseCurrency);
        uint256 davidCurrentQuoteBalance = quoteToken.balanceOf(david) + balanceManager.getBalance(david, quoteCurrency);

        uint256 davidBaseIncrease = davidCurrentBaseBalance - davidInitialBaseBalance;
        uint256 davidQuoteDecrease = davidInitialQuoteBalance - davidCurrentQuoteBalance;

        assertApproxEqAbs(
            davidBaseIncrease, davidQuantityUnwrapped - davidMakerFee, 100, "David didn't receive correct base tokens"
        );

        assertApproxEqAbs(davidQuoteDecrease, davidExpectedLocked, 100, "David's quote token decrease incorrect");

        // Check that orderbook is now empty at those price levels
        (uint48 orderCount1, uint256 volume1) = orderBook.getOrderQueue(IOrderBook.Side.BUY, alicePrice);
        (uint48 orderCount2, uint256 volume2) = orderBook.getOrderQueue(IOrderBook.Side.BUY, charliePrice);
        (uint48 orderCount3, uint256 volume3) = orderBook.getOrderQueue(IOrderBook.Side.BUY, davidPrice);

        assertEq(orderCount1, 0, "Orders should be fully matched at price 2505");
        assertEq(orderCount2, 0, "Orders should be fully matched at price 2502");
        assertEq(orderCount3, 0, "Orders should be fully matched at price 2500");

        assertEq(volume1, 0, "Volume should be zero at price 2505");
        assertEq(volume2, 0, "Volume should be zero at price 2502");
        assertEq(volume3, 0, "Volume should be zero at price 2500");

        console.log("\n--- Verification Results ---");
        console.log("Alice's trade:");
        console.log("  Amount: 2505 USDC at 2505 WETH/USDC =", aliceTradeValue, "USDC");
        console.log("  Received: ", aliceBaseIncrease, "WETH");
        console.log("  Maker fee: ", aliceMakerFee, "WETH");

        console.log("Charlie's trade:");
        console.log("  Amount: 2502 USDC at 2502 WETH/USDC =", charlieTradeValue, "USDC");
        console.log("  Received: ", charlieBaseIncrease, "WETH");
        console.log("  Maker fee: ", charlieMakerFee, "WETH");

        console.log("David's trade:");
        console.log("  Amount: 2500 USDC at 2500 WETH/USDC =", davidTradeValue, "USDC");
        console.log("  Received: ", davidBaseIncrease, "WETH");
        console.log("  Maker fee: ", davidMakerFee, "WETH");

        console.log("Bob's total:");
        console.log("  Sold: 3 WETH");
        console.log("  Received: ", bobQuoteIncrease, "USDC");
        console.log("  Taker fee: ", bobTakerFee, "USDC");

        console.log("Fee collector received:");
        console.log("  Total maker fees: ", totalMakerFee);
        console.log("  Total taker fees: ", totalTakerFee);

        console.log("Total trade value:", totalTradeValue);
    }

    function testSingleMakerMultipleTakersPartialOrderMatchingWithHigherMakerQuantity() public {
        console.log("\n=== SIGLE MARKER MULTIPLE TAKERS PARTIAL ORDER MATCHING WITH HIGHER MAKER QUANTITY TEST ===");

        // Get initial balances for all participants
        uint256 aliceInitialBaseBalance = baseToken.balanceOf(alice);
        uint256 aliceInitialQuoteBalance = quoteToken.balanceOf(alice);
        uint256 bobInitialBaseBalance = baseToken.balanceOf(bob);
        uint256 bobInitialQuoteBalance = quoteToken.balanceOf(bob);
        uint256 charlieInitialBaseBalance = baseToken.balanceOf(charlie);
        uint256 charlieInitialQuoteBalance = quoteToken.balanceOf(charlie);
        uint256 davidInitialBaseBalance = baseToken.balanceOf(david);
        uint256 davidInitialQuoteBalance = quoteToken.balanceOf(david);

        uint256 feeCollectorInitialBaseBalance = balanceManager.getBalance(feeCollector, baseCurrency);
        uint256 feeCollectorInitialQuoteBalance = balanceManager.getBalance(feeCollector, quoteCurrency);

        // Define order parameters
        uint128 alicePrice = uint128(2500 * (10 ** quoteDecimals)); // Alice's limit price

        // Alice places a large sell order (maker)
        uint128 aliceQuantity = uint128(5 * (10 ** baseDecimals)); // 5 WETH

        // Multiple takers will place market orders to buy from Alice
        uint128 bobQuantity = uint128(1 * (10 ** baseDecimals)); // 1 WETH
        uint128 charlieQuantity = uint128(2 * (10 ** baseDecimals)); // 2 WETH
        uint128 davidQuantity = uint128((3 * (10 ** baseDecimals)) / 2); // 1.5 WETH

        // Calculate expected locked amounts
        uint256 aliceExpectedLocked = aliceQuantity;

        // Alice places a large sell limit order (maker)
        vm.startPrank(alice);
        console.log("--- Alice places sell order at 2500 USDC per WETH (5 WETH) ---");
        router.placeOrderWithDeposit(pool, alicePrice, aliceQuantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC);
        vm.stopPrank();

        // Verify Alice's base token was locked
        uint256 aliceLockedAfterOrder = balanceManager.getLockedBalance(alice, address(orderBook), baseCurrency);
        assertEq(aliceLockedAfterOrder, aliceExpectedLocked, "Alice's locked amount incorrect");

        // Verify Alice's wallet balance decreased
        assertApproxEqAbs(
            aliceInitialBaseBalance - baseToken.balanceOf(alice),
            aliceExpectedLocked,
            100,
            "Alice's wallet balance should have decreased by locked amount"
        );

        // Log balances after Alice places sell order
        console.log("--- Balances After Alice Places Sell Order ---");
        logBalance("Alice", alice);
        logBalance("Fee Collector", feeCollector);

        // Verify order book has correct sell order
        (uint48 orderCountAlice, uint256 volumeAlice) = orderBook.getOrderQueue(IOrderBook.Side.SELL, alicePrice);
        assertEq(orderCountAlice, 1, "Should be 1 order at Alice's price");
        assertEq(volumeAlice, aliceQuantity, "Volume at Alice's price incorrect");

        // Multiple takers place market buy orders to match against Alice's order

        // Bob's market buy order
        vm.startPrank(bob);
        console.log("\n--- Bob places market buy order for 1 WETH ---");
        router.placeMarketOrderWithDeposit(
            pool, bobQuantity, IOrderBook.Side.BUY, (bobQuantity * 95) / 100, 0, (bobQuantity * 95) / 100
        );
        vm.stopPrank();

        // Charlie's market buy order
        vm.startPrank(charlie);
        console.log("--- Charlie places market buy order for 2 WETH ---");
        router.placeMarketOrderWithDeposit(
            pool, charlieQuantity, IOrderBook.Side.BUY, (charlieQuantity * 95) / 100, 0, (charlieQuantity * 95) / 100
        );
        vm.stopPrank();

        // David's market buy order
        vm.startPrank(david);
        console.log("--- David places market buy order for 1.5 WETH ---");
        router.placeMarketOrderWithDeposit(
            pool, davidQuantity, IOrderBook.Side.BUY, (davidQuantity * 95) / 100, 0, (davidQuantity * 95) / 100
        );
        vm.stopPrank();

        // Log final balances for all users
        console.log("\n--- Final Balances After Multiple Takers Matching ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);
        logBalance("David", david);
        logBalance("Fee Collector", feeCollector);

        // VERIFY BALANCES AFTER MATCHING

        // Calculate expected values for filled amounts
        uint256 alicePriceUnwrapped = alicePrice;
        uint256 bobQuantityUnwrapped = bobQuantity;
        uint256 charlieQuantityUnwrapped = charlieQuantity;
        uint256 davidQuantityUnwrapped = davidQuantity;
        uint256 aliceQuantityUnwrapped = aliceQuantity;

        // Total quantity taken from Alice's order
        uint256 totalFilledQuantity = bobQuantityUnwrapped + charlieQuantityUnwrapped + davidQuantityUnwrapped;

        // Expected remaining quantity in Alice's order
        uint256 expectedRemainingQuantity = aliceQuantityUnwrapped - totalFilledQuantity;

        // Calculate trade values and fees
        uint256 bobTradeValue = bobQuantityUnwrapped;
        uint256 charlieTradeValue = charlieQuantityUnwrapped;
        uint256 davidTradeValue = davidQuantityUnwrapped;
        uint256 totalTradeValue = bobTradeValue + charlieTradeValue + davidTradeValue;

        uint256 bobTradeValueInQuote =
            (bobTradeValue * (10 ** quoteDecimals) * alicePriceUnwrapped) / (10 ** quoteDecimals) / (10 ** baseDecimals);
        uint256 charlieTradeValueInQuote = (charlieTradeValue * (10 ** quoteDecimals) * alicePriceUnwrapped)
            / (10 ** quoteDecimals) / (10 ** baseDecimals);
        uint256 davidTradeValueInQuote = (davidTradeValue * (10 ** quoteDecimals) * alicePriceUnwrapped)
            / (10 ** quoteDecimals) / (10 ** baseDecimals);
        uint256 totalFilledQuantityInQuote = totalFilledQuantity * (10 ** quoteDecimals) * alicePriceUnwrapped
            / (10 ** quoteDecimals) / (10 ** baseDecimals);

        uint256 feeUnit = balanceManager.getFeeUnit();

        // Taker fees (for buyers)
        uint256 bobTakerFee = (bobTradeValue * feeTaker) / feeUnit;
        uint256 charlieTakerFee = (charlieTradeValue * feeTaker) / feeUnit;
        uint256 davidTakerFee = (davidTradeValue * feeTaker) / feeUnit;
        uint256 totalTakerFee = bobTakerFee + charlieTakerFee + davidTakerFee;

        console.log("\n--- Taker fees ---");
        console.log("bob taker fee:", bobTakerFee);
        console.log("charlie taker fee:", charlieTakerFee);
        console.log("david taker fee:", davidTakerFee);
        console.log("total taker fee:", totalTakerFee);

        console.log("\n--- Trade values ---");
        console.log("bob trade value:", bobTradeValue);
        console.log("charlie trade value:", charlieTradeValue);
        console.log("david trade value:", davidTradeValue);
        console.log("total trade value:", totalTradeValue);

        // Maker fee (for Alice)
        uint256 aliceMakerFee = (
            (((totalFilledQuantity * (10 ** quoteDecimals)) / (10 ** baseDecimals)) * feeMaker) / feeUnit
        ) * (alicePriceUnwrapped / (10 ** quoteDecimals));

        console.log("total filled quantity:", totalFilledQuantity);
        console.log("alice price unwrapped:", alicePriceUnwrapped);

        console.log("\n--- Maker fee ---");
        console.log("alice maker fee:", aliceMakerFee);

        // 1. Verify fee collector received correct fees
        uint256 feeCollectorBaseBalance = balanceManager.getBalance(feeCollector, baseCurrency);
        uint256 feeCollectorQuoteBalance = balanceManager.getBalance(feeCollector, quoteCurrency);

        uint256 baseBalanceDiff = feeCollectorBaseBalance - feeCollectorInitialBaseBalance;
        uint256 quoteBalanceDiff = feeCollectorQuoteBalance - feeCollectorInitialQuoteBalance;

        assertApproxEqAbs(baseBalanceDiff, totalTakerFee, 100, "Fee collector base balance incorrect");
        assertApproxEqAbs(quoteBalanceDiff, aliceMakerFee, 100, "Fee collector quote balance incorrect");

        // 2. Verify Bob's balances
        uint256 bobCurrentBaseBalance = baseToken.balanceOf(bob) + balanceManager.getBalance(bob, baseCurrency);
        uint256 bobCurrentQuoteBalance = quoteToken.balanceOf(bob) + balanceManager.getBalance(bob, quoteCurrency);

        uint256 bobBaseIncrease = bobCurrentBaseBalance - bobInitialBaseBalance;
        uint256 bobQuoteDecrease = bobInitialQuoteBalance - bobCurrentQuoteBalance;

        assertApproxEqAbs(
            bobBaseIncrease, bobQuantityUnwrapped - bobTakerFee, 100, "Bob's base token increase incorrect"
        );
        assertApproxEqAbs(bobQuoteDecrease, bobTradeValueInQuote, 100, "Bob's quote token decrease incorrect");

        // 3. Verify Charlie's balances
        uint256 charlieCurrentBaseBalance =
            baseToken.balanceOf(charlie) + balanceManager.getBalance(charlie, baseCurrency);
        uint256 charlieCurrentQuoteBalance =
            quoteToken.balanceOf(charlie) + balanceManager.getBalance(charlie, quoteCurrency);

        uint256 charlieBaseIncrease = charlieCurrentBaseBalance - charlieInitialBaseBalance;
        uint256 charlieQuoteDecrease = charlieInitialQuoteBalance - charlieCurrentQuoteBalance;

        assertApproxEqAbs(
            charlieBaseIncrease,
            charlieQuantityUnwrapped - charlieTakerFee,
            100,
            "Charlie's base token increase incorrect"
        );
        assertApproxEqAbs(
            charlieQuoteDecrease, charlieTradeValueInQuote, 100, "Charlie's quote token decrease incorrect"
        );

        // 4. Verify David's balances
        uint256 davidCurrentBaseBalance = baseToken.balanceOf(david) + balanceManager.getBalance(david, baseCurrency);
        uint256 davidCurrentQuoteBalance = quoteToken.balanceOf(david) + balanceManager.getBalance(david, quoteCurrency);

        uint256 davidBaseIncrease = davidCurrentBaseBalance - davidInitialBaseBalance;
        uint256 davidQuoteDecrease = davidInitialQuoteBalance - davidCurrentQuoteBalance;

        assertApproxEqAbs(
            davidBaseIncrease, davidQuantityUnwrapped - davidTakerFee, 100, "David's base token increase incorrect"
        );
        assertApproxEqAbs(davidQuoteDecrease, davidTradeValueInQuote, 100, "David's quote token decrease incorrect");

        // 5. Verify Alice's balances
        uint256 aliceCurrentBaseBalance = baseToken.balanceOf(alice) + balanceManager.getBalance(alice, baseCurrency)
            + balanceManager.getLockedBalance(alice, address(orderBook), baseCurrency);
        uint256 aliceCurrentQuoteBalance = quoteToken.balanceOf(alice) + balanceManager.getBalance(alice, quoteCurrency);

        uint256 aliceBaseDecrease = aliceInitialBaseBalance - aliceCurrentBaseBalance;
        uint256 aliceQuoteIncrease = aliceCurrentQuoteBalance - aliceInitialQuoteBalance;

        assertApproxEqAbs(
            aliceBaseDecrease, totalFilledQuantity, 100, "Alice's base token decrease incorrect"
        );
        assertApproxEqAbs(
            aliceQuoteIncrease,
            totalFilledQuantityInQuote - aliceMakerFee,
            100,
            "Alice's quote token increase incorrect"
        );

        // 4. Verify Alice's remaining locked base tokens
        uint256 aliceRemainingLocked = balanceManager.getLockedBalance(alice, address(orderBook), baseCurrency);

        assertApproxEqAbs(
            aliceRemainingLocked, expectedRemainingQuantity, 100, "Alice's remaining locked balance incorrect"
        );

        // 5. Verify the order book state after all market orders
        (uint48 orderCountAfter, uint256 volumeAfter) = orderBook.getOrderQueue(IOrderBook.Side.SELL, alicePrice);

        if (expectedRemainingQuantity > 0) {
            assertEq(orderCountAfter, 1, "Alice's order should still be in the book");
            assertApproxEqAbs(
                volumeAfter, expectedRemainingQuantity, 100, "Remaining volume at Alice's price incorrect"
            );
        } else {
            assertEq(orderCountAfter, 0, "Alice's order should be fully matched and removed");
            assertEq(volumeAfter, 0, "Volume at Alice's price should be zero");
        }

        console.log("\n--- Verification Results ---");
        console.log("Alice's sell order:");
        console.log("  Original quantity: 5 WETH at 2500 USDC/WETH");
        console.log("  Total filled: ", totalFilledQuantity, "WETH");
        console.log("  Received: ", aliceQuoteIncrease, "USDC");
        console.log("  Maker fee: ", aliceMakerFee, "USDC");
        console.log("  Remaining quantity: ", expectedRemainingQuantity, "WETH");
        console.log("  Remaining locked: ", aliceRemainingLocked, "WETH");

        console.log("Bob's trade:");
        console.log("  Bought: ", bobQuantityUnwrapped, "WETH");
        console.log("  Paid: ", bobTradeValue + bobTakerFee, "USDC");
        console.log("  Taker fee: ", bobTakerFee, "USDC");

        console.log("Charlie's trade:");
        console.log("  Bought: ", charlieQuantityUnwrapped, "WETH");
        console.log("  Paid: ", charlieTradeValue + charlieTakerFee, "USDC");
        console.log("  Taker fee: ", charlieTakerFee, "USDC");

        console.log("David's trade:");
        console.log("  Bought: ", davidQuantityUnwrapped, "WETH");
        console.log("  Paid: ", davidTradeValue + davidTakerFee, "USDC");
        console.log("  Taker fee: ", davidTakerFee, "USDC");

        console.log("Fee collector received:");
        console.log("  Total taker fees: ", totalTakerFee, "USDC");
        console.log("  Alice maker fee: ", aliceMakerFee, "USDC");

        console.log("Total trade value:", totalTradeValue, "USDC");
    }

    function testMultipleMakersSingleTakerPartialOrderMatchingWithHigherMakerQuantity() public {
        console.log("\n=== MULTIPLE MAKERS SINGLE TAKER PARTIAL ORDER MATCHING WITH HIGHER MAKER QUANTITY TEST ===");

        // Get initial balances for all participants
        uint256 aliceInitialBaseBalance = baseToken.balanceOf(alice);
        uint256 aliceInitialQuoteBalance = quoteToken.balanceOf(alice);
        uint256 bobInitialBaseBalance = baseToken.balanceOf(bob);
        uint256 bobInitialQuoteBalance = quoteToken.balanceOf(bob);
        uint256 charlieInitialBaseBalance = baseToken.balanceOf(charlie);
        uint256 charlieInitialQuoteBalance = quoteToken.balanceOf(charlie);
        uint256 davidInitialBaseBalance = baseToken.balanceOf(david);
        uint256 davidInitialQuoteBalance = quoteToken.balanceOf(david);

        uint256 feeCollectorInitialBaseBalance = balanceManager.getBalance(feeCollector, baseCurrency);
        uint256 feeCollectorInitialQuoteBalance = balanceManager.getBalance(feeCollector, quoteCurrency);

        // Define order parameters
        uint128 alicePrice = uint128(2500 * (10 ** quoteDecimals)); // Alice's limit price

        // Alice places a large sell order (maker)
        uint128 aliceQuantity = uint128(5 * (10 ** baseDecimals)); // 5 WETH

        // Multiple takers will place market orders to buy from Alice
        uint128 bobQuantity = uint128(1 * (10 ** baseDecimals)); // 1 WETH
        uint128 charlieQuantity = uint128(2 * (10 ** baseDecimals)); // 2 WETH
        uint128 davidQuantity = uint128((3 * (10 ** baseDecimals)) / 2); // 1.5 WETH

        // Calculate expected locked amounts
        uint256 aliceExpectedLocked = aliceQuantity;

        // Alice places a large sell limit order (maker)
        vm.startPrank(alice);
        console.log("--- Alice places sell order at 2500 USDC per WETH (5 WETH) ---");
        router.placeOrderWithDeposit(pool, alicePrice, aliceQuantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC);
        vm.stopPrank();

        // Verify Alice's base token was locked
        uint256 aliceLockedAfterOrder = balanceManager.getLockedBalance(alice, address(orderBook), baseCurrency);
        assertEq(aliceLockedAfterOrder, aliceExpectedLocked, "Alice's locked amount incorrect");

        // Verify Alice's wallet balance decreased
        assertApproxEqAbs(
            aliceInitialBaseBalance - baseToken.balanceOf(alice),
            aliceExpectedLocked,
            100,
            "Alice's wallet balance should have decreased by locked amount"
        );

        // Log balances after Alice places sell order
        console.log("--- Balances After Alice Places Sell Order ---");
        logBalance("Alice", alice);
        logBalance("Fee Collector", feeCollector);

        // Verify order book has correct sell order
        (uint48 orderCountAlice, uint256 volumeAlice) = orderBook.getOrderQueue(IOrderBook.Side.SELL, alicePrice);
        assertEq(orderCountAlice, 1, "Should be 1 order at Alice's price");
        assertEq(volumeAlice, aliceQuantity, "Volume at Alice's price incorrect");

        // Multiple takers place market buy orders to match against Alice's order

        // Bob's market buy order
        vm.startPrank(bob);
        console.log("\n--- Bob places market buy order for 1 WETH ---");
        router.placeMarketOrderWithDeposit(
            pool, bobQuantity, IOrderBook.Side.BUY, (bobQuantity * 95) / 100, 0, (bobQuantity * 95) / 100
        );
        vm.stopPrank();

        // Charlie's market buy order
        vm.startPrank(charlie);
        console.log("--- Charlie places market buy order for 2 WETH ---");
        router.placeMarketOrderWithDeposit(
            pool, charlieQuantity, IOrderBook.Side.BUY, (charlieQuantity * 95) / 100, 0, (charlieQuantity * 95) / 100
        );
        vm.stopPrank();

        // David's market buy order
        vm.startPrank(david);
        console.log("--- David places market buy order for 1.5 WETH ---");
        router.placeMarketOrderWithDeposit(
            pool, davidQuantity, IOrderBook.Side.BUY, (davidQuantity * 95) / 100, 0, (davidQuantity * 95) / 100
        );
        vm.stopPrank();

        // Log final balances for all users
        console.log("\n--- Final Balances After Multiple Takers Matching ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);
        logBalance("David", david);
        logBalance("Fee Collector", feeCollector);

        // VERIFY BALANCES AFTER MATCHING

        // Calculate expected values for filled amounts
        uint256 alicePriceUnwrapped = alicePrice;
        uint256 bobQuantityUnwrapped = bobQuantity;
        uint256 charlieQuantityUnwrapped = charlieQuantity;
        uint256 davidQuantityUnwrapped = davidQuantity;
        uint256 aliceQuantityUnwrapped = aliceQuantity;

        // Total quantity taken from Alice's order
        uint256 totalFilledQuantity = bobQuantityUnwrapped + charlieQuantityUnwrapped + davidQuantityUnwrapped;

        // Expected remaining quantity in Alice's order
        uint256 expectedRemainingQuantity = aliceQuantityUnwrapped - totalFilledQuantity;

        // Calculate trade values and fees
        uint256 bobTradeValue = bobQuantityUnwrapped;
        uint256 charlieTradeValue = charlieQuantityUnwrapped;
        uint256 davidTradeValue = davidQuantityUnwrapped;
        uint256 totalTradeValue = bobTradeValue + charlieTradeValue + davidTradeValue;

        uint256 bobTradeValueInQuote =
            (bobTradeValue * (10 ** quoteDecimals) * alicePriceUnwrapped) / (10 ** quoteDecimals) / (10 ** baseDecimals);
        uint256 charlieTradeValueInQuote = (charlieTradeValue * (10 ** quoteDecimals) * alicePriceUnwrapped)
            / (10 ** quoteDecimals) / (10 ** baseDecimals);
        uint256 davidTradeValueInQuote = (davidTradeValue * (10 ** quoteDecimals) * alicePriceUnwrapped)
            / (10 ** quoteDecimals) / (10 ** baseDecimals);
        uint256 totalFilledQuantityInQuote = totalFilledQuantity * (10 ** quoteDecimals) * alicePriceUnwrapped
            / (10 ** quoteDecimals) / (10 ** baseDecimals);

        uint256 feeUnit = balanceManager.getFeeUnit();

        // Taker fees (for buyers)
        uint256 bobTakerFee = (bobTradeValue * feeTaker) / feeUnit;
        uint256 charlieTakerFee = (charlieTradeValue * feeTaker) / feeUnit;
        uint256 davidTakerFee = (davidTradeValue * feeTaker) / feeUnit;
        uint256 totalTakerFee = bobTakerFee + charlieTakerFee + davidTakerFee;

        console.log("\n--- Taker fees ---");
        console.log("bob taker fee:", bobTakerFee);
        console.log("charlie taker fee:", charlieTakerFee);
        console.log("david taker fee:", davidTakerFee);
        console.log("total taker fee:", totalTakerFee);

        console.log("\n--- Trade values ---");
        console.log("bob trade value:", bobTradeValue);
        console.log("charlie trade value:", charlieTradeValue);
        console.log("david trade value:", davidTradeValue);
        console.log("total trade value:", totalTradeValue);

        // Maker fee (for Alice)
        uint256 aliceMakerFee = (
            (((totalFilledQuantity * (10 ** quoteDecimals)) / (10 ** baseDecimals)) * feeMaker) / feeUnit
        ) * (alicePriceUnwrapped / (10 ** quoteDecimals));

        console.log("total filled quantity:", totalFilledQuantity);
        console.log("alice price unwrapped:", alicePriceUnwrapped);

        console.log("\n--- Maker fee ---");
        console.log("alice maker fee:", aliceMakerFee);

        // 1. Verify fee collector received correct fees
        uint256 feeCollectorBaseBalance = balanceManager.getBalance(feeCollector, baseCurrency);
        uint256 feeCollectorQuoteBalance = balanceManager.getBalance(feeCollector, quoteCurrency);

        uint256 baseBalanceDiff = feeCollectorBaseBalance - feeCollectorInitialBaseBalance;
        uint256 quoteBalanceDiff = feeCollectorQuoteBalance - feeCollectorInitialQuoteBalance;

        assertApproxEqAbs(baseBalanceDiff, totalTakerFee, 100, "Fee collector base balance incorrect");
        assertApproxEqAbs(quoteBalanceDiff, aliceMakerFee, 100, "Fee collector quote balance incorrect");

        // 2. Verify Bob's balances
        uint256 bobCurrentBaseBalance = baseToken.balanceOf(bob) + balanceManager.getBalance(bob, baseCurrency);
        uint256 bobCurrentQuoteBalance = quoteToken.balanceOf(bob) + balanceManager.getBalance(bob, quoteCurrency);

        uint256 bobBaseIncrease = bobCurrentBaseBalance - bobInitialBaseBalance;
        uint256 bobQuoteDecrease = bobInitialQuoteBalance - bobCurrentQuoteBalance;

        assertApproxEqAbs(
            bobBaseIncrease, bobQuantityUnwrapped - bobTakerFee, 100, "Bob's base token increase incorrect"
        );
        assertApproxEqAbs(bobQuoteDecrease, bobTradeValueInQuote, 100, "Bob's quote token decrease incorrect");

        // 3. Verify Charlie's balances
        uint256 charlieCurrentBaseBalance =
            baseToken.balanceOf(charlie) + balanceManager.getBalance(charlie, baseCurrency);
        uint256 charlieCurrentQuoteBalance =
            quoteToken.balanceOf(charlie) + balanceManager.getBalance(charlie, quoteCurrency);

        uint256 charlieBaseIncrease = charlieCurrentBaseBalance - charlieInitialBaseBalance;
        uint256 charlieQuoteDecrease = charlieInitialQuoteBalance - charlieCurrentQuoteBalance;

        assertApproxEqAbs(
            charlieBaseIncrease,
            charlieQuantityUnwrapped - charlieTakerFee,
            100,
            "Charlie's base token increase incorrect"
        );
        assertApproxEqAbs(
            charlieQuoteDecrease, charlieTradeValueInQuote, 100, "Charlie's quote token decrease incorrect"
        );

        // 4. Verify David's balances
        uint256 davidCurrentBaseBalance = baseToken.balanceOf(david) + balanceManager.getBalance(david, baseCurrency);
        uint256 davidCurrentQuoteBalance = quoteToken.balanceOf(david) + balanceManager.getBalance(david, quoteCurrency);

        uint256 davidBaseIncrease = davidCurrentBaseBalance - davidInitialBaseBalance;
        uint256 davidQuoteDecrease = davidInitialQuoteBalance - davidCurrentQuoteBalance;

        assertApproxEqAbs(
            davidBaseIncrease, davidQuantityUnwrapped - davidTakerFee, 100, "David's base token increase incorrect"
        );
        assertApproxEqAbs(davidQuoteDecrease, davidTradeValueInQuote, 100, "David's quote token decrease incorrect");

        // 5. Verify Alice's balances
        uint256 aliceCurrentBaseBalance = baseToken.balanceOf(alice) + balanceManager.getBalance(alice, baseCurrency)
            + balanceManager.getLockedBalance(alice, address(orderBook), baseCurrency);
        uint256 aliceCurrentQuoteBalance = quoteToken.balanceOf(alice) + balanceManager.getBalance(alice, quoteCurrency);

        uint256 aliceBaseDecrease = aliceInitialBaseBalance - aliceCurrentBaseBalance;
        uint256 aliceQuoteIncrease = aliceCurrentQuoteBalance - aliceInitialQuoteBalance;

        assertApproxEqAbs(
            aliceBaseDecrease, totalFilledQuantity, 100, "Alice's base token decrease incorrect"
        );
        assertApproxEqAbs(
            aliceQuoteIncrease,
            totalFilledQuantityInQuote - aliceMakerFee,
            100,
            "Alice's quote token increase incorrect"
        );

        // 6. Verify Alice's remaining locked base tokens
        uint256 aliceRemainingLocked = balanceManager.getLockedBalance(alice, address(orderBook), baseCurrency);

        assertApproxEqAbs(
            aliceRemainingLocked, expectedRemainingQuantity, 100, "Alice's remaining locked balance incorrect"
        );

        // 7. Verify the order book state after all market orders
        (uint48 orderCountAfter, uint256 volumeAfter) = orderBook.getOrderQueue(IOrderBook.Side.SELL, alicePrice);

        if (expectedRemainingQuantity > 0) {
            assertEq(orderCountAfter, 1, "Alice's order should still be in the book");
            assertApproxEqAbs(
                volumeAfter, expectedRemainingQuantity, 100, "Remaining volume at Alice's price incorrect"
            );
        } else {
            assertEq(orderCountAfter, 0, "Alice's order should be fully matched and removed");
            assertEq(volumeAfter, 0, "Volume at Alice's price should be zero");
        }

        console.log("\n--- Verification Results ---");
        console.log("Alice's sell order:");
        console.log("  Original quantity: 5 WETH at 2500 USDC/WETH");
        console.log("  Total filled: ", totalFilledQuantity, "WETH");
        console.log("  Received: ", aliceQuoteIncrease, "USDC");
        console.log("  Maker fee: ", aliceMakerFee, "USDC");
        console.log("  Remaining quantity: ", expectedRemainingQuantity, "WETH");
        console.log("  Remaining locked: ", aliceRemainingLocked, "WETH");

        console.log("Bob's trade:");
        console.log("  Bought: ", bobQuantityUnwrapped, "WETH");
        console.log("  Paid: ", bobTradeValue + bobTakerFee, "USDC");
        console.log("  Taker fee: ", bobTakerFee, "USDC");

        console.log("Charlie's trade:");
        console.log("  Bought: ", charlieQuantityUnwrapped, "WETH");
        console.log("  Paid: ", charlieTradeValue + charlieTakerFee, "USDC");
        console.log("  Taker fee: ", charlieTakerFee, "USDC");

        console.log("David's trade:");
        console.log("  Bought: ", davidQuantityUnwrapped, "WETH");
        console.log("  Paid: ", davidTradeValue + davidTakerFee, "USDC");
        console.log("  Taker fee: ", davidTakerFee, "USDC");

        console.log("Fee collector received:");
        console.log("  Total taker fees: ", totalTakerFee, "USDC");
        console.log("  Alice maker fee: ", aliceMakerFee, "USDC");

        console.log("Total trade value:", totalTradeValue, "USDC");
    }

    function testMultipleMakersSingleTakerPartialOrderMatchingWithHigherTakerQuantity() public {
        console.log("\n=== MULTIPLE MAKERS SINGLE TAKER PARTIAL ORDER MATCHING WITH HIGHER TAKER QUANTITY TEST ===");

        // Get initial balances for all participants
        uint256 aliceInitialBaseBalance = baseToken.balanceOf(alice);
        uint256 aliceInitialQuoteBalance = quoteToken.balanceOf(alice);
        uint256 bobInitialBaseBalance = baseToken.balanceOf(bob);
        uint256 bobInitialQuoteBalance = quoteToken.balanceOf(bob);
        uint256 charlieInitialBaseBalance = baseToken.balanceOf(charlie);
        uint256 charlieInitialQuoteBalance = quoteToken.balanceOf(charlie);
        uint256 davidInitialBaseBalance = baseToken.balanceOf(david);
        uint256 davidInitialQuoteBalance = quoteToken.balanceOf(david);

        uint256 feeCollectorInitialBaseBalance = balanceManager.getBalance(feeCollector, baseCurrency);
        uint256 feeCollectorInitialQuoteBalance = balanceManager.getBalance(feeCollector, quoteCurrency);

        // Define order parameters
        uint128 alicePrice = uint128(2500 * (10 ** quoteDecimals)); // Alice's limit price

        // Alice places a large sell order (maker)
        uint128 aliceQuantity = uint128(5 * (10 ** baseDecimals)); // 5 WETH

        // Multiple takers will place market orders to buy from Alice
        uint128 bobQuantity = uint128(1 * (10 ** baseDecimals)); // 1 WETH
        uint128 charlieQuantity = uint128(2 * (10 ** baseDecimals)); // 2 WETH
        uint128 davidQuantity = uint128((3 * (10 ** baseDecimals)) / 2); // 1.5 WETH

        // Calculate expected locked amounts
        uint256 aliceExpectedLocked = aliceQuantity;

        // Alice places a large sell limit order (maker)
        vm.startPrank(alice);
        console.log("--- Alice places sell order at 2500 USDC per WETH (5 WETH) ---");
        router.placeOrderWithDeposit(pool, alicePrice, aliceQuantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC);
        vm.stopPrank();

        // Verify Alice's base token was locked
        uint256 aliceLockedAfterOrder = balanceManager.getLockedBalance(alice, address(orderBook), baseCurrency);
        assertEq(aliceLockedAfterOrder, aliceExpectedLocked, "Alice's locked amount incorrect");

        // Verify Alice's wallet balance decreased
        assertApproxEqAbs(
            aliceInitialBaseBalance - baseToken.balanceOf(alice),
            aliceExpectedLocked,
            100,
            "Alice's wallet balance should have decreased by locked amount"
        );

        // Log balances after Alice places sell order
        console.log("--- Balances After Alice Places Sell Order ---");
        logBalance("Alice", alice);
        logBalance("Fee Collector", feeCollector);

        // Verify order book has correct sell order
        (uint48 orderCountAlice, uint256 volumeAlice) = orderBook.getOrderQueue(IOrderBook.Side.SELL, alicePrice);
        assertEq(orderCountAlice, 1, "Should be 1 order at Alice's price");
        assertEq(volumeAlice, aliceQuantity, "Volume at Alice's price incorrect");

        // Multiple takers place market buy orders to match against Alice's order

        // Bob's market buy order
        vm.startPrank(bob);
        console.log("\n--- Bob places market buy order for 1 WETH ---");
        router.placeMarketOrderWithDeposit(
            pool, bobQuantity, IOrderBook.Side.BUY, (bobQuantity * 95) / 100, 0, (bobQuantity * 95) / 100
        );
        vm.stopPrank();

        // Charlie's market buy order
        vm.startPrank(charlie);
        console.log("--- Charlie places market buy order for 2 WETH ---");
        router.placeMarketOrderWithDeposit(
            pool, charlieQuantity, IOrderBook.Side.BUY, (charlieQuantity * 95) / 100, 0, (charlieQuantity * 95) / 100
        );
        vm.stopPrank();

        // David's market buy order
        vm.startPrank(david);
        console.log("--- David places market buy order for 1.5 WETH ---");
        router.placeMarketOrderWithDeposit(
            pool, davidQuantity, IOrderBook.Side.BUY, (davidQuantity * 95) / 100, 0, (davidQuantity * 95) / 100
        );
        vm.stopPrank();

        // Log final balances for all users
        console.log("\n--- Final Balances After Multiple Takers Matching ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);
        logBalance("David", david);
        logBalance("Fee Collector", feeCollector);

        // VERIFY BALANCES AFTER MATCHING

        // Calculate expected values for filled amounts
        uint256 alicePriceUnwrapped = alicePrice;
        uint256 bobQuantityUnwrapped = bobQuantity;
        uint256 charlieQuantityUnwrapped = charlieQuantity;
        uint256 davidQuantityUnwrapped = davidQuantity;
        uint256 aliceQuantityUnwrapped = aliceQuantity;

        // Total quantity taken from Alice's order
        uint256 totalFilledQuantity = bobQuantityUnwrapped + charlieQuantityUnwrapped + davidQuantityUnwrapped;

        // Expected remaining quantity in Alice's order
        uint256 expectedRemainingQuantity = aliceQuantityUnwrapped - totalFilledQuantity;

        // Calculate trade values and fees
        uint256 bobTradeValue = bobQuantityUnwrapped;
        uint256 charlieTradeValue = charlieQuantityUnwrapped;
        uint256 davidTradeValue = davidQuantityUnwrapped;
        uint256 totalTradeValue = bobTradeValue + charlieTradeValue + davidTradeValue;

        uint256 bobTradeValueInQuote =
            (bobTradeValue * (10 ** quoteDecimals) * alicePriceUnwrapped) / (10 ** quoteDecimals) / (10 ** baseDecimals);
        uint256 charlieTradeValueInQuote = (charlieTradeValue * (10 ** quoteDecimals) * alicePriceUnwrapped)
            / (10 ** quoteDecimals) / (10 ** baseDecimals);
        uint256 davidTradeValueInQuote = (davidTradeValue * (10 ** quoteDecimals) * alicePriceUnwrapped)
            / (10 ** quoteDecimals) / (10 ** baseDecimals);
        uint256 totalFilledQuantityInQuote = totalFilledQuantity * (10 ** quoteDecimals) * alicePriceUnwrapped
            / (10 ** quoteDecimals) / (10 ** baseDecimals);

        uint256 feeUnit = balanceManager.getFeeUnit();

        // Taker fees (for buyers)
        uint256 bobTakerFee = (bobTradeValue * feeTaker) / feeUnit;
        uint256 charlieTakerFee = (charlieTradeValue * feeTaker) / feeUnit;
        uint256 davidTakerFee = (davidTradeValue * feeTaker) / feeUnit;
        uint256 totalTakerFee = bobTakerFee + charlieTakerFee + davidTakerFee;

        console.log("\n--- Taker fees ---");
        console.log("bob taker fee:", bobTakerFee);
        console.log("charlie taker fee:", charlieTakerFee);
        console.log("david taker fee:", davidTakerFee);
        console.log("total taker fee:", totalTakerFee);

        console.log("\n--- Trade values ---");
        console.log("bob trade value:", bobTradeValue);
        console.log("charlie trade value:", charlieTradeValue);
        console.log("david trade value:", davidTradeValue);
        console.log("total trade value:", totalTradeValue);

        // Maker fee (for Alice)
        uint256 aliceMakerFee = (
            (((totalFilledQuantity * (10 ** quoteDecimals)) / (10 ** baseDecimals)) * feeMaker) / feeUnit
        ) * (alicePriceUnwrapped / (10 ** quoteDecimals));

        console.log("total filled quantity:", totalFilledQuantity);
        console.log("alice price unwrapped:", alicePriceUnwrapped);

        console.log("\n--- Maker fee ---");
        console.log("alice maker fee:", aliceMakerFee);

        // 1. Verify fee collector received correct fees
        uint256 feeCollectorBaseBalance = balanceManager.getBalance(feeCollector, baseCurrency);
        uint256 feeCollectorQuoteBalance = balanceManager.getBalance(feeCollector, quoteCurrency);

        uint256 baseBalanceDiff = feeCollectorBaseBalance - feeCollectorInitialBaseBalance;
        uint256 quoteBalanceDiff = feeCollectorQuoteBalance - feeCollectorInitialQuoteBalance;

        assertApproxEqAbs(baseBalanceDiff, totalTakerFee, 100, "Fee collector base balance incorrect");
        assertApproxEqAbs(quoteBalanceDiff, aliceMakerFee, 100, "Fee collector quote balance incorrect");

        // 2. Verify Bob's balances
        uint256 bobCurrentBaseBalance = baseToken.balanceOf(bob) + balanceManager.getBalance(bob, baseCurrency);
        uint256 bobCurrentQuoteBalance = quoteToken.balanceOf(bob) + balanceManager.getBalance(bob, quoteCurrency);

        uint256 bobBaseIncrease = bobCurrentBaseBalance - bobInitialBaseBalance;
        uint256 bobQuoteDecrease = bobInitialQuoteBalance - bobCurrentQuoteBalance;

        assertApproxEqAbs(
            bobBaseIncrease, bobQuantityUnwrapped - bobTakerFee, 100, "Bob's base token increase incorrect"
        );
        assertApproxEqAbs(bobQuoteDecrease, bobTradeValueInQuote, 100, "Bob's quote token decrease incorrect");

        // 3. Verify Charlie's balances
        uint256 charlieCurrentBaseBalance =
            baseToken.balanceOf(charlie) + balanceManager.getBalance(charlie, baseCurrency);
        uint256 charlieCurrentQuoteBalance =
            quoteToken.balanceOf(charlie) + balanceManager.getBalance(charlie, quoteCurrency);

        uint256 charlieBaseIncrease = charlieCurrentBaseBalance - charlieInitialBaseBalance;
        uint256 charlieQuoteDecrease = charlieInitialQuoteBalance - charlieCurrentQuoteBalance;

        assertApproxEqAbs(
            charlieBaseIncrease,
            charlieQuantityUnwrapped - charlieTakerFee,
            100,
            "Charlie's base token increase incorrect"
        );
        assertApproxEqAbs(
            charlieQuoteDecrease, charlieTradeValueInQuote, 100, "Charlie's quote token decrease incorrect"
        );

        // 4. Verify David's balances
        uint256 davidCurrentBaseBalance = baseToken.balanceOf(david) + balanceManager.getBalance(david, baseCurrency);
        uint256 davidCurrentQuoteBalance = quoteToken.balanceOf(david) + balanceManager.getBalance(david, quoteCurrency);

        uint256 davidBaseIncrease = davidCurrentBaseBalance - davidInitialBaseBalance;
        uint256 davidQuoteDecrease = davidInitialQuoteBalance - davidCurrentQuoteBalance;

        assertApproxEqAbs(
            davidBaseIncrease, davidQuantityUnwrapped - davidTakerFee, 100, "David's base token increase incorrect"
        );
        assertApproxEqAbs(davidQuoteDecrease, davidTradeValueInQuote, 100, "David's quote token decrease incorrect");

        // 5. Verify Alice's balances
        uint256 aliceCurrentBaseBalance = baseToken.balanceOf(alice) + balanceManager.getBalance(alice, baseCurrency)
            + balanceManager.getLockedBalance(alice, address(orderBook), baseCurrency);
        uint256 aliceCurrentQuoteBalance = quoteToken.balanceOf(alice) + balanceManager.getBalance(alice, quoteCurrency);

        uint256 aliceBaseDecrease = aliceInitialBaseBalance - aliceCurrentBaseBalance;
        uint256 aliceQuoteIncrease = aliceCurrentQuoteBalance - aliceInitialQuoteBalance;

        assertApproxEqAbs(
            aliceBaseDecrease, totalFilledQuantity, 100, "Alice's base token decrease incorrect"
        );
        assertApproxEqAbs(
            aliceQuoteIncrease,
            totalFilledQuantityInQuote - aliceMakerFee,
            100,
            "Alice's quote token increase incorrect"
        );

        // 6. Verify Alice's remaining locked base tokens
        uint256 aliceRemainingLocked = balanceManager.getLockedBalance(alice, address(orderBook), baseCurrency);

        assertApproxEqAbs(
            aliceRemainingLocked, expectedRemainingQuantity, 100, "Alice's remaining locked balance incorrect"
        );

        // 7. Verify the order book state after all market orders
        (uint48 orderCountAfter, uint256 volumeAfter) = orderBook.getOrderQueue(IOrderBook.Side.SELL, alicePrice);

        if (expectedRemainingQuantity > 0) {
            assertEq(orderCountAfter, 1, "Alice's order should still be in the book");
            assertApproxEqAbs(
                volumeAfter, expectedRemainingQuantity, 100, "Remaining volume at Alice's price incorrect"
            );
        } else {
            assertEq(orderCountAfter, 0, "Alice's order should be fully matched and removed");
            assertEq(volumeAfter, 0, "Volume at Alice's price should be zero");
        }

        console.log("\n--- Verification Results ---");
        console.log("Alice's sell order:");
        console.log("  Original quantity: 5 WETH at 2500 USDC/WETH");
        console.log("  Total filled: ", totalFilledQuantity, "WETH");
        console.log("  Received: ", aliceQuoteIncrease, "USDC");
        console.log("  Maker fee: ", aliceMakerFee, "USDC");
        console.log("  Remaining quantity: ", expectedRemainingQuantity, "WETH");
        console.log("  Remaining locked: ", aliceRemainingLocked, "WETH");

        console.log("Bob's trade:");
        console.log("  Bought: ", bobQuantityUnwrapped, "WETH");
        console.log("  Paid: ", bobTradeValue + bobTakerFee, "USDC");
        console.log("  Taker fee: ", bobTakerFee, "USDC");

        console.log("Charlie's trade:");
        console.log("  Bought: ", charlieQuantityUnwrapped, "WETH");
        console.log("  Paid: ", charlieTradeValue + charlieTakerFee, "USDC");
        console.log("  Taker fee: ", charlieTakerFee, "USDC");

        console.log("David's trade:");
        console.log("  Bought: ", davidQuantityUnwrapped, "WETH");
        console.log("  Paid: ", davidTradeValue + davidTakerFee, "USDC");
        console.log("  Taker fee: ", davidTakerFee, "USDC");

        console.log("Fee collector received:");
        console.log("  Total taker fees: ", totalTakerFee, "USDC");
        console.log("  Alice maker fee: ", aliceMakerFee, "USDC");

        console.log("Total trade value:", totalTradeValue, "USDC");
    }

    function testMarketOrderWithNoLiquidity() public {
        console.log("\n=== MARKET ORDER WITH NO LIQUIDITY TEST ===");

        // Get initial balances for Bob
        uint256 bobInitialBaseBalance = baseToken.balanceOf(bob);
        uint256 bobInitialQuoteBalance = quoteToken.balanceOf(bob);

        // Define a market order quantity
        uint128 bobQuantity = uint128(2 * (10 ** baseDecimals)); // 2 WETH

        // Verify the order book is empty to start with
        (uint48 orderCountAlice, uint256 volumeAlice) =
            orderBook.getOrderQueue(IOrderBook.Side.BUY, uint128(2505 * (10 ** quoteDecimals)));
        assertEq(orderCountAlice, 0, "Order book should be empty at this price");
        assertEq(volumeAlice, 0, "Volume should be zero at this price");

        console.log("Initial order book state: Empty");
        console.log("Bob's initial WETH balance:", bobInitialBaseBalance);
        console.log("Bob's initial USDC balance:", bobInitialQuoteBalance);

        console.log("\n--- Bob attempts to place a market sell order for 2 WETH with no buy orders in the book ---");

        // Depending on your implementation, this might:
        // 1. Revert the transaction
        // 2. Return the tokens to the user
        // 3. Create a limit order at a predefined price

        // Wrap in a try-catch to handle potential revert
        vm.startPrank(bob);
        bool success = true;
        IPoolManager.Pool memory _poolDetails = _getPool(poolManager, baseCurrency, quoteCurrency);
        try router.placeMarketOrderWithDeposit(
            _poolDetails, bobQuantity, IOrderBook.Side.SELL, (bobQuantity * 95) / 100, 0, (bobQuantity * 95) / 100
        ) {
            // Order placed successfully
        } catch {
            success = false;
        }
        vm.stopPrank();

        assertTrue(!success, "Market order should fail when there is no liquidity");

        // Verify the order book state after the attempted market order
        (uint48 finalOrderCount, uint256 finalVolume) =
            orderBook.getOrderQueue(IOrderBook.Side.BUY, uint128(2505 * (10 ** quoteDecimals)));

        console.log("\n--- Final Order Book State ---");
        console.log("BUY order count:", finalOrderCount);
        console.log("BUY volume:", finalVolume);

        // Check for any sell orders that might have been created
        (uint48 sellOrderCount, uint256 sellVolume) = orderBook.getOrderQueue(IOrderBook.Side.SELL, uint128(1));
        console.log("SELL order count:", sellOrderCount);
        console.log("SELL volume:", sellVolume);

        // Verify Bob's final balances
        uint256 bobFinalBaseBalance = baseToken.balanceOf(bob) + balanceManager.getBalance(bob, baseCurrency);
        uint256 bobFinalQuoteBalance = quoteToken.balanceOf(bob) + balanceManager.getBalance(bob, quoteCurrency);

        console.log("\n--- Bob's Final Balances ---");
        console.log("WETH balance:", bobFinalBaseBalance);
        console.log("USDC balance:", bobFinalQuoteBalance);
        console.log("WETH change:", int256(bobFinalBaseBalance) - int256(bobInitialBaseBalance));
        console.log("USDC change:", int256(bobFinalQuoteBalance) - int256(bobInitialQuoteBalance));

        // Check locked balances
        uint256 bobLockedBaseBalance = balanceManager.getLockedBalance(bob, address(orderBook), baseCurrency);
        uint256 bobLockedQuoteBalance = balanceManager.getLockedBalance(bob, address(orderBook), quoteCurrency);

        console.log("WETH locked:", bobLockedBaseBalance);
        console.log("USDC locked:", bobLockedQuoteBalance);

        console.log("\n--- Test Summary ---");
        if (bobLockedBaseBalance > 0) {
            console.log("Result: Market order was converted to a limit order");
        } else if (bobFinalBaseBalance < bobInitialBaseBalance) {
            console.log("Result: Bob's tokens were taken despite no matching orders");
        } else if (success) {
            console.log("Result: Market order was accepted but no tokens were taken");
        } else {
            console.log("Result: Market order was rejected (transaction reverted)");
        }
    }

    // Helper function to log balances
    function logBalance(string memory user, address addr) internal view {
        console.log(user, "balances:");
        console.log("  WETH in wallet:", baseToken.balanceOf(addr));
        console.log("  USDC in wallet:", quoteToken.balanceOf(addr));
        console.log("  WETH available in contract:", balanceManager.getBalance(addr, baseCurrency));
        console.log(
            "  WETH locked in contract:", balanceManager.getLockedBalance(addr, address(orderBook), baseCurrency)
        );
        console.log("  USDC available in contract:", balanceManager.getBalance(addr, quoteCurrency));
        console.log(
            "  USDC locked in contract:", balanceManager.getLockedBalance(addr, address(orderBook), quoteCurrency)
        );
    }
}
