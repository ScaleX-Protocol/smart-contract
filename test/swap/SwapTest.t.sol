// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {BalanceManager} from "@scalexcore/BalanceManager.sol";
// import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
// import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
// import {ScaleXRouter} from "@scalexcore/ScaleXRouter.sol";
// import {OrderBook} from "@scalexcore/OrderBook.sol";
// import {PoolManager} from "@scalexcore/PoolManager.sol";
// import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
// import {Currency} from "@scalexcore/libraries/Currency.sol";
// import {PoolKey} from "@scalexcore/libraries/Pool.sol";
// import {MockToken} from "@scalex/mocks/MockToken.sol";

// import {BeaconDeployer} from "../core/helpers/BeaconDeployer.t.sol";
// import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
// import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {Test, console} from "forge-std/Test.sol";

// import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
// import {SyntheticTokenFactory} from "../../src/factories/SyntheticTokenFactory.sol";
// import {TokenRegistry} from "../../src/core/TokenRegistry.sol";

// contract SwapTest is Test {
//     // Contracts
//     IBalanceManager public balanceManager;
//     ITokenRegistry public tokenRegistry;
//     SyntheticTokenFactory public tokenFactory;
//     PoolManager public poolManager;
//     ScaleXRouter public router;

//     // Mock tokens
//     MockToken public weth;
//     MockToken public usdc;

//     // Test users
//     address alice = address(0x1);
//     address bob = address(0x2);
//     address owner = address(0x5);
//     address feeCollector = address(0x6);

//     // Define fee structure
//     uint256 feeMaker = 10; // 0.1%
//     uint256 feeTaker = 20; // 0.2%

//     // Trading rules
//     IOrderBook.TradingRules rules;

//     function setUp() public {
//         // Deploy mock tokens
//         weth = new MockToken("Wrapped Ether", "WETH", 18);
//         usdc = new MockToken("USD Coin", "USDC", 6);

//         // Fund test accounts
//         weth.mint(alice, 100 ether);
//         weth.mint(bob, 100 ether);
//         usdc.mint(alice, 100_000 * 1e6);
//         usdc.mint(bob, 100_000 * 1e6);

//         // Set up trading rules
//         rules = IOrderBook.TradingRules({
//             minTradeAmount: 1e14,
//             minAmountMovement: 1e13,
//             minOrderSize: 1e4,
//             minPriceMovement: 1e4
//         });

//         BeaconDeployer beaconDeployer = new BeaconDeployer();

//         // Deploy BalanceManager
//         (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
//             address(new BalanceManager()),
//             owner,
//             abi.encodeCall(BalanceManager.initialize, (owner, feeCollector, feeMaker, feeTaker))
//         );
//         balanceManager = IBalanceManager(payable(address(balanceManagerProxy)));

//         // Deploy OrderBook beacon
//         IBeacon orderBookBeacon = new UpgradeableBeacon(address(new OrderBook()), owner);
//         address orderBookBeaconAddress = address(orderBookBeacon);

//         // Deploy PoolManager
//         (BeaconProxy poolManagerProxy,) = beaconDeployer.deployUpgradeableContract(
//             address(new PoolManager()),
//             owner,
//             abi.encodeCall(PoolManager.initialize, (owner, address(balanceManager), address(orderBookBeaconAddress)))
//         );
//         poolManager = PoolManager(address(poolManagerProxy));

//         // Deploy Router
//         (BeaconProxy routerProxy,) = beaconDeployer.deployUpgradeableContract(
//             address(new ScaleXRouter()),
//             owner,
//             abi.encodeCall(ScaleXRouter.initialize, (address(poolManager), address(balanceManager)))
//         );
//         router = ScaleXRouter(address(routerProxy));

//         // Set up TokenFactory and TokenRegistry
//         tokenFactory = new SyntheticTokenFactory();
//         tokenFactory.initialize(owner, address(balanceManager)); // Set BalanceManager as tokenDeployer
        
//         // Deploy TokenRegistry
//         address tokenRegistryImpl = address(new TokenRegistry());
//         ERC1967Proxy tokenRegistryProxy = new ERC1967Proxy(
//             tokenRegistryImpl,
//             abi.encodeWithSelector(
//                 TokenRegistry.initialize.selector,
//                 owner
//             )
//         );
//         tokenRegistry = ITokenRegistry(address(tokenRegistryProxy));

//         // Set up permissions and connections
//         vm.startPrank(owner);
        
//         // Create synthetic tokens and set up TokenRegistry
//         address wethSynthetic = tokenFactory.createSyntheticToken(address(weth));
//         address usdcSynthetic = tokenFactory.createSyntheticToken(address(usdc));
        
//         balanceManager.addSupportedAsset(address(weth), wethSynthetic);
//         balanceManager.addSupportedAsset(address(usdc), usdcSynthetic);
        
