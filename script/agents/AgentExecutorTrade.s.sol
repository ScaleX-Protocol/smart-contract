// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {MockERC8004Identity} from "@scalexagents/mocks/MockERC8004Identity.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";

/**
 * @title AgentExecutorTrade
 * @notice Agent executor places trade using primary wallet's funds
 * @dev Executor signs transaction, but uses primary wallet's BalanceManager funds
 */
contract AgentExecutorTrade is Script {
    function run() external {
        console.log("=== AGENT EXECUTOR TRADE ===");
        console.log("");

        // Load deployment addresses
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");
        string memory json = vm.readFile(deploymentPath);

        address identityRegistry = _extractAddress(json, "IdentityRegistry");
        address agentRouter = _extractAddress(json, "AgentRouter");
        address balanceManager = _extractAddress(json, "BalanceManager");

        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        address quoteToken = _extractAddress(json, quoteSymbol);
        address weth = _extractAddress(json, "WETH");
        address wethPool = _extractAddress(json, string.concat("WETH_", quoteSymbol, "_Pool"));

        // Primary wallet (owns funds and agent)
        address primaryWallet = vm.envAddress("PRIMARY_WALLET_ADDRESS");

        // Executor wallet (authorized to trade)
        uint256 executorPrivateKey = vm.envUint("EXECUTOR_PRIVATE_KEY");
        address executorWallet = vm.addr(executorPrivateKey);

        console.log("Configuration:");
        console.log("  Primary Wallet (Owner):", primaryWallet);
        console.log("  Executor Wallet (Trader):", executorWallet);
        console.log("  AgentRouter:", agentRouter);
        console.log("  Pool:", wethPool);
        console.log("");

        // Strategy agent ID (the executor's NFT — set via env var STRATEGY_AGENT_ID)
        uint256 agentId = vm.envUint("STRATEGY_AGENT_ID");
        console.log("Strategy Agent ID:", agentId);
        console.log("");

        // Check authorization: primary wallet must have authorized the strategy agent
        bool isAuthorized = AgentRouter(agentRouter).isAuthorized(primaryWallet, agentId);
        console.log("Authorization (primaryWallet -> agentId):", isAuthorized ? "YES" : "NO");

        if (!isAuthorized) {
            console.log("");
            console.log("[ERROR] Strategy agent not authorized by primary wallet!");
            console.log("Primary wallet must call AgentRouter.authorize(strategyAgentId, policy) first.");
            revert("Agent not authorized");
        }

        // Check primary wallet's balance
        uint256 primaryBalance = IBalanceManager(balanceManager).getBalance(
            primaryWallet,
            Currency.wrap(quoteToken)
        );
        console.log("Primary Wallet Balance:", primaryBalance / 1e6, quoteSymbol);

        // Check executor's balance (should be low, just for gas)
        uint256 executorBalance = IBalanceManager(balanceManager).getBalance(
            executorWallet,
            Currency.wrap(quoteToken)
        );
        console.log("Executor Balance:", executorBalance / 1e6, quoteSymbol);
        console.log("");

        // Place order
        console.log("=== PLACING ORDER ===");
        console.log("Executor signs transaction (pays gas)");
        console.log("Uses primary wallet's funds");
        console.log("");

        // Build pool struct (wethPool is the orderBook address)
        IPoolManager.Pool memory poolStruct = IPoolManager.Pool({
            baseCurrency:  Currency.wrap(weth),
            quoteCurrency: Currency.wrap(quoteToken),
            orderBook:     IOrderBook(wethPool)
        });

        uint128 quantity = 0.01e18; // 0.01 WETH
        IOrderBook.Side side = IOrderBook.Side.BUY;

        console.log("Order Details:");
        console.log("  Side: BUY");
        console.log("  Quantity: 0.01 WETH");
        console.log("  User (primaryWallet):", primaryWallet);
        console.log("  Strategy Agent ID:", agentId);
        console.log("");

        // Executor broadcasts (signs with executor key, uses primary wallet's funds)
        vm.startBroadcast(executorPrivateKey);

        try AgentRouter(agentRouter).executeMarketOrder(
            primaryWallet, // user whose funds are used
            agentId,       // strategy agent's NFT ID
            poolStruct,
            side,
            quantity,
            0,             // minOutAmount
            false,         // autoRepay
            false          // autoBorrow
        ) returns (uint48 orderId, uint128 filled) {
            console.log("[SUCCESS] Order executed!");
            console.log("  Order ID:", orderId);
            console.log("  Filled:", filled);
            console.log("");

            // Check balances after
            uint256 newPrimaryBalance = IBalanceManager(balanceManager).getBalance(
                primaryWallet,
                Currency.wrap(quoteToken)
            );
            console.log("Primary Wallet Balance After:", newPrimaryBalance / 1e6, quoteSymbol);
            int256 change = int256(newPrimaryBalance) - int256(primaryBalance);
            if (change >= 0) {
                console.log("Primary Wallet Change: +", uint256(change), "base units");
            } else {
                console.log("Primary Wallet Change: -", uint256(-change), "base units");
            }

        } catch Error(string memory reason) {
            console.log("[FAIL] Order failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("[FAIL] Order failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== KEY POINTS ===");
        console.log("1. Executor wallet:", executorWallet);
        console.log("   - Signed the transaction");
        console.log("   - Paid gas fees");
        console.log("");
        console.log("2. Primary wallet:", primaryWallet);
        console.log("   - Owns the agent NFT");
        console.log("   - Owns the funds in BalanceManager");
        console.log("   - Funds were used for the trade");
        console.log("");
        console.log("3. Fund Flow:");
        console.log("   - Deducted from:", primaryWallet);
        console.log("   - Executed by:", executorWallet);
        console.log("   - Gas paid by:", executorWallet);
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
