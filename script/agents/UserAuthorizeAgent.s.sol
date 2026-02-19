// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {PolicyFactoryStorage} from "@scalexagents/storages/PolicyFactoryStorage.sol";

/**
 * @title UserAuthorizeAgent
 * @notice User grants a strategy agent permission to execute orders on their behalf.
 * @dev Run this AFTER the agent wallet has registered its NFT via CreateMultipleAgents.
 *
 * Flow:
 *   1. Agent wallet runs CreateMultipleAgents  →  registers NFT, gets strategyAgentId
 *   2. User wallet runs this script            →  AgentRouter.authorize(strategyAgentId, policy)
 *   3. Agent wallet calls AgentRouter.execute*(userAddress, strategyAgentId, ...)
 *      AgentRouter checks:
 *        • msg.sender == ownerOf(strategyAgentId)        (agent wallet owns NFT)
 *        • authorizedStrategyAgents[user][strategyAgentId]  (user granted permission)
 *
 * Required env vars:
 *   USER_PRIVATE_KEY    — wallet that owns funds and is granting authorization
 *   STRATEGY_AGENT_ID  — NFT token ID of the agent being authorized (from CreateMultipleAgents)
 *
 * @dev The via_ir=true setting in foundry.toml handles any potential stack-depth issues
 *      when ABI-encoding the 42-field Policy struct.
 */
contract UserAuthorizeAgent is Script {
    function run() external {
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");
        string memory json = vm.readFile(deploymentPath);

        address agentRouter = _extractAddress(json, "AgentRouter");

        uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
        address userWallet = vm.addr(userPrivateKey);
        uint256 strategyAgentId = vm.envUint("STRATEGY_AGENT_ID");

        console.log("=== USER AUTHORIZE AGENT ===");
        console.log("");
        console.log("AgentRouter:       ", agentRouter);
        console.log("User Wallet:       ", userWallet);
        console.log("Strategy Agent ID: ", strategyAgentId);
        console.log("");

        PolicyFactoryStorage.Policy memory policy = _buildDefaultPolicy();

        vm.startBroadcast(userPrivateKey);
        // If already authorized, revoke first so we can reinstall the updated policy.
        if (AgentRouter(agentRouter).isAuthorized(userWallet, strategyAgentId)) {
            console.log("[INFO] Already authorized - revoking to reinstall updated policy...");
            AgentRouter(agentRouter).revoke(strategyAgentId);
        }
        AgentRouter(agentRouter).authorize(strategyAgentId, policy);
        vm.stopBroadcast();

        // Verify
        bool authorized = AgentRouter(agentRouter).isAuthorized(userWallet, strategyAgentId);
        if (authorized) {
            console.log("[OK] Authorization confirmed");
            console.log("");
            console.log("Agent", strategyAgentId, "can now execute orders on behalf of user:");
            console.log(" ", userWallet);
        } else {
            console.log("[FAIL] Authorization not recorded - check agent ID and router address");
        }
    }

    function _buildDefaultPolicy() private pure returns (PolicyFactoryStorage.Policy memory p) {
        address[] memory empty = new address[](0);
        p.expiryTimestamp             = type(uint256).max;
        p.maxOrderSize                = type(uint128).max; // no per-order cap for this policy
        p.minOrderSize                = 0;
        p.whitelistedTokens           = empty;
        p.blacklistedTokens           = empty;
        p.allowMarketOrders           = true;
        p.allowLimitOrders            = true;
        p.allowSwap                   = true;
        p.allowBorrow                 = true;
        p.allowRepay                  = true;
        p.allowSupplyCollateral       = true;
        p.allowWithdrawCollateral     = true;
        p.allowPlaceLimitOrder        = true;
        p.allowCancelOrder            = true;
        p.allowBuy                    = true;
        p.allowSell                   = true;
        p.allowAutoBorrow             = true;
        p.maxAutoBorrowAmount         = 5000e6;
        p.allowAutoRepay              = true;
        p.minDebtToRepay              = 100e6;
        p.minHealthFactor             = 13e17;   // 1.3 = 30% safety buffer
        p.maxSlippageBps              = 500;      // 5%
        p.minTimeBetweenTrades        = 60;       // 1 minute
        // Leave dailyVolumeLimit, weeklyVolumeLimit, maxDailyDrawdown, maxWeeklyDrawdown,
        // maxTradeVsTVLBps, maxPositionConcentrationBps, maxTradesPerDay, maxTradesPerHour at 0
        // so PolicyFactory computes requiresChainlinkFunctions = false.
        p.maxCorrelationBps           = 10000;
        p.tradingEndHour              = 23;
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes.concat('"', bytes(key), '": "');

        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) return address(0);

        uint256 addressStart = keyPos + keyBytes.length;
        bytes memory addressBytes = new bytes(42);
        for (uint256 i = 0; i < 42; i++) {
            addressBytes[i] = jsonBytes[addressStart + i];
        }
        return _bytesToAddress(addressBytes);
    }

    function _indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        if (needle.length == 0 || haystack.length < needle.length) return type(uint256).max;

        uint256 needleLength = needle.length;
        for (uint256 i = 0; i <= haystack.length - needleLength; i++) {
            bool found = true;
            for (uint256 j = 0; j < needleLength; j++) {
                if (haystack[i + j] != needle[j]) { found = false; break; }
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
            uint8 b = uint8(data[i]);
            uint256 digit;
            if (b >= 48 && b <= 57)       digit = uint256(b) - 48;
            else if (b >= 97 && b <= 102) digit = uint256(b) - 87;
            else if (b >= 65 && b <= 70)  digit = uint256(b) - 55;
            else continue;
            result = result * 16 + digit;
        }
        return result;
    }
}
