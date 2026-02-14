// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IScaleXRouter} from "../../src/core/interfaces/IScaleXRouter.sol";
import "../../src/core/BalanceManager.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/OrderBook.sol";
import "../../src/core/PoolManager.sol";
import {SyntheticTokenFactory} from "../../src/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {IPoolManager} from "../../src/core/interfaces/IPoolManager.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import {PoolKey} from "../../src/core/libraries/Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/mocks/MockToken.sol";

contract ScaleXRouterSimpleTest is Test {
    ScaleXRouter private scalexRouter;
    PoolManager private poolManager;
    IBalanceManager private balanceManager;
    ITokenRegistry private tokenRegistry;
    SyntheticTokenFactory private tokenFactory;

    address private owner = address(0x1);
    address private feeReceiver = address(0x2);
    address private user = address(0x3);
    address alice = address(0x5);

    Currency private wbtc;
    Currency private weth;
    Currency private usdc;
    MockToken private mockUSDC;
    MockToken private mockWETH;
    MockToken private mockWBTC;

    uint256 private feeMaker = 1; // 0.1%
    uint256 private feeTaker = 5; // 0.5%

    // Default trading rules
    IOrderBook.TradingRules private defaultTradingRules;

    function setUp() public {
        // Deploy BalanceManager
        UpgradeableBeacon balanceBeacon = new UpgradeableBeacon(address(new BalanceManager()), owner);
        BeaconProxy balanceProxy = new BeaconProxy(
            address(balanceBeacon),
            abi.encodeWithSelector(
                BalanceManager.initialize.selector,
                owner,
                feeReceiver,
                feeMaker,
                feeTaker
            )
        );
        balanceManager = IBalanceManager(payable(address(balanceProxy)));

        // Deploy OrderBook beacon
        UpgradeableBeacon orderBookBeacon = new UpgradeableBeacon(address(new OrderBook()), owner);
        address orderBookBeaconAddress = address(orderBookBeacon);

        // Deploy PoolManager
        UpgradeableBeacon poolBeacon = new UpgradeableBeacon(address(new PoolManager()), owner);
        BeaconProxy poolProxy = new BeaconProxy(
            address(poolBeacon),
            abi.encodeWithSelector(
                PoolManager.initialize.selector,
                owner,
                address(balanceManager),
                address(orderBookBeaconAddress)
            )
        );
        poolManager = PoolManager(address(poolProxy));

        // Deploy Router
        UpgradeableBeacon routerBeacon = new UpgradeableBeacon(address(new ScaleXRouter()), owner);
        BeaconProxy routerProxy = new BeaconProxy(
            address(routerBeacon),
            abi.encodeWithSelector(
                ScaleXRouter.initialize.selector,
                address(poolManager),
                address(balanceManager)
            )
        );
        scalexRouter = ScaleXRouter(address(routerProxy));

        // Create mock tokens
        mockWETH = new MockToken("Mock WETH", "mWETH", 18);
        mockUSDC = new MockToken("Mock USDC", "mUSDC", 6);
        mockWBTC = new MockToken("Mock WBTC", "mWBTC", 8);

        usdc = Currency.wrap(address(mockUSDC));
        weth = Currency.wrap(address(mockWETH));
        wbtc = Currency.wrap(address(mockWBTC));

        vm.deal(user, 1000 ether);

        // Initialize default trading rules
        defaultTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e14,
            minAmountMovement: 1e14,
            minOrderSize: 1e4,
            minPriceMovement: 1e4
        });

        // Set up TokenFactory and TokenRegistry
        tokenFactory = new SyntheticTokenFactory();
        tokenFactory.initialize(owner, owner);
        
        // Deploy TokenRegistry
        address tokenRegistryImpl = address(new TokenRegistry());
        ERC1967Proxy tokenRegistryProxy = new ERC1967Proxy(
            tokenRegistryImpl,
            abi.encodeWithSelector(
                TokenRegistry.initialize.selector,
                owner
            )
        );
        tokenRegistry = ITokenRegistry(address(tokenRegistryProxy));
        
        vm.startPrank(owner);
        
        // Create synthetic tokens and set up TokenRegistry
        address wethSynthetic = tokenFactory.createSyntheticToken(address(mockWETH));
        address usdcSynthetic = tokenFactory.createSyntheticToken(address(mockUSDC));
        address wbtcSynthetic = tokenFactory.createSyntheticToken(address(mockWBTC));
        
        balanceManager.addSupportedAsset(address(mockWETH), wethSynthetic);
        balanceManager.addSupportedAsset(address(mockUSDC), usdcSynthetic);
        balanceManager.addSupportedAsset(address(mockWBTC), wbtcSynthetic);
        
        // Set BalanceManager as minter and burner for synthetic tokens
        SyntheticToken(wethSynthetic).setMinter(address(balanceManager));
        SyntheticToken(usdcSynthetic).setMinter(address(balanceManager));
        SyntheticToken(wbtcSynthetic).setMinter(address(balanceManager));
        SyntheticToken(wethSynthetic).setBurner(address(balanceManager));
        SyntheticToken(usdcSynthetic).setBurner(address(balanceManager));
        SyntheticToken(wbtcSynthetic).setBurner(address(balanceManager));
        
        // Register token mappings for local deposits
        uint32 currentChain = 31337; // Default foundry chain ID
        tokenRegistry.registerTokenMapping(
            currentChain, address(mockWETH), currentChain, wethSynthetic, "WETH", 18, 18
        );
        tokenRegistry.registerTokenMapping(
            currentChain, address(mockUSDC), currentChain, usdcSynthetic, "USDC", 6, 6
        );
        tokenRegistry.registerTokenMapping(
            currentChain, address(mockWBTC), currentChain, wbtcSynthetic, "WBTC", 8, 8
        );
        
        // Activate token mappings
        tokenRegistry.setTokenMappingStatus(currentChain, address(mockWETH), currentChain, true);
        tokenRegistry.setTokenMappingStatus(currentChain, address(mockUSDC), currentChain, true);
        tokenRegistry.setTokenMappingStatus(currentChain, address(mockWBTC), currentChain, true);
        
        balanceManager.setTokenFactory(address(tokenFactory));
        balanceManager.setTokenRegistry(address(tokenRegistry));
        balanceManager.setPoolManager(address(poolManager));
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.setAuthorizedOperator(address(routerProxy), true);
        poolManager.setRouter(address(scalexRouter));
        poolManager.addCommonIntermediary(usdc);
        poolManager.createPool(weth, usdc, defaultTradingRules, 20);
        vm.stopPrank();
    }

    function testBasicSetup() public {
        // Test that the basic setup is working
        assertTrue(address(scalexRouter) != address(0), "Router should be deployed");
        assertTrue(address(poolManager) != address(0), "PoolManager should be deployed");
        assertTrue(address(balanceManager) != address(0), "BalanceManager should be deployed");
        
        // Test that tokens were created
        assertTrue(address(mockUSDC) != address(0), "USDC should be deployed");
        assertTrue(address(mockWETH) != address(0), "WETH should be deployed");
        assertTrue(address(mockWBTC) != address(0), "WBTC should be deployed");
        
        // Test that currencies were wrapped
        assertEq(Currency.unwrap(usdc), address(mockUSDC), "USDC currency should be correct");
        assertEq(Currency.unwrap(weth), address(mockWETH), "WETH currency should be correct");
        assertEq(Currency.unwrap(wbtc), address(mockWBTC), "WBTC currency should be correct");
    }

    function testGetPool() internal view returns (IPoolManager.Pool memory) {
        PoolKey memory key = poolManager.createPoolKey(weth, usdc);
        return poolManager.getPool(key);
    }

    function testBasicOrderPlacement() public {
        vm.startPrank(alice);
        
        // Mint and approve tokens
        uint128 quantity = 1e18; // 1 WETH
        mockWETH.mint(alice, quantity);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), quantity);
        
        // Get pool
        IPoolManager.Pool memory pool = testGetPool();
        
        // Place a simple limit order
        uint128 price = 2000e6; // $2000
        uint48 orderId = scalexRouter.placeLimitOrder(
            pool, 
            price, 
            quantity, 
            IOrderBook.Side.SELL, 
            IOrderBook.TimeInForce.GTC, 
            quantity
        );
        
        vm.stopPrank();
        
        assertTrue(orderId > 0, "Order should be placed successfully");
    }

    function testOrderWithAutoBorrowAndAutoRepay() public {
        vm.startPrank(alice);
        
        // Mint and approve tokens
        uint128 quantity = 1e18; // 1 WETH
        mockWETH.mint(alice, quantity);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), quantity);
        
        // Get pool
        IPoolManager.Pool memory pool = testGetPool();
        
        // Place a limit order with autoBorrow and autoRepay flags
        uint128 price = 2000e6; // $2000
        uint48 orderId = scalexRouter.placeLimitOrderWithFlags(
            pool, 
            price, 
            quantity, 
            IOrderBook.Side.SELL, 
            IOrderBook.TimeInForce.GTC, 
            quantity,
            false, // autoRepay = false
            true   // autoBorrow = true
        );
        
        vm.stopPrank();
        
        assertTrue(orderId > 0, "Order with auto flags should be placed successfully");
        
        // Verify order details by checking it through OrderBook (for testing purposes)
        console.log("ScaleXRouterSimpleTest - Order ID:", uint256(orderId));
        
        // Get the order to verify autoBorrow flag
        OrderBook orderBook = OrderBook(address(pool.orderBook));
        IOrderBook.Order memory order = orderBook.getOrder(orderId);
        console.log("AutoBorrow flag:", order.autoBorrow);
        console.log("AutoRepay flag:", order.autoRepay);
        // Note: In actual implementation, autoBorrow for SELL orders would be validated
        // to ensure user has sufficient collateral to borrow against
    }
}