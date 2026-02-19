// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {MockERC8004Identity} from "@scalexagents/mocks/MockERC8004Identity.sol";

/**
 * @title CreateMultipleAgents
 * @notice Register NFT identities for multiple agent wallets.
 * @dev Each agent wallet calls IdentityRegistry.register() to mint its own NFT.
 *      The NFT token ID (strategyAgentId) must then be given to users so they can
 *      call AgentRouter.authorize(strategyAgentId, policy) to grant the agent
 *      permission to trade on their behalf.
 *
 * Flow:
 *   1. Run this script  →  each agent wallet gets a strategyAgentId NFT
 *   2. Note the printed strategyAgentIds
 *   3. Run user-authorize-agent.sh  →  users authorize those agent IDs
 *   4. Agent wallets can now call AgentRouter.execute*() on behalf of authorized users
 *
 * Required env vars:
 *   AGENT1_PRIVATE_KEY  — wallet for agent 1
 *   AGENT2_PRIVATE_KEY  — wallet for agent 2
 *   AGENT3_PRIVATE_KEY  — wallet for agent 3
 */
contract CreateMultipleAgents is Script {
    struct AgentSetup {
        address wallet;
        uint256 privateKey;
        uint256 agentId;
        string name;
    }

    function run() external {
        console.log("=== REGISTER AGENT IDENTITIES ===");
        console.log("");

        // Load deployment addresses
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");
        string memory json = vm.readFile(deploymentPath);

        address identityRegistry = _extractAddress(json, "IdentityRegistry");

        console.log("IdentityRegistry:", identityRegistry);
        console.log("");

        AgentSetup[] memory agents = new AgentSetup[](3);

        agents[0] = AgentSetup({
            wallet: address(0),
            privateKey: vm.envUint("AGENT1_PRIVATE_KEY"),
            agentId: 0,
            name: "Agent 1"
        });
        agents[1] = AgentSetup({
            wallet: address(0),
            privateKey: vm.envUint("AGENT2_PRIVATE_KEY"),
            agentId: 0,
            name: "Agent 2"
        });
        agents[2] = AgentSetup({
            wallet: address(0),
            privateKey: vm.envUint("AGENT3_PRIVATE_KEY"),
            agentId: 0,
            name: "Agent 3"
        });

        for (uint256 i = 0; i < agents.length; i++) {
            agents[i].wallet = vm.addr(agents[i].privateKey);
        }

        // Register each agent wallet
        for (uint256 i = 0; i < agents.length; i++) {
            console.log(string.concat("Registering ", agents[i].name, "..."));
            console.log("  Wallet:", agents[i].wallet);

            vm.startBroadcast(agents[i].privateKey);
            agents[i].agentId = MockERC8004Identity(identityRegistry).register();
            vm.stopBroadcast();

            console.log("  [OK] strategyAgentId:", agents[i].agentId);
            console.log("");
        }

        console.log("=== SUMMARY ===");
        console.log("");
        console.log("Agent wallets registered. Share these IDs with users:");
        console.log("");
        for (uint256 i = 0; i < agents.length; i++) {
            console.log(string.concat(agents[i].name, ":"));
            console.log("  Wallet:          ", agents[i].wallet);
            console.log("  strategyAgentId: ", agents[i].agentId);
            console.log("");
        }
        console.log("Next step: Users run user-authorize-agent.sh to grant each agent permission.");
        console.log("  STRATEGY_AGENT_ID=<id> bash shellscripts/user-authorize-agent.sh");
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
