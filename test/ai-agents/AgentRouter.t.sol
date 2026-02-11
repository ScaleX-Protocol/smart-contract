// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/ai-agents/AgentRouter.sol";
import "../../src/ai-agents/PolicyFactory.sol";
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
 * @notice Comprehensive tests for AgentRouter contract
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
    address public executor;

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
        executor = address(0x300);

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

        // Mint agent NFTs
        vm.prank(user1);
        agent1 = identityRegistry.mintAuto(user1, "ipfs://agent1");

        vm.prank(user2);
        agent2 = identityRegistry.mintAuto(user2, "ipfs://agent2");

        // Setup default health factor
        lendingManager.setHealthFactor(user1, 2e18); // 200%
        lendingManager.setHealthFactor(user2, 2e18);
    }

    // ============ Agent Installation Verification Tests ============

    function test_AgentInstallationVerification() public {
        // 1. Verify agent NOT installed initially
        assertFalse(policyFactory.isAgentEnabled(user1, agent1));

        // Attempting to get policy for non-installed agent should return default/empty policy
        PolicyFactory.Policy memory emptyPolicy = policyFactory.getPolicy(user1, agent1);
        assertEq(emptyPolicy.installedAt, 0);
        assertFalse(emptyPolicy.enabled);

        // 2. Install agent with moderate template (without dailyVolumeLimit to keep it simple)
        vm.startPrank(user1);
        PolicyFactory.PolicyCustomization memory customization;
        customization.maxOrderSize = 10000e6;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);
        vm.stopPrank();

        // 3. Verify agent IS installed
        assertTrue(policyFactory.isAgentEnabled(user1, agent1));

        // 4. Verify policy details are correct
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(user1, agent1);
        assertEq(policy.agentTokenId, agent1);
        assertTrue(policy.enabled);
        assertEq(policy.maxOrderSize, 10000e6);
        assertGt(policy.installedAt, 0); // Installation timestamp recorded
        assertGt(policy.expiryTimestamp, block.timestamp); // Has valid expiry

        // 5. Verify agent appears in user's installed agents list
        uint256[] memory installedAgents = policyFactory.getInstalledAgents(user1);
        assertEq(installedAgents.length, 1);
        assertEq(installedAgents[0], agent1);
    }

    function test_AgentNotInstalledCannotTrade() public {
        // Agent is NOT installed, should fail to execute any trade
        vm.prank(user1);
        vm.expectRevert("Agent disabled");
        agentRouter.executeMarketOrder(
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
        balanceManager.setBalance(user1, Currency.wrap(WETH), 0); // Owner starts with 0 WETH
        balanceManager.setBalance(user1, Currency.wrap(USDC), 10000e6); // Owner has 10,000 USDC

        // 2. Install agent for user1 with simple custom policy (no Chainlink requirements)
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.requiresChainlinkFunctions = false; // No Chainlink needed
        customPolicy.dailyVolumeLimit = 0; // No daily limit
        policyFactory.installAgent(agent1, customPolicy);

        // 3. Verify agent is installed
        assertTrue(policyFactory.isAgentEnabled(user1, agent1));

        // 4. Setup order book to return filled order
        orderBook.setNextOrderResponse(1, 1000e6); // Order ID 1, fills 1000 units

        // 5. Agent places BUY order for WETH using owner's USDC
        (uint48 orderId, uint128 filled) = agentRouter.executeMarketOrder(
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
        // The orderBook should have been called with owner=user1
        assertEq(orderBook.lastOrderOwner(), user1); // Critical: Owner's assets used

        vm.stopPrank();
    }

    function test_AgentPlacesLimitOrderUsingOwnerAssets() public {
        // 1. Setup owner's balances
        balanceManager.setBalance(user1, Currency.wrap(WETH), 5e18); // Owner has 5 WETH
        balanceManager.setBalance(user1, Currency.wrap(USDC), 5000e6); // Owner has 5,000 USDC

        // 2. Install agent with simple custom policy (uses default maxOrderSize of 25000e6)
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.requiresChainlinkFunctions = false;
        customPolicy.dailyVolumeLimit = 0;
        // Keep default maxOrderSize of 25000e6 from _createCustomPolicy
        policyFactory.installAgent(agent1, customPolicy);

        // 3. Verify agent is installed
        assertTrue(policyFactory.isAgentEnabled(user1, agent1));

        // 4. Setup order book to return order ID
        orderBook.setNextOrderId(100);

        // 5. Agent places SELL limit order using owner's WETH
        uint48 orderId = agentRouter.executeLimitOrder(
            agent1,
            wethUsdcPool,
            2000e6, // price: 2000 USDC (in 6 decimals)
            1000e6, // quantity: 1000 units (in 6 decimals, representing 1 WETH equivalent in value)
            IOrderBook.Side.SELL,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        );

        // 6. Verify order was placed
        assertEq(orderId, 100);

        // 7. Verify the order used OWNER's address (user1)
        assertEq(orderBook.lastOrderOwner(), user1); // Critical: Owner's assets used

        vm.stopPrank();
    }

    function test_AgentCannotPlaceOrderForDifferentOwner() public {
        // 1. Install agent1 for user1
        vm.prank(user1);
        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        // 2. Install agent2 for user2
        vm.prank(user2);
        policyFactory.installAgentFromTemplate(agent2, "moderate", customization);

        // 3. user1 tries to use agent2 (owned by user2) - should fail
        vm.prank(user1);
        vm.expectRevert("Not authorized executor");
        agentRouter.executeMarketOrder(
            agent2, // user2's agent
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        // 4. user2 tries to use agent1 (owned by user1) - should fail
        vm.prank(user2);
        vm.expectRevert("Not authorized executor");
        agentRouter.executeMarketOrder(
            agent1, // user1's agent
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );
    }

    function test_EventsDistinguishOwnerFromAgentExecution() public {
        // Setup: Install agent for user1
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.requiresChainlinkFunctions = false;
        customPolicy.dailyVolumeLimit = 0;
        policyFactory.installAgent(agent1, customPolicy);
        vm.stopPrank();

        orderBook.setNextOrderResponse(1, 1000e6);

        // Scenario 1: Owner executes directly (owner == executor)
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentSwapExecuted(
            user1,      // owner
            agent1,     // agentTokenId
            user1,      // executor (SAME as owner - owner executed directly!)
            WETH,
            USDC,
            1000e6,
            1000e6,
            block.timestamp
        );
        agentRouter.executeMarketOrder(agent1, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);

        // Scenario 2: Authorized executor (agent service) executes on behalf of owner
        // Note: In real implementation, executor address would be authorized via _isAuthorizedExecutor
        // Here we test that the event correctly captures user1 as owner and executor as msg.sender

        // The event structure allows differentiation:
        // - If owner == executor: Owner acted directly
        // - If owner != executor: Agent service acted on behalf of owner
    }

    // ============ COMPREHENSIVE EVENT TRACING TESTS ============

    function test_TraceMarketOrderPlacement() public {
        console.log("\n=== TRACING MARKET ORDER PLACEMENT ===");

        // Setup
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.requiresChainlinkFunctions = false;
        customPolicy.dailyVolumeLimit = 0;
        policyFactory.installAgent(agent1, customPolicy);
        vm.stopPrank();

        orderBook.setNextOrderResponse(42, 1500e6);

        // Execute market order and verify event
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentSwapExecuted(
            user1,           // owner: user1 owns the assets
            agent1,          // agentTokenId: agent policy #1 used
            user1,           // executor: user1 executed it themselves
            WETH,            // tokenIn: buying WETH
            USDC,            // tokenOut: selling USDC
            1500e6,          // amountIn: 1500 units
            1500e6,          // amountOut: 1500 units filled
            block.timestamp  // timestamp
        );
        agentRouter.executeMarketOrder(agent1, wethUsdcPool, IOrderBook.Side.BUY, 1500e6, 1400e6, false, false);

        console.log("Market Order Event Emitted:");
        console.log("  Owner:", user1);
        console.log("  Agent ID:", agent1);
        console.log("  Executor:", user1);
        console.log("  Token In: WETH");
        console.log("  Token Out: USDC");
        console.log("  Amount: 1500e6");
    }

    function test_TraceLimitOrderPlacement() public {
        console.log("\n=== TRACING LIMIT ORDER PLACEMENT ===");

        // Setup
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.requiresChainlinkFunctions = false;
        customPolicy.dailyVolumeLimit = 0;
        policyFactory.installAgent(agent1, customPolicy);
        vm.stopPrank();

        orderBook.setNextOrderId(999);

        // Execute limit order and verify event
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentLimitOrderPlaced(
            user1,                  // owner: user1 owns the assets
            agent1,                 // agentTokenId: agent policy #1 used
            user1,                  // executor: user1 executed it themselves
            bytes32(uint256(999)),  // orderId: order #999
            WETH,                   // tokenIn: WETH
            USDC,                   // tokenOut: USDC
            500e6,                  // amount: 500 units
            2100e6,                 // limitPrice: 2100 USDC per WETH
            false,                  // isBuy: false (SELL order)
            block.timestamp         // timestamp
        );
        agentRouter.executeLimitOrder(agent1, wethUsdcPool, 2100e6, 500e6, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, false, false);

        console.log("Limit Order Event Emitted:");
        console.log("  Owner:", user1);
        console.log("  Agent ID:", agent1);
        console.log("  Executor:", user1);
        console.log("  Order ID: 999");
        console.log("  Side: SELL");
        console.log("  Price: 2100e6");
        console.log("  Amount: 500e6");
    }

    function test_TraceBorrowAction() public {
        console.log("\n=== TRACING BORROW ACTION ===");

        // Setup
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.requiresChainlinkFunctions = false;
        customPolicy.dailyVolumeLimit = 0;
        policyFactory.installAgent(agent1, customPolicy);
        vm.stopPrank();

        lendingManager.setHealthFactor(user1, 3e18); // 300% health factor

        // Execute borrow and verify event
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentBorrowExecuted(
            user1,           // owner: user1 is borrowing
            agent1,          // agentTokenId: using agent policy #1
            user1,           // executor: user1 executed it themselves
            USDC,            // token: borrowing USDC
            2000e6,          // amount: 2000 USDC
            3e18,            // newHealthFactor: 300%
            block.timestamp  // timestamp
        );
        agentRouter.executeBorrow(agent1, USDC, 2000e6);

        console.log("Borrow Event Emitted:");
        console.log("  Owner:", user1);
        console.log("  Agent ID:", agent1);
        console.log("  Executor:", user1);
        console.log("  Token: USDC");
        console.log("  Amount: 2000e6");
        console.log("  Health Factor: 300%");
    }

    function test_TraceRepayAction() public {
        console.log("\n=== TRACING REPAY ACTION ===");

        // Setup
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.requiresChainlinkFunctions = false;
        customPolicy.dailyVolumeLimit = 0;
        policyFactory.installAgent(agent1, customPolicy);
        vm.stopPrank();

        lendingManager.setHealthFactor(user1, 2e18); // 200% health factor

        // Execute repay and verify event
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentRepayExecuted(
            user1,           // owner: user1 is repaying
            agent1,          // agentTokenId: using agent policy #1
            user1,           // executor: user1 executed it themselves
            USDC,            // token: repaying USDC
            1000e6,          // amount: 1000 USDC
            2e18,            // newHealthFactor: 200%
            block.timestamp  // timestamp
        );
        agentRouter.executeRepay(agent1, USDC, 1000e6);

        console.log("Repay Event Emitted:");
        console.log("  Owner:", user1);
        console.log("  Agent ID:", agent1);
        console.log("  Executor:", user1);
        console.log("  Token: USDC");
        console.log("  Amount: 1000e6");
        console.log("  Health Factor: 200%");
    }

    function test_TraceDepositCollateral() public {
        console.log("\n=== TRACING DEPOSIT COLLATERAL ===");

        // Setup
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.requiresChainlinkFunctions = false;
        customPolicy.dailyVolumeLimit = 0;
        policyFactory.installAgent(agent1, customPolicy);
        vm.stopPrank();

        // Execute deposit and verify event
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentCollateralSupplied(
            user1,           // owner: user1 owns the collateral
            agent1,          // agentTokenId: using agent policy #1
            user1,           // executor: user1 executed it themselves
            WETH,            // token: depositing WETH
            3e18,            // amount: 3 WETH
            block.timestamp  // timestamp
        );
        agentRouter.executeSupplyCollateral(agent1, WETH, 3e18);

        console.log("Deposit Collateral Event Emitted:");
        console.log("  Owner:", user1);
        console.log("  Agent ID:", agent1);
        console.log("  Executor:", user1);
        console.log("  Token: WETH");
        console.log("  Amount: 3e18 (3 WETH)");
    }

    function test_TraceWithdrawCollateral() public {
        console.log("\n=== TRACING WITHDRAW COLLATERAL ===");

        // Setup
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.requiresChainlinkFunctions = false;
        customPolicy.dailyVolumeLimit = 0;
        policyFactory.installAgent(agent1, customPolicy);
        vm.stopPrank();

        lendingManager.setHealthFactor(user1, 3e18); // 300% health factor (safe to withdraw)

        // Execute withdrawal and verify event
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentCollateralWithdrawn(
            user1,           // owner: user1 owns the collateral
            agent1,          // agentTokenId: using agent policy #1
            user1,           // executor: user1 executed it themselves
            WETH,            // token: withdrawing WETH
            1e18,            // amount: 1 WETH
            block.timestamp  // timestamp
        );
        agentRouter.executeWithdrawCollateral(agent1, WETH, 1e18);

        console.log("Withdraw Collateral Event Emitted:");
        console.log("  Owner:", user1);
        console.log("  Agent ID:", agent1);
        console.log("  Executor:", user1);
        console.log("  Token: WETH");
        console.log("  Amount: 1e18 (1 WETH)");
    }

    function test_TraceCancelOrder() public {
        console.log("\n=== TRACING ORDER CANCELLATION ===");

        // Setup
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.requiresChainlinkFunctions = false;
        customPolicy.dailyVolumeLimit = 0;
        policyFactory.installAgent(agent1, customPolicy);
        vm.stopPrank();

        // Execute cancel and verify event
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentOrderCancelled(
            user1,                  // owner: user1 owns the order
            agent1,                 // agentTokenId: using agent policy #1
            user1,                  // executor: user1 executed it themselves
            bytes32(uint256(777)),  // orderId: cancelling order #777
            block.timestamp         // timestamp
        );
        agentRouter.cancelOrder(agent1, wethUsdcPool, 777);

        console.log("Cancel Order Event Emitted:");
        console.log("  Owner:", user1);
        console.log("  Agent ID:", agent1);
        console.log("  Executor:", user1);
        console.log("  Order ID: 777");
    }

    // ============ COMPREHENSIVE VERIFICATION TEST ============

    function test_VERIFICATION_AllCriticalAssertions() public {
        console.log("\n");
        console.log("===========================================");
        console.log("COMPREHENSIVE VERIFICATION TEST");
        console.log("===========================================");

        // SETUP
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.requiresChainlinkFunctions = false;
        customPolicy.dailyVolumeLimit = 0;
        policyFactory.installAgent(agent1, customPolicy);
        vm.stopPrank();

        console.log("\n[1] VERIFY: Agent is installed");
        assertTrue(policyFactory.isAgentEnabled(user1, agent1));
        console.log("    [OK] Agent is enabled for user1");

        PolicyFactory.Policy memory policy = policyFactory.getPolicy(user1, agent1);
        assertEq(policy.agentTokenId, agent1);
        console.log("    [OK] Policy agentTokenId matches");
        assertTrue(policy.enabled);
        console.log("    [OK] Policy is enabled");

        console.log("\n[2] VERIFY: Agent uses OWNER's assets for market order");
        orderBook.setNextOrderResponse(1, 1000e6);

        vm.prank(user1);
        agentRouter.executeMarketOrder(agent1, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);

        // CRITICAL: Verify the order was placed with OWNER's address
        assertEq(orderBook.lastOrderOwner(), user1);
        console.log("    [OK] Order placed with OWNER address (user1):", user1);
        console.log("    [OK] NOT with agent address - uses OWNER's funds!");

        console.log("\n[3] VERIFY: Agent uses OWNER's assets for limit order");
        orderBook.setNextOrderId(100);

        vm.prank(user1);
        agentRouter.executeLimitOrder(agent1, wethUsdcPool, 2000e6, 500e6, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, false, false);

        // CRITICAL: Verify the order was placed with OWNER's address
        assertEq(orderBook.lastOrderOwner(), user1);
        console.log("    [OK] Limit order placed with OWNER address (user1):", user1);
        console.log("    [OK] NOT with agent address - uses OWNER's funds!");

        console.log("\n[4] VERIFY: Borrow operation works for owner");
        lendingManager.setHealthFactor(user1, 3e18);

        vm.prank(user1);
        agentRouter.executeBorrow(agent1, USDC, 1000e6);

        assertTrue(lendingManager.borrowCalled());
        console.log("    [OK] Borrow executed successfully");
        assertEq(lendingManager.lastBorrowToken(), USDC);
        console.log("    [OK] Borrowed token: USDC");
        assertEq(lendingManager.lastBorrowAmount(), 1000e6);
        console.log("    [OK] Borrowed amount: 1000e6");

        console.log("\n[5] VERIFY: Repay operation works for owner");
        lendingManager.setHealthFactor(user1, 2e18);

        vm.prank(user1);
        agentRouter.executeRepay(agent1, USDC, 500e6);

        assertTrue(lendingManager.repayCalled());
        console.log("    [OK] Repay executed successfully");
        assertEq(lendingManager.lastRepayToken(), USDC);
        console.log("    [OK] Repaid token: USDC");
        assertEq(lendingManager.lastRepayAmount(), 500e6);
        console.log("    [OK] Repaid amount: 500e6");

        console.log("\n[6] VERIFY: Authorization prevents cross-owner access");
        vm.startPrank(user2);
        PolicyFactory.Policy memory customPolicy2 = _createCustomPolicy(agent2);
        customPolicy2.requiresChainlinkFunctions = false;
        customPolicy2.dailyVolumeLimit = 0;
        policyFactory.installAgent(agent2, customPolicy2);
        vm.stopPrank();

        // user1 tries to use user2's agent - should fail
        vm.prank(user1);
        vm.expectRevert("Not authorized executor");
        agentRouter.executeMarketOrder(agent2, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);
        console.log("    [OK] user1 CANNOT use user2's agent");

        // user2 tries to use user1's agent - should fail
        vm.prank(user2);
        vm.expectRevert("Not authorized executor");
        agentRouter.executeMarketOrder(agent1, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);
        console.log("    [OK] user2 CANNOT use user1's agent");

        console.log("\n===========================================");
        console.log("ALL CRITICAL VERIFICATIONS PASSED [OK]");
        console.log("===========================================");
        console.log("[OK] Agent installation verified");
        console.log("[OK] Orders use OWNER's assets (NOT agent's)");
        console.log("[OK] Borrow/Repay works correctly");
        console.log("[OK] Authorization properly enforced");
        console.log("===========================================\n");
    }

    // ============ Market Order Tests ============

    function test_ExecuteMarketOrder() public {
        // Install agent with custom policy (no Chainlink requirements)
        vm.startPrank(user1);
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.maxOrderSize = 5000e6;
        customPolicy.minTimeBetweenTrades = 0; // No cooldown
        policyFactory.installAgent(agent1, customPolicy);
        vm.stopPrank();

        // Setup order book response
        orderBook.setNextOrderResponse(1, 1000e6);

        // Execute market order
        vm.prank(user1);
        (uint48 orderId, uint128 filled) = agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        // Verify order was executed
        assertEq(orderId, 1);
        assertEq(filled, 1000e6);

        // Verify tracking updated
        assertEq(agentRouter.getLastTradeTime(agent1), block.timestamp);
        assertEq(agentRouter.getDailyVolume(agent1), 1000e6);
    }

    function test_RevertMarketOrderAgentDisabled() public {
        vm.startPrank(user1);
        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        // Disable agent
        policyFactory.setAgentEnabled(agent1, false);

        // Try to execute order
        vm.expectRevert("Agent disabled");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderAgentExpired() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        customization.expiryTimestamp = block.timestamp + 1 days;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        // Warp past expiry
        vm.warp(block.timestamp + 2 days);

        // Try to execute order
        vm.expectRevert("Agent expired");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderUnauthorizedExecutor() public {
        vm.prank(user1);
        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        // User2 tries to execute user1's agent
        vm.prank(user2);
        vm.expectRevert("Not authorized executor");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );
    }

    function test_RevertMarketOrderRequiresChainlink() public {
        vm.startPrank(user1);

        // Install with daily volume limit (requires Chainlink)
        PolicyFactory.PolicyCustomization memory customization;
        customization.dailyVolumeLimit = 10000e6;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        // Try to execute - should require Chainlink version
        vm.expectRevert("Use executeMarketOrderWithMetrics");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderSizeTooLarge() public {
        vm.startPrank(user1);
        PolicyFactory.PolicyCustomization memory customization;
        customization.maxOrderSize = 100e6;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        vm.expectRevert("Order too large");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderSizeTooSmall() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.minOrderSize = 1000e6;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Order too small");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            100e6,
            95e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderTokenNotAllowed() public {
        vm.startPrank(user1);

        // Install with WBTC whitelist only
        PolicyFactory.PolicyCustomization memory customization;
        address[] memory whitelist = new address[](1);
        whitelist[0] = WBTC;
        customization.whitelistedTokens = whitelist;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        // Try to trade WETH/USDC
        vm.expectRevert("Base token not allowed");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderSwapNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.allowSwap = false;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Swap not allowed");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderBuyNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.allowBuy = false;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Buy orders not allowed");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderSellNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.allowSell = false;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Sell orders not allowed");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.SELL,
            1000e6,
            950e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderAutoBorrowNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.allowAutoBorrow = false;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Auto-borrow not allowed");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            true // autoBorrow
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderAutoRepayNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.allowAutoRepay = false;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Auto-repay not allowed");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            true, // autoRepay
            false
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderHealthFactorTooLow() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        // Set health factor below minimum
        lendingManager.setHealthFactor(user1, 1e18); // 100%

        vm.expectRevert("Health factor too low");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_RevertMarketOrderCooldownActive() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.minTimeBetweenTrades = 60; // 60 second cooldown
        policyFactory.installAgent(agent1, customPolicy);

        orderBook.setNextOrderResponse(1, 1000e6);

        // First trade
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        // Warp forward 30 seconds (still in cooldown)
        vm.warp(block.timestamp + 30);

        // Try second trade
        vm.expectRevert("Cooldown period active");
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_MarketOrderAfterCooldown() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.minTimeBetweenTrades = 60;
        policyFactory.installAgent(agent1, customPolicy);

        orderBook.setNextOrderResponse(1, 1000e6);

        // First trade
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        // Warp past cooldown
        vm.warp(block.timestamp + 61);

        orderBook.setNextOrderResponse(2, 1000e6);

        // Second trade should succeed
        (uint48 orderId,) = agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        assertEq(orderId, 2);

        vm.stopPrank();
    }

    function test_MarketOrderEventEmission() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        orderBook.setNextOrderResponse(1, 1000e6);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentSwapExecuted(
            user1,
            agent1,
            user1,
            WETH,
            USDC,
            1000e6,
            1000e6,
            block.timestamp
        );

        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_MarketOrderReputationRecorded() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        orderBook.setNextOrderResponse(1, 1000e6);

        // Execute order
        agentRouter.executeMarketOrder(
            agent1,
            wethUsdcPool,
            IOrderBook.Side.BUY,
            1000e6,
            950e6,
            false,
            false
        );

        // Verify reputation was updated
        (uint256 totalTrades,,,) = reputationRegistry.getMetrics(agent1);
        assertEq(totalTrades, 1);

        vm.stopPrank();
    }

    // ============ Limit Order Tests ============

    function test_ExecuteLimitOrder() public {
        vm.startPrank(user1);

        // Use custom policy to avoid Chainlink requirement and cooldown
        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.maxOrderSize = 5000e6;
        customPolicy.minTimeBetweenTrades = 0; // No cooldown
        policyFactory.installAgent(agent1, customPolicy);

        orderBook.setNextOrderId(100);

        uint48 orderId = agentRouter.executeLimitOrder(
            agent1,
            wethUsdcPool,
            2000e6, // price
            1000e6, // quantity
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        );

        assertEq(orderId, 100);
        assertEq(agentRouter.getLastTradeTime(agent1), block.timestamp);

        vm.stopPrank();
    }

    function test_RevertLimitOrderNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.allowLimitOrders = false;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Limit orders not allowed");
        agentRouter.executeLimitOrder(
            agent1,
            wethUsdcPool,
            2000e6,
            1000e6,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        );

        vm.stopPrank();
    }

    function test_LimitOrderEventEmission() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        orderBook.setNextOrderId(100);

        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentLimitOrderPlaced(
            user1,
            agent1,
            user1,
            bytes32(uint256(100)),
            WETH,
            USDC,
            1000e6,
            2000e6,
            true, // isBuy
            block.timestamp
        );

        agentRouter.executeLimitOrder(
            agent1,
            wethUsdcPool,
            2000e6,
            1000e6,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        );

        vm.stopPrank();
    }

    // ============ Cancel Order Tests ============

    function test_CancelOrder() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        agentRouter.cancelOrder(agent1, wethUsdcPool, 100);

        // Verify orderBook.cancelOrder was called
        assertTrue(orderBook.cancelOrderCalled());

        vm.stopPrank();
    }

    function test_RevertCancelOrderNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.allowCancelOrder = false;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Cancelling orders not allowed");
        agentRouter.cancelOrder(agent1, wethUsdcPool, 100);

        vm.stopPrank();
    }

    function test_CancelOrderEventEmission() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentOrderCancelled(
            user1,
            agent1,
            user1,
            bytes32(uint256(100)),
            block.timestamp
        );

        agentRouter.cancelOrder(agent1, wethUsdcPool, 100);

        vm.stopPrank();
    }

    // ============ Borrow Tests ============

    function test_ExecuteBorrow() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        lendingManager.setHealthFactor(user1, 3e18); // 300%

        agentRouter.executeBorrow(agent1, USDC, 1000e6);

        // Verify borrow was called
        assertTrue(lendingManager.borrowCalled());
        assertEq(lendingManager.lastBorrowToken(), USDC);
        assertEq(lendingManager.lastBorrowAmount(), 1000e6);

        vm.stopPrank();
    }

    function test_RevertBorrowNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.allowBorrow = false;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Borrowing not allowed");
        agentRouter.executeBorrow(agent1, USDC, 1000e6);

        vm.stopPrank();
    }

    function test_RevertBorrowExceedsLimit() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        customization.maxOrderSize = 5000e6; // moderate template
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        vm.expectRevert("Borrow amount exceeds limit");
        agentRouter.executeBorrow(agent1, USDC, 100000e6);

        vm.stopPrank();
    }

    function test_RevertBorrowTokenNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        address[] memory whitelist = new address[](1);
        whitelist[0] = WETH;
        customization.whitelistedTokens = whitelist;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        vm.expectRevert("Token not allowed");
        agentRouter.executeBorrow(agent1, USDC, 1000e6);

        vm.stopPrank();
    }

    function test_RevertBorrowHealthFactorTooLow() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        lendingManager.setHealthFactor(user1, 1e18); // 100%

        vm.expectRevert("Health factor too low");
        agentRouter.executeBorrow(agent1, USDC, 1000e6);

        vm.stopPrank();
    }

    function test_BorrowEventEmission() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        lendingManager.setHealthFactor(user1, 3e18);

        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentBorrowExecuted(
            user1,
            agent1,
            user1,
            USDC,
            1000e6,
            3e18,
            block.timestamp
        );

        agentRouter.executeBorrow(agent1, USDC, 1000e6);

        vm.stopPrank();
    }

    function test_BorrowReputationRecorded() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        lendingManager.setHealthFactor(user1, 3e18);

        agentRouter.executeBorrow(agent1, USDC, 1000e6);

        // Check reputation registry received feedback
        IERC8004Reputation.Feedback[] memory feedbacks =
            reputationRegistry.getFeedbackHistory(agent1, 0, 10);

        assertEq(feedbacks.length, 1);
        assertEq(uint256(feedbacks[0].feedbackType), uint256(IERC8004Reputation.FeedbackType.BORROW));

        vm.stopPrank();
    }

    // ============ Repay Tests ============

    function test_ExecuteRepay() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        agentRouter.executeRepay(agent1, USDC, 500e6);

        assertTrue(lendingManager.repayCalled());
        assertEq(lendingManager.lastRepayToken(), USDC);
        assertEq(lendingManager.lastRepayAmount(), 500e6);

        vm.stopPrank();
    }

    function test_RevertRepayNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.allowRepay = false;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Repaying not allowed");
        agentRouter.executeRepay(agent1, USDC, 500e6);

        vm.stopPrank();
    }

    function test_RepayEventEmission() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        lendingManager.setHealthFactor(user1, 2e18);

        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentRepayExecuted(
            user1,
            agent1,
            user1,
            USDC,
            500e6,
            2e18,
            block.timestamp
        );

        agentRouter.executeRepay(agent1, USDC, 500e6);

        vm.stopPrank();
    }

    // ============ Supply Collateral Tests ============

    function test_ExecuteSupplyCollateral() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        agentRouter.executeSupplyCollateral(agent1, WETH, 1e18);

        assertTrue(lendingManager.depositCalled());
        assertEq(lendingManager.lastDepositToken(), WETH);
        assertEq(lendingManager.lastDepositAmount(), 1e18);

        vm.stopPrank();
    }

    function test_RevertSupplyCollateralNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.allowSupplyCollateral = false;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Supplying collateral not allowed");
        agentRouter.executeSupplyCollateral(agent1, WETH, 1e18);

        vm.stopPrank();
    }

    function test_SupplyCollateralEventEmission() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentCollateralSupplied(
            user1,
            agent1,
            user1,
            WETH,
            1e18,
            block.timestamp
        );

        agentRouter.executeSupplyCollateral(agent1, WETH, 1e18);

        vm.stopPrank();
    }

    // ============ Withdraw Collateral Tests ============

    function test_ExecuteWithdrawCollateral() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        lendingManager.setHealthFactor(user1, 3e18);

        agentRouter.executeWithdrawCollateral(agent1, WETH, 1e18);

        assertTrue(lendingManager.withdrawCalled());
        assertEq(lendingManager.lastWithdrawToken(), WETH);
        assertEq(lendingManager.lastWithdrawAmount(), 1e18);

        vm.stopPrank();
    }

    function test_RevertWithdrawCollateralNotAllowed() public {
        vm.startPrank(user1);

        PolicyFactory.Policy memory customPolicy = _createCustomPolicy(agent1);
        customPolicy.allowWithdrawCollateral = false;
        policyFactory.installAgent(agent1, customPolicy);

        vm.expectRevert("Withdrawing collateral not allowed");
        agentRouter.executeWithdrawCollateral(agent1, WETH, 1e18);

        vm.stopPrank();
    }

    function test_RevertWithdrawHealthFactorTooLow() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        lendingManager.setHealthFactor(user1, 1e18);

        vm.expectRevert("Health factor too low");
        agentRouter.executeWithdrawCollateral(agent1, WETH, 1e18);

        vm.stopPrank();
    }

    function test_WithdrawCollateralEventEmission() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        lendingManager.setHealthFactor(user1, 3e18);

        vm.expectEmit(true, true, true, true);
        emit AgentRouter.AgentCollateralWithdrawn(
            user1,
            agent1,
            user1,
            WETH,
            1e18,
            block.timestamp
        );

        agentRouter.executeWithdrawCollateral(agent1, WETH, 1e18);

        vm.stopPrank();
    }

    // ============ View Function Tests ============

    function test_GetDailyVolume() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        orderBook.setNextOrderResponse(1, 1000e6);
        agentRouter.executeMarketOrder(agent1, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);

        orderBook.setNextOrderResponse(2, 2000e6);
        agentRouter.executeMarketOrder(agent1, wethUsdcPool, IOrderBook.Side.BUY, 2000e6, 1900e6, false, false);

        uint256 volume = agentRouter.getDailyVolume(agent1);
        assertEq(volume, 3000e6);

        vm.stopPrank();
    }

    function test_GetLastTradeTime() public {
        vm.startPrank(user1);

        PolicyFactory.PolicyCustomization memory customization;
        policyFactory.installAgentFromTemplate(agent1, "moderate", customization);

        orderBook.setNextOrderResponse(1, 1000e6);
        agentRouter.executeMarketOrder(agent1, wethUsdcPool, IOrderBook.Side.BUY, 1000e6, 950e6, false, false);

        uint256 lastTime = agentRouter.getLastTradeTime(agent1);
        assertEq(lastTime, block.timestamp);

        vm.stopPrank();
    }

    // ============ Helper Functions ============

    function _createCustomPolicy(uint256 agentTokenId) internal view returns (PolicyFactory.Policy memory) {
        address[] memory emptyArray = new address[](0);

        return PolicyFactory.Policy({
            enabled: true,
            installedAt: 0,
            expiryTimestamp: block.timestamp + 90 days,
            agentTokenId: agentTokenId,
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
            maxTradesPerDay: 0, // Set to 0 to avoid Chainlink requirement
            maxTradesPerHour: 0,
            tradingStartHour: 0,
            tradingEndHour: 0,
            minReputationScore: 50,
            useReputationMultiplier: true,
            requiresChainlinkFunctions: false
        });
    }
}
