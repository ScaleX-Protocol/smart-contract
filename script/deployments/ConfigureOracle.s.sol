// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";

contract ConfigureOracle is Script {
    function run() external {
        console.log("=== CONFIGURE ORACLE IN EXISTING ORDERBOOKS ===");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);

        // Load addresses from deployment file
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deploymentPath = string.concat(root, "/deployments/", chainIdStr, ".json");

        if (!vm.exists(deploymentPath)) {
            revert("Deployment file not found. Run deployment first.");
        }

        string memory json = vm.readFile(deploymentPath);
        address oracle = _extractAddress(json, "Oracle");
        address wethUsdcPool = _extractAddress(json, "WETH_USDC_Pool");
        address wbtcUsdcPool = _extractAddress(json, "WBTC_USDC_Pool");

        console.log("Loaded addresses:");
        console.log("  Oracle:", oracle);
        console.log("  WETH/USDC OrderBook:", wethUsdcPool);
        console.log("  WBTC/USDC OrderBook:", wbtcUsdcPool);

        // Validate addresses
        require(oracle != address(0), "Oracle address is zero");
        require(wethUsdcPool != address(0), "WETH/USDC pool address is zero");
        require(wbtcUsdcPool != address(0), "WBTC/USDC pool address is zero");

        vm.startBroadcast(deployerPrivateKey);

        // Configure Oracle in WETH/USDC OrderBook
        console.log("Configuring Oracle in WETH/USDC OrderBook...");
        IOrderBook(wethUsdcPool).setOracle(oracle);
        console.log("[OK] Oracle configured in WETH/USDC OrderBook");

        // Configure Oracle in WBTC/USDC OrderBook
        console.log("Configuring Oracle in WBTC/USDC OrderBook...");
        IOrderBook(wbtcUsdcPool).setOracle(oracle);
        console.log("[OK] Oracle configured in WBTC/USDC OrderBook");

        vm.stopBroadcast();

        // Verify Oracle is set correctly
        console.log("=== VERIFYING ORACLE CONFIGURATION ===");

        address wethUsdcOracle = IOrderBook(wethUsdcPool).oracle();
        console.log("WETH/USDC OrderBook Oracle:", vm.toString(wethUsdcOracle));
        require(wethUsdcOracle == oracle, "WETH/USDC OrderBook Oracle not set correctly");
        console.log("[OK] WETH/USDC OrderBook Oracle verified");

        address wbtcUsdcOracle = IOrderBook(wbtcUsdcPool).oracle();
        console.log("WBTC/USDC OrderBook Oracle:", vm.toString(wbtcUsdcOracle));
        require(wbtcUsdcOracle == oracle, "WBTC/USDC OrderBook Oracle not set correctly");
        console.log("[OK] WBTC/USDC OrderBook Oracle verified");

        console.log("=== ORACLE CONFIGURATION COMPLETED ===");
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes.concat('"', bytes(key), '"');

        uint256 keyIndex = _findSubstring(jsonBytes, keyBytes);
        if (keyIndex == type(uint256).max) {
            return address(0);
        }

        uint256 colonIndex = keyIndex + keyBytes.length;
        while (colonIndex < jsonBytes.length && jsonBytes[colonIndex] != ':') {
            colonIndex++;
        }
        if (colonIndex >= jsonBytes.length) {
            return address(0);
        }

        uint256 start = colonIndex + 1;
        while (start < jsonBytes.length && jsonBytes[start] != '"') {
            start++;
        }
        if (start >= jsonBytes.length) {
            return address(0);
        }
        start++;

        uint256 end = start;
        while (end < jsonBytes.length && jsonBytes[end] != '"') {
            end++;
        }
        if (end >= jsonBytes.length) {
            return address(0);
        }

        bytes memory addrBytes = new bytes(end - start);
        for (uint256 i = 0; i < end - start; i++) {
            addrBytes[i] = jsonBytes[start + i];
        }

        return _bytesToAddress(addrBytes);
    }

    function _findSubstring(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
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
