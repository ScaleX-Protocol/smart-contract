// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/ai-agents/AgentRouter.sol";
import "../../src/ai-agents/PolicyFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/ai-agents/mocks/MockERC8004Identity.sol";
import "../../src/ai-agents/mocks/MockERC8004Reputation.sol";
import "../../src/ai-agents/mocks/MockERC8004Validation.sol";
import "./mocks/MockPoolManager.sol";
import "./mocks/MockOrderBook.sol";
import "./mocks/MockLendingManager.sol";
import "./mocks/MockBalanceManager.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";

/**
 * @title AgentRouterTest
 * @notice Comprehensive tests for AgentRouter contract (ERC-8004 simplified auth model).
 *
 * New auth model (no userAgentId NFT):
 *   1. Strategy agent mints its own NFT via identityRegistry.mintAuto(agentService, ...)
 *   2. User calls agentRouter.authorize(strategyAgentId, policy) — one tx installs policy + grants auth
 *   3. Strategy agent owner calls agentRouter.execute*(userAddress, strategyAgentId, ...)
 *
 * In these tests user1/user2 own their own agent NFTs, so they act as both user and agent executor.
 */
contract AgentRouterTest is Test {
    AgentRouter public agentRouter;
    PolicyFactory public policyFactory;

    MockERC8004Identity public identityRegistry;
    MockERC8004Reputation public reputationRegistry;
    MockERC8004Validation public validationRegistry;

    MockPoolManager public poolManager;
    MockOrderBook public orderBook;
    MockLendingManager public lendingManager;
    MockBalanceManager public balanceManager;

    address public owner;
    address public user1;
    address public user2;

    uint256 public agent1;
    uint256 public agent2;

    address public WETH = address(0x1);
    address public USDC = address(0x2);
    address public WBTC = address(0x3);

    IPoolManager.Pool public wethUsdcPool;

    function setUp() public {
        owner = address(this);
        user1 = address(0x100);
        user2 = address(0x200);

        // Deploy registries
        identityRegistry = new MockERC8004Identity();
        reputationRegistry = new MockERC8004Reputation();
        validationRegistry = new MockERC8004Validation();

        // Deploy PolicyFactory
        policyFactory = new PolicyFactory(address(identityRegistry));

        // Deploy mocks
        poolManager = new MockPoolManager();
        balanceManager = new MockBalanceManager();
        lendingManager = new MockLendingManager();
        orderBook = new MockOrderBook();

        // Setup WETH/USDC pool
        wethUsdcPool = IPoolManager.Pool({
            baseCurrency: Currency.wrap(WETH),
            quoteCurrency: Currency.wrap(USDC),
            orderBook: orderBook
        });

        // Setup pool manager to return this pool
        poolManager.setPool(wethUsdcPool);

        // Deploy AgentRouter
        agentRouter = new AgentRouter(
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry),
            address(policyFactory),
            address(poolManager),
            address(balanceManager),
            address(lendingManager)
        );

        // Authorize AgentRouter in PolicyFactory
        policyFactory.setAuthorizedRouter(address(agentRouter), true);

        // Authorize AgentRouter in reputation registry
        reputationRegistry.setAuthorizedSubmitter(address(agentRouter), true);

        // Mint strategy agent NFTs (user1 owns agent1, user2 owns agent2)
        vm.prank(user1);
        agent1 = identityRegistry.mintAuto(user1, "ipfs://agent1");

        vm.prank(user2);
        agent2 = identityRegistry.mintAuto(user2, "ipfs://agent2");

        // Setup default health factor
        lendingManager.setHealthFactor(user1, 2e18); // 200%
        lendingManager.setHealthFactor(user2, 2e18);

        // Warp to a reasonable timestamp so minTimeBetweenTrades cooldown tests work
        // (default block.timestamp=1 is < any cooldown period starting from lastTradeTime=0)
        vm.warp(1000);
    }

    // ============ Agent Installation Verification Tests ============

    function test_AgentInstallationVerification() public {
        // 1. Verify agent NOT authorized initially
        assertFalse(agentRouter.isAuthorized(user1, agent1));

        // Attempting to get policy for non-installed agent should return default/empty policy
        PolicyFactory.Policy memory emptyPolicy = policyFactory.getPolicy(user1, agent1);
        assertEq(emptyPolicy.installedAt, 0);
        assertFalse(emptyPolicy.enabled);

        // 2. Authorize agent with custom policy (maxOrderSize = 10000e6)
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.maxOrderSize = 10000e6;
        agentRouter.authorize(agent1, p);
        vm.stopPrank();

        // 3. Verify agent IS authorized
        assertTrue(agentRouter.isAuthorized(user1, agent1));
        assertTrue(policyFactory.isAgentEnabled(user1, agent1));

        // 4. Verify policy details are correct
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(user1, agent1);
        assertTrue(policy.enabled);
        assertEq(policy.maxOrderSize, 10000e6);
        assertGt(policy.installedAt, 0); // Installation timestamp recorded
        assertGt(policy.expiryTimestamp, block.timestamp); // Has valid expiry

        // 5. Verify agent appears in user's installed agents list
        uint256[] memory agentList = policyFactory.getInstalledAgents(user1);
        assertEq(agentList.length, 1);
        assertEq(agentList[0], agent1);
    }

    function test_AgentNotInstalledCannotTrade() public {
        // Agent is NOT authorized — expect "Strategy agent not authorized"
        vm.prank(user1);
        vm.expectRevert("Strategy agent not authorized");
        agentRouter.executeMarketOrder(
            user1,
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );
    }

    // ============ Agent Order Placement Tests (Using Owner Assets) ============

    function test_AgentPlacesMarketOrderUsingOwnerAssets() public {
        // 1. Setup owner's initial balances
        balanceManager.setBalance(user1, Currency.wrap(WETH), 0);
        balanceManager.setBalance(user1, Currency.wrap(USDC), 10000e6);

        // 2. Authorize agent for user1
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        // 3. Verify agent is authorized
        assertTrue(agentRouter.isAuthorized(user1, agent1));

        // 4. Setup order book to return filled order
        orderBook.setNextOrderResponse(1, 1000e6);

        // 5. Agent places BUY order for WETH using owner's USDC
        vm.prank(user1);
        (uint48 orderId, uint128 filled) = agentRouter.executeMarketOrder(
            user1,
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        // 6. Verify order was executed
        assertEq(orderId, 1);
        assertEq(filled, 1000e6);

        // 7. Verify the order used OWNER's address (user1), not the agent's
        assertEq(orderBook.lastOrderOwner(), user1);
    }

    function test_AgentPlacesLimitOrderUsingOwnerAssets() public {
        // 1. Setup owner's balances
        balanceManager.setBalance(user1, Currency.wrap(WETH), 5e18);
        balanceManager.setBalance(user1, Currency.wrap(USDC), 5000e6);

        // 2. Authorize agent with simple custom policy
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        // 3. Verify agent is authorized
        assertTrue(agentRouter.isAuthorized(user1, agent1));

        // 4. Setup order book to return order ID
        orderBook.setNextOrderId(100);

        // 5. Agent places SELL limit order using owner's WETH
        vm.prank(user1);
        uint48 orderId = agentRouter.executeLimitOrder(
            user1,
            agent1,
            wethUsdcPool,
            2000e6,
            1000e6,
            IOrderBook.Side.SELL,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        );

        // 6. Verify order was placed
        assertEq(orderId, 100);

        // 7. Verify the order used OWNER's address (user1)
        assertEq(orderBook.lastOrderOwner(), user1);
    }

    function test_AgentCannotPlaceOrderForDifferentOwner() public {
        // user1 tries to execute with agent2 (owned by user2) - should fail: not agent owner
        vm.prank(user1);
        vm.expectRevert("Not strategy agent owner");
        agentRouter.executeMarketOrder(
            user1,
            agent2,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        // user2 tries to execute with agent1 (owned by user1) - should fail: not agent owner
        vm.prank(user2);
        vm.expectRevert("Not strategy agent owner");
        agentRouter.executeMarketOrder(
            user2,
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );
    }

    function test_EventsDistinguishOwnerFromAgentExecution() public {
        // Setup: Authorize agent for user1
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        orderBook.setNextOrderResponse(1, 1000e6);

        // Scenario: Owner (user1) also owns the agent NFT — owner == executor in event
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentSwapExecuted(
            user1, agent1, user1,
            WETH, USDC, 1000e6, 1000e6,
            block.timestamp
        );
        agentRouter.executeMarketOrder(user1, agent1, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);
    }

    // ============ COMPREHENSIVE EVENT TRACING TESTS ============

    function test_TraceMarketOrderPlacement() public {
        console.log("\n=== TRACING MARKET ORDER PLACEMENT ===");

        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        orderBook.setNextOrderResponse(42, 1500e6);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentSwapExecuted(
            user1, agent1, user1,
            WETH, USDC, 1500e6, 1500e6,
            block.timestamp
        );
        agentRouter.executeMarketOrder(user1, agent1, wethUsdcPool, IOrderBook.Side.BUY, 1500e6, 1400e6, false, false);

        console.log("Market Order Event Emitted:");
        console.log("  Owner:", user1);
        console.log("  Agent ID:", agent1);
        console.log("  Amount: 1500e6");
    }

    function test_TraceLimitOrderPlacement() public {
        console.log("\n=== TRACING LIMIT ORDER PLACEMENT ===");

        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        orderBook.setNextOrderId(999);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentLimitOrderPlaced(
            user1, agent1, user1,
            bytes32(uint256(999)),
            WETH, USDC, 500e6, 2100e6,
            false,
            block.timestamp
        );
        agentRouter.executeLimitOrder(user1, agent1, wethUsdcPool, 2100e6, 500e6, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, false, false);

        console.log("Limit Order Event Emitted:");
        console.log("  Order ID: 999, Side: SELL, Price: 2100e6");
    }

    function test_TraceBorrowAction() public {
        console.log("\n=== TRACING BORROW ACTION ===");

        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        lendingManager.setHealthFactor(user1, 3e18);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentBorrowExecuted(
            user1, agent1, user1,
            USDC, 2000e6, 3e18,
            block.timestamp
        );
        agentRouter.executeBorrow(user1, agent1, USDC, 2000e6);

        console.log("Borrow Event Emitted: 2000e6 USDC");
    }

    function test_TraceRepayAction() public {
        console.log("\n=== TRACING REPAY ACTION ===");

        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        lendingManager.setHealthFactor(user1, 2e18);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentRepayExecuted(
            user1, agent1, user1,
            USDC, 1000e6, 2e18,
            block.timestamp
        );
        agentRouter.executeRepay(user1, agent1, USDC, 1000e6);

        console.log("Repay Event Emitted: 1000e6 USDC");
    }

    function test_TraceDepositCollateral() public {
        console.log("\n=== TRACING DEPOSIT COLLATERAL ===");

        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        // Mock ERC20 calls since WETH = address(0x1) is a precompile, not a real token
        vm.mockCall(WETH, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.mockCall(WETH, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentCollateralSupplied(
            user1, agent1, user1,
            WETH, 3e18,
            block.timestamp
        );
        agentRouter.executeSupplyCollateral(user1, agent1, WETH, 3e18);

        console.log("Deposit Collateral Event Emitted: 3 WETH");
    }

    function test_TraceWithdrawCollateral() public {
        console.log("\n=== TRACING WITHDRAW COLLATERAL ===");

        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        lendingManager.setHealthFactor(user1, 3e18);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentCollateralWithdrawn(
            user1, agent1, user1,
            WETH, 1e18,
            block.timestamp
        );
        agentRouter.executeWithdrawCollateral(user1, agent1, WETH, 1e18);

        console.log("Withdraw Collateral Event Emitted: 1 WETH");
    }

    function test_TraceCancelOrder() public {
        console.log("\n=== TRACING ORDER CANCELLATION ===");

        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentOrderCancelled(
            user1, agent1, user1,
            bytes32(uint256(777)),
            block.timestamp
        );
        agentRouter.cancelOrder(user1, agent1, wethUsdcPool, 777);

        console.log("Cancel Order Event Emitted: orderId 777");
    }

    // ============ COMPREHENSIVE VERIFICATION TEST ============

    function test_VERIFICATION_AllCriticalAssertions() public {
        console.log("\n===========================================");
        console.log("COMPREHENSIVE VERIFICATION TEST");
        console.log("===========================================");

        // SETUP: authorize agent1 for user1
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        console.log("\n[1] VERIFY: Agent is authorized and policy is enabled");
        assertTrue(agentRouter.isAuthorized(user1, agent1));
        assertTrue(policyFactory.isAgentEnabled(user1, agent1));

        PolicyFactory.Policy memory policy = policyFactory.getPolicy(user1, agent1);
        assertTrue(policy.enabled);
        console.log("    [OK] Policy is enabled");

        console.log("\n[2] VERIFY: Agent uses OWNER's assets for market order");
        orderBook.setNextOrderResponse(1, 1000e6);

        vm.prank(user1);
        agentRouter.executeMarketOrder(user1, agent1, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);

        assertEq(orderBook.lastOrderOwner(), user1);
        console.log("    [OK] Order placed with OWNER address (user1)");

        console.log("\n[3] VERIFY: Agent uses OWNER's assets for limit order");
        orderBook.setNextOrderId(100);

        vm.prank(user1);
        agentRouter.executeLimitOrder(user1, agent1, wethUsdcPool, 2000e6, 500e6, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, false, false);

        assertEq(orderBook.lastOrderOwner(), user1);
        console.log("    [OK] Limit order placed with OWNER address (user1)");

        console.log("\n[4] VERIFY: Borrow operation works for owner");
        lendingManager.setHealthFactor(user1, 3e18);

        vm.prank(user1);
        agentRouter.executeBorrow(user1, agent1, USDC, 1000e6);

        assertTrue(balanceManager.borrowCalled());
        assertEq(balanceManager.lastBorrowToken(), USDC);
        assertEq(balanceManager.lastBorrowAmount(), 1000e6);
        console.log("    [OK] Borrow executed: 1000e6 USDC");

        console.log("\n[5] VERIFY: Repay operation works for owner");
        lendingManager.setHealthFactor(user1, 2e18);

        vm.prank(user1);
        agentRouter.executeRepay(user1, agent1, USDC, 500e6);

        assertTrue(balanceManager.repayCalled());
        assertEq(balanceManager.lastRepayToken(), USDC);
        assertEq(balanceManager.lastRepayAmount(), 500e6);
        console.log("    [OK] Repay executed: 500e6 USDC");

        console.log("\n[6] VERIFY: Non-owner cannot use another user's agent");

        // user1 can't execute with agent2 (owned by user2)
        vm.prank(user1);
        vm.expectRevert("Not strategy agent owner");
        agentRouter.executeMarketOrder(user1, agent2, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);
        console.log("    [OK] user1 CANNOT use agent2 (owned by user2)");

        // user2 can't execute with agent1 (owned by user1)
        vm.prank(user2);
        vm.expectRevert("Not strategy agent owner");
        agentRouter.executeMarketOrder(user2, agent1, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);
        console.log("    [OK] user2 CANNOT use agent1 (owned by user1)");

        console.log("\n===========================================");
        console.log("ALL CRITICAL VERIFICATIONS PASSED [OK]");
        console.log("===========================================\n");
    }

    // ============ Market Order Tests ============

    function test_ExecuteMarketOrder() public {
        vm.prank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.maxOrderSize = 5000e6;
        p.minTimeBetweenTrades = 0;
        agentRouter.authorize(agent1, p);

        orderBook.setNextOrderResponse(1, 1000e6);

        vm.prank(user1);
        (uint48 orderId, uint128 filled) = agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );

        assertEq(orderId, 1);
        assertEq(filled, 1000e6);
        assertEq(agentRouter.getLastTradeTime(agent1), block.timestamp);
        assertEq(agentRouter.getDailyVolume(agent1), 1000e6);
    }

    function test_RevertMarketOrderAgentDisabled() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        // Disable agent via PolicyFactory
        policyFactory.setAgentEnabled(agent1, false);

        vm.expectRevert("Agent disabled");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderAgentExpired() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.expiryTimestamp = block.timestamp + 1 days;
        agentRouter.authorize(agent1, p);

        // Warp past expiry
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert("Agent expired");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderUnauthorizedExecutor() public {
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        // user2 tries to execute with agent1 (user2 is not the NFT owner)
        vm.prank(user2);
        vm.expectRevert("Not strategy agent owner");
        agentRouter.executeMarketOrder(
            user2, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );
    }

    function test_RevertMarketOrderRequiresChainlink() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.dailyVolumeLimit = 10000e6; // triggers requiresChainlinkFunctions
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Use executeMarketOrderWithMetrics");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderSizeTooLarge() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.maxOrderSize = 100e6;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Order too large");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderSizeTooSmall() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.minOrderSize = 1000e6;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Order too small");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            100e6, 95e6, false, false
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderTokenNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        address[] memory whitelist = new address[](1);
        whitelist[0] = WBTC;
        p.whitelistedTokens = whitelist;
        agentRouter.authorize(agent1, p);

        // WETH/USDC pool — WETH not in whitelist
        vm.expectRevert("Base token not allowed");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderSwapNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.allowSwap = false;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Swap not allowed");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderBuyNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.allowBuy = false;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Buy orders not allowed");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderSellNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.allowSell = false;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Sell orders not allowed");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.SELL,
            1000e6, 950e6, false, false
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderAutoBorrowNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.allowAutoBorrow = false;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Auto-borrow not allowed");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false,
            true // autoBorrow
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderAutoRepayNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.allowAutoRepay = false;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Auto-repay not allowed");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6,
            true, // autoRepay
            false
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderHealthFactorTooLow() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        // Set health factor below minimum (policy requires 150%)
        lendingManager.setHealthFactor(user1, 1e18); // 100%

        vm.expectRevert("Health factor too low");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );
        vm.stopPrank();
    }

    function test_RevertMarketOrderCooldownActive() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.minTimeBetweenTrades = 60; // 60 second cooldown
        agentRouter.authorize(agent1, p);

        orderBook.setNextOrderResponse(1, 1000e6);

        // First trade
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );

        // Warp forward 30 seconds (still in cooldown)
        vm.warp(block.timestamp + 30);

        vm.expectRevert("Cooldown period active");
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );
        vm.stopPrank();
    }

    function test_MarketOrderAfterCooldown() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.minTimeBetweenTrades = 60;
        agentRouter.authorize(agent1, p);

        orderBook.setNextOrderResponse(1, 1000e6);

        // First trade
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );

        // Warp past cooldown
        vm.warp(block.timestamp + 61);
        orderBook.setNextOrderResponse(2, 1000e6);

        // Second trade should succeed
        (uint48 orderId,) = agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );

        assertEq(orderId, 2);
        vm.stopPrank();
    }

    function test_MarketOrderEventEmission() public {
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        orderBook.setNextOrderResponse(1, 1000e6);

        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentSwapExecuted(
            user1, agent1, user1,
            WETH, USDC, 1000e6, 1000e6,
            block.timestamp
        );

        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );
        vm.stopPrank();
    }

    function test_MarketOrderReputationRecorded() public {
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        orderBook.setNextOrderResponse(1, 1000e6);

        vm.prank(user1);
        agentRouter.executeMarketOrder(
            user1, agent1, wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6, 950e6, false, false
        );

        // Verify reputation was updated
        (uint256 totalTrades,,,) = reputationRegistry.getMetrics(agent1);
        assertEq(totalTrades, 1);
    }

    // ============ Limit Order Tests ============

    function test_ExecuteLimitOrder() public {
        vm.prank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.maxOrderSize = 5000e6;
        p.minTimeBetweenTrades = 0;
        agentRouter.authorize(agent1, p);

        orderBook.setNextOrderId(100);

        vm.prank(user1);
        uint48 orderId = agentRouter.executeLimitOrder(
            user1, agent1, wethUsdcPool,
            2000e6, 1000e6,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false, false
        );

        assertEq(orderId, 100);
        assertEq(agentRouter.getLastTradeTime(agent1), block.timestamp);
    }

    function test_RevertLimitOrderNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.allowLimitOrders = false;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Limit orders not allowed");
        agentRouter.executeLimitOrder(
            user1, agent1, wethUsdcPool,
            2000e6, 1000e6,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false, false
        );
        vm.stopPrank();
    }

    function test_LimitOrderEventEmission() public {
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        orderBook.setNextOrderId(100);

        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentLimitOrderPlaced(
            user1, agent1, user1,
            bytes32(uint256(100)),
            WETH, USDC, 1000e6, 2000e6,
            true, // isBuy
            block.timestamp
        );

        agentRouter.executeLimitOrder(
            user1, agent1, wethUsdcPool,
            2000e6, 1000e6,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false, false
        );
        vm.stopPrank();
    }

    // ============ Cancel Order Tests ============

    function test_CancelOrder() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        agentRouter.cancelOrder(user1, agent1, wethUsdcPool, 100);

        assertTrue(orderBook.cancelOrderCalled());
        vm.stopPrank();
    }

    function test_RevertCancelOrderNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.allowCancelOrder = false;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Cancelling orders not allowed");
        agentRouter.cancelOrder(user1, agent1, wethUsdcPool, 100);
        vm.stopPrank();
    }

    function test_CancelOrderEventEmission() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentOrderCancelled(
            user1, agent1, user1,
            bytes32(uint256(100)),
            block.timestamp
        );

        agentRouter.cancelOrder(user1, agent1, wethUsdcPool, 100);
        vm.stopPrank();
    }

    // ============ Borrow Tests ============

    function test_ExecuteBorrow() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        lendingManager.setHealthFactor(user1, 3e18);

        agentRouter.executeBorrow(user1, agent1, USDC, 1000e6);

        assertTrue(balanceManager.borrowCalled());
        assertEq(balanceManager.lastBorrowToken(), USDC);
        assertEq(balanceManager.lastBorrowAmount(), 1000e6);
        vm.stopPrank();
    }

    function test_RevertBorrowNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.allowBorrow = false;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Borrowing not allowed");
        agentRouter.executeBorrow(user1, agent1, USDC, 1000e6);
        vm.stopPrank();
    }

    function test_RevertBorrowExceedsLimit() public {
        vm.startPrank(user1);
        // Default policy has maxAutoBorrowAmount = 10000e6
        agentRouter.authorize(agent1, _createCustomPolicy());

        vm.expectRevert("Borrow amount exceeds limit");
        agentRouter.executeBorrow(user1, agent1, USDC, 100000e6);
        vm.stopPrank();
    }

    function test_RevertBorrowTokenNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        address[] memory whitelist = new address[](1);
        whitelist[0] = WETH;
        p.whitelistedTokens = whitelist;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Token not allowed");
        agentRouter.executeBorrow(user1, agent1, USDC, 1000e6);
        vm.stopPrank();
    }

    function test_RevertBorrowHealthFactorTooLow() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        lendingManager.setHealthFactor(user1, 1e18); // 100% < 150% minHealthFactor

        vm.expectRevert("Health factor too low");
        agentRouter.executeBorrow(user1, agent1, USDC, 1000e6);
        vm.stopPrank();
    }

    function test_BorrowEventEmission() public {
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        lendingManager.setHealthFactor(user1, 3e18);

        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentBorrowExecuted(
            user1, agent1, user1,
            USDC, 1000e6, 3e18,
            block.timestamp
        );

        agentRouter.executeBorrow(user1, agent1, USDC, 1000e6);
        vm.stopPrank();
    }

    function test_BorrowReputationRecorded() public {
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        lendingManager.setHealthFactor(user1, 3e18);

        vm.prank(user1);
        agentRouter.executeBorrow(user1, agent1, USDC, 1000e6);

        IERC8004Reputation.Feedback[] memory feedbacks =
            reputationRegistry.getFeedbackHistory(agent1, 0, 10);

        assertEq(feedbacks.length, 1);
        assertEq(uint256(feedbacks[0].feedbackType), uint256(IERC8004Reputation.FeedbackType.BORROW));
    }

    // ============ Repay Tests ============

    function test_ExecuteRepay() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        agentRouter.executeRepay(user1, agent1, USDC, 500e6);

        assertTrue(balanceManager.repayCalled());
        assertEq(balanceManager.lastRepayToken(), USDC);
        assertEq(balanceManager.lastRepayAmount(), 500e6);
        vm.stopPrank();
    }

    function test_RevertRepayNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.allowRepay = false;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Repaying not allowed");
        agentRouter.executeRepay(user1, agent1, USDC, 500e6);
        vm.stopPrank();
    }

    function test_RepayEventEmission() public {
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        lendingManager.setHealthFactor(user1, 2e18);

        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentRepayExecuted(
            user1, agent1, user1,
            USDC, 500e6, 2e18,
            block.timestamp
        );

        agentRouter.executeRepay(user1, agent1, USDC, 500e6);
        vm.stopPrank();
    }

    // ============ Supply Collateral Tests ============

    function test_ExecuteSupplyCollateral() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        // Mock ERC20 calls since WETH = address(0x1) is a precompile, not a real token
        vm.mockCall(WETH, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.mockCall(WETH, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

        agentRouter.executeSupplyCollateral(user1, agent1, WETH, 1e18);

        assertTrue(balanceManager.depositLocalCalled());
        assertEq(balanceManager.lastDepositLocalToken(), WETH);
        assertEq(balanceManager.lastDepositLocalAmount(), 1e18);
        vm.stopPrank();
    }

    function test_RevertSupplyCollateralNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.allowSupplyCollateral = false;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Supplying collateral not allowed");
        agentRouter.executeSupplyCollateral(user1, agent1, WETH, 1e18);
        vm.stopPrank();
    }

    function test_SupplyCollateralEventEmission() public {
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        // Mock ERC20 calls since WETH = address(0x1) is a precompile, not a real token
        vm.mockCall(WETH, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.mockCall(WETH, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentCollateralSupplied(
            user1, agent1, user1,
            WETH, 1e18,
            block.timestamp
        );

        agentRouter.executeSupplyCollateral(user1, agent1, WETH, 1e18);
        vm.stopPrank();
    }

    // ============ Withdraw Collateral Tests ============

    function test_ExecuteWithdrawCollateral() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        lendingManager.setHealthFactor(user1, 3e18);

        agentRouter.executeWithdrawCollateral(user1, agent1, WETH, 1e18);

        assertTrue(balanceManager.withdrawCalled());
        assertEq(balanceManager.lastWithdrawToken(), WETH);
        assertEq(balanceManager.lastWithdrawAmount(), 1e18);
        vm.stopPrank();
    }

    function test_RevertWithdrawCollateralNotAllowed() public {
        vm.startPrank(user1);
        PolicyFactory.Policy memory p = _createCustomPolicy();
        p.allowWithdrawCollateral = false;
        agentRouter.authorize(agent1, p);

        vm.expectRevert("Withdrawing collateral not allowed");
        agentRouter.executeWithdrawCollateral(user1, agent1, WETH, 1e18);
        vm.stopPrank();
    }

    function test_RevertWithdrawHealthFactorTooLow() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        lendingManager.setHealthFactor(user1, 1e18); // 100% < 150% minimum

        vm.expectRevert("Health factor too low");
        agentRouter.executeWithdrawCollateral(user1, agent1, WETH, 1e18);
        vm.stopPrank();
    }

    function test_WithdrawCollateralEventEmission() public {
        vm.prank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        lendingManager.setHealthFactor(user1, 3e18);

        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentCollateralWithdrawn(
            user1, agent1, user1,
            WETH, 1e18,
            block.timestamp
        );

        agentRouter.executeWithdrawCollateral(user1, agent1, WETH, 1e18);
        vm.stopPrank();
    }

    // ============ View Function Tests ============

    function test_GetDailyVolume() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        orderBook.setNextOrderResponse(1, 1000e6);
        agentRouter.executeMarketOrder(user1, agent1, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);

        orderBook.setNextOrderResponse(2, 2000e6);
        agentRouter.executeMarketOrder(user1, agent1, wethUsdcPool, IOrderBook.Side.BUY, 2000e6, 1900e6, false, false);
        vm.stopPrank();

        uint256 volume = agentRouter.getDailyVolume(agent1);
        assertEq(volume, 3000e6);
    }

    function test_GetLastTradeTime() public {
        vm.startPrank(user1);
        agentRouter.authorize(agent1, _createCustomPolicy());

        orderBook.setNextOrderResponse(1, 1000e6);
        agentRouter.executeMarketOrder(user1, agent1, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);
        vm.stopPrank();

        uint256 lastTime = agentRouter.getLastTradeTime(agent1);
        assertEq(lastTime, block.timestamp);
    }

    // ============ Helper Functions ============

    /// @dev Build a default custom policy for tests.
    ///      All Chainlink-requiring fields are 0, requiresChainlinkFunctions is auto-set to false.
    function _createCustomPolicy() internal view returns (PolicyFactory.Policy memory) {
        address[] memory emptyArray = new address[](0);

        return PolicyFactory.Policy({
            enabled: true,
            installedAt: 0,
            expiryTimestamp: block.timestamp + 90 days,
            maxOrderSize: 25000e6,
            minOrderSize: 100e6,
            whitelistedTokens: emptyArray,
            blacklistedTokens: emptyArray,
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
            minDebtToRepay: 100e6,
            minHealthFactor: 15e17, // 150%
            maxSlippageBps: 150,
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
            minReputationScore: 50,
            useReputationMultiplier: true,
            requiresChainlinkFunctions: false
        });
    }
}
