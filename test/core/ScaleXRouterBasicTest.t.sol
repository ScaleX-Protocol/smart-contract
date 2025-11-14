// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../src/core/BalanceManager.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/mocks/MockToken.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockWETH.sol";
import "../../src/core/OrderBook.sol";
import "../../src/core/PoolManager.sol";
import {SyntheticTokenFactory} from "../../src/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {IOrderBookErrors} from "../../src/core/interfaces/IOrderBookErrors.sol";
import {IPoolManager} from "../../src/core/interfaces/IPoolManager.sol";
import {IBalanceManagerErrors} from "../../src/core/interfaces/IBalanceManagerErrors.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import {PoolKey, PoolIdLibrary} from "../../src/core/libraries/Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Test, console} from "forge-std/Test.sol";

contract ScaleXRouterBasicTest is Test {
    ScaleXRouter private scalexRouter;
    PoolManager private poolManager;
    IBalanceManager private balanceManager;
    ITokenRegistry private tokenRegistry;
    SyntheticTokenFactory private tokenFactory;

    address private owner = address(0x1);
    address private feeReceiver = address(0x2);
    address private user = address(0x3);

    address alice = address(0x5);
    address bob = address(0x6);

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

    function setUp() public {
        BeaconDeployer beaconDeployer = new BeaconDeployer();

        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeReceiver, feeMaker, feeTaker))
        );
        balanceManager = IBalanceManager(payable(address(balanceManagerProxy)));

        IBeacon orderBookBeacon = new UpgradeableBeacon(address(new OrderBook()), owner);
        address orderBookBeaconAddress = address(orderBookBeacon);

        (BeaconProxy poolManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new PoolManager()),
            owner,
            abi.encodeCall(PoolManager.initialize, (owner, address(balanceManager), address(orderBookBeaconAddress)))
        );
        poolManager = PoolManager(address(poolManagerProxy));

        (BeaconProxy routerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new ScaleXRouter()),
            owner,
            abi.encodeCall(ScaleXRouter.initialize, (address(poolManager), address(balanceManager)))
        );
        scalexRouter = ScaleXRouter(address(routerProxy));

        mockWETH = new MockWETH();
        mockUSDC = new MockUSDC();
        mockWBTC = new MockToken("Mock WBTC", "mWBTC", 8);

        usdc = Currency.wrap(address(mockUSDC));
        weth = Currency.wrap(address(mockWETH));
        wbtc = Currency.wrap(address(mockWBTC));

        vm.deal(user, initialBalance);

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
        
        // Use the actual owner address
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
        
        IOrderBook.TradingRules memory defaultTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e14, // 0.0001 ETH
            minAmountMovement: 1e14, // 0.0001 ETH
            minOrderSize: 1e4, // 0.01 USDC
            minPriceMovement: 1e4 // 0.01 USDC with 6 decimals
        });
        
        poolManager.createPool(weth, usdc, defaultTradingRules);
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
            scalexRouter.placeLimitOrder(pool, price, quantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, quantity);
        vm.stopPrank();

        (uint48 orderCount, uint256 totalVolume) = scalexRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, price);

        // Assertions for order count and total volume
        assertEq(orderCount, 1, "Order count should be 1 after placing the limit order");
        assertEq(totalVolume, quantity, "Total volume should match the placed order quantity");

        // Assertions for the order details
        IOrderBook.Order memory order = scalexRouter.getOrder(weth, usdc, orderId);
        assertEq(order.id, orderId, "Order ID should match the returned order ID");
        assertEq(order.price, price, "Order price should match the placed price");
        assertEq(order.quantity, quantity, "Order quantity should match the placed quantity");
        assertEq(uint8(order.side), uint8(IOrderBook.Side.SELL), "Order side should be SELL");
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

        uint48 orderId =
            scalexRouter.placeLimitOrder(pool, price, quantity, side, IOrderBook.TimeInForce.GTC, uint128(quantity));
        
        (uint48 orderCount, uint256 totalVolume) = scalexRouter.getOrderQueue(weth, usdc, side, price);
        assertEq(orderCount, 1);
        assertEq(totalVolume, quantity);
    }
}