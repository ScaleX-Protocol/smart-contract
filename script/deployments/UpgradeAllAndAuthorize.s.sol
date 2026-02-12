// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {OrderBook} from "@scalexcore/OrderBook.sol";
import {PoolManager} from "@scalexcore/PoolManager.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title UpgradeAllAndAuthorize
 * @notice Deploys new implementations, upgrades beacons, and authorizes AgentRouter
 */
contract UpgradeAllAndAuthorize is Script {
    function run() external {
        console.log("=== UPGRADE ALL & AUTHORIZE AGENT ROUTER ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("");

        // Load addresses
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");
        string memory json = vm.readFile(deploymentPath);

        address poolManagerAddr = _extractAddress(json, "PoolManager");
        address agentRouterAddr = _extractAddress(json, "AgentRouter");
        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");

        // Beacon addresses
        address orderBookBeacon = 0xF756457e5CB37EB69A36cb62326Ae0FeE20f0765;
        address poolManagerBeacon = 0x2122F7Afef5D7E921482C0c55d4F975c50577D90;

        console.log("OrderBook Beacon:", orderBookBeacon);
        console.log("PoolManager Beacon:", poolManagerBeacon);
        console.log("AgentRouter:", agentRouterAddr);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new implementations
        console.log("Step 1: Deploying new implementations...");
        OrderBook newOrderBookImpl = new OrderBook();
        console.log("[OK] OrderBook implementation:", address(newOrderBookImpl));

        PoolManager newPoolManagerImpl = new PoolManager();
        console.log("[OK] PoolManager implementation:", address(newPoolManagerImpl));
        console.log("");

        // Step 2: Upgrade beacons
        console.log("Step 2: Upgrading beacons...");
        UpgradeableBeacon(orderBookBeacon).upgradeTo(address(newOrderBookImpl));
        console.log("[OK] OrderBook beacon upgraded");

        UpgradeableBeacon(poolManagerBeacon).upgradeTo(address(newPoolManagerImpl));
        console.log("[OK] PoolManager beacon upgraded");
        console.log("");

        // Step 3: Authorize AgentRouter on all pools
        console.log("Step 3: Authorizing AgentRouter on all OrderBooks...");

        string[] memory poolKeys = new string[](8);
        poolKeys[0] = string.concat("WETH_", quoteSymbol, "_Pool");
        poolKeys[1] = string.concat("WBTC_", quoteSymbol, "_Pool");
        poolKeys[2] = string.concat("GOLD_", quoteSymbol, "_Pool");
        poolKeys[3] = string.concat("SILVER_", quoteSymbol, "_Pool");
        poolKeys[4] = string.concat("GOOGLE_", quoteSymbol, "_Pool");
        poolKeys[5] = string.concat("NVIDIA_", quoteSymbol, "_Pool");
        poolKeys[6] = string.concat("MNT_", quoteSymbol, "_Pool");
        poolKeys[7] = string.concat("APPLE_", quoteSymbol, "_Pool");

        string[] memory poolNames = new string[](8);
        poolNames[0] = "WETH";
        poolNames[1] = "WBTC";
        poolNames[2] = "GOLD";
        poolNames[3] = "SILVER";
        poolNames[4] = "GOOGLE";
        poolNames[5] = "NVIDIA";
        poolNames[6] = "MNT";
        poolNames[7] = "APPLE";

        PoolManager pm = PoolManager(poolManagerAddr);

        for (uint256 i = 0; i < poolKeys.length; i++) {
            address poolAddr = _extractAddress(json, poolKeys[i]);
            if (poolAddr == address(0)) {
                console.log("  [SKIP]", poolNames[i]);
                continue;
            }

            pm.addAuthorizedRouterToOrderBook(poolAddr, agentRouterAddr);
            console.log("  [OK]", poolNames[i], "- AgentRouter authorized");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("[SUCCESS] All upgrades and authorizations complete!");
        console.log("OrderBook impl:", address(newOrderBookImpl));
        console.log("PoolManager impl:", address(newPoolManagerImpl));
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(string.concat('"', key, '": "'));
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
