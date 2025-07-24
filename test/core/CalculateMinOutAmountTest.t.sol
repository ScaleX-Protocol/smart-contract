
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@gtx/mocks/MockToken.sol";
import "@gtx/mocks/MockUSDC.sol";
import "@gtx/mocks/MockWETH.sol";
import "@gtxcore/BalanceManager.sol";
import "@gtxcore/GTXRouter.sol";
import "@gtxcore/OrderBook.sol";
import "@gtxcore/PoolManager.sol";
import {IOrderBook} from "@gtxcore/interfaces/IOrderBook.sol";
import {IOrderBookErrors} from "@gtxcore/interfaces/IOrderBookErrors.sol";
import {IPoolManager} from "@gtxcore/interfaces/IPoolManager.sol";
import {Currency} from "@gtxcore/libraries/Currency.sol";
import {PoolKey} from "@gtxcore/libraries/Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Test, console} from "forge-std/Test.sol";

contract CalculateMinOutAmountTest is Test {
    GTXRouter private gtxRouter;
    PoolManager private poolManager;
    BalanceManager private balanceManager;

    address private owner = address(0x1);
    address private feeReceiver = address(0x2);
    address private seller = address(0x3);
    address private buyer = address(0x4);

    Currency private weth;
    Currency private usdc;
    MockUSDC private mockUSDC;
    MockWETH private mockWETH;

    uint256 private feeMaker = 1; // 0.1%
    uint256 private feeTaker = 5; // 0.5%
    uint256 constant FEE_UNIT = 1000;

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

        usdc = Currency.wrap(address(mockUSDC));
        weth = Currency.wrap(address(mockWETH));

        // Initialize default trading rules
        defaultTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e14, // 0.0001 ETH
            minAmountMovement: 1e14, // 0.0001 ETH
            minOrderSize: 1e4, // 0.01 USDC
            minPriceMovement: 1e4 // 0.01 USDC with 6 decimals
        });

        // Setup contracts
        vm.startPrank(owner);
        balanceManager.setPoolManager(address(poolManager));
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.setAuthorizedOperator(address(routerProxy), true);
        poolManager.setRouter(address(gtxRouter));
        poolManager.addCommonIntermediary(usdc);
        poolManager.createPool(weth, usdc, defaultTradingRules);
        vm.stopPrank();
    }

    function _getPool(Currency currency1, Currency currency2) internal view returns (IPoolManager.Pool memory pool) {
        IPoolManager _poolManager = IPoolManager(poolManager);
        PoolKey memory key = _poolManager.createPoolKey(currency1, currency2);
        return _poolManager.getPool(key);
    }

    function _setupLiquidity() internal {
        // Setup sell orders to provide liquidity
        vm.startPrank(seller);

        // Mint WETH for seller
        mockWETH.mint(seller, 10 ether);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 10 ether);

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Place multiple sell orders at different prices to create a realistic order book
        // Order 1: 1 ETH at 2000 USDC
        gtxRouter.placeLimitOrder(pool, 2000e6, 1e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 1e18);

        // Order 2: 1 ETH at 2010 USDC
        gtxRouter.placeLimitOrder(pool, 2010e6, 1e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 1e18);

        // Order 3: 1 ETH at 2020 USDC
        gtxRouter.placeLimitOrder(pool, 2020e6, 1e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 1e18);

        vm.stopPrank();
    }

    function testCalculateMinOutAmountBasic() public {
        _setupLiquidity();

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Test calculating min output for 1000 USDC (should buy 0.5 ETH at 2000 USDC/ETH)
        uint256 quoteAmount = 1000e6; // 1000 USDC
        uint256 slippageBps = 500; // 5% slippage

        uint128 minOutAmount =
            gtxRouter.calculateMinOutAmountForMarket(pool, quoteAmount, IOrderBook.Side.BUY, slippageBps);

        console.log("Quote amount:", quoteAmount);
        console.log("Min out amount (with 5% slippage):", minOutAmount);

        // Expected calculation:
        // 1000 USDC can buy 0.5 ETH at 2000 USDC/ETH
        // After taker fee (0.5%): 0.5 ETH * (1000-5)/1000 = 0.4975 ETH
        // After slippage (5%): 0.4975 ETH * (10000-500)/10000 = 0.472625 ETH
        uint256 expectedBaseAmount = (1000e6 * 1e18) / 2000e6; // 0.5 ETH
        uint256 expectedAfterFees = (expectedBaseAmount * (FEE_UNIT - feeTaker)) / FEE_UNIT;
        uint256 expectedMinOut = (expectedAfterFees * (10_000 - slippageBps)) / 10_000;

        console.log("Expected min out:", expectedMinOut);

        // Allow for small rounding differences
        assertApproxEqRel(minOutAmount, expectedMinOut, 1e15, "Min out amount should match expected calculation");
        assertTrue(minOutAmount > 0, "Min out amount should be greater than 0");
    }

    function testCalculateMinOutAmountMultiplePriceLevels() public {
        _setupLiquidity();

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Test with amount that spans multiple price levels
        uint256 quoteAmount = 5000e6; // 5000 USDC
        uint256 slippageBps = 300; // 3% slippage

        uint128 minOutAmount =
            gtxRouter.calculateMinOutAmountForMarket(pool, quoteAmount, IOrderBook.Side.BUY, slippageBps);

        console.log("Large quote amount:", quoteAmount);
        console.log("Min out amount (multiple levels):", minOutAmount);

        // Should buy:
        // 2000 USDC -> 1 ETH at 2000 USDC/ETH
        // 2010 USDC -> 1 ETH at 2010 USDC/ETH
        // 990 USDC -> ~0.49 ETH at 2020 USDC/ETH
        // Total: ~2.49 ETH before fees

        assertTrue(minOutAmount > 2.3e18, "Should receive more than 2.3 ETH after fees and slippage");
        assertTrue(minOutAmount < 2.5e18, "Should receive less than 2.5 ETH due to fees and slippage");
    }

    function testPlaceMarketOrderWithCalculatedMinOut() public {
        _setupLiquidity();

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Buyer setup
        vm.startPrank(buyer);
        uint256 depositAmount = 1500e6; // 1500 USDC
        mockUSDC.mint(buyer, depositAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), depositAmount);

        // Calculate minimum output with 2% slippage tolerance
        uint256 slippageBps = 200; // 2%
        uint128 minOutAmount =
            gtxRouter.calculateMinOutAmountForMarket(pool, depositAmount, IOrderBook.Side.BUY, slippageBps);

        console.log("Deposit amount:", depositAmount);
        console.log("Calculated min out amount:", minOutAmount);

        // Record initial balances
        uint256 initialUSDCBalance = mockUSDC.balanceOf(buyer);
        uint256 initialWETHBalance = balanceManager.getBalance(buyer, weth);

        console.log("Initial USDC balance:", initialUSDCBalance);
        console.log("Initial WETH balance:", initialWETHBalance);

        // Place market order with deposit using calculated min out amount
        (uint48 orderId, uint128 filled) = gtxRouter.placeMarketOrder(
            pool,
            uint128(depositAmount), // Quote amount for BUY orders
            IOrderBook.Side.BUY,
            uint128(depositAmount), // Deposit amount
            minOutAmount // Min out amount
        );

        vm.stopPrank();

        // Verify the order was executed successfully
        assertTrue(orderId > 0, "Order ID should be greater than 0");
        assertTrue(filled >= minOutAmount, "Filled amount should be at least minOutAmount");

        // Check final balances
        uint256 finalWETHBalance = balanceManager.getBalance(buyer, weth);
        uint256 finalUSDCBalance = mockUSDC.balanceOf(buyer);

        console.log("Final WETH balance:", finalWETHBalance);
        console.log("Final USDC balance:", finalUSDCBalance);
        console.log("Filled amount:", filled);

        // Assertions
        assertEq(finalWETHBalance, filled, "WETH balance should equal filled amount");
        assertTrue(finalWETHBalance >= minOutAmount, "Final WETH balance should be at least minOutAmount");
        assertEq(finalUSDCBalance, 0, "All USDC should have been used");

        // The filled amount should be close to our calculated minimum (allowing for precision)
        assertApproxEqRel(
            filled,
            minOutAmount * 10_500 / 10_000,
            5e16,
            "Filled should be close to calculated minimum * (1 + slippage)"
        );
    }

    function testCalculateMinOutAmountZeroInput() public {
        _setupLiquidity();

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        uint128 minOutAmount = gtxRouter.calculateMinOutAmountForMarket(pool, 0, IOrderBook.Side.BUY, 500);
        assertEq(minOutAmount, 0, "Min out amount should be 0 for zero input");
    }

    function testCalculateMinOutAmountHighSlippage() public {
        _setupLiquidity();

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Test with very high slippage (should revert)
        vm.expectRevert(abi.encodeWithSelector(IOrderBookErrors.InvalidSlippageTolerance.selector, 11_000));
        gtxRouter.calculateMinOutAmountForMarket(pool, 1000e6, IOrderBook.Side.BUY, 11_000); // 110%
    }

    function testCalculateMinOutAmountNoLiquidity() public {
        // Don't setup liquidity
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        uint128 minOutAmount = gtxRouter.calculateMinOutAmountForMarket(pool, 1000e6, IOrderBook.Side.SELL, 500);
        assertEq(minOutAmount, 0, "Min out amount should be 0 when no liquidity");
    }

    function testMarketOrderSlippageProtection() public {
        _setupLiquidity();

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        vm.startPrank(buyer);
        uint256 depositAmount = 1000e6;
        mockUSDC.mint(buyer, depositAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), depositAmount);

        // Calculate a realistic min out for CLOB (with 0.5% slippage)
        uint128 realisticMinOut = gtxRouter.calculateMinOutAmountForMarket(pool, depositAmount, IOrderBook.Side.BUY, 50); // 0.5%

        // This should succeed with realistic CLOB slippage
        (uint48 orderId1, uint128 filled1) = gtxRouter.placeMarketOrder(
            pool,
            uint128(depositAmount), // Quote amount for BUY orders
            IOrderBook.Side.BUY,
            uint128(depositAmount), // Deposit amount
            realisticMinOut // Min out amount
        );

        assertTrue(filled1 >= realisticMinOut, "Should succeed with realistic 0.5% slippage");

        // Mint more USDC for second test
        mockUSDC.mint(buyer, depositAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), depositAmount);
        
        // Now try with an unrealistically high min out amount
        vm.expectRevert(); // Should revert due to SlippageTooHigh
        gtxRouter.placeMarketOrder(
            pool,
            uint128(depositAmount), // Quote amount for BUY orders
            IOrderBook.Side.BUY,
            uint128(depositAmount), // Deposit amount
            1e18 // Expecting 1 ETH but we can only get ~0.5 ETH with 1000 USDC
        );

        vm.stopPrank();
    }

    function testCLOBPrecisionWithVeryLowSlippage() public {
        _setupLiquidity();

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        vm.startPrank(buyer);
        uint256 depositAmount = 1000e6; // 1000 USDC
        mockUSDC.mint(buyer, depositAmount);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), depositAmount);

        // Test very tight slippage tolerances that would be impossible in AMMs
        uint128 minOut_01pct = gtxRouter.calculateMinOutAmountForMarket(pool, depositAmount, IOrderBook.Side.BUY, 10); // 0.1%
        uint128 minOut_05pct = gtxRouter.calculateMinOutAmountForMarket(pool, depositAmount, IOrderBook.Side.BUY, 50); // 0.5%
        uint128 minOut_1pct = gtxRouter.calculateMinOutAmountForMarket(pool, depositAmount, IOrderBook.Side.BUY, 100); // 1%

        console.log("Min out with 0.1% slippage:", minOut_01pct);
        console.log("Min out with 0.5% slippage:", minOut_05pct);
        console.log("Min out with 1.0% slippage:", minOut_1pct);

        // All should be different and ordered correctly
        assertTrue(minOut_01pct > minOut_05pct, "0.1% slippage should give higher min out than 0.5%");
        assertTrue(minOut_05pct > minOut_1pct, "0.5% slippage should give higher min out than 1%");

        // Test that very low slippage (0.1%) still works in CLOB
        (uint48 orderId, uint128 filled) = gtxRouter.placeMarketOrder(
            pool,
            uint128(depositAmount), // Quote amount for BUY orders
            IOrderBook.Side.BUY,
            uint128(depositAmount), // Deposit amount
            minOut_01pct // Very tight 0.1% slippage tolerance
        );

        assertTrue(filled >= minOut_01pct, "Should succeed even with very tight 0.1% slippage in CLOB");
        console.log("Actual filled amount:", filled);
        console.log("Difference from min out:", filled - minOut_01pct);

        vm.stopPrank();
    }

    function testCalculateMinOutAmountForMarketSell() public {
        _setupLiquidity();

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Setup buy orders to provide liquidity for selling
        vm.startPrank(buyer);
        mockUSDC.mint(buyer, 10_000e6); // 10,000 USDC
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 10_000e6);

        // Place buy orders at different prices
        gtxRouter.placeLimitOrder(pool, 1990e6, 1e18, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 1990e6);
        gtxRouter.placeLimitOrder(pool, 1980e6, 1e18, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 1980e6);
        gtxRouter.placeLimitOrder(pool, 1970e6, 1e18, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 1970e6);
        vm.stopPrank();

        // Test selling 1 ETH
        uint256 baseAmount = 1e18; // 1 ETH
        uint256 slippageBps = 300; // 3% slippage

        // Test SELL market order calculation
        uint128 minQuoteFromSell =
            gtxRouter.calculateMinOutAmountForMarket(pool, baseAmount, IOrderBook.Side.SELL, slippageBps);

        console.log("Base amount to sell:", baseAmount);
        console.log("Min quote from sell:", minQuoteFromSell);

        // Should receive close to 1990 USDC (minus fees and slippage)
        assertTrue(minQuoteFromSell > 1900e6, "Should receive more than 1900 USDC");
        assertTrue(minQuoteFromSell < 1990e6, "Should receive less than 1990 USDC due to fees and slippage");
    }

    function testCalculateMinOutAmountForMarketBoth() public {
        _setupLiquidity();

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Test BUY side
        uint256 quoteAmount = 1000e6; // 1000 USDC
        uint128 minBaseFromBuy = gtxRouter.calculateMinOutAmountForMarket(pool, quoteAmount, IOrderBook.Side.BUY, 200); // 2%
        uint128 minBaseFromMarket =
            gtxRouter.calculateMinOutAmountForMarket(pool, quoteAmount, IOrderBook.Side.BUY, 200);

        assertEq(minBaseFromBuy, minBaseFromMarket, "Both BUY calls should return same result");

        // Setup buy liquidity for sell test
        vm.startPrank(buyer);
        mockUSDC.mint(buyer, 5000e6);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 5000e6);
        gtxRouter.placeLimitOrder(pool, 1990e6, 2e18, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 3980e6); // 2 * 1990
        vm.stopPrank();

        // Test SELL side
        uint256 baseAmount = 1e18; // 1 ETH
        uint128 minQuoteFromSell = gtxRouter.calculateMinOutAmountForMarket(pool, baseAmount, IOrderBook.Side.SELL, 200); // 2%
        uint128 minQuoteFromMarket2 =
            gtxRouter.calculateMinOutAmountForMarket(pool, baseAmount, IOrderBook.Side.SELL, 200);

        assertEq(minQuoteFromSell, minQuoteFromMarket2, "Both SELL calls should return same result");

        console.log("BUY: 1000 USDC -> min", minBaseFromBuy, "ETH");
        console.log("SELL: 1 ETH -> min", minQuoteFromSell, "USDC");
    }

    function testCalculateMinOutAmountForMarketEdgeCases() public {
        _setupLiquidity();

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Test zero input
        uint128 result1 = gtxRouter.calculateMinOutAmountForMarket(pool, 0, IOrderBook.Side.BUY, 500);
        assertEq(result1, 0, "Zero input should return zero output");

        // Test high slippage tolerance (should revert)
        vm.expectRevert(abi.encodeWithSelector(IOrderBookErrors.InvalidSlippageTolerance.selector, 10_001));
        gtxRouter.calculateMinOutAmountForMarket(pool, 1000e6, IOrderBook.Side.BUY, 10_001);

        // Test with no liquidity on opposite side
        IPoolManager.Pool memory emptyPool = _getPool(weth, usdc);
        uint128 result2 = gtxRouter.calculateMinOutAmountForMarket(emptyPool, 1000e6, IOrderBook.Side.SELL, 500);
        // Should return 0 since there are no buy orders for selling into
        assertEq(result2, 0, "No liquidity should return zero output");
    }
}

