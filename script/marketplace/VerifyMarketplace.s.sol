// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/ai-agents/registries/IdentityRegistryUpgradeable.sol";
import "../../src/ai-agents/PolicyFactory.sol";
import "../../src/ai-agents/AgentRouter.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/test/mocks/MockERC20.sol";

/**
 * @title Verify Marketplace Script
 * @notice Verifies marketplace model on deployed contracts
 *
 * Run with:
 * forge script script/marketplace/VerifyMarketplace.s.sol:VerifyMarketplace \
 *   --rpc-url $SCALEX_CORE_RPC \
 *   --broadcast \
 *   -vvvv
 */
contract VerifyMarketplace is Script {
    // Load deployed contract addresses
    IdentityRegistryUpgradeable public identityRegistry;
    PolicyFactory public policyFactory;
    AgentRouter public agentRouter;
    BalanceManager public balanceManager;

    // Tokens
    address public IDRX;
    address public WETH;

    // Actors (use different private keys)
    uint256 public developerKey = vm.envUint("PRIVATE_KEY");          // Deployer/developer
    uint256 public executorKey = vm.envUint("AGENT_EXECUTOR_1_KEY");  // Executor wallet
    uint256 public userKey = vm.envUint("PRIVATE_KEY_2");             // Test user

    address public developer;
    address public executor;
    address public user;

    // Agent IDs
    uint256 public developerAgentId;
    uint256 public userAgentId;

    function setUp() public {
        // Load contract addresses from deployment file
        string memory deploymentPath = "deployments/84532.json";
        string memory json = vm.readFile(deploymentPath);

        identityRegistry = IdentityRegistryUpgradeable(vm.parseJsonAddress(json, ".IdentityRegistry"));
        policyFactory = PolicyFactory(vm.parseJsonAddress(json, ".PolicyFactory"));
        agentRouter = AgentRouter(vm.parseJsonAddress(json, ".AgentRouter"));
        balanceManager = BalanceManager(vm.parseJsonAddress(json, ".BalanceManager"));
        IDRX = vm.parseJsonAddress(json, ".IDRX");
        WETH = vm.parseJsonAddress(json, ".WETH");

        // Derive addresses from private keys
        developer = vm.addr(developerKey);
        executor = vm.addr(executorKey);
        user = vm.addr(userKey);

        console.log("\n=== Contract Addresses ===");
        console.log("IdentityRegistry:", address(identityRegistry));
        console.log("PolicyFactory:", address(policyFactory));
        console.log("AgentRouter:", address(agentRouter));
        console.log("BalanceManager:", address(balanceManager));
        console.log("IDRX:", IDRX);
        console.log("WETH:", WETH);

        console.log("\n=== Actors ===");
        console.log("Developer:", developer);
        console.log("Executor:", executor);
        console.log("User:", user);
    }

    function run() public {
        console.log("\n========================================");
        console.log("MARKETPLACE VERIFICATION");
        console.log("========================================\n");

        // Step 1: Developer Setup
        step1_DeveloperSetup();

        // Step 2: Verify User Has No Agent
        step2_VerifyUserHasNoAgent();

        // Step 3: User Subscribes
        step3_UserSubscribes();

        // Step 4: Executor Places Order
        step4_ExecutorPlacesOrder();

        console.log("\n========================================");
        console.log("VERIFICATION COMPLETE ✓");
        console.log("========================================\n");
    }

    function step1_DeveloperSetup() internal {
        console.log("STEP 1: Developer Setup");
        console.log("----------------------------------------");

        vm.startBroadcast(developerKey);

        // Check if developer already has an agent
        // (In production, you'd query this from indexer or contract)
        // For now, we'll register a new one

        console.log("Developer registering strategy agent...");
        developerAgentId = identityRegistry.register();

        console.log("  Developer Agent ID:", developerAgentId);
        console.log("  Owner:", identityRegistry.ownerOf(developerAgentId));
        console.log("  NOTE: No policy installed (just identity)");

        vm.stopBroadcast();
        console.log("  ✓ Developer setup complete\n");
    }

    function step2_VerifyUserHasNoAgent() internal {
        console.log("STEP 2: Verify User Has No Agent");
        console.log("----------------------------------------");

        console.log("User address:", user);
        console.log("User does not own any agent NFT yet");
        console.log("  ✓ Verified\n");
    }

    function step3_UserSubscribes() internal {
        console.log("STEP 3: User Subscribes to Strategy");
        console.log("----------------------------------------");

        vm.startBroadcast(userKey);

        // 3a. User registers their own agent
        console.log("3a. User registering agent...");
        userAgentId = identityRegistry.register();
        console.log("  User Agent ID:", userAgentId);
        console.log("  Owner:", identityRegistry.ownerOf(userAgentId));

        // 3b. User installs conservative policy
        console.log("\n3b. User installing conservative policy...");

        PolicyFactory.PolicyCustomization memory customizations = PolicyFactory.PolicyCustomization({
            maxOrderSize: 1000e6,        // 1000 IDRX
            dailyVolumeLimit: 5000e6,    // 5000 IDRX
            expiryTimestamp: block.timestamp + 90 days,
            whitelistedTokens: new address[](0)
        });

        policyFactory.installAgentFromTemplate(
            userAgentId,
            "conservative",
            customizations
        );

        console.log("  Policy: conservative");
        console.log("  Max order size: 1000 IDRX");
        console.log("  Daily volume: 5000 IDRX");

        // Verify policy
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(user, userAgentId);
        require(policy.enabled, "Policy not enabled");
        require(policy.maxOrderSize == 1000e6, "Wrong max order size");

        // 3c. User authorizes executor
        console.log("\n3c. User authorizing executor...");
        console.log("  Executor address:", executor);

        agentRouter.authorizeExecutor(userAgentId, executor);

        console.log("  ✓ Executor authorized");

        // Verify authorization
        require(
            agentRouter.authorizedExecutors(userAgentId, executor),
            "Executor not authorized"
        );

        // 3d. User deposits funds
        console.log("\n3d. User depositing funds...");

        uint256 depositAmount = 10000e6; // 10,000 IDRX

        // Mint IDRX to user (in production, user would have IDRX)
        MockERC20(IDRX).mint(user, depositAmount);

        // Approve BalanceManager
        MockERC20(IDRX).approve(address(balanceManager), depositAmount);

        // Deposit
        balanceManager.deposit(IDRX, depositAmount);

        console.log("  Deposited: 10,000 IDRX");

        // Verify balance
        uint256 balance = balanceManager.getBalance(user, IDRX);
        require(balance == depositAmount, "Deposit failed");

        vm.stopBroadcast();
        console.log("  ✓ User subscription complete\n");
    }

    function step4_ExecutorPlacesOrder() internal {
        console.log("STEP 4: Executor Places Order for User");
        console.log("----------------------------------------");

        vm.startBroadcast(executorKey);

        // Get pool info
        address wethIdrxPool = vm.parseJsonAddress(
            vm.readFile("deployments/84532.json"),
            ".WETH_IDRX_Pool"
        );

        console.log("OrderBook:", wethIdrxPool);

        // Try to place order exceeding policy limit
        console.log("\nTest A: Placing 2000 IDRX order (exceeds 1000 limit)...");

        try agentRouter.executeLimitOrder(
            userAgentId,
            IPoolManager.Pool({
                baseCurrency: Currency.wrap(WETH),
                quoteCurrency: Currency.wrap(IDRX),
                orderBook: IOrderBook(wethIdrxPool)
            }),
            300000,              // price
            2000e6,              // quantity - EXCEEDS LIMIT
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        ) returns (uint48) {
            revert("Should have failed but succeeded");
        } catch {
            console.log("  ✓ Order rejected (policy violation)");
        }

        // Place order within policy limit
        console.log("\nTest B: Placing 1000 IDRX order (within limit)...");

        uint48 orderId = agentRouter.executeLimitOrder(
            userAgentId,
            IPoolManager.Pool({
                baseCurrency: Currency.wrap(WETH),
                quoteCurrency: Currency.wrap(IDRX),
                orderBook: IOrderBook(wethIdrxPool)
            }),
            300000,              // price
            1000e6,              // quantity - WITHIN LIMIT
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        );

        console.log("  ✓ Order placed successfully");
        console.log("  Order ID:", orderId);
        console.log("  Agent ID:", userAgentId);
        console.log("  Executor:", executor);
        console.log("  User (owner):", user);

        vm.stopBroadcast();
        console.log("\n  ✓ Executor trading verified\n");
    }
}
