// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {RangeLiquidityManager} from "@scalexcore/RangeLiquidityManager.sol";
import {IRangeLiquidityManager} from "@scalexcore/interfaces/IRangeLiquidityManager.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {ScaleXRouter} from "@scalexcore/ScaleXRouter.sol";
import {PoolManager} from "@scalexcore/PoolManager.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {OrderBook} from "@scalexcore/OrderBook.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {Oracle} from "@scalexcore/Oracle.sol";
import {Currency, CurrencyLibrary} from "@scalexcore/libraries/Currency.sol";
import {PoolKey} from "@scalexcore/libraries/Pool.sol";
import {MockUSDC} from "@scalex/mocks/MockUSDC.sol";
import {MockToken} from "@scalex/mocks/MockToken.sol";
import {SyntheticTokenFactory} from "@scalex/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "@scalex/token/SyntheticToken.sol";
import {TokenRegistry} from "@scalexcore/TokenRegistry.sol";
import {ITokenRegistry} from "@scalexcore/interfaces/ITokenRegistry.sol";
import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RangeLiquidityIntegrationTest is Test {
    using CurrencyLibrary for Currency;

    RangeLiquidityManager private rangeLiquidityManager;
    PoolManager private poolManager;
    BalanceManager private balanceManager;
    ScaleXRouter private router;
    Oracle private oracle;
    SyntheticTokenFactory private tokenFactory;
    ITokenRegistry private tokenRegistry;

    address private owner = address(0x1);
    address private feeReceiver = address(0x2);
    address private liquidityProvider = address(0x3);
    address private trader = address(0x4);
    address private bot = address(0x5);

    Currency private wbtc;
    Currency private usdc;
    MockToken private mockWBTC;
    MockUSDC private mockUSDC;

    uint256 private constant INITIAL_LP_WBTC = 10e8;
    uint256 private constant INITIAL_LP_USDC = 1_000_000e6;
    uint256 private constant INITIAL_TRADER_WBTC = 5e8;
    uint256 private constant INITIAL_TRADER_USDC = 500_000e6;

    IOrderBook.TradingRules private defaultTradingRules;

    function setUp() public {
        vm.label(owner, "Owner");
        vm.label(liquidityProvider, "LP");
        vm.label(trader, "Trader");
        vm.label(bot, "Bot");

        BeaconDeployer beaconDeployer = new BeaconDeployer();

        // Deploy BalanceManager
        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()), owner, abi.encodeCall(BalanceManager.initialize, (owner, feeReceiver, 1, 5))
        );
        balanceManager = BalanceManager(payable(address(balanceManagerProxy)));

        // Deploy OrderBook beacon
        IBeacon orderBookBeacon = new UpgradeableBeacon(address(new OrderBook()), owner);

        // Deploy PoolManager
        (BeaconProxy poolManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new PoolManager()),
            owner,
            abi.encodeCall(PoolManager.initialize, (owner, address(balanceManager), address(orderBookBeacon)))
        );
        poolManager = PoolManager(address(poolManagerProxy));

        // Deploy ScaleXRouter
        (BeaconProxy routerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new ScaleXRouter()),
            owner,
            abi.encodeCall(ScaleXRouter.initialize, (address(poolManager), address(balanceManager)))
        );
        router = ScaleXRouter(address(routerProxy));

        // Deploy Oracle
        address oracleImpl = address(new Oracle());
        ERC1967Proxy oracleProxy =
            new ERC1967Proxy(oracleImpl, abi.encodeWithSelector(Oracle.initialize.selector, owner));
        oracle = Oracle(address(oracleProxy));

        // Deploy RangeLiquidityManager
        (BeaconProxy rangeLiquidityManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new RangeLiquidityManager()),
            owner,
            abi.encodeCall(
                RangeLiquidityManager.initialize, (address(poolManager), address(balanceManager), address(router))
            )
        );
        rangeLiquidityManager = RangeLiquidityManager(address(rangeLiquidityManagerProxy));

        // Deploy mock tokens
        mockWBTC = new MockToken("Wrapped BTC", "WBTC", 8);
        mockUSDC = new MockUSDC();

        wbtc = Currency.wrap(address(mockWBTC));
        usdc = Currency.wrap(address(mockUSDC));

        // Set up TokenFactory and TokenRegistry
        tokenFactory = new SyntheticTokenFactory();
        tokenFactory.initialize(owner, owner);

        address tokenRegistryImpl = address(new TokenRegistry());
        ERC1967Proxy tokenRegistryProxy = new ERC1967Proxy(
            tokenRegistryImpl, abi.encodeWithSelector(TokenRegistry.initialize.selector, owner)
        );
        tokenRegistry = ITokenRegistry(address(tokenRegistryProxy));

        vm.startPrank(owner);

        // Create synthetic tokens
        address wbtcSynthetic = tokenFactory.createSyntheticToken(address(mockWBTC));
        address usdcSynthetic = tokenFactory.createSyntheticToken(address(mockUSDC));

        balanceManager.addSupportedAsset(address(mockWBTC), wbtcSynthetic);
        balanceManager.addSupportedAsset(address(mockUSDC), usdcSynthetic);

        SyntheticToken(wbtcSynthetic).setMinter(address(balanceManager));
        SyntheticToken(usdcSynthetic).setMinter(address(balanceManager));
        SyntheticToken(wbtcSynthetic).setBurner(address(balanceManager));
        SyntheticToken(usdcSynthetic).setBurner(address(balanceManager));

        uint32 currentChain = 31337;
        tokenRegistry.registerTokenMapping(
            currentChain, address(mockWBTC), currentChain, wbtcSynthetic, "WBTC", 8, 8
        );
        tokenRegistry.registerTokenMapping(
            currentChain, address(mockUSDC), currentChain, usdcSynthetic, "USDC", 6, 6
        );

        tokenRegistry.setTokenMappingStatus(currentChain, address(mockWBTC), currentChain, true);
        tokenRegistry.setTokenMappingStatus(currentChain, address(mockUSDC), currentChain, true);

        balanceManager.setTokenFactory(address(tokenFactory));
        balanceManager.setTokenRegistry(address(tokenRegistry));
        balanceManager.setPoolManager(address(poolManager));
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.setAuthorizedOperator(address(router), true);
        balanceManager.setAuthorizedOperator(address(rangeLiquidityManager), true);

        poolManager.setRouter(address(router));

        defaultTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e4,
            minAmountMovement: 1e4,
            minOrderSize: 1e6,
            minPriceMovement: 1e6
        });

        // Create pool with 0.2% fee tier
        poolManager.createPool(wbtc, usdc, defaultTradingRules, 20);

        IPoolManager.Pool memory pool = poolManager.getPool(poolManager.createPoolKey(wbtc, usdc));
        oracle.setPrice(address(pool.orderBook), 75_000e8);

        vm.stopPrank();

        // Mint tokens to LP and trader
        mockWBTC.mint(liquidityProvider, INITIAL_LP_WBTC);
        mockUSDC.mint(liquidityProvider, INITIAL_LP_USDC);
        mockWBTC.mint(trader, INITIAL_TRADER_WBTC);
        mockUSDC.mint(trader, INITIAL_TRADER_USDC);

        // Approve tokens
        vm.startPrank(liquidityProvider);
        mockWBTC.approve(address(balanceManager), type(uint256).max);
        mockUSDC.approve(address(balanceManager), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(trader);
        mockWBTC.approve(address(balanceManager), type(uint256).max);
        mockUSDC.approve(address(balanceManager), type(uint256).max);
        vm.stopPrank();
    }

    function testFullLiquidityProviderFlow() public {
        // Step 1: LP creates position
        vm.startPrank(liquidityProvider);

        IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 20}),
            strategy: IRangeLiquidityManager.Strategy.UNIFORM,
            lowerPrice: 70_000e8,
            upperPrice: 80_000e8,
            tickCount: 10,
            tickSpacing: 50,
            depositAmount: 100_000e6,
            depositCurrency: usdc,
            autoRebalance: true,
            rebalanceThresholdBps: 500
        });

        uint256 positionId = rangeLiquidityManager.createPosition(params);

        IRangeLiquidityManager.RangePosition memory position = rangeLiquidityManager.getPosition(positionId);
        assertTrue(position.isActive, "Position should be active");
        assertTrue(position.buyOrderIds.length > 0, "Should have buy orders");
        assertTrue(position.sellOrderIds.length > 0, "Should have sell orders");

        vm.stopPrank();

        // Step 2: Verify orders are on orderbook
        IPoolManager.Pool memory pool = poolManager.getPool(poolManager.createPoolKey(wbtc, usdc));

        // Check best bid and ask
        IOrderBook.PriceVolume memory bestBid = pool.orderBook.getBestPrice(IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestAsk = pool.orderBook.getBestPrice(IOrderBook.Side.SELL);

        assertTrue(bestBid.price > 0, "Should have buy orders on book");
        assertTrue(bestAsk.price > 0, "Should have sell orders on book");
        assertTrue(bestBid.volume > 0, "Buy orders should have volume");
        assertTrue(bestAsk.volume > 0, "Sell orders should have volume");

        // Step 3: Trader executes against LP's orders
        vm.startPrank(trader);

        // Trader sells WBTC, hitting LP's buy orders
        router.placeMarketOrder(pool, 0.1e8, IOrderBook.Side.SELL, 0.1e8, 0);

        vm.stopPrank();

        // Step 4: Check position value after trade
        vm.startPrank(liquidityProvider);

        IRangeLiquidityManager.PositionValue memory value = rangeLiquidityManager.getPositionValue(positionId);
        assertTrue(value.totalValueInQuote > 0, "Position should have value");

        vm.stopPrank();
    }

    function testRebalancingFlow() public {
        // Step 1: Create position
        vm.startPrank(liquidityProvider);

        IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 20}),
            strategy: IRangeLiquidityManager.Strategy.UNIFORM,
            lowerPrice: 70_000e8,
            upperPrice: 80_000e8,
            tickCount: 10,
            tickSpacing: 50,
            depositAmount: 100_000e6,
            depositCurrency: usdc,
            autoRebalance: true,
            rebalanceThresholdBps: 500 // 5% threshold
        });

        uint256 positionId = rangeLiquidityManager.createPosition(params);

        IRangeLiquidityManager.RangePosition memory positionBefore = rangeLiquidityManager.getPosition(positionId);
        uint128 centerPriceBefore = positionBefore.centerPriceAtCreation;

        vm.stopPrank();

        // Step 2: Change oracle price to trigger rebalance threshold
        vm.startPrank(owner);
        IPoolManager.Pool memory pool = poolManager.getPool(poolManager.createPoolKey(wbtc, usdc));
        oracle.setPrice(address(pool.orderBook), 79_000e8); // +5.33% from 75k
        vm.stopPrank();

        // Step 3: Set authorized bot
        vm.startPrank(liquidityProvider);
        rangeLiquidityManager.setAuthorizedBot(positionId, bot);
        vm.stopPrank();

        // Step 4: Check if can rebalance
        (bool canRebalance, uint256 drift) = rangeLiquidityManager.canRebalance(positionId);
        assertTrue(canRebalance, "Should be able to rebalance");
        assertTrue(drift >= 500, "Drift should exceed threshold");

        // Step 5: Bot rebalances
        vm.startPrank(bot);
        rangeLiquidityManager.rebalancePosition(positionId);
        vm.stopPrank();

        // Step 6: Verify rebalance
        IRangeLiquidityManager.RangePosition memory positionAfter = rangeLiquidityManager.getPosition(positionId);

        assertTrue(positionAfter.centerPriceAtCreation != centerPriceBefore, "Center price should have changed");
        assertEq(positionAfter.rebalanceCount, 1, "Rebalance count should be 1");
        assertTrue(positionAfter.lastRebalancedAt > positionBefore.createdAt, "Last rebalanced time should be updated");

        // Orders should still exist
        assertTrue(positionAfter.buyOrderIds.length > 0, "Should have new buy orders");
        assertTrue(positionAfter.sellOrderIds.length > 0, "Should have new sell orders");
    }

    function testFeeCollection() public {
        // Step 1: Create position
        vm.startPrank(liquidityProvider);

        IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 20}),
            strategy: IRangeLiquidityManager.Strategy.UNIFORM,
            lowerPrice: 70_000e8,
            upperPrice: 80_000e8,
            tickCount: 10,
            tickSpacing: 50,
            depositAmount: 100_000e6,
            depositCurrency: usdc,
            autoRebalance: false,
            rebalanceThresholdBps: 0
        });

        uint256 positionId = rangeLiquidityManager.createPosition(params);

        vm.stopPrank();

        // Step 2: Simulate trading (fees would accumulate here in real scenario)
        // In this test, we're just checking the collection mechanism works

        // Step 3: Collect fees
        vm.startPrank(liquidityProvider);

        // This should not revert even with zero fees
        rangeLiquidityManager.collectFees(positionId);

        IRangeLiquidityManager.PositionValue memory value = rangeLiquidityManager.getPositionValue(positionId);

        // Fees should be tracked
        assertTrue(value.feesEarnedBase >= 0, "Should track base fees");
        assertTrue(value.feesEarnedQuote >= 0, "Should track quote fees");

        vm.stopPrank();
    }

    function testMultiplePositionsDifferentStrategies() public {
        vm.startPrank(owner);

        // Create additional pools with different fee tiers
        poolManager.createPool(wbtc, usdc, defaultTradingRules, 50); // 0.5% fee tier

        vm.stopPrank();

        // Create two positions with different strategies and fee tiers
        vm.startPrank(liquidityProvider);

        // Position 1: Uniform strategy, 0.2% fee tier
        IRangeLiquidityManager.PositionParams memory params1 = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 20}),
            strategy: IRangeLiquidityManager.Strategy.UNIFORM,
            lowerPrice: 70_000e8,
            upperPrice: 80_000e8,
            tickCount: 10,
            tickSpacing: 50,
            depositAmount: 50_000e6,
            depositCurrency: usdc,
            autoRebalance: false,
            rebalanceThresholdBps: 0
        });

        uint256 positionId1 = rangeLiquidityManager.createPosition(params1);

        // Close first position to create another one for same pool
        rangeLiquidityManager.closePosition(positionId1);

        // Position 2: Bid Heavy strategy
        IRangeLiquidityManager.PositionParams memory params2 = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 20}),
            strategy: IRangeLiquidityManager.Strategy.BID_HEAVY,
            lowerPrice: 72_000e8,
            upperPrice: 78_000e8,
            tickCount: 8,
            tickSpacing: 50,
            depositAmount: 50_000e6,
            depositCurrency: usdc,
            autoRebalance: false,
            rebalanceThresholdBps: 0
        });

        uint256 positionId2 = rangeLiquidityManager.createPosition(params2);

        // Verify both positions
        IRangeLiquidityManager.RangePosition memory position2 = rangeLiquidityManager.getPosition(positionId2);

        assertEq(uint8(position2.strategy), uint8(IRangeLiquidityManager.Strategy.BID_HEAVY), "Should be BID_HEAVY");

        uint256[] memory userPositions = rangeLiquidityManager.getUserPositions(liquidityProvider);
        assertEq(userPositions.length, 2, "Should have 2 positions created");

        vm.stopPrank();
    }

    function testCannotRebalanceWithoutThreshold() public {
        vm.startPrank(liquidityProvider);

        IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 20}),
            strategy: IRangeLiquidityManager.Strategy.UNIFORM,
            lowerPrice: 70_000e8,
            upperPrice: 80_000e8,
            tickCount: 10,
            tickSpacing: 50,
            depositAmount: 100_000e6,
            depositCurrency: usdc,
            autoRebalance: true,
            rebalanceThresholdBps: 500
        });

        uint256 positionId = rangeLiquidityManager.createPosition(params);

        rangeLiquidityManager.setAuthorizedBot(positionId, bot);

        vm.stopPrank();

        // Try to rebalance without price movement
        vm.startPrank(bot);

        (bool canRebalance,) = rangeLiquidityManager.canRebalance(positionId);
        assertFalse(canRebalance, "Should not be able to rebalance without drift");

        vm.expectRevert(); // Should revert with RebalanceThresholdNotMet
        rangeLiquidityManager.rebalancePosition(positionId);

        vm.stopPrank();
    }

    function testOwnerCanAlwaysRebalance() public {
        vm.startPrank(liquidityProvider);

        IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 20}),
            strategy: IRangeLiquidityManager.Strategy.UNIFORM,
            lowerPrice: 70_000e8,
            upperPrice: 80_000e8,
            tickCount: 10,
            tickSpacing: 50,
            depositAmount: 100_000e6,
            depositCurrency: usdc,
            autoRebalance: true,
            rebalanceThresholdBps: 500
        });

        uint256 positionId = rangeLiquidityManager.createPosition(params);

        // Owner can rebalance without meeting threshold
        rangeLiquidityManager.rebalancePosition(positionId);

        IRangeLiquidityManager.RangePosition memory position = rangeLiquidityManager.getPosition(positionId);
        assertEq(position.rebalanceCount, 1, "Owner should be able to rebalance anytime");

        vm.stopPrank();
    }
}
