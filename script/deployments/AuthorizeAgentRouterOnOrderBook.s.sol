// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PoolManager} from "@scalexcore/PoolManager.sol";

/**
 * @title AuthorizeAgentRouterOnOrderBook
 * @notice Authorizes AgentRouter on PoolManager so agents can execute orders
 */
contract AuthorizeAgentRouterOnOrderBook is Script {
    function run() external {
        console.log("=== AUTHORIZE AGENT ROUTER ON ORDERBOOK ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("");

        // Load addresses from deployment file
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deploymentPath = string.concat(root, "/deployments/", chainIdStr, ".json");

        if (!vm.exists(deploymentPath)) {
            revert("Deployment file not found");
        }

        string memory json = vm.readFile(deploymentPath);
        address poolManagerAddr = _extractAddress(json, "PoolManager");
        address agentRouterAddr = _extractAddress(json, "AgentRouter");

        console.log("Loaded addresses:");
        console.log("  PoolManager:", poolManagerAddr);
        console.log("  AgentRouter:", agentRouterAddr);
        console.log("");

        require(poolManagerAddr != address(0), "PoolManager address is zero");
        require(agentRouterAddr != address(0), "AgentRouter address is zero");

        vm.startBroadcast(deployerPrivateKey);

        // Authorize AgentRouter in PoolManager
        console.log("Authorizing AgentRouter on PoolManager OrderBook...");
        PoolManager poolManager = PoolManager(poolManagerAddr);
        poolManager.addAuthorizedOperator(agentRouterAddr);
        console.log("[OK] AgentRouter authorized on OrderBook");

        vm.stopBroadcast();

        console.log("");
        console.log("[SUCCESS] AgentRouter can now execute orders via OrderBook!");
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

        uint256 needleLength = needle.length;
        if (needleLength == 0) return 0;

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
