// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/ai-agents/AgentRouter.sol";
import "../../src/ai-agents/PolicyFactory.sol";
import {PolicyFactoryStorage} from "../../src/ai-agents/storages/PolicyFactoryStorage.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../../src/ai-agents/mocks/MockERC8004Identity.sol";
import "../../src/ai-agents/mocks/MockERC8004Reputation.sol";
import "../../src/ai-agents/mocks/MockERC8004Validation.sol";
import "../ai-agents/mocks/MockPoolManager.sol";
import "../ai-agents/mocks/MockOrderBook.sol";
import "../ai-agents/mocks/MockLendingManager.sol";
import "../ai-agents/mocks/MockBalanceManager.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";

/**
 * @title AgentMarketplaceTest
 * @notice Tests the "AI agent marketplace" flow under the simplified ERC-8004 auth model.
 *
 * NEW marketplace model (post-refactor):
 *   1. Developer registers a strategy agent NFT (developerAgentId) via IdentityRegistry
 *   2. Each user calls agentRouter.authorize(developerAgentId, policy) to grant
 *      the developer's agent permission to trade their funds, with their own policy limits
 *   3. The developer's wallet (which owns the developerAgentId NFT) calls
 *      agentRouter.execute*(userAddress, developerAgentId, ...) to trade for each user
 *   4. The same NFT can serve multiple users — each user sets their own policy
 *
 * NOTE: The previous "userAgentId + authorizeExecutor" flow was removed in the ERC-8004
 * simplification. Users no longer need their own NFT.
 */