//         // Register token mappings
//         uint32 currentChain = 31337;
//         tokenRegistry.registerTokenMapping(
//             currentChain, address(weth), currentChain, wethSynthetic, "WETH", 18, 18
//         );
//         tokenRegistry.registerTokenMapping(
//             currentChain, address(usdc), currentChain, usdcSynthetic, "USDC", 6, 6
//         );
        
//         // Activate token mappings
//         tokenRegistry.setTokenMappingStatus(currentChain, address(weth), currentChain, true);
//         tokenRegistry.setTokenMappingStatus(currentChain, address(usdc), currentChain, true);
        
//         balanceManager.setTokenFactory(address(tokenFactory));
//         balanceManager.setTokenRegistry(address(tokenRegistry));
//         balanceManager.setPoolManager(address(poolManager));
        
//         // Set BalanceManager as authorized operator for PoolManager and Router first
//         balanceManager.setAuthorizedOperator(address(poolManager), true);
//         balanceManager.setAuthorizedOperator(address(router), true);
        
//         // Set up router in PoolManager before creating pools
//         poolManager.setRouter(address(router));
        
//         // Set up approvals
//         vm.startPrank(alice);
//         weth.approve(address(balanceManager), type(uint256).max);
//         usdc.approve(address(balanceManager), type(uint256).max);
//         vm.stopPrank();
        
//         vm.startPrank(bob);
//         weth.approve(address(balanceManager), type(uint256).max);
//         usdc.approve(address(balanceManager), type(uint256).max);
//         vm.stopPrank();

//         // Create pool
//         vm.startPrank(owner);
//         poolManager.createPool(Currency.wrap(address(weth)), Currency.wrap(address(usdc)), rules);
//         vm.stopPrank();
//     }

//     function testWethToUsdcSwap() public {
//         // Alice deposits WETH and places a sell order
//         vm.startPrank(alice);
//         balanceManager.deposit(Currency.wrap(address(weth)), 10 ether, alice, alice);
        
//         // Get pool
//         PoolKey memory poolKey = poolManager.createPoolKey(Currency.wrap(address(weth)), Currency.wrap(address(usdc)));
//         IPoolManager.Pool memory pool = poolManager.getPool(poolKey);
        
//         // Place sell order at 2000 USDC per WETH
//         router.placeLimitOrder(
//             pool,
//             2000e6, // 2000 USDC
//             5 ether, // 5 WETH
//             IOrderBook.Side.SELL,
//             IOrderBook.TimeInForce.GTC,
//             5 ether
//         );
//         vm.stopPrank();
        
//         // Bob places a buy order (market order)
//         vm.startPrank(bob);
//         balanceManager.deposit(Currency.wrap(address(usdc)), 6000 * 1e6, bob, bob);
        
//         uint256 receivedWeth = router.swap(
//             Currency.wrap(address(usdc)),
//             Currency.wrap(address(weth)),
//             5000 * 1e6, // 5000 USDC
//             0,
//             0,
//             bob
//         );
//         vm.stopPrank();
        
//         // Verify swap executed
//         assertGt(receivedWeth, 0, "Should receive WETH");
//         assertLt(receivedWeth, 5 ether, "Should receive less than 5 WETH due to fees");
//     }

//     function testUsdcToWethSwap() public {
//         // Alice deposits USDC and places a buy order
//         vm.startPrank(alice);
//         balanceManager.deposit(Currency.wrap(address(usdc)), 10000 * 1e6, alice, alice);
        
//         // Get pool
//         PoolKey memory poolKey = poolManager.createPoolKey(Currency.wrap(address(weth)), Currency.wrap(address(usdc)));
//         IPoolManager.Pool memory pool = poolManager.getPool(poolKey);
        
//         // Place buy order at 2000 USDC per WETH
//         router.placeLimitOrder(
//             pool,
//             2000e6, // 2000 USDC
//             3 ether, // 3 WETH
//             IOrderBook.Side.BUY,
//             IOrderBook.TimeInForce.GTC,
//             6000 * 1e6 // 6000 USDC deposit
//         );
//         vm.stopPrank();
        
//         // Bob sells WETH via market order
//         vm.startPrank(bob);
//         balanceManager.deposit(Currency.wrap(address(weth)), 5 ether, bob, bob);
        
//         uint256 receivedUsdc = router.swap(
//             Currency.wrap(address(weth)),
//             Currency.wrap(address(usdc)),
//             2 ether, // 2 WETH
//             0,
//             0,
//             bob
//         );
//         vm.stopPrank();
        
//         // Verify swap executed
//         assertGt(receivedUsdc, 0, "Should receive USDC");
//         assertLt(receivedUsdc, 4000 * 1e6, "Should receive less than 4000 USDC due to fees");
//     }
// }