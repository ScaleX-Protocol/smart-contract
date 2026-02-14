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
import {PoolKey, PoolId, PoolIdLibrary} from "@scalexcore/libraries/Pool.sol";
import {FeeTier} from "@scalexcore/libraries/FeeTier.sol";
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

contract RangeLiquidityFeeTierTest is Test {
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

    Currency private wbtc;
    Currency private usdc;
    MockToken private mockWBTC;
    MockUSDC private mockUSDC;

    uint256 private constant INITIAL_WBTC = 10e8;
    uint256 private constant INITIAL_USDC = 1_000_000e6;

    IOrderBook.TradingRules private defaultTradingRules;

    function setUp() public {
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

        // Deploy TokenRegistry first (needed by Oracle)
        address tokenRegistryImpl = address(new TokenRegistry());
        ERC1967Proxy tokenRegistryProxy = new ERC1967Proxy(
            tokenRegistryImpl, abi.encodeWithSelector(TokenRegistry.initialize.selector, owner)
        );
        tokenRegistry = ITokenRegistry(address(tokenRegistryProxy));

        // Deploy Oracle (requires tokenRegistry)
        address oracleImpl = address(new Oracle());
        ERC1967Proxy oracleProxy =
            new ERC1967Proxy(oracleImpl, abi.encodeCall(Oracle.initialize, (owner, address(tokenRegistry))));
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

        // Set up TokenFactory
        tokenFactory = new SyntheticTokenFactory();
        tokenFactory.initialize(owner, owner);

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

        vm.stopPrank();

        mockWBTC.mint(liquidityProvider, INITIAL_WBTC);
        mockUSDC.mint(liquidityProvider, INITIAL_USDC);

        vm.startPrank(liquidityProvider);
        mockWBTC.approve(address(balanceManager), type(uint256).max);
        mockUSDC.approve(address(balanceManager), type(uint256).max);
        vm.stopPrank();
    }

    function testFeeTierLow() public {
        vm.startPrank(owner);
        poolManager.createPool(wbtc, usdc, defaultTradingRules, 20); // 0.2% fee tier
        IPoolManager.Pool memory pool = poolManager.getPool(poolManager.createPoolKey(wbtc, usdc, 20));
        oracle.addToken(address(mockWBTC), 1);
        oracle.setPrice(address(mockWBTC), 75_000e8);
        IOrderBook(address(pool.orderBook)).setOracle(address(oracle));
        vm.stopPrank();

        vm.startPrank(liquidityProvider);

        IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 20}),
            strategy: IRangeLiquidityManager.Strategy.UNIFORM,
            lowerPrice: 70_000e8,
            upperPrice: 80_000e8,
            tickCount: 10,
            tickSpacing: 50, // Matches 0.2% fee tier
            depositAmount: 100_000e6,
            depositCurrency: usdc,
            autoRebalance: false,
            rebalanceThresholdBps: 0
        });

        uint256 positionId = rangeLiquidityManager.createPosition(params);

        IRangeLiquidityManager.RangePosition memory position = rangeLiquidityManager.getPosition(positionId);
        assertEq(position.tickSpacing, 50, "Tick spacing should be 50 for 0.2% fee tier");

        vm.stopPrank();
    }

    function testFeeTierMedium() public {
        vm.startPrank(owner);
        poolManager.createPool(wbtc, usdc, defaultTradingRules, 50); // 0.5% fee tier
        IPoolManager.Pool memory pool = poolManager.getPool(poolManager.createPoolKey(wbtc, usdc, 50));
        oracle.addToken(address(mockWBTC), 1);
        oracle.setPrice(address(mockWBTC), 75_000e8);
        IOrderBook(address(pool.orderBook)).setOracle(address(oracle));
        vm.stopPrank();

        vm.startPrank(liquidityProvider);

        IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 50}),
            strategy: IRangeLiquidityManager.Strategy.UNIFORM,
            lowerPrice: 70_000e8,
            upperPrice: 80_000e8,
            tickCount: 10,
            tickSpacing: 200, // Matches 0.5% fee tier
            depositAmount: 100_000e6,
            depositCurrency: usdc,
            autoRebalance: false,
            rebalanceThresholdBps: 0
        });

        uint256 positionId = rangeLiquidityManager.createPosition(params);

        IRangeLiquidityManager.RangePosition memory position = rangeLiquidityManager.getPosition(positionId);
        assertEq(position.tickSpacing, 200, "Tick spacing should be 200 for 0.5% fee tier");

        vm.stopPrank();
    }

    function testFeeTierLibraryValidation() public pure {
        // Test valid fee tiers
        assertTrue(FeeTier.isValidFeeTier(20), "20 bps should be valid");
        assertTrue(FeeTier.isValidFeeTier(50), "50 bps should be valid");

        // Test invalid fee tiers
        assertFalse(FeeTier.isValidFeeTier(10), "10 bps should be invalid");
        assertFalse(FeeTier.isValidFeeTier(100), "100 bps should be invalid");
    }

    function testTickSpacingValidation() public pure {
        // Test valid tick spacing
        assertTrue(FeeTier.isValidTickSpacing(50), "50 tick spacing should be valid");
        assertTrue(FeeTier.isValidTickSpacing(200), "200 tick spacing should be valid");

        // Test invalid tick spacing
        assertFalse(FeeTier.isValidTickSpacing(100), "100 tick spacing should be invalid");
        assertFalse(FeeTier.isValidTickSpacing(1), "1 tick spacing should be invalid");
    }

    function testGetTickSpacingForFeeTier() public pure {
        assertEq(FeeTier.getTickSpacingForFeeTier(20), 50, "0.2% fee tier should have 50 tick spacing");
        assertEq(FeeTier.getTickSpacingForFeeTier(50), 200, "0.5% fee tier should have 200 tick spacing");
    }

    function testGetFeeTierForTickSpacing() public pure {
        assertEq(FeeTier.getFeeTierForTickSpacing(50), 20, "50 tick spacing should map to 0.2% fee tier");
        assertEq(FeeTier.getFeeTierForTickSpacing(200), 50, "200 tick spacing should map to 0.5% fee tier");
    }

    function testCalculateLPFee() public pure {
        // Test 0.5% fee tier with 0.1% protocol fee
        uint256 lpFee = FeeTier.calculateLPFee(50, 10);
        assertEq(lpFee, 40, "LP should earn 0.4% (40 bps)");

        // Test 0.2% fee tier with 0.1% protocol fee
        lpFee = FeeTier.calculateLPFee(20, 10);
        assertEq(lpFee, 10, "LP should earn 0.1% (10 bps)");
    }

    function testCalculateFeeAmount() public pure {
        // Test 100 USDC trade with 0.5% fee
        uint256 feeAmount = FeeTier.calculateFee(100e6, 50);
        assertEq(feeAmount, 0.5e6, "Fee should be 0.5 USDC");

        // Test 100 USDC trade with 0.2% fee
        feeAmount = FeeTier.calculateFee(100e6, 20);
        assertEq(feeAmount, 0.2e6, "Fee should be 0.2 USDC");
    }

    function testSplitFee() public pure {
        // Test split with 50 bps total fee and 10 bps protocol fee
        uint256 totalFee = 50e6; // 50 USDC

        (uint256 protocolFee, uint256 lpFee) = FeeTier.splitFee(totalFee, 50, 10);

        assertEq(protocolFee, 10e6, "Protocol should get 10 USDC");
        assertEq(lpFee, 40e6, "LP should get 40 USDC");
        assertEq(protocolFee + lpFee, totalFee, "Fees should sum to total");
    }

    function testPoolKeyWithFeeTier() public pure {
        Currency baseCurrency = Currency.wrap(address(0x1));
        Currency quoteCurrency = Currency.wrap(address(0x2));

        PoolKey memory key1 = PoolKey({baseCurrency: baseCurrency, quoteCurrency: quoteCurrency, feeTier: 20});

        PoolKey memory key2 = PoolKey({baseCurrency: baseCurrency, quoteCurrency: quoteCurrency, feeTier: 50});

        // Different fee tiers should produce different pool IDs
        bytes32 id1 = keccak256(abi.encode(key1));
        bytes32 id2 = keccak256(abi.encode(key2));

        assertTrue(id1 != id2, "Different fee tiers should create different pool IDs");
    }

    function testFeeTierConstants() public pure {
        assertEq(PoolIdLibrary.FEE_TIER_LOW, 20, "FEE_TIER_LOW should be 20 bps");
        assertEq(PoolIdLibrary.FEE_TIER_MEDIUM, 50, "FEE_TIER_MEDIUM should be 50 bps");
        assertEq(PoolIdLibrary.TICK_SPACING_LOW, 50, "TICK_SPACING_LOW should be 50");
        assertEq(PoolIdLibrary.TICK_SPACING_MEDIUM, 200, "TICK_SPACING_MEDIUM should be 200");
    }

    function testProtocolFeeInitialization() public view {
        // Check that protocol fee is initialized to 10 bps (0.1%)
        uint16 protocolFee = rangeLiquidityManager.getProtocolFee();
        assertEq(protocolFee, 10, "Default protocol fee should be 10 bps");
    }

    function testSetProtocolFee() public {
        vm.startPrank(owner);

        // Set protocol fee to 15 bps (0.15%)
        rangeLiquidityManager.setProtocolFee(15);

        uint16 protocolFee = rangeLiquidityManager.getProtocolFee();
        assertEq(protocolFee, 15, "Protocol fee should be 15 bps");

        vm.stopPrank();
    }

    function testCannotSetProtocolFeeTooHigh() public {
        vm.startPrank(owner);

        // Try to set protocol fee above 10% (1000 bps)
        vm.expectRevert();
        rangeLiquidityManager.setProtocolFee(1001);

        vm.stopPrank();
    }

    function testGetLPYield() public {
        vm.startPrank(owner);
        poolManager.createPool(wbtc, usdc, defaultTradingRules, 50);
        IPoolManager.Pool memory pool = poolManager.getPool(poolManager.createPoolKey(wbtc, usdc, 50));
        oracle.addToken(address(mockWBTC), 1);
        oracle.setPrice(address(mockWBTC), 75_000e8);
        IOrderBook(address(pool.orderBook)).setOracle(address(oracle));
        vm.stopPrank();

        vm.startPrank(liquidityProvider);

        IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 50}),
            strategy: IRangeLiquidityManager.Strategy.UNIFORM,
            lowerPrice: 70_000e8,
            upperPrice: 80_000e8,
            tickCount: 10,
            tickSpacing: 200,
            depositAmount: 100_000e6,
            depositCurrency: usdc,
            autoRebalance: false,
            rebalanceThresholdBps: 0
        });

        uint256 positionId = rangeLiquidityManager.createPosition(params);

        uint24 lpYield = rangeLiquidityManager.getLPYield(positionId);

        // With 0.5% fee tier and 0.1% protocol fee, LP should earn 0.4%
        assertEq(lpYield, 40, "LP yield should be 40 bps (0.4%)");

        vm.stopPrank();
    }
}
