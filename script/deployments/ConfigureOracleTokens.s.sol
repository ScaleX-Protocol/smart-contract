// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IOracle} from "@scalexcore/interfaces/IOracle.sol";

contract ConfigureOracleTokens is Script {
    function run() external {
        console.log("=== CONFIGURING ORACLE TOKENS ===");

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
        address gsUSDC = _extractAddress(json, "gsUSDC");
        address gsWETH = _extractAddress(json, "gsWETH");
        address gsWBTC = _extractAddress(json, "gsWBTC");
        address wethUsdcPool = _extractAddress(json, "WETH_USDC_Pool");
        address wbtcUsdcPool = _extractAddress(json, "WBTC_USDC_Pool");

        console.log("Loaded addresses:");
        console.log("  Oracle:", oracle);
        console.log("  gsUSDC:", gsUSDC);
        console.log("  gsWETH:", gsWETH);
        console.log("  gsWBTC:", gsWBTC);
        console.log("  WETH/USDC Pool:", wethUsdcPool);
        console.log("  WBTC/USDC Pool:", wbtcUsdcPool);

        // Validate addresses
        require(oracle != address(0), "Oracle address is zero");
        require(gsUSDC != address(0), "gsUSDC address is zero");
        require(gsWETH != address(0), "gsWETH address is zero");
        require(gsWBTC != address(0), "gsWBTC address is zero");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Add tokens to Oracle
        console.log("Step 1: Adding tokens to Oracle...");

        IOracle(oracle).addToken(gsUSDC, 0);
        console.log("[OK] gsUSDC added to Oracle");

        IOracle(oracle).addToken(gsWETH, 0);
        console.log("[OK] gsWETH added to Oracle");

        IOracle(oracle).addToken(gsWBTC, 0);
        console.log("[OK] gsWBTC added to Oracle");

        // Step 2: Set OrderBooks for each token
        console.log("Step 2: Setting OrderBooks for tokens...");

        IOracle(oracle).setTokenOrderBook(gsWETH, wethUsdcPool);
        console.log("[OK] gsWETH OrderBook set");

        IOracle(oracle).setTokenOrderBook(gsWBTC, wbtcUsdcPool);
        console.log("[OK] gsWBTC OrderBook set");

        // Step 3: Initialize prices (for bootstrapping)
        console.log("Step 3: Initializing prices...");

        IOracle(oracle).initializePrice(gsWETH, 3000e6); // $3000 per WETH (6 decimals for USD)
        console.log("[OK] gsWETH price initialized: $3000");

        IOracle(oracle).initializePrice(gsWBTC, 95000e6); // $95000 per WBTC
        console.log("[OK] gsWBTC price initialized: $95000");

        IOracle(oracle).initializePrice(gsUSDC, 1e6); // $1 per USDC
        console.log("[OK] gsUSDC price initialized: $1");

        vm.stopBroadcast();

        // Verify configuration
        console.log("=== VERIFYING CONFIGURATION ===");

        // Note: We'll verify prices work instead, as tokenPriceData.supported is internal
        console.log("Verifying prices...");

        uint256 gsWETHPrice = IOracle(oracle).getSpotPrice(gsWETH);
        console.log("gsWETH spot price:", gsWETHPrice);
        require(gsWETHPrice == 3000e6, "gsWETH price incorrect");

        uint256 gsUSDCPrice = IOracle(oracle).getSpotPrice(gsUSDC);
        console.log("gsUSDC spot price:", gsUSDCPrice);
        require(gsUSDCPrice == 1e6, "gsUSDC price incorrect");

        uint256 gsWBTCPrice = IOracle(oracle).getSpotPrice(gsWBTC);
        console.log("gsWBTC spot price:", gsWBTCPrice);
        require(gsWBTCPrice == 95000e6, "gsWBTC price incorrect");

        console.log("=== ORACLE TOKEN CONFIGURATION COMPLETED ===");
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
