// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BalanceManager} from "@gtxcore/BalanceManager.sol";
import {GTXRouter} from "@gtxcore/GTXRouter.sol";
import {OrderBook} from "@gtxcore/OrderBook.sol";
import {PoolManager} from "@gtxcore/PoolManager.sol";
import {IOrderBook} from "@gtxcore/interfaces/IOrderBook.sol";
import {IOrderBookErrors} from "@gtxcore/interfaces/IOrderBookErrors.sol";
import {IPoolManager} from "@gtxcore/interfaces/IPoolManager.sol";
import {Currency} from "@gtxcore/libraries/Currency.sol";
import {PoolKey} from "@gtxcore/libraries/Pool.sol";
import {MockToken} from "@gtx/mocks/MockToken.sol";
import {BeaconDeployer} from "../core/helpers/BeaconDeployer.t.sol";
import {PoolHelper} from "../core/helpers/PoolHelper.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/interfaces/IERC1967.sol";

/**
 * @title SlippageProtectionTest
 * @notice Test to verify critical slippage protection fix in multi-hop swaps
 */
contract SlippageProtectionTest is Test, PoolHelper {
    GTXRouter public router;
    PoolManager public poolManager;
    BalanceManager public balanceManager;
    MockToken public weth;
    MockToken public usdc;
    MockToken public wbtc;
    BeaconDeployer public beaconDeployer;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public owner = address(this);
    address public feeCollector = address(0x999);
    
    mapping(string => IPoolManager.Pool) public pools;
    
    uint256 public constant feeMaker = 10; // 1%
    uint256 public constant feeTaker = 20; // 2%
    uint256 public constant feeUnit = 1000;
    
    IOrderBook.TradingRules public rules;
    
    function setUp() public {
        // Deploy tokens
        weth = new MockToken("Wrapped Ether", "WETH", 18);
        usdc = new MockToken("USD Coin", "USDC", 6);
        wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);
        
        // Set up trading rules
        rules = IOrderBook.TradingRules({
            minTradeAmount: 1e6, // 0.01 tokens (scaled for different decimals)
            minAmountMovement: 1e5, // 0.001 tokens (scaled for different decimals)
            minOrderSize: 1e3, // 0.001 USDC (6 decimals)
            minPriceMovement: 1e3 // 0.001 USDC (6 decimals)
        });

        beaconDeployer = new BeaconDeployer();

        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeCollector, feeMaker, feeTaker))
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
        router = GTXRouter(address(routerProxy));
        
        // Set up authorized operators and router
        balanceManager.setPoolManager(address(poolManager));
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.setAuthorizedOperator(address(router), true);
        poolManager.setRouter(address(router));
        
        // Create pools
        poolManager.createPool(Currency.wrap(address(weth)), Currency.wrap(address(usdc)), rules);
        poolManager.createPool(Currency.wrap(address(wbtc)), Currency.wrap(address(usdc)), rules);
        
        pools["WETH/USDC"] = _getPool(poolManager, Currency.wrap(address(weth)), Currency.wrap(address(usdc)));
        pools["WBTC/USDC"] = _getPool(poolManager, Currency.wrap(address(wbtc)), Currency.wrap(address(usdc)));
        
        // Add USDC as common intermediary for multi-hop routing
        poolManager.addCommonIntermediary(Currency.wrap(address(usdc)));
        
        // Mint tokens and set approvals
        setupTokensAndApprovals();
    }
    
    function setupTokensAndApprovals() internal {
        address[2] memory users = [alice, bob];
        
        for (uint i = 0; i < users.length; i++) {
            weth.mint(users[i], 1000e18);
            usdc.mint(users[i], 1000000e6);
            wbtc.mint(users[i], 100e8);
            
            vm.startPrank(users[i]);
            weth.approve(address(balanceManager), type(uint256).max);
            usdc.approve(address(balanceManager), type(uint256).max);
            wbtc.approve(address(balanceManager), type(uint256).max);
            vm.stopPrank();
        }
    }
    
    /**
     * @notice Test that multi-hop swaps now properly enforce slippage protection on final output
     * @dev This tests the fix for the critical bug where second hop used minDstAmount=0
     */
    function testMultiHopSlippageProtectionWorks() public {
        console.log("\n=== CRITICAL TEST: Multi-hop slippage protection ===");
        
        // Setup: Alice provides liquidity with very bad prices
        vm.startPrank(alice);
        
        // WETH/USDC: Alice buys WETH at only 1000 USDC/WETH (bad price)
        router.placeLimitOrder(
            pools["WETH/USDC"],
            1000e6, // 1000 USDC per WETH
            5e18,   // 5 WETH
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            5000e6  // 5000 USDC deposit
        );
        
        // WBTC/USDC: Alice sells WBTC at 50000 USDC/WBTC (very expensive)
        router.placeLimitOrder(
            pools["WBTC/USDC"],
            50000e6, // 50,000 USDC per WBTC
            1e8,     // 1 WBTC
            IOrderBook.Side.SELL,
            IOrderBook.TimeInForce.GTC,
            1e8      // 1 WBTC deposit
        );
        vm.stopPrank();
        
        // Bob tries multi-hop swap WETH → USDC → WBTC
        // Expected path: 1 WETH → 1000 USDC → 0.02 WBTC (before fees)
        // After fees (~2% twice): ~0.0192 WBTC = 1,920,000 satoshis
        // But Bob demands more than possible
        uint256 unrealisticMinimum = 3e6; // 0.03 WBTC (3,000,000 satoshis) - impossible to achieve
        
        vm.startPrank(bob);
        
        // This should now FAIL due to slippage protection (before the fix, it would succeed with 0 minimum)
        vm.expectRevert(); // Should revert with slippage error
        router.swap(
            Currency.wrap(address(weth)),
            Currency.wrap(address(wbtc)),
            1e18,               // 1 WETH
            unrealisticMinimum, // Impossible minimum
            2,                  // max 2 hops
            bob
        );
        
        vm.stopPrank();
        
        console.log("SUCCESS: Multi-hop swap correctly enforces slippage protection on final output");
        console.log("This confirms the critical bug fix where second hop was using minDstAmount=0");
    }
    
    /**
     * @notice Test that multi-hop swaps succeed when slippage requirements can be met
     */
    function testMultiHopSlippageProtectionAllowsValidSwaps() public {
        console.log("\n=== TEST: Multi-hop swap succeeds with reasonable slippage ===");
        
        // Setup: Alice provides liquidity with reasonable prices
        vm.startPrank(alice);
        
        // WETH/USDC: Alice buys WETH at 2000 USDC/WETH
        router.placeLimitOrder(
            pools["WETH/USDC"],
            2000e6, // 2000 USDC per WETH
            5e18,   // 5 WETH
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            10000e6 // 10,000 USDC deposit
        );
        
        // WBTC/USDC: Alice sells WBTC at 30000 USDC/WBTC
        router.placeLimitOrder(
            pools["WBTC/USDC"],
            30000e6, // 30,000 USDC per WBTC
            1e8,     // 1 WBTC
            IOrderBook.Side.SELL,
            IOrderBook.TimeInForce.GTC,
            1e8      // 1 WBTC deposit
        );
        vm.stopPrank();
        
        // Bob does multi-hop swap WETH → USDC → WBTC
        // Expected: 1 WETH → 2000 USDC → 0.0667 WBTC (before fees)
        // After fees (~2% twice): ~0.0639 WBTC = 6,390,000 satoshis
        uint256 reasonableMinimum = 6.2e6; // 0.062 WBTC - achievable
        
        vm.startPrank(bob);
        
        uint256 received = router.swap(
            Currency.wrap(address(weth)),
            Currency.wrap(address(wbtc)),
            1e18,               // 1 WETH
            reasonableMinimum,  // Achievable minimum
            2,                  // max 2 hops
            bob
        );
        
        vm.stopPrank();
        
        console.log("Received WBTC (satoshis):", received);
        assertTrue(received >= reasonableMinimum, "Should receive at least minimum amount");
        console.log("SUCCESS: Multi-hop swap succeeds when slippage requirements are met");
    }
}