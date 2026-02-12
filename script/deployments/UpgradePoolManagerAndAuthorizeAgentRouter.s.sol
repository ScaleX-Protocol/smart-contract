// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PoolManager} from "@scalexcore/PoolManager.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {OrderBook} from "@scalexcore/OrderBook.sol";

/**
 * @title UpgradePoolManagerAndAuthorizeAgentRouter
 * @notice Upgrades PoolManager beacon and authorizes AgentRouter on all OrderBooks
 */
contract UpgradePoolManagerAndAuthorizeAgentRouter is Script {
    function run() external {
        console.log("=== UPGRADE POOLMANAGER & AUTHORIZE AGENT ROUTER ===");
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

        // Load core addresses
        address poolManagerAddr = _extractAddress(json, "PoolManager");
        address agentRouterAddr = _extractAddress(json, "AgentRouter");

        console.log("Loaded addresses:");
        console.log("  PoolManager:", poolManagerAddr);
        console.log("  AgentRouter:", agentRouterAddr);
        console.log("");

        require(poolManagerAddr != address(0), "PoolManager address is zero");
        require(agentRouterAddr != address(0), "AgentRouter address is zero");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new PoolManager implementation
        console.log("Step 1: Deploying new PoolManager implementation...");
        PoolManager newPoolManagerImpl = new PoolManager();
        console.log("[OK] New PoolManager implementation:", address(newPoolManagerImpl));
        console.log("");

        // Step 2: Get PoolManager beacon address
        console.log("Step 2: Getting PoolManager beacon address...");
        bytes32 beaconSlot = bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);
        address beaconAddr = address(uint160(uint256(vm.load(poolManagerAddr, beaconSlot))));
        console.log("[OK] PoolManager Beacon:", beaconAddr);
        console.log("");

        // Step 3: Upgrade PoolManager beacon
        console.log("Step 3: Upgrading PoolManager beacon...");
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddr);
        beacon.upgradeTo(address(newPoolManagerImpl));
        console.log("[OK] Beacon upgraded to new PoolManager implementation");
        console.log("");

        // Step 4: Authorize AgentRouter on all OrderBooks
        console.log("Step 4: Authorizing AgentRouter on all OrderBooks...");

        // Load pool addresses from deployment file
        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");

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
                console.log("  [SKIP]", poolNames[i], "pool - not in deployment file");
                continue;
            }

            // Call addAuthorizedRouterToOrderBook through upgraded PoolManager
            pm.addAuthorizedRouterToOrderBook(poolAddr, agentRouterAddr);
            console.log("  [OK]", poolNames[i], "pool - AgentRouter authorized");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("[SUCCESS] PoolManager upgraded and AgentRouter authorized on all pools!");
        console.log("New PoolManager implementation:", address(newPoolManagerImpl));
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
