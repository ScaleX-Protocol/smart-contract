// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import "@scalexcore/interfaces/IOrderBook.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {Currency} from "@scalexcore/libraries/Currency.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {MockToken} from "@scalex/mocks/MockToken.sol";
import {ScaleXRouter} from "@scalexcore/ScaleXRouter.sol";
import {OrderBook} from "@scalexcore/OrderBook.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";

import {PoolKey} from "@scalexcore/libraries/Pool.sol";

import {PoolManager} from "@scalexcore/PoolManager.sol";
import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {SyntheticTokenFactory} from "../../src/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MarketOrderQuantityValidationTest is Test {
    OrderBook public orderBook;

    IOrderBook.TradingRules rules;

    address alice = address(0x1);
    address bob = address(0x2);

    address owner = address(0x5);

    address baseTokenAddress;
    address quoteTokenAddress;

    Currency baseCurrency;
    Currency quoteCurrency;

    uint256 feeMaker = 1; // Example fee maker value
    uint256 feeTaker = 1; // Example fee taker value
    uint256 lotSize = 1e18; // Example lot size
    uint256 maxOrderAmount = 500e18; // Example max order amount

    ScaleXRouter router;
    PoolManager poolManager;
    IBalanceManager balanceManager;
    ITokenRegistry tokenRegistry;
    SyntheticTokenFactory tokenFactory;

    function setUp() public {
        baseTokenAddress = address(new MockToken("ETH", "ETH", 18));
        quoteTokenAddress = address(new MockToken("USDC", "USDC", 6));

        rules = IOrderBook.TradingRules({
            minTradeAmount: 1e14, // 0.0001 ETH (18 decimals)
            minAmountMovement: 1e13, // 0.00001 ETH (18 decimals)
            minOrderSize: 1e4, // 0.01 USDC (6 decimals)
            minPriceMovement: 1e4 // 0.01 USDC (6 decimals)
        });

        MockToken(baseTokenAddress).mint(alice, 100e18);
        MockToken(baseTokenAddress).mint(bob, 100e18);
        MockToken(quoteTokenAddress).mint(alice, 100_000e6);
        MockToken(quoteTokenAddress).mint(bob, 100_000e6);

        baseCurrency = Currency.wrap(baseTokenAddress);
        quoteCurrency = Currency.wrap(quoteTokenAddress);

        PoolKey memory key =
            PoolKey({baseCurrency: Currency.wrap(baseTokenAddress), quoteCurrency: Currency.wrap(quoteTokenAddress), feeTier: 20});

        BeaconDeployer beaconDeployer = new BeaconDeployer();

        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, owner, feeMaker, feeTaker))
        );
        balanceManager = IBalanceManager(payable(address(balanceManagerProxy)));

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
        router = ScaleXRouter(address(routerProxy));

        vm.startPrank(owner);
        
        // Create synthetic tokens and set up TokenRegistry
        address baseSynthetic = tokenFactory.createSyntheticToken(baseTokenAddress);
        address quoteSynthetic = tokenFactory.createSyntheticToken(quoteTokenAddress);
        
        balanceManager.addSupportedAsset(baseTokenAddress, baseSynthetic);
        balanceManager.addSupportedAsset(quoteTokenAddress, quoteSynthetic);
        
        // Set BalanceManager as minter and burner for synthetic tokens
        SyntheticToken(baseSynthetic).setMinter(address(balanceManager));
        SyntheticToken(quoteSynthetic).setMinter(address(balanceManager));
        SyntheticToken(baseSynthetic).setBurner(address(balanceManager));
        SyntheticToken(quoteSynthetic).setBurner(address(balanceManager));
        
        // Register token mappings for local deposits
        uint32 currentChain = 31337; // Default foundry chain ID
        tokenRegistry.registerTokenMapping(
            currentChain, baseTokenAddress, currentChain, baseSynthetic, "ETH", 18, 18
        );
        tokenRegistry.registerTokenMapping(
            currentChain, quoteTokenAddress, currentChain, quoteSynthetic, "USDC", 6, 6
        );
        
        // Activate token mappings
        tokenRegistry.setTokenMappingStatus(currentChain, baseTokenAddress, currentChain, true);
        tokenRegistry.setTokenMappingStatus(currentChain, quoteTokenAddress, currentChain, true);
        
        balanceManager.setTokenFactory(address(tokenFactory));
        balanceManager.setTokenRegistry(address(tokenRegistry));
        
        balanceManager.setPoolManager(address(poolManager));
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.setAuthorizedOperator(address(routerProxy), true);
        poolManager.setRouter(address(router));
        vm.stopPrank();

        vm.startPrank(alice);
        MockToken(baseTokenAddress).approve(address(balanceManager), type(uint256).max);
        MockToken(quoteTokenAddress).approve(address(balanceManager), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        MockToken(baseTokenAddress).approve(address(balanceManager), type(uint256).max);
        MockToken(quoteTokenAddress).approve(address(balanceManager), type(uint256).max);
        vm.stopPrank();

        poolManager.createPool(baseCurrency, quoteCurrency, rules, 20);

        key = poolManager.createPoolKey(baseCurrency, quoteCurrency);

        IPoolManager.Pool memory pool = poolManager.getPool(key);
        orderBook = OrderBook(address(pool.orderBook));
    }

    function testSimpleMarketOrder() public {
        IPoolManager.Pool memory pool = _getPool(baseCurrency, quoteCurrency);

        // Record initial balances
        uint256 aliceInitialETH = MockToken(baseTokenAddress).balanceOf(alice);
        uint256 aliceInitialUSDC = MockToken(quoteTokenAddress).balanceOf(alice);
        uint256 bobInitialETH = MockToken(baseTokenAddress).balanceOf(bob);
        uint256 bobInitialUSDC = MockToken(quoteTokenAddress).balanceOf(bob);

        // Alice sells 4 ETH at 2000 USD each
        vm.startPrank(alice);
        router.placeLimitOrder(pool, 2000e6, 4e18, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 4e18);
        vm.stopPrank();

        // Bob buys with 2000 USD (should get 1 ETH)
        // For BUY market orders, quantity is the quote amount (USDC)
        vm.startPrank(bob);

        router.placeMarketOrder(pool, 2000e6, IOrderBook.Side.BUY, 2000e6, 0);
        vm.stopPrank();

        // Verify order book state: 3 ETH remaining
        (, uint256 remainingVolume) = orderBook.getOrderQueue(IOrderBook.Side.SELL, 2000e6);
        assertEq(remainingVolume, 3e18, "Should have 3 ETH remaining in sell order");

        // Check balance manager balances (internal balances after trade)
        uint256 aliceETHBalance = balanceManager.getBalance(alice, baseCurrency);
        uint256 aliceUSDCBalance = balanceManager.getBalance(alice, quoteCurrency);
        uint256 bobETHBalance = balanceManager.getBalance(bob, baseCurrency);
        uint256 bobUSDCBalance = balanceManager.getBalance(bob, quoteCurrency);

        console.log("Alice ETH balance in BalanceManager:", aliceETHBalance);
        console.log("Alice USDC balance in BalanceManager:", aliceUSDCBalance);
        console.log("Bob ETH balance in BalanceManager:", bobETHBalance);
        console.log("Bob USDC balance in BalanceManager:", bobUSDCBalance);

        // Verify order book state
        assertEq(remainingVolume, 3e18, "Should have 3 ETH remaining in sell order");

        // Verify current best price is still 2000 USDC (the remaining order)
        IOrderBook.PriceVolume memory bestPriceVolume = orderBook.getBestPrice(IOrderBook.Side.SELL);
        assertEq(bestPriceVolume.price, 2000e6, "Best sell price should still be 2000 USDC");
        assertEq(bestPriceVolume.volume, 3e18, "Best sell volume should be 3 ETH remaining");

        // Verify balance changes with fees
        assertEq(aliceUSDCBalance, 1998e6, "Alice should have received 2000 USDC minus 2 USDC fee");
        assertEq(bobETHBalance, 999e15, "Bob should have 0.999 ETH in balance manager (1 ETH minus 0.001 ETH fee)");
    }

    function _getPool(Currency currency1, Currency currency2) internal view returns (IPoolManager.Pool memory pool) {
        IPoolManager _poolManager = IPoolManager(poolManager);
        PoolKey memory key = _poolManager.createPoolKey(currency1, currency2);

        return _poolManager.getPool(key);
    }
}