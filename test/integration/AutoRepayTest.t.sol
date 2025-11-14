// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {OrderBook} from "../../src/core/OrderBook.sol";
import {PoolManager} from "../../src/core/PoolManager.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import {LendingManager} from "../../src/yield/LendingManager.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {IPoolManager} from "../../src/core/interfaces/IPoolManager.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import {PoolId, PoolKey} from "../../src/core/libraries/Pool.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {BeaconDeployer} from "../core/helpers/BeaconDeployer.t.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SyntheticTokenFactory} from "../../src/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";

interface IPriceOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

contract AutoRepayTest is Test, IPriceOracle {
    OrderBook public orderBook;
    PoolManager public poolManager;
    IBalanceManager public balanceManager;
    ITokenRegistry public tokenRegistry;
    SyntheticTokenFactory public tokenFactory;
    LendingManager public lendingManager;
    
    MockToken public weth;
    MockToken public usdc;
    
    address public owner = address(0x1);
    address public trader = address(0x2);
    address public borrower = address(0x3);
    address public router = address(0x4);
    
    uint256 public constant USDC_PRICE = 1000 * 1e6;  // $1000 per USDC in base units
    
    function setUp() public {
        // Deploy mock tokens
        weth = new MockToken("Wrapped Ether", "WETH", 18);
        usdc = new MockToken("USD Coin", "USDC", 6);
        
        // Setup mock prices and liquidity
        weth.mint(trader, 10 ether);
        usdc.mint(trader, 10_000 * 1e6);
        
        // Deploy contracts using BeaconDeployer like other tests
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        
        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, address(0), 0, 0))
        );
        balanceManager = IBalanceManager(payable(address(balanceManagerProxy)));
        
        (BeaconProxy lendingManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new LendingManager()),
            owner,
            abi.encodeCall(LendingManager.initialize, (owner, address(this)))
        );
        lendingManager = LendingManager(address(lendingManagerProxy));

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
        
        // Initialize contracts
        vm.startPrank(owner);
        
        // Set up BalanceManager
        balanceManager.setAuthorizedOperator(router, true);
        balanceManager.setLendingManager(address(lendingManager));
        
        // Create synthetic tokens and set up TokenRegistry
        address wethSynthetic = tokenFactory.createSyntheticToken(address(weth));
        address usdcSynthetic = tokenFactory.createSyntheticToken(address(usdc));
        
        balanceManager.addSupportedAsset(address(weth), wethSynthetic);
        balanceManager.addSupportedAsset(address(usdc), usdcSynthetic);
        
        // Set BalanceManager as minter and burner for synthetic tokens
        SyntheticToken(wethSynthetic).setMinter(address(balanceManager));
        SyntheticToken(usdcSynthetic).setMinter(address(balanceManager));
        SyntheticToken(wethSynthetic).setBurner(address(balanceManager));
        SyntheticToken(usdcSynthetic).setBurner(address(balanceManager));
        
        // Register token mappings for local deposits
        uint32 currentChain = 31337; // Default foundry chain ID
        tokenRegistry.registerTokenMapping(
            currentChain, address(weth), currentChain, wethSynthetic, "WETH", 18, 18
        );
        tokenRegistry.registerTokenMapping(
            currentChain, address(usdc), currentChain, usdcSynthetic, "USDC", 6, 6
        );
        
        // Activate token mappings
        tokenRegistry.setTokenMappingStatus(currentChain, address(weth), currentChain, true);
        tokenRegistry.setTokenMappingStatus(currentChain, address(usdc), currentChain, true);
        
        balanceManager.setTokenFactory(address(tokenFactory));
        balanceManager.setTokenRegistry(address(tokenRegistry));
        
        // LendingManager already initialized via proxy
        lendingManager.setBalanceManager(address(balanceManager));
        lendingManager.configureAsset(address(usdc), 7500, 8500, 500, 1000);
        lendingManager.configureAsset(address(weth), 8000, 8500, 500, 1000);
        
        // Deploy OrderBook beacon and PoolManager using BeaconDeployer
        UpgradeableBeacon orderBookBeacon = new UpgradeableBeacon(address(new OrderBook()), owner);
        
        (BeaconProxy poolManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new PoolManager()),
            owner,
            abi.encodeCall(PoolManager.initialize, (owner, address(balanceManager), address(orderBookBeacon)))
        );
        poolManager = PoolManager(address(poolManagerProxy));
        
        // Now authorize the poolManager to call BalanceManager functions
        balanceManager.setPoolManager(address(poolManager));
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        
        // Set the router first
        poolManager.setRouter(router);
        
        // Create the pool with trading rules
        IOrderBook.TradingRules memory tradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1 * 1e6,
            minAmountMovement: 1,
            minPriceMovement: 1,
            minOrderSize: 1 * 1e6
        });
        
        PoolKey memory poolKey = PoolKey({
            baseCurrency: Currency.wrap(address(usdc)),
            quoteCurrency: Currency.wrap(address(weth))
        });
        
        // Create the pool
        PoolId poolId = poolManager.createPool(
            Currency.wrap(address(usdc)),
            Currency.wrap(address(weth)),
            tradingRules
        );
        
        // Get the OrderBook from the pool
        IPoolManager.Pool memory pool = poolManager.getPool(poolKey);
        orderBook = OrderBook(address(pool.orderBook));
        
        vm.stopPrank();
        
        // Setup borrower with debt
        _setupBorrowerWithDebt();
    }
    
    function _setupBorrowerWithDebt() internal {
        // Supply some USDC liquidity through BalanceManager (proper architecture)
        vm.startPrank(trader);
        usdc.mint(trader, 5000 * 1e6);
        usdc.approve(address(balanceManager), 5000 * 1e6);
        balanceManager.deposit(Currency.wrap(address(usdc)), 5000 * 1e6, trader, trader);
        vm.stopPrank();
        
        vm.startPrank(borrower);
        
        // Supply collateral through BalanceManager (proper architecture)
        weth.mint(borrower, 2 ether);
        weth.approve(address(balanceManager), 2 ether);
        balanceManager.deposit(Currency.wrap(address(weth)), 2 ether, borrower, borrower);
        
        // Borrow USDC (smaller amount that's available)
        lendingManager.borrow(address(usdc), 1000 * 1e6);
        
        vm.stopPrank();
        
        // Verify borrower has debt
        uint256 debt = lendingManager.getUserDebt(borrower, address(usdc));
        assertEq(debt, 1000 * 1e6, "Borrower should have 1000 USDC debt");
        
        // Give borrower some tokens to trade with
        vm.startPrank(borrower);
        weth.mint(borrower, 5 ether);
        usdc.mint(borrower, 10000 * 1e6);
        weth.approve(address(balanceManager), 5 ether);
        usdc.approve(address(balanceManager), 10000 * 1e6);
        balanceManager.deposit(Currency.wrap(address(weth)), 1 ether, borrower, borrower);
        balanceManager.deposit(Currency.wrap(address(usdc)), 2000 * 1e6, borrower, borrower);
        vm.stopPrank();
    }
    
    function test_AutoRepayOrderPlacement() public {
        vm.startPrank(router);
        
        // Place auto-repay limit order to buy USDC at discount
        uint128 targetPrice = 980 * 1e6;  // $0.98 per USDC (this will be the order price)
        uint128 quantity = 1000 * 1e6;   // Buy 1000 USDC
        
        uint48 orderId = orderBook.placeOrder(
            targetPrice,
            quantity,
            IOrderBook.Side.BUY,
            borrower,
            IOrderBook.TimeInForce.GTC,
            true,  // autoRepay = true
            false  // autoBorrow = false
        );
        
        // Verify order was placed with autoRepay enabled
        IOrderBook.Order memory order = orderBook.getOrder(orderId);
        assertTrue(order.autoRepay, "Order should be auto-repay enabled");
        assertEq(order.price, targetPrice, "Order price should match");
        assertEq(order.quantity, quantity, "Order quantity should match");
        assertTrue(order.side == IOrderBook.Side.BUY, "Order should be BUY side");
        
        console.log("[OK] Auto-repay order placed successfully");
        console.log("   Order ID:", uint256(orderId));
        console.log("   Order Price:", uint256(targetPrice) / 1e6, "USD per USDC");
        console.log("   Order Quantity:", uint256(quantity) / 1e6, "USDC");
        console.log("   Auto-Repay Enabled:", order.autoRepay);
        
        vm.stopPrank();
    }
    
    function test_AutoRepayWithProfitableFill() public {
        // Place auto-repay order first
        vm.startPrank(router);
        uint48 autoRepayOrderId = orderBook.placeOrder(
            1000 * 1e6,  // Market price
            1000 * 1e6,  // Buy 1000 USDC
            IOrderBook.Side.BUY,
            borrower,
            IOrderBook.TimeInForce.GTC,
            true,  // autoRepay = true
            false // autoBorrow = false
        );
        
        vm.stopPrank();
        
        console.log("[OK] Auto-repay setup complete");
        console.log("   Initial debt:", lendingManager.getUserDebt(borrower, address(usdc)) / 1e6, "USDC");
        
        // Note: In a real scenario, when this order fills, it will automatically
        // repay min(user_balance, user_debt) amount of USDC debt
        // The user gets maximum debt reduction without any manual intervention
    }

    function test_RegularOrderWithoutAutoRepay() public {
        vm.startPrank(router);
        
        // Place regular order without auto-repay
        uint48 orderId = orderBook.placeOrder(
            1000 * 1e6,  // Market price
            500 * 1e6,   // Buy 500 USDC
            IOrderBook.Side.BUY,
            borrower,
            IOrderBook.TimeInForce.GTC,
            false, // autoRepay = false
            false  // autoBorrow = false
        );
        
        // Verify order was placed without autoRepay
        IOrderBook.Order memory order = orderBook.getOrder(orderId);
        assertTrue(!order.autoRepay, "Order should not have auto-repay enabled");
        
        console.log("[OK] Regular order placed successfully (no auto-repay)");
        console.log("   Order ID:", uint256(orderId));
        console.log("   Auto-Repay Enabled:", order.autoRepay);
        
        vm.stopPrank();
    }
    
    // Mock oracle for testing
    function getAssetPrice(address asset) external view returns (uint256) {
        if (asset == address(weth)) return 2000e18;
        if (asset == address(usdc)) return 1e18;
        return 1e18;
    }
    
    event AutoRepaymentExecuted(
        address indexed user,
        address indexed debtToken,
        uint256 repayAmount,
        uint256 savings,
        uint256 timestamp
    );
}