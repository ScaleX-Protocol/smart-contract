// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoolManager} from "../src/core/PoolManager.sol";

interface IBeacon {
    function upgradeTo(address newImplementation) external;
    function implementation() external view returns (address);
}

interface IPoolManager {
    function updatePoolRouter(bytes32 poolId, address newRouter) external;
    function owner() external view returns (address);
}

/**
 * @title UpdatePoolManagerBeaconAndRouter
 * @notice Updates PoolManager Beacon implementation then sets AgentRouter
 */
contract UpdatePoolManagerBeaconAndRouter is Script {
    function run() external {
        console.log("=== UPDATE POOLMANAGER BEACON AND SET AGENT ROUTER ===");
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
        // PoolManager uses BeaconProxy - beacon address stored at slot 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50
        address poolManagerBeacon = 0x2122F7Afef5D7E921482C0c55d4F975c50577D90;
        address agentRouter = _extractAddress(json, "AgentRouter");

        console.log("PoolManager Proxy:", poolManagerProxy);
        console.log("PoolManager Beacon:", poolManagerBeacon);
        console.log("AgentRouter:", agentRouter);
        console.log("");

        // Check current implementation
        address currentImpl = IBeacon(poolManagerBeacon).implementation();
        console.log("Current PoolManager implementation:", currentImpl);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new PoolManager implementation
        console.log("Step 1: Deploying new PoolManager implementation...");
        PoolManager newImpl = new PoolManager();
        console.log("  New implementation deployed at:", address(newImpl));
        console.log("");

        // Step 2: Update Beacon
        console.log("Step 2: Updating Beacon to new implementation...");
        IBeacon(poolManagerBeacon).upgradeTo(address(newImpl));
        console.log("  Beacon updated successfully!");
        console.log("");

        // Step 3: Set AgentRouter for WETH/IDRX pool
        console.log("Step 3: Setting AgentRouter for WETH/IDRX pool...");

        address weth = _extractAddress(json, "WETH");
        address idrx = _extractAddress(json, "IDRX");

        // baseCurrency should be the one with lower address value
        address base = weth < idrx ? weth : idrx;
        address quote = weth < idrx ? idrx : weth;

        bytes32 poolId = keccak256(abi.encode(base, quote));

        console.log("  WETH:", weth);
        console.log("  IDRX:", idrx);
        console.log("  Base currency:", base);
        console.log("  Quote currency:", quote);
        console.log("  Pool ID:", vm.toString(poolId));
        console.log("  Setting router to:", agentRouter);
        console.log("");

        IPoolManager(poolManagerProxy).updatePoolRouter(poolId, agentRouter);
        console.log("  AgentRouter set successfully!");

        vm.stopBroadcast();

        console.log("");
        console.log("=== SUCCESS ===");
        console.log("PoolManager upgraded and AgentRouter authorized for WETH/IDRX pool");
        console.log("");
        console.log("Run TestAgentOrderExecution.s.sol to verify agent can place orders");
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
