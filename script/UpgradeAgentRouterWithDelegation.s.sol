// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {IERC8004Identity} from "@scalexagents/interfaces/IERC8004Identity.sol";
import {IERC8004Reputation} from "@scalexagents/interfaces/IERC8004Reputation.sol";
import {IERC8004Validation} from "@scalexagents/interfaces/IERC8004Validation.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {ChainlinkMetricsConsumer} from "@scalexagents/ChainlinkMetricsConsumer.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {ILendingManager} from "@scalexcore/interfaces/ILendingManager.sol";

/**
 * @title UpgradeAgentRouterWithDelegation
 * @notice Deploys new AgentRouter with delegation support for dedicated agent wallets
 * @dev Redeploys AgentRouter - note that existing authorizations will be lost
 */
contract UpgradeAgentRouterWithDelegation is Script {

    function run() external {
        console.log("=== UPGRADING AGENT ROUTER WITH DELEGATION SUPPORT ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("");

        // Load deployment addresses
        string memory root = vm.projectRoot();
        string memory deploymentPath = string.concat(root, "/deployments/84532.json");
        string memory json = vm.readFile(deploymentPath);

        address identityRegistry = _extractAddress(json, "IdentityRegistry");
        address reputationRegistry = _extractAddress(json, "ReputationRegistry");
        address validationRegistry = _extractAddress(json, "ValidationRegistry");
        address policyFactory = _extractAddress(json, "PolicyFactory");
        address poolManager = _extractAddress(json, "PoolManager");
        address balanceManager = _extractAddress(json, "BalanceManager");
        address lendingManager = _extractAddress(json, "LendingManager");
        address oldAgentRouter = _extractAddress(json, "AgentRouter");

        console.log("Current AgentRouter:", oldAgentRouter);
        console.log("");
        console.log("Deploying new AgentRouter with delegation support...");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new AgentRouter
        AgentRouter newAgentRouter = new AgentRouter(
            IERC8004Identity(identityRegistry),
            IERC8004Reputation(reputationRegistry),
            IERC8004Validation(validationRegistry),
            PolicyFactory(policyFactory),
            IPoolManager(poolManager),
            IBalanceManager(balanceManager),
            ILendingManager(lendingManager)
        );

        console.log("New AgentRouter deployed:", address(newAgentRouter));
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Update deployments/84532.json with new AgentRouter address");
        console.log("2. Update OrderBook router authorization (FixAgentRouterAuth.s.sol)");
        console.log("3. Existing agent authorizations will be lost - owners must re-authorize agent wallets");
        console.log("");
        console.log("New AgentRouter address:", address(newAgentRouter));

        vm.stopBroadcast();
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(string.concat('"', key, '": "'));

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

        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
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
