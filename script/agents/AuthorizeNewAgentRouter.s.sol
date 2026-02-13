// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/core/PoolManager.sol";

contract AuthorizeNewAgentRouter is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Load deployment addresses
        string memory json = vm.readFile("deployments/84532.json");
        address poolManagerAddr = vm.parseJsonAddress(json, ".PoolManager");
        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");

        address newAgentRouter = 0x9F7D22e7065d68F689FBC4354C9f70c9a85D8982;

        console.log("=== Authorize New AgentRouter on All Pools ===");
        console.log("PoolManager:", poolManagerAddr);
        console.log("New AgentRouter:", newAgentRouter);
        console.log("");

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

        vm.startBroadcast(deployerKey);

        PoolManager pm = PoolManager(poolManagerAddr);

        for (uint256 i = 0; i < poolKeys.length; i++) {
            address poolAddr = _extractAddress(json, poolKeys[i]);
            if (poolAddr == address(0)) {
                console.log("  [SKIP]", poolNames[i]);
                continue;
            }

            pm.addAuthorizedRouterToOrderBook(poolAddr, newAgentRouter);
            console.log("  [OK]", poolNames[i], "pool:", poolAddr);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("[SUCCESS] All pools authorized!");
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
