// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";

/**
 * @title AgentExecutorTrade
 * @notice Agent wallet places trade using user wallet's funds
 * @dev Agent signs transaction, but uses user wallet's BalanceManager funds
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

        address agentRouter = _extractAddress(json, "AgentRouter");
        address balanceManager = _extractAddress(json, "BalanceManager");

        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        address quoteToken = _extractAddress(json, quoteSymbol);
        address weth = _extractAddress(json, "WETH");
        address wethPool = _extractAddress(json, string.concat("WETH_", quoteSymbol, "_Pool"));

        // User wallet (owns funds)
        address userWallet = vm.envAddress("USER_ADDRESS");

        // Agent wallet (authorized to trade)
        uint256 agentPrivateKey = vm.envUint("AGENT_PRIVATE_KEY");
        address agentWallet = vm.addr(agentPrivateKey);

        console.log("Configuration:");
        console.log("  User Wallet (Owner):", userWallet);
        console.log("  Agent Wallet (Trader):", agentWallet);
        console.log("  AgentRouter:", agentRouter);
        console.log("  Pool:", wethPool);
        console.log("");

        // Strategy agent ID (the executor's NFT — set via env var STRATEGY_AGENT_ID)
        uint256 agentId = vm.envUint("STRATEGY_AGENT_ID");
        console.log("Strategy Agent ID:", agentId);
        console.log("");

        // Check authorization: user wallet must have authorized the strategy agent
        bool isAuthorized = AgentRouter(agentRouter).isAuthorized(userWallet, agentId);
        console.log("Authorization (userWallet -> agentId):", isAuthorized ? "YES" : "NO");

        if (!isAuthorized) {
            console.log("");
            console.log("[ERROR] Strategy agent not authorized by user wallet!");
            console.log("User wallet must call AgentRouter.authorize(strategyAgentId, policy) first.");
            revert("Agent not authorized");
        }

        // Check user wallet's balance
        uint256 userBalance = IBalanceManager(balanceManager).getBalance(
            userWallet,
            Currency.wrap(quoteToken)
        );
        console.log("User Wallet Balance:", userBalance / 1e6, quoteSymbol);

        // Check agent's balance (should be low, just for gas)
        uint256 agentBalance = IBalanceManager(balanceManager).getBalance(
            agentWallet,
            Currency.wrap(quoteToken)
        );
        console.log("Agent Balance:", agentBalance / 1e6, quoteSymbol);
        console.log("");

        // Place order
        console.log("=== PLACING ORDER ===");
        console.log("Agent signs transaction (pays gas)");
        console.log("Uses user wallet's funds");
        console.log("");

        // Build pool struct (wethPool is the orderBook address)
        IPoolManager.Pool memory poolStruct = IPoolManager.Pool({
            baseCurrency:  Currency.wrap(weth),
            quoteCurrency: Currency.wrap(quoteToken),
            orderBook:     IOrderBook(wethPool)
        });

        uint128 price    = 3000e6;   // $3000 IDRX per WETH (6-decimal quote)
        uint128 quantity = 0.01e18;  // 0.01 WETH (18-decimal base)
        IOrderBook.Side side = IOrderBook.Side.BUY;
        IOrderBook.TimeInForce tif = IOrderBook.TimeInForce.GTC;

        console.log("Order Details:");
        console.log("  Type: LIMIT BUY GTC");
        console.log("  Price:", price / 1e6, quoteSymbol, "per WETH");
        console.log("  Quantity: 0.01 WETH");
        console.log("  User (userWallet):", userWallet);
        console.log("  Strategy Agent ID:", agentId);
        console.log("");

        // Agent broadcasts (signs with agent key, uses user wallet's funds)
        vm.startBroadcast(agentPrivateKey);

        try AgentRouter(agentRouter).executeLimitOrder(
            userWallet,  // user whose funds are used
            agentId,     // strategy agent's NFT ID
            poolStruct,
            price,
            quantity,
            side,
            tif,
            false,       // autoRepay
            false        // autoBorrow
        ) returns (uint48 orderId) {
            console.log("[SUCCESS] Limit order placed!");
            console.log("  Order ID:", orderId);
            console.log("");

        } catch Error(string memory reason) {
            console.log("[FAIL] Order failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("[FAIL] Order failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== KEY POINTS ===");
        console.log("1. Agent wallet:", agentWallet);
        console.log("   - Signed the transaction, paid gas");
        console.log("");
        console.log("2. User wallet:", userWallet);
        console.log("   - Authorized agent NFT, owns funds");
        console.log("   - Funds locked in BalanceManager when order fills");
        console.log("");
        console.log("3. Order sits in the order book until matched or cancelled");
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
