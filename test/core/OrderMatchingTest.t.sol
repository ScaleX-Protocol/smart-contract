// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import "@scalexcore/interfaces/IOrderBook.sol";
import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
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

contract OrderMatchingTest is Test {
    OrderBook public orderBook;

    IOrderBook.TradingRules rules;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address david = address(0x4);

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
        baseTokenAddress = address(new MockToken("WETH", "WETH", 18));
        quoteTokenAddress = address(new MockToken("USDC", "USDC", 6));

        rules = IOrderBook.TradingRules({
            minTradeAmount: 1e14, // 0.0001 ETH (18 decimals)
            minAmountMovement: 1e13, // 0.00001 ETH (18 decimals)
            minOrderSize: 1e4, // 0.01 USDC (6 decimals)
            minPriceMovement: 1e4 // 0.01 USDC (6 decimals)
        });

        MockToken(baseTokenAddress).mint(alice, 1_000_000_000e18);
        MockToken(baseTokenAddress).mint(bob, 1_000_000_000e18);
        MockToken(baseTokenAddress).mint(charlie, 1_000_000_000e18);
        MockToken(baseTokenAddress).mint(david, 1_000_000_000e18);
        MockToken(quoteTokenAddress).mint(alice, 1_000_000_000e18);
        MockToken(quoteTokenAddress).mint(bob, 1_000_000_000e18);
        MockToken(quoteTokenAddress).mint(charlie, 1_000_000_000e18);
        MockToken(quoteTokenAddress).mint(david, 1_000_000_000e18);

        baseCurrency = Currency.wrap(baseTokenAddress);
        quoteCurrency = Currency.wrap(quoteTokenAddress);

        PoolKey memory key = PoolKey({
            baseCurrency: Currency.wrap(baseTokenAddress),
            quoteCurrency: Currency.wrap(quoteTokenAddress)
        });

        BeaconDeployer beaconDeployer = new BeaconDeployer();

        (BeaconProxy balanceManagerProxy, ) = beaconDeployer
            .deployUpgradeableContract(
                address(new BalanceManager()),
                owner,
                abi.encodeCall(
                    BalanceManager.initialize,
                    (owner, owner, feeMaker, feeTaker)
                )
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

        IBeacon orderBookBeacon = new UpgradeableBeacon(
            address(new OrderBook()),
            owner
        );
        address orderBookBeaconAddress = address(orderBookBeacon);

        (BeaconProxy poolManagerProxy, ) = beaconDeployer
            .deployUpgradeableContract(
                address(new PoolManager()),
                owner,
                abi.encodeCall(
                    PoolManager.initialize,
                    (
                        owner,
                        address(balanceManager),
                        address(orderBookBeaconAddress)
                    )
                )
            );
        poolManager = PoolManager(address(poolManagerProxy));

        (BeaconProxy routerProxy, ) = beaconDeployer.deployUpgradeableContract(
            address(new ScaleXRouter()),
            owner,
            abi.encodeCall(
                ScaleXRouter.initialize,
                (address(poolManager), address(balanceManager))
            )
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
            currentChain, baseTokenAddress, currentChain, baseSynthetic, "WETH", 18, 18
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
        MockToken(baseTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        MockToken(quoteTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        vm.stopPrank();

        vm.startPrank(bob);
        MockToken(baseTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        MockToken(quoteTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        vm.stopPrank();

        vm.startPrank(charlie);
        MockToken(baseTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        MockToken(quoteTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        vm.stopPrank();

        vm.startPrank(david);
        MockToken(baseTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        MockToken(quoteTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        vm.stopPrank();

        poolManager.createPool(baseCurrency, quoteCurrency, rules);

        key = poolManager.createPoolKey(baseCurrency, quoteCurrency);

        IPoolManager.Pool memory pool = poolManager.getPool(key);
        orderBook = OrderBook(address(pool.orderBook));
    }

    function testBasicOrderPlacement() public {
        vm.startPrank(alice);

        uint128 price = 1e8;
        uint128 quantity = 1e18;
        IOrderBook.Side side = IOrderBook.Side.BUY;

        IPoolManager.Pool memory pool = _getPool(baseCurrency, quoteCurrency);
        // Calculate required deposit for the order
        uint128 requiredDeposit = (price * quantity) / 1e18; // Convert from ETH to USDC amount
        
        router.placeLimitOrder(
            pool,
            price,
            quantity,
            side,
            IOrderBook.TimeInForce.GTC,
            requiredDeposit
        );

        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(
            side,
            price
        );

        assertEq(orderCount, 1);
        assertEq(totalVolume, quantity);

        vm.stopPrank();
    }

    function testMarketOrder() public {
        vm.startPrank(bob);
        uint128 limitPrice = 1e8;
        uint128 limitQuantity = 5e18;
        IOrderBook.Side limitSide = IOrderBook.Side.BUY;

        IPoolManager.Pool memory pool = _getPool(baseCurrency, quoteCurrency);
        // Calculate required deposit for the limit order
        uint128 requiredDeposit = (limitPrice * limitQuantity) / 1e18; // Convert from ETH to USDC amount
        
        router.placeLimitOrder(
            pool,
            limitPrice,
            limitQuantity,
            limitSide,
            IOrderBook.TimeInForce.GTC,
            requiredDeposit
        );
        vm.stopPrank();

        vm.startPrank(alice);
        uint128 quantity = 2e18;
        IOrderBook.Side side = IOrderBook.Side.SELL;

        // For SELL market order: selling 2 ETH should get ~200 USDC (2 ETH * 100 USDC/ETH)
        // Expected quote amount: 200 USDC, with 95% slippage protection: 190 USDC
        uint128 expectedQuoteAmount = uint128((quantity * limitPrice) / 1e18); // 200 USDC
        uint128 minOutAmount = (expectedQuoteAmount * 95) / 100; // 190 USDC (95% of expected)
        
        router.placeMarketOrder(
            pool,
            quantity,
            side,
            quantity, // deposit amount (base currency for SELL)
            minOutAmount // min out amount in quote currency (USDC)
        );

        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(
            limitSide,
            limitPrice
        );

        assertEq(totalVolume, limitQuantity - quantity);
        assertEq(orderCount, 1);

        vm.stopPrank();
    }

    function testMarketBuyOrderWithSlippageCalculation() public {
        // First, set up sell limit orders to provide liquidity
        vm.startPrank(bob);
        uint128 limitPrice1 = 1e8; // 100 USDC per ETH
        uint128 limitPrice2 = 1.01e8; // 101 USDC per ETH
        uint128 limitQuantity = 2e18; // 2 ETH each
        IOrderBook.Side limitSide = IOrderBook.Side.SELL;

        IPoolManager.Pool memory pool = _getPool(baseCurrency, quoteCurrency);
        
        // Place first sell limit order at 100 USDC/ETH
        router.placeLimitOrder(
            pool,
            limitPrice1,
            limitQuantity,
            limitSide,
            IOrderBook.TimeInForce.GTC,
            limitQuantity // deposit amount (base currency for SELL)
        );
        
        // Place second sell limit order at 101 USDC/ETH
        router.placeLimitOrder(
            pool,
            limitPrice2,
            limitQuantity,
            limitSide,
            IOrderBook.TimeInForce.GTC,
            limitQuantity // deposit amount (base currency for SELL)
        );
        vm.stopPrank();

        // Now place a market buy order with slippage calculation
        vm.startPrank(alice);
        uint128 buyQuantity = 3e18; // Want to buy 3 ETH
        IOrderBook.Side marketSide = IOrderBook.Side.BUY;
        uint256 slippageToleranceBps = 500; // 5% slippage tolerance

        // For BUY market order: spending quote currency (USDC) to get base currency (ETH)
        // Calculate required deposit (quote currency amount)
        uint128 maxQuoteAmount = uint128((buyQuantity * limitPrice2) / 1e18); // Use higher price for safety

        // Calculate minimum output amount using calculateMinOutAmountForMarket
        // For BUY orders, input amount should be in quote currency (USDC)
        uint128 minOutAmount = router.calculateMinOutAmountForMarket(
            pool,
            maxQuoteAmount, // input amount in quote currency (USDC)
            marketSide,
            slippageToleranceBps
        );
        
        router.placeMarketOrder(
            pool,
            buyQuantity,
            marketSide,
            maxQuoteAmount, // deposit amount (quote currency for BUY)
            minOutAmount // min out amount in base currency (ETH)
        );

        // Verify that orders were filled (don't need exact amounts due to fees)
        (, uint256 totalVolume1) = orderBook.getOrderQueue(
            limitSide,
            limitPrice1
        );
        (, uint256 totalVolume2) = orderBook.getOrderQueue(
            limitSide,
            limitPrice2
        );

        // First order should be completely filled
        assertEq(totalVolume1, 0);
        // Second order should be partially filled (some volume remaining)
        assertLt(totalVolume2, limitQuantity);

        vm.stopPrank();
    }

    function _getPool(
        Currency currency1,
        Currency currency2
    ) internal view returns (IPoolManager.Pool memory pool) {
        IPoolManager _poolManager = IPoolManager(poolManager);
        PoolKey memory key = _poolManager.createPoolKey(currency1, currency2);

        return _poolManager.getPool(key);
    }
}