contract AgentMarketplaceTest is Test {
    AgentRouter public agentRouter;
    PolicyFactory public policyFactory;

    MockERC8004Identity public identityRegistry;
    MockERC8004Reputation public reputationRegistry;
    MockERC8004Validation public validationRegistry;

    MockPoolManager public poolManager;
    MockOrderBook public orderBook;
    MockLendingManager public lendingManager;
    MockBalanceManager public balanceManager;

    address public developer = makeAddr("developer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public developerAgentId;

    address public IDRX = address(0x1);
    address public WETH = address(0x2);

    IPoolManager.Pool public wethIdrxPool;

    function setUp() public {
        // Deploy registries
        identityRegistry = new MockERC8004Identity();
        reputationRegistry = new MockERC8004Reputation();
        validationRegistry = new MockERC8004Validation();

        // Deploy PolicyFactory through BeaconProxy
        PolicyFactory policyFactoryImpl = new PolicyFactory();
        UpgradeableBeacon pfBeacon = new UpgradeableBeacon(address(policyFactoryImpl), address(this));
        BeaconProxy pfProxy = new BeaconProxy(
            address(pfBeacon),
            abi.encodeCall(PolicyFactory.initialize, (address(this), address(identityRegistry)))
        );
        policyFactory = PolicyFactory(address(pfProxy));

        // Deploy mocks
        poolManager = new MockPoolManager();
        balanceManager = new MockBalanceManager();
        lendingManager = new MockLendingManager();
        orderBook = new MockOrderBook();

        // Setup WETH/IDRX pool
        wethIdrxPool = IPoolManager.Pool({
            baseCurrency: Currency.wrap(WETH),
            quoteCurrency: Currency.wrap(IDRX),
            orderBook: orderBook
        });
        poolManager.setPool(wethIdrxPool);

        // Deploy AgentRouter through BeaconProxy
        AgentRouter agentRouterImpl = new AgentRouter();
        UpgradeableBeacon arBeacon = new UpgradeableBeacon(address(agentRouterImpl), address(this));
        BeaconProxy arProxy = new BeaconProxy(
            address(arBeacon),
            abi.encodeCall(AgentRouter.initialize, (
                address(this),
                address(identityRegistry),
                address(reputationRegistry),
                address(validationRegistry),
                address(policyFactory),
                address(poolManager),
                address(balanceManager),
                address(lendingManager)
            ))
        );
        agentRouter = AgentRouter(address(arProxy));

        policyFactory.setAuthorizedRouter(address(agentRouter), true);
        reputationRegistry.setAuthorizedSubmitter(address(agentRouter), true);

        // Developer registers their strategy agent NFT
        vm.prank(developer);
        developerAgentId = identityRegistry.mintAuto(developer, "ipfs://strategy-agent");

        // Setup health factors
        lendingManager.setHealthFactor(alice, 2e18);
        lendingManager.setHealthFactor(bob, 2e18);
    }

    /**
     * @notice Core marketplace flow: developer's agent serves multiple users,
     *         each user sets their own policy limits.
     */
    function test_MarketplaceFlow_MultipleUsersOneAgent() public {
        console.log("\n=== MARKETPLACE FLOW: Multiple users, one strategy agent ===\n");

        // -- Alice subscribes: conservative policy, max 1000 IDRX per order --
        vm.prank(alice);
        agentRouter.authorize(developerAgentId, _makePolicy(1000e6));

        assertTrue(agentRouter.isAuthorized(alice, developerAgentId));
        console.log("Alice authorized developer agent with 1000 IDRX limit");

        // -- Bob subscribes: aggressive policy, max 10000 IDRX per order --
        vm.prank(bob);
        agentRouter.authorize(developerAgentId, _makePolicy(10000e6));

        assertTrue(agentRouter.isAuthorized(bob, developerAgentId));
        console.log("Bob authorized developer agent with 10000 IDRX limit");

        // -- Developer places an order for Alice within her limit --
        orderBook.setNextOrderId(1);
        vm.prank(developer);
        uint48 aliceOrderId = agentRouter.executeLimitOrder(
            alice, developerAgentId, wethIdrxPool,
            300000, 1000e6,            // price=300000, quantity=1000 IDRX (within Alice's limit)
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false, false
        );
        assertEq(aliceOrderId, 1);
        assertEq(orderBook.lastOrderOwner(), alice); // Uses Alice's funds
        console.log("Order placed for Alice using her funds [OK]");

        // -- Developer tries to exceed Alice's limit — should fail --
        vm.prank(developer);
        vm.expectRevert("Order too large");
        agentRouter.executeLimitOrder(
            alice, developerAgentId, wethIdrxPool,
            300000, 5000e6,            // 5000 IDRX — exceeds Alice's 1000 limit
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false, false
        );
        console.log("Alice's policy enforced: 5000 IDRX order rejected [OK]");

        // -- Developer places 5000 IDRX for Bob (within his 10000 limit) --
        orderBook.setNextOrderId(2);
        vm.prank(developer);
        uint48 bobOrderId = agentRouter.executeLimitOrder(
            bob, developerAgentId, wethIdrxPool,
            300000, 5000e6,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false, false
        );
        assertEq(bobOrderId, 2);
        assertEq(orderBook.lastOrderOwner(), bob); // Uses Bob's funds
        console.log("Bob's 5000 IDRX order placed successfully [OK]");

        console.log("\n=== Marketplace test passed [OK] ===");
    }

    /**
     * @notice Non-owner of the strategy agent NFT cannot execute orders.
     */
    function test_RevertNonOwnerCannotExecute() public {
        // Alice authorizes developer's agent
        vm.prank(alice);
        agentRouter.authorize(developerAgentId, _makePolicy(1000e6));

        // An attacker (not the NFT owner) tries to execute with the developer's agent
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert("Not strategy agent owner");
        agentRouter.executeLimitOrder(
            alice, developerAgentId, wethIdrxPool,
            300000, 500e6,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false, false
        );
    }

    /**
     * @notice Developer cannot trade for a user who hasn't authorized the agent.
     */
    function test_RevertUnauthorizedUser() public {
        // Alice has NOT authorized developer's agent
        vm.prank(developer);
        vm.expectRevert("Strategy agent not authorized");
        agentRouter.executeLimitOrder(
            alice, developerAgentId, wethIdrxPool,
            300000, 500e6,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false, false
        );
    }

    /**
     * @notice User can revoke authorization at any time.
     */
    function test_UserCanRevoke() public {
        vm.prank(alice);
        agentRouter.authorize(developerAgentId, _makePolicy(1000e6));
        assertTrue(agentRouter.isAuthorized(alice, developerAgentId));

        // Alice revokes
        vm.prank(alice);
        agentRouter.revoke(developerAgentId);
        assertFalse(agentRouter.isAuthorized(alice, developerAgentId));

        // Developer can no longer trade for Alice
        vm.prank(developer);
        vm.expectRevert("Strategy agent not authorized");
        agentRouter.executeLimitOrder(
            alice, developerAgentId, wethIdrxPool,
            300000, 500e6,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false, false
        );
    }

    // ============ Helpers ============

    function _makePolicy(uint256 maxOrderSize) internal view returns (PolicyFactoryStorage.Policy memory) {
        address[] memory empty = new address[](0);
        return PolicyFactoryStorage.Policy({
            enabled: true,
            installedAt: 0,
            expiryTimestamp: block.timestamp + 365 days,
            maxOrderSize: maxOrderSize,
            minOrderSize: 0,
            whitelistedTokens: empty,
            blacklistedTokens: empty,
            allowMarketOrders: true,
            allowLimitOrders: true,
            allowSwap: true,
            allowBorrow: true,
            allowRepay: true,
            allowSupplyCollateral: true,
            allowWithdrawCollateral: true,
            allowPlaceLimitOrder: true,
            allowCancelOrder: true,
            allowBuy: true,
            allowSell: true,
            allowAutoBorrow: true,
            maxAutoBorrowAmount: 10000e6,
            allowAutoRepay: true,
            minDebtToRepay: 0,
            minHealthFactor: 1e18, // 100%
            maxSlippageBps: 500,
            minTimeBetweenTrades: 0,
            emergencyRecipient: address(0),
            dailyVolumeLimit: 0,
            weeklyVolumeLimit: 0,
            maxDailyDrawdown: 0,
            maxWeeklyDrawdown: 0,
            maxTradeVsTVLBps: 0,
            minWinRateBps: 0,
            minSharpeRatio: 0,
            maxPositionConcentrationBps: 0,
            maxCorrelationBps: 0,
            maxTradesPerDay: 0,
            maxTradesPerHour: 0,
            tradingStartHour: 0,
            tradingEndHour: 0,
            minReputationScore: 0,
            useReputationMultiplier: false,
            requiresChainlinkFunctions: false
        });
    }
}
