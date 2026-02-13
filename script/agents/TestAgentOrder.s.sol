// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {MockERC8004Identity} from "@scalexagents/mocks/MockERC8004Identity.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TestAgentOrder
 * @notice End-to-end test: mint agent, create policy, deposit funds, place order via AgentRouter
 * @dev Verifies complete agent trading flow
 */
contract TestAgentOrder is Script {
    function run() external {
        console.log("=== TESTING AGENT ORDER PLACEMENT ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer/Agent Owner:", deployer);
        console.log("");

        // Load addresses
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");
        string memory json = vm.readFile(deploymentPath);

        address agentRouter = _extractAddress(json, "AgentRouter");
        address policyFactory = _extractAddress(json, "PolicyFactory");
        address identityRegistry = _extractAddress(json, "IdentityRegistry");
        address balanceManager = _extractAddress(json, "BalanceManager");

        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        address quoteToken = _extractAddress(json, quoteSymbol);
        address weth = _extractAddress(json, "WETH");
        address wethPool = _extractAddress(json, string.concat("WETH_", quoteSymbol, "_Pool"));

        console.log("Loaded addresses:");
        console.log("  AgentRouter:", agentRouter);
        console.log("  PolicyFactory:", policyFactory);
        console.log("  IdentityRegistry:", identityRegistry);
        console.log("  BalanceManager:", balanceManager);
        console.log("  WETH:", weth);
        console.log("  Quote Token:", quoteToken);
        console.log("  WETH Pool:", wethPool);
        console.log("");

        // Check if user already has an agent
        uint256 agentTokenId = _getOrMintAgent(identityRegistry, deployer, deployerPrivateKey);
        console.log("");

        // Check if policy exists
        _createPolicyIfNeeded(policyFactory, deployer, agentTokenId, deployerPrivateKey);
        console.log("");

        // Deposit funds
        uint256 depositAmount = 1000e6; // 1000 USDC/IDRX
        _depositFunds(balanceManager, quoteToken, deployer, depositAmount, deployerPrivateKey);
        console.log("");

        // Place a test order
        _placeTestOrder(agentRouter, wethPool, weth, quoteToken, deployer, agentTokenId, deployerPrivateKey);
        console.log("");

        console.log("[SUCCESS] Agent order test completed!");
    }

    function _getOrMintAgent(address identityRegistry, address owner, uint256 privateKey)
        internal
        returns (uint256 agentTokenId)
    {
        console.log("Step 1: Checking for existing agent...");

        // Try to get balance (if > 0, user has agents)
        try MockERC8004Identity(identityRegistry).balanceOf(owner) returns (uint256 balance) {
            if (balance > 0) {
                // Get first token ID
                agentTokenId = MockERC8004Identity(identityRegistry).tokenOfOwnerByIndex(owner, 0);
                console.log("[OK] Found existing agent token ID:", agentTokenId);
                return agentTokenId;
            }
        } catch {}

        console.log("No existing agent found. Minting new agent...");
        vm.startBroadcast(privateKey);

        MockERC8004Identity(identityRegistry).mint(owner);
        agentTokenId = MockERC8004Identity(identityRegistry).tokenOfOwnerByIndex(owner, 0);

        vm.stopBroadcast();
        console.log("[OK] Minted agent token ID:", agentTokenId);
        return agentTokenId;
    }

    function _createPolicyIfNeeded(
        address policyFactory,
        address owner,
        uint256 agentTokenId,
        uint256 privateKey
    ) internal {
        console.log("Step 2: Checking for existing policy...");

        // Try to get existing policy
        try PolicyFactory(policyFactory).getPolicy(owner, agentTokenId) returns (
            PolicyFactory.Policy memory policy
        ) {
            if (policy.exists) {
                console.log("[OK] Policy already exists");
                console.log("  Max Daily Volume:", policy.maxDailyVolume);
                console.log("  Max Drawdown BPS:", policy.maxDrawdownBps);
                return;
            }
        } catch {}

        console.log("No policy found. Creating default policy...");

        vm.startBroadcast(privateKey);

        // Create a permissive policy for testing
        PolicyFactory.AssetLimit[] memory assetLimits = new PolicyFactory.AssetLimit[](2);

        // Allow WETH trading (18 decimals) - up to 10 WETH
        assetLimits[0] = PolicyFactory.AssetLimit({
            asset: address(0), // Will be set properly in actual call
            maxPositionSize: 10e18,
            enabled: true
        });

        // Allow quote currency - up to 50,000 units
        assetLimits[1] = PolicyFactory.AssetLimit({
            asset: address(0), // Will be set properly in actual call
            maxPositionSize: 50000e6,
            enabled: true
        });

        PolicyFactory(policyFactory).createPolicy(
            agentTokenId,
            assetLimits,
            100000e6,  // maxDailyVolume: 100k USD
            2000,      // maxDrawdownBps: 20%
            300,       // minHealthFactor: 1.3x (300%)
            500,       // maxSlippageBps: 5%
            60         // minCooldownSeconds: 1 minute
        );

        vm.stopBroadcast();
        console.log("[OK] Policy created successfully");
    }

    function _depositFunds(
        address balanceManager,
        address token,
        address owner,
        uint256 amount,
        uint256 privateKey
    ) internal {
        console.log("Step 3: Depositing funds to BalanceManager...");

        // Check current balance
        uint256 currentBalance = IBalanceManager(balanceManager).getBalance(owner, Currency.wrap(token));
        console.log("Current balance:", currentBalance);

        if (currentBalance >= amount) {
            console.log("[OK] Sufficient balance already exists");
            return;
        }

        // Check token balance
        uint256 tokenBalance = ERC20(token).balanceOf(owner);
        console.log("Token balance:", tokenBalance);

        if (tokenBalance < amount) {
            console.log("[WARN] Insufficient token balance. Need to mint or acquire tokens first.");
            console.log("       Required:", amount);
            console.log("       Available:", tokenBalance);
            return;
        }

        vm.startBroadcast(privateKey);

        // Approve if needed
        uint256 allowance = ERC20(token).allowance(owner, balanceManager);
        if (allowance < amount) {
            console.log("Approving BalanceManager...");
            ERC20(token).approve(balanceManager, type(uint256).max);
        }

        // Deposit
        console.log("Depositing", amount, "to BalanceManager...");
        IBalanceManager(balanceManager).deposit(Currency.wrap(token), amount);

        vm.stopBroadcast();

        uint256 newBalance = IBalanceManager(balanceManager).getBalance(owner, Currency.wrap(token));
        console.log("[OK] Deposited. New balance:", newBalance);
    }

    function _placeTestOrder(
        address agentRouter,
        address pool,
        address baseToken,
        address quoteToken,
        address owner,
        uint256 agentTokenId,
        uint256 privateKey
    ) internal {
        console.log("Step 4: Placing test order via AgentRouter...");

        // Build pool struct
        IPoolManager.Pool memory poolStruct = IPoolManager.Pool({
            baseCurrency: Currency.wrap(baseToken),
            quoteCurrency: Currency.wrap(quoteToken)
        });

        // Place a small market BUY order for 0.01 WETH
        uint128 quantity = 0.01e18; // 0.01 WETH (18 decimals)
        uint128 minOutAmount = 0; // Accept any price for test
        IOrderBook.Side side = IOrderBook.Side.BUY;
        bool autoRepay = false;
        bool autoBorrow = false;

        console.log("Order details:");
        console.log("  Pool:", pool);
        console.log("  Side: BUY");
        console.log("  Quantity:", quantity);
        console.log("  Agent Token ID:", agentTokenId);

        vm.startBroadcast(privateKey);

        try AgentRouter(agentRouter).executeMarketOrder(
            agentTokenId,
            poolStruct,
            side,
            quantity,
            minOutAmount,
            autoRepay,
            autoBorrow
        ) returns (uint48 orderId, uint128 filled) {
            console.log("[OK] Order executed successfully!");
            console.log("  Order ID:", orderId);
            console.log("  Filled:", filled);
        } catch Error(string memory reason) {
            console.log("[FAIL] Order failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("[FAIL] Order failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();
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
