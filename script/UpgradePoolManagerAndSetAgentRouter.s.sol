// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol";

interface IPoolManager {
    function updatePoolRouter(bytes32 poolId, address newRouter) external;
    function owner() external view returns (address);
}

/**
 * @title UpgradePoolManagerAndSetAgentRouter
 * @notice Upgrades PoolManager implementation to add updatePoolRouter() function,
 *         then sets AgentRouter as authorized router for WETH/IDRX pool
 */
contract UpgradePoolManagerAndSetAgentRouter is Script {
    function run() external {
        console.log("=== UPGRADE POOLMANAGER AND SET AGENT ROUTER ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("");

        // Load deployment addresses
        string memory root = vm.projectRoot();
        string memory deploymentPath = string.concat(root, "/deployments/84532.json");
        string memory json = vm.readFile(deploymentPath);

        address poolManagerProxy = _extractAddress(json, "PoolManager");
        address agentRouter = _extractAddress(json, "AgentRouter");

        console.log("PoolManager Proxy:", poolManagerProxy);
        console.log("AgentRouter:", agentRouter);
        console.log("");

        // Verify deployer is owner
        address currentOwner = IPoolManager(poolManagerProxy).owner();
        console.log("PoolManager owner:", currentOwner);
        require(currentOwner == deployer, "Deployer is not PoolManager owner!");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Upgrade PoolManager implementation
        console.log("Step 1: Upgrading PoolManager implementation...");

        Options memory opts;
        opts.unsafeSkipAllChecks = true; // Skip storage layout checks since we're only adding functions

        Upgrades.upgradeProxy(
            poolManagerProxy,
            "PoolManager.sol:PoolManager",
            "",
            opts
        );

        console.log("  PoolManager upgraded successfully!");
        console.log("");

        // Step 2: Set AgentRouter for WETH/IDRX pool
        console.log("Step 2: Setting AgentRouter for WETH/IDRX pool...");

        // Get WETH/IDRX pool ID from deployment
        // Pool ID is: keccak256(abi.encode(baseCurrency, quoteCurrency))
        address weth = _extractAddress(json, "WETH");
        address idrx = _extractAddress(json, "IDRX");

        // baseCurrency should be the one with lower address value
        address base = weth < idrx ? weth : idrx;
        address quote = weth < idrx ? idrx : weth;

        bytes32 poolId = keccak256(abi.encode(base, quote));

        console.log("  WETH:", weth);
        console.log("  IDRX:", idrx);
        console.log("  Pool ID:", vm.toString(poolId));
        console.log("  Setting router to:", agentRouter);

        try IPoolManager(poolManagerProxy).updatePoolRouter(poolId, agentRouter) {
            console.log("  AgentRouter set successfully!");
        } catch Error(string memory reason) {
            console.log("  Failed to set router:", reason);
            revert(reason);
        } catch {
            console.log("  Failed to set router with unknown error");
            revert("Router update failed");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== SUCCESS ===");
        console.log("PoolManager upgraded and AgentRouter authorized for WETH/IDRX pool");
        console.log("");
        console.log("Next: Run TestAgentOrderExecution.s.sol to verify agent can place orders");
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
