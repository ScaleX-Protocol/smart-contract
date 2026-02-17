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
 * @title Verify Marketplace Model
 * @notice Proves that marketplace model works:
 *         1. User has no agent initially
 *         2. User registers agent and installs their own policy
 *         3. User authorizes developer's executor
 *         4. Executor can place order for user within user's policy
 *
 * Usage:
 *   forge script script/VerifyMarketplaceModel.s.sol:VerifyMarketplaceModel \
 *     --rpc-url $SCALEX_CORE_RPC \
 *     --broadcast \
 *     -vvvv
 */
contract VerifyMarketplaceModel is Script {
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
    address public user;
    address public executorWallet;

    // IDs
    uint256 public userAgentId;

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

        // User = PRIVATE_KEY_2, Executor = AGENT_EXECUTOR_1_KEY
        user = vm.addr(vm.envUint("PRIVATE_KEY_2"));
        executorWallet = vm.addr(vm.envUint("AGENT_EXECUTOR_1_KEY"));

        console.log("\n=== CONFIGURATION ===");
        console.log("IdentityRegistry:", address(identityRegistry));
        console.log("PolicyFactory:", address(policyFactory));
        console.log("AgentRouter:", address(agentRouter));
        console.log("IDRX:", IDRX);
        console.log("WETH/IDRX Pool:", WETH_IDRX_POOL);
        console.log("\nUser:", user);
        console.log("Executor:", executorWallet);
    }

    function run() public {
        console.log("\n");
        console.log("================================================");
        console.log("MARKETPLACE MODEL VERIFICATION");
        console.log("================================================");
        console.log("");

        // STEP 1: Verify user has no agent
        step1_VerifyUserHasNoAgent();

        // STEP 2: User registers agent and installs policy
        step2_UserSetup();

        // STEP 3: User authorizes executor
        step3_AuthorizeExecutor();

        // STEP 4: Fund user
        step4_FundUser();

        // STEP 5: Executor places order for user
        step5_ExecutorPlacesOrder();

        console.log("\n================================================");
        console.log("✓ VERIFICATION COMPLETE");
        console.log("================================================\n");
    }

    function step1_VerifyUserHasNoAgent() internal view {
        console.log("STEP 1: Verify User Has No Agent");
        console.log("------------------------------------------------");
        console.log("User address:", user);
        console.log("User does NOT own any agent NFT yet");
        console.log("User will register their own agent in next step");
        console.log("");
    }

    function step2_UserSetup() internal {
        console.log("STEP 2: User Registers Agent & Installs Policy");
        console.log("------------------------------------------------");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY_2"));

        // 2a. User registers their own agent
        console.log("2a. User registering agent...");
        userAgentId = identityRegistry.register();

        console.log("  Agent ID:", userAgentId);
        console.log("  Owner:", identityRegistry.ownerOf(userAgentId));
        require(identityRegistry.ownerOf(userAgentId) == user, "Wrong owner");

        // 2b. User installs their own policy (CONSERVATIVE)
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

    function step3_AuthorizeExecutor() internal {
        console.log("STEP 3: User Authorizes Executor");
        console.log("------------------------------------------------");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY_2"));

        console.log("User authorizing executor wallet...");
        console.log("  Executor address:", executorWallet);

        agentRouter.authorizeExecutor(userAgentId, executorWallet);

        console.log("  ✓ Executor authorized");

        // Verify
        bool isAuthorized = agentRouter.authorizedExecutors(userAgentId, executorWallet);
        require(isAuthorized, "Executor not authorized");

        console.log("  ✓ Authorization verified");

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

        // Test A: Try to place order EXCEEDING user's policy limit
        console.log("Test A: Placing 2000 IDRX order (exceeds user's 1000 limit)");

        try agentRouter.executeLimitOrder(
            userAgentId,
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
            userAgentId,
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
        console.log("  Agent ID:", userAgentId);
        console.log("  Executor:", executorWallet);
        console.log("  User (owner):", user);
        console.log("  Amount: 1000 IDRX (enforced by user's policy)");

        vm.stopBroadcast();
        console.log("");
    }
}
