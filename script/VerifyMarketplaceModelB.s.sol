// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ai-agents/registries/IdentityRegistryUpgradeable.sol";
import "../src/ai-agents/PolicyFactory.sol";
import "../src/ai-agents/AgentRouter.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/PoolManager.sol";
import "../src/core/OrderBook.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import "../src/test/mocks/MockERC20.sol";

/**
 * @title Verify Marketplace Model B
 * @notice Proves that Model B (agent-based authorization) works:
 *         1. Developer (Alice) registers strategy agent and executor wallet
 *         2. User (Bob) registers personal agent and installs policy
 *         3. User authorizes strategy AGENT (not wallet)
 *         4. Executor can trade for user within user's policy
 *
 * Usage:
 *   forge script script/VerifyMarketplaceModelB.s.sol:VerifyMarketplaceModelB \
 *     --rpc-url $SCALEX_CORE_RPC \
 *     --broadcast \
 *     -vvvv
 */
contract VerifyMarketplaceModelB is Script {
    // Contracts
    IdentityRegistryUpgradeable public identityRegistry;
    PolicyFactory public policyFactory;
    AgentRouter public agentRouter;
    BalanceManager public balanceManager;

    // Tokens
    address public IDRX;
    address public WETH;
    address public WETH_IDRX_POOL;

    // Actors
    address public developer;       // Alice - owns strategy agent
    address public user;            // Bob - subscribes to strategy
    address public executorWallet;  // Alice's executor wallet

    // IDs
    uint256 public strategyAgentId;  // Alice's Agent #500
    uint256 public userAgentId;      // Bob's Agent #101

    function setUp() public {
        // Load deployed contracts
        string memory json = vm.readFile("deployments/84532.json");

        identityRegistry = IdentityRegistryUpgradeable(
            vm.parseJsonAddress(json, ".IdentityRegistry")
        );
        policyFactory = PolicyFactory(
            vm.parseJsonAddress(json, ".PolicyFactory")
        );
        agentRouter = AgentRouter(
            vm.parseJsonAddress(json, ".AgentRouter")
        );
        balanceManager = BalanceManager(
            vm.parseJsonAddress(json, ".BalanceManager")
        );
        IDRX = vm.parseJsonAddress(json, ".IDRX");
        WETH = vm.parseJsonAddress(json, ".WETH");
        WETH_IDRX_POOL = vm.parseJsonAddress(json, ".WETH_IDRX_Pool");

        // Developer = PRIVATE_KEY (deployer)
        // User = PRIVATE_KEY_2
        // Executor = AGENT_EXECUTOR_1_KEY
        developer = vm.addr(vm.envUint("PRIVATE_KEY"));
        user = vm.addr(vm.envUint("PRIVATE_KEY_2"));
        executorWallet = vm.addr(vm.envUint("AGENT_EXECUTOR_1_KEY"));

        console.log("\n=== CONFIGURATION ===");
        console.log("IdentityRegistry:", address(identityRegistry));
        console.log("PolicyFactory:", address(policyFactory));
        console.log("AgentRouter:", address(agentRouter));
        console.log("IDRX:", IDRX);
        console.log("WETH/IDRX Pool:", WETH_IDRX_POOL);
        console.log("\nDeveloper (Alice):", developer);
        console.log("User (Bob):", user);
        console.log("Executor Wallet:", executorWallet);
    }

    function run() public {
        console.log("\n");
        console.log("================================================");
        console.log("MODEL B VERIFICATION");
        console.log("(Agent-Based Authorization)");
        console.log("================================================");
        console.log("");

        // STEP 1: Developer setup
        step1_DeveloperSetup();

        // STEP 2: User setup
        step2_UserSetup();

        // STEP 3: User authorizes strategy agent
        step3_UserAuthorizesStrategy();

        // STEP 4: Fund user
        step4_FundUser();

        // STEP 5: Executor trades for user
        step5_ExecutorPlacesOrder();

        console.log("\n================================================");
        console.log("✓ MODEL B VERIFICATION COMPLETE");
        console.log("================================================\n");
    }

    function step1_DeveloperSetup() internal {
        console.log("STEP 1: Developer (Alice) Setup");
        console.log("------------------------------------------------");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // 1a. Developer registers strategy agent
        console.log("1a. Developer registering strategy agent...");
        strategyAgentId = identityRegistry.register();

        console.log("  Strategy Agent ID:", strategyAgentId);
        console.log("  Owner:", identityRegistry.ownerOf(strategyAgentId));
        require(identityRegistry.ownerOf(strategyAgentId) == developer, "Wrong owner");

        // 1b. Developer registers executor wallet for strategy agent
        console.log("\n1b. Developer registering executor wallet...");
        agentRouter.registerAgentExecutor(strategyAgentId, executorWallet);

        console.log("  Executor wallet:", executorWallet);
        console.log("  ✓ Executor registered for Strategy Agent #", strategyAgentId);

        // Verify executor is registered
        address registeredExecutor = agentRouter.getStrategyExecutor(strategyAgentId);
        require(registeredExecutor == executorWallet, "Executor not registered");
        console.log("  ✓ Executor registration verified");

        // Note: Developer does NOT install policy for strategy agent
        console.log("\nNote: Strategy agent has NO policy (it's just an identity)");

        vm.stopBroadcast();
        console.log("");
    }

    function step2_UserSetup() internal {
        console.log("STEP 2: User (Bob) Setup");
        console.log("------------------------------------------------");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY_2"));

        // 2a. User registers their own personal agent
        console.log("2a. User registering personal agent...");
        userAgentId = identityRegistry.register();

        console.log("  User Agent ID:", userAgentId);
        console.log("  Owner:", identityRegistry.ownerOf(userAgentId));
        require(identityRegistry.ownerOf(userAgentId) == user, "Wrong owner");

        // 2b. User installs THEIR OWN policy (conservative)
        console.log("\n2b. User installing CONSERVATIVE policy...");

        PolicyFactory.PolicyCustomization memory customizations =
            PolicyFactory.PolicyCustomization({
                maxOrderSize: 1000e6,        // 1000 IDRX max per order
                dailyVolumeLimit: 5000e6,    // 5000 IDRX max per day
                expiryTimestamp: block.timestamp + 90 days,
                whitelistedTokens: new address[](0)
            });

        policyFactory.installAgentFromTemplate(
            userAgentId,
            "conservative",
            customizations
        );

        console.log("  Policy template: conservative");
        console.log("  Max order size: 1,000 IDRX");
        console.log("  Daily volume limit: 5,000 IDRX");

        // Verify policy installed
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(user, userAgentId);
        require(policy.enabled, "Policy not enabled");
        require(policy.maxOrderSize == 1000e6, "Wrong max order size");

        console.log("  ✓ Policy installed and verified");

        vm.stopBroadcast();
        console.log("");
    }

    function step3_UserAuthorizesStrategy() internal {
        console.log("STEP 3: User Authorizes Strategy Agent");
        console.log("------------------------------------------------");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY_2"));

        console.log("User authorizing Strategy Agent #", strategyAgentId);
        console.log("  User's Personal Agent: #", userAgentId);
        console.log("  Strategy Agent to authorize: #", strategyAgentId);

        // User authorizes the STRATEGY AGENT with simple function!
        // Just: authorize(strategyAgentId) - that's it!
        agentRouter.authorize(strategyAgentId);

        console.log("  ✓ Strategy agent authorized");

        // Verify
        bool isAuthorized = agentRouter.isAuthorized(user, strategyAgentId);
        require(isAuthorized, "Strategy agent not authorized");

        console.log("  ✓ Authorization verified");
        console.log("\nNote: Simple authorization - just authorize(", strategyAgentId, ")");
        console.log("      User doesn't need to specify their agent ID");
        console.log("      Policy comes from user's personal agent during execution");

        vm.stopBroadcast();
        console.log("");
    }

    function step4_FundUser() internal {
        console.log("STEP 4: Fund User");
        console.log("------------------------------------------------");

        // Mint tokens as deployer
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        console.log("Minting 10,000 IDRX to user...");
        MockERC20(IDRX).mint(user, 10000e6);

        vm.stopBroadcast();

        // User approves and deposits
        vm.startBroadcast(vm.envUint("PRIVATE_KEY_2"));

        console.log("User approving BalanceManager...");
        MockERC20(IDRX).approve(address(balanceManager), 10000e6);

        console.log("User depositing to BalanceManager...");
        balanceManager.deposit(IDRX, 10000e6);

        // Verify
        uint256 balance = balanceManager.getBalance(user, IDRX);
        console.log("  User balance:", balance / 1e6, "IDRX");
        require(balance == 10000e6, "Wrong balance");

        console.log("  ✓ User funded with 10,000 IDRX");

        vm.stopBroadcast();
        console.log("");
    }

    function step5_ExecutorPlacesOrder() internal {
        console.log("STEP 5: Executor Places Order for User");
        console.log("------------------------------------------------");

        vm.startBroadcast(vm.envUint("AGENT_EXECUTOR_1_KEY"));

        console.log("Executor wallet:", executorWallet);
        console.log("Strategy Agent ID:", strategyAgentId);
        console.log("User Agent ID:", userAgentId);

        // Test A: Try to place order EXCEEDING user's policy limit
        console.log("\nTest A: Placing 2000 IDRX order (exceeds user's 1000 limit)");

        try agentRouter.executeLimitOrder(
            userAgentId,          // Bob's personal agent
            strategyAgentId,      // Alice's strategy agent
            IPoolManager.Pool({
                baseCurrency: Currency.wrap(WETH),
                quoteCurrency: Currency.wrap(IDRX),
                orderBook: IOrderBook(WETH_IDRX_POOL)
            }),
            300000,              // price: 0.3 IDRX per WETH
            2000e6,              // quantity: 2000 IDRX (EXCEEDS LIMIT!)
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,               // autoRepay
            false                // autoBorrow
        ) returns (uint48) {
            revert("ERROR: Should have been rejected but succeeded!");
        } catch Error(string memory reason) {
            console.log("  ✓ Order rejected:", reason);
        } catch {
            console.log("  ✓ Order rejected (policy violation)");
        }

        // Test B: Place order WITHIN user's policy limit
        console.log("\nTest B: Placing 1000 IDRX order (within user's limit)");

        uint48 orderId = agentRouter.executeLimitOrder(
            userAgentId,          // Bob's personal agent
            strategyAgentId,      // Alice's strategy agent
            IPoolManager.Pool({
                baseCurrency: Currency.wrap(WETH),
                quoteCurrency: Currency.wrap(IDRX),
                orderBook: IOrderBook(WETH_IDRX_POOL)
            }),
            300000,              // price
            1000e6,              // quantity: 1000 IDRX (WITHIN LIMIT)
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        );

        console.log("  ✓ Order placed successfully!");
        console.log("  Order ID:", orderId);
        console.log("  User Agent ID:", userAgentId);
        console.log("  Strategy Agent ID:", strategyAgentId);
        console.log("  Executor:", executorWallet);
        console.log("  User (owner):", user);
        console.log("  Amount: 1000 IDRX (enforced by user's policy)");

        console.log("\n  KEY INSIGHT:");
        console.log("  - User authorized Agent #", strategyAgentId);
        console.log("  - Contract looked up executor wallet for Agent #", strategyAgentId);
        console.log("  - Found executor:", executorWallet);
        console.log("  - Executor successfully traded for user");

        vm.stopBroadcast();
        console.log("");
    }
}
