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

abstract contract RangeLiquidityTestBase is Test {
    using CurrencyLibrary for Currency;

    RangeLiquidityManager internal rangeLiquidityManager;
    PoolManager internal poolManager;
    BalanceManager internal balanceManager;
    ScaleXRouter internal router;
    Oracle internal oracle;
    SyntheticTokenFactory internal tokenFactory;
    ITokenRegistry internal tokenRegistry;

    address internal owner = address(0x1);
    address internal feeReceiver = address(0x2);
    address internal liquidityProvider = address(0x3);
    address internal trader = address(0x4);
    address internal bot = address(0x5);

    Currency internal wbtc;
    Currency internal usdc;
    MockToken internal mockWBTC;
    MockUSDC internal mockUSDC;

    uint256 internal constant INITIAL_LP_WBTC = 10e8;
    uint256 internal constant INITIAL_LP_USDC = 1_000_000e6;
    uint256 internal constant INITIAL_TRADER_WBTC = 5e8;
    uint256 internal constant INITIAL_TRADER_USDC = 500_000e6;

    IOrderBook.TradingRules internal defaultTradingRules;

    function setUp() public virtual {
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

        // Create pool with 0.2% fee tier
        poolManager.createPool(wbtc, usdc, defaultTradingRules, 20);

        IPoolManager.Pool memory pool = poolManager.getPool(poolManager.createPoolKey(wbtc, usdc));

        // Configure oracle: register token, set price, and link to orderbook
        oracle.addToken(address(mockWBTC), 1);
        oracle.setPrice(address(mockWBTC), 75_000e8);
        IOrderBook(address(pool.orderBook)).setOracle(address(oracle));

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

    /// @dev Helper to create a default uniform position for the LP
    function _createDefaultPosition() internal returns (uint256 positionId) {
        return _createPosition(
            IRangeLiquidityManager.Strategy.UNIFORM,
            70_000e8,
            80_000e8,
            10,
            100_000e6,
            true,
            500
        );
    }

    function _createPosition(
        IRangeLiquidityManager.Strategy strategy,
        uint128 lowerPrice,
        uint128 upperPrice,
        uint8 tickCount,
        uint128 depositAmount,
        bool autoRebalance,
        uint16 rebalanceThresholdBps
    ) internal returns (uint256 positionId) {
        IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 20}),
            strategy: strategy,
            lowerPrice: lowerPrice,
            upperPrice: upperPrice,
            tickCount: tickCount,
            tickSpacing: 50,
            depositAmount: depositAmount,
            depositCurrency: usdc,
            autoRebalance: autoRebalance,
            rebalanceThresholdBps: rebalanceThresholdBps
        });
        positionId = rangeLiquidityManager.createPosition(params);
    }
}
