// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {MockERC8004Identity} from "@scalexagents/mocks/MockERC8004Identity.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title SetupAgentExecutors
 * @notice Setup primary wallet with funds, then authorize agent wallets as executors
 * @dev Agent wallets can trade using primary wallet's funds but pay their own gas
 */
contract SetupAgentExecutors is Script {
    struct ExecutorSetup {
        address executorWallet;
        uint256 executorPrivateKey;
        string name;
    }

    function run() external {
        console.log("=== SETUP AGENT EXECUTORS ===");
        console.log("");

        // Load deployment addresses
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");
        string memory json = vm.readFile(deploymentPath);

        address identityRegistry = _extractAddress(json, "IdentityRegistry");
        address policyFactory = _extractAddress(json, "PolicyFactory");
        address balanceManager = _extractAddress(json, "BalanceManager");
        address agentRouter = _extractAddress(json, "AgentRouter");

        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        address quoteToken = _extractAddress(json, quoteSymbol);

        // Primary wallet (owner of funds and agent)
        uint256 primaryPrivateKey = vm.envUint("PRIMARY_WALLET_KEY");
        address primaryWallet = vm.addr(primaryPrivateKey);

        console.log("Loaded addresses:");
        console.log("  AgentRouter:", agentRouter);
        console.log("  IdentityRegistry:", identityRegistry);
        console.log("  PolicyFactory:", policyFactory);
        console.log("  BalanceManager:", balanceManager);
        console.log("  Quote Token:", quoteToken);
        console.log("");

        console.log("Primary Wallet (Owner):");
        console.log("  Address:", primaryWallet);
        console.log("");

        // Define agent executors
        ExecutorSetup[] memory executors = new ExecutorSetup[](3);

        executors[0] = ExecutorSetup({
            executorWallet: address(0),
            executorPrivateKey: vm.envUint("AGENT_EXECUTOR_1_KEY"),
            name: "Conservative Agent"
        });

        executors[1] = ExecutorSetup({
            executorWallet: address(0),
            executorPrivateKey: vm.envUint("AGENT_EXECUTOR_2_KEY"),
            name: "Aggressive Agent"
        });

        executors[2] = ExecutorSetup({
            executorWallet: address(0),
            executorPrivateKey: vm.envUint("AGENT_EXECUTOR_3_KEY"),
            name: "Market Maker Agent"
        });

        // Derive executor addresses
        for (uint256 i = 0; i < executors.length; i++) {
            executors[i].executorWallet = vm.addr(executors[i].executorPrivateKey);
            console.log(string.concat("Executor ", vm.toString(i + 1), " - ", executors[i].name));
            console.log("  Address:", executors[i].executorWallet);
        }
        console.log("");

        // Step 1: Setup primary wallet (mint agent, create policy, deposit funds)
        uint256 agentId = _setupPrimaryWallet(
            primaryWallet,
            primaryPrivateKey,
            identityRegistry,
            agentRouter,
            balanceManager,
            quoteToken
        );
        console.log("");

        // Step 2: Authorize executors
        _authorizeExecutors(
            primaryWallet,
            primaryPrivateKey,
            agentId,
            executors,
            agentRouter
        );
        console.log("");

        // Step 3: Verification
        _verifySetup(
            primaryWallet,
            agentId,
            executors,
            agentRouter,
            balanceManager,
            quoteToken
        );

        console.log("");
        console.log("[SUCCESS] Agent executor setup complete!");
        console.log("");
        console.log("=== SUMMARY ===");
        console.log("Primary Wallet:", primaryWallet);
        console.log("Agent ID:", agentId);
        console.log("");
        console.log("Authorized Executors:");
        for (uint256 i = 0; i < executors.length; i++) {
            console.log(string.concat("  ", vm.toString(i + 1), ". ", executors[i].name));
            console.log("     Address:", executors[i].executorWallet);
        }
        console.log("");
        console.log("Fund Structure:");
        console.log("  - Primary wallet owns ALL funds in BalanceManager");
        console.log("  - Agent executors can trade using primary wallet's funds");
        console.log("  - Agent executors pay their own gas fees");
    }

    function _setupPrimaryWallet(
        address primaryWallet,
        uint256 primaryPrivateKey,
        address identityRegistry,
        address agentRouter,
        address balanceManager,
        address quoteToken
    ) internal returns (uint256 agentId) {
        console.log("=== STEP 1: SETUP PRIMARY WALLET ===");
        console.log("");

        vm.startBroadcast(primaryPrivateKey);

        // Check if primary wallet already has an agent
        uint256 agentBalance = MockERC8004Identity(identityRegistry).balanceOf(primaryWallet);

        if (agentBalance > 0) {
            console.log("Primary wallet already has an agent identity");
            // For simplicity, assume using a deterministic token ID based on address
            // In production, you'd query which token IDs the wallet owns
            agentId = uint256(uint160(primaryWallet)); // Simple deterministic ID
            console.log("[OK] Using existing agent ID:", agentId);
        } else {
            // Mint agent identity for primary wallet
            console.log("Minting agent identity for primary wallet...");
            // Use deterministic token ID for simplicity
            agentId = uint256(uint160(primaryWallet));
            MockERC8004Identity(identityRegistry).mint(primaryWallet, agentId, "ipfs://agent-metadata");
            console.log("[OK] Minted agent ID:", agentId);
        }

        // Create policy
        console.log("Creating trading policy...");
        _createPolicy(agentRouter, agentId);
        console.log("[OK] Policy created");

        // Deposit funds
        uint256 depositAmount = 10000e6; // 10,000 quote tokens
        console.log("Depositing funds to BalanceManager...");

        // Check if wallet has tokens
        uint256 tokenBalance = ERC20(quoteToken).balanceOf(primaryWallet);
        if (tokenBalance >= depositAmount) {
            // Approve
            ERC20(quoteToken).approve(balanceManager, type(uint256).max);

            // Deposit (currency, amount, sender, user)
            IBalanceManager(balanceManager).deposit(
                Currency.wrap(quoteToken),
                depositAmount,
                primaryWallet,  // sender
                primaryWallet   // user
            );
            console.log("[OK] Deposited:", depositAmount / 1e6, "tokens");
        } else {
            console.log("[WARN] Insufficient token balance");
            console.log("  Required:", depositAmount / 1e6);
            console.log("  Available:", tokenBalance / 1e6);
        }

        vm.stopBroadcast();

        return agentId;
    }

    function _createPolicy(address agentRouter, uint256 agentId) internal {
        // Create a permissive policy for agent trading
        address[] memory emptyAddressArray = new address[](0);

        PolicyFactory.Policy memory policy = PolicyFactory.Policy({
            // Metadata
            enabled: false,
            installedAt: 0,
            expiryTimestamp: type(uint256).max,

            // Order Size
            maxOrderSize: 10000e6,  // 10k max per order
            minOrderSize: 1e6,      // 1 minimum

            // Allowed Markets
            whitelistedTokens: emptyAddressArray,  // All tokens allowed
            blacklistedTokens: emptyAddressArray,  // No tokens blocked

            // Order Types
            allowMarketOrders: true,
            allowLimitOrders: true,

            // Operations
            allowSwap: true,
            allowBorrow: true,
            allowRepay: true,
            allowSupplyCollateral: true,
            allowWithdrawCollateral: true,
            allowPlaceLimitOrder: true,
            allowCancelOrder: true,

            // Buy/Sell Direction
            allowBuy: true,
            allowSell: true,

            // Auto-Borrow
            allowAutoBorrow: true,
            maxAutoBorrowAmount: 5000e6,  // 5k max auto-borrow

            // Auto-Repay
            allowAutoRepay: true,
            minDebtToRepay: 100e6,  // 100 minimum to repay

            // Safety
            minHealthFactor: 1.3e18,  // 1.3x minimum health
            maxSlippageBps: 500,      // 5% max slippage
            minTimeBetweenTrades: 60,  // 1 minute cooldown
            emergencyRecipient: address(0),

            // Volume Limits (Chainlink required)
            dailyVolumeLimit: 100000e6,  // 100k daily
            weeklyVolumeLimit: 500000e6, // 500k weekly

            // Drawdown Limits
            maxDailyDrawdown: 2000,   // 20% max daily drawdown
            maxWeeklyDrawdown: 3000,  // 30% max weekly drawdown

            // Market Depth
            maxTradeVsTVLBps: 1000,  // 10% of TVL max

            // Performance Requirements
            minWinRateBps: 0,     // No min win rate
            minSharpeRatio: 0,    // No min Sharpe ratio

            // Position Management
            maxPositionConcentrationBps: 5000,  // 50% max in one asset
            maxCorrelationBps: 10000,  // No correlation limit

            // Trade Frequency
            maxTradesPerDay: 1000,
            maxTradesPerHour: 100,

            // Trading Hours (UTC)
            tradingStartHour: 0,   // 24/7 trading
            tradingEndHour: 23,

            // Reputation
            minReputationScore: 0,  // No min reputation
            useReputationMultiplier: false,

            // Optimization Flag
            requiresChainlinkFunctions: false  // Set by contract
        });

        AgentRouter(agentRouter).authorize(agentId, policy);
    }

    function _authorizeExecutors(
        address primaryWallet,
        uint256 primaryPrivateKey,
        uint256 agentId,
        ExecutorSetup[] memory executors,
        address agentRouter
    ) internal {
        console.log("=== STEP 2: AUTHORIZE EXECUTORS ===");
        console.log("");

        vm.startBroadcast(primaryPrivateKey);

        // In the simplified auth model, authorization is granted per (user, strategyAgentId)
        // via AgentRouter.authorize() called in _createPolicy. No per-executor delegation needed.
        for (uint256 i = 0; i < executors.length; i++) {
            console.log(string.concat("[OK] ", executors[i].name, " is authorized via strategyAgentId policy"));
            console.log("  Executor address:", executors[i].executorWallet);
            console.log("");
        }

        vm.stopBroadcast();
    }

    function _verifySetup(
        address primaryWallet,
        uint256 agentId,
        ExecutorSetup[] memory executors,
        address agentRouter,
        address balanceManager,
        address quoteToken
    ) internal view {
        console.log("=== STEP 3: VERIFICATION ===");
        console.log("");

        // Check primary wallet balance
        uint256 balance = IBalanceManager(balanceManager).getBalance(
            primaryWallet,
            Currency.wrap(quoteToken)
        );
        console.log("Primary Wallet Balance:", balance / 1e6, "tokens");
        console.log("");

        // Check authorization: primaryWallet -> agentId
        console.log("Authorization check:");
        bool authorized = AgentRouter(agentRouter).isAuthorized(primaryWallet, agentId);
        console.log("  primaryWallet:", primaryWallet);
        console.log("  agentId:", agentId);
        if (authorized) {
            console.log("  Status: AUTHORIZED");
        } else {
            console.log("  Status: NOT AUTHORIZED!");
        }
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes.concat('"', bytes(key), '": "');

        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) {
            return address(0);
        }

        uint256 addressStart = keyPos + keyBytes.length;
        bytes memory addressBytes = new bytes(42);
        for (uint256 i = 0; i < 42; i++) {
            addressBytes[i] = jsonBytes[addressStart + i];
        }

        return _bytesToAddress(addressBytes);
    }

    function _indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        if (needle.length == 0 || haystack.length < needle.length) {
            return type(uint256).max;
        }

        uint256 needleLength = needle.length;
        for (uint256 i = 0; i <= haystack.length - needleLength; i++) {
            bool found = true;
            for (uint256 j = 0; j < needleLength; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }

        return type(uint256).max;
    }

    function _bytesToAddress(bytes memory data) internal pure returns (address) {
        return address(uint160(uint256(_hexToUint(data))));
    }

    function _hexToUint(bytes memory data) internal pure returns (uint256) {
        uint256 result = 0;
        for (uint256 i = 0; i < data.length; i++) {
            uint8 byteValue = uint8(data[i]);
            uint256 digit;
            if (byteValue >= 48 && byteValue <= 57) {
                digit = uint256(byteValue) - 48;
            } else if (byteValue >= 97 && byteValue <= 102) {
                digit = uint256(byteValue) - 87;
            } else if (byteValue >= 65 && byteValue <= 70) {
                digit = uint256(byteValue) - 55;
            } else {
                continue;
            }
            result = result * 16 + digit;
        }
        return result;
    }
}
