// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IOracle} from "@scalexcore/interfaces/IOracle.sol";

/**
 * @title ConfigureAllOracleTokens
 * @notice Registers ALL synthetic tokens (crypto + RWA) to the Oracle
 * @dev This is a comprehensive script that registers all 9 synthetic tokens
 */
contract ConfigureAllOracleTokens is Script {
    function run() external {
        console.log("=== CONFIGURING ALL ORACLE TOKENS ===");

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

        // Get quote symbol dynamically
        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        string memory sxQuoteKey = string.concat("sx", quoteSymbol);

        // Load all addresses
        address oracle = _extractAddress(json, "Oracle");
        address sxQuote = _extractAddress(json, sxQuoteKey);
        address sxWETH = _extractAddress(json, "sxWETH");
        address sxWBTC = _extractAddress(json, "sxWBTC");
        address sxGOLD = _extractAddress(json, "sxGOLD");
        address sxSILVER = _extractAddress(json, "sxSILVER");
        address sxGOOGLE = _extractAddress(json, "sxGOOGLE");
        address sxNVIDIA = _extractAddress(json, "sxNVIDIA");
        address sxMNT = _extractAddress(json, "sxMNT");
        address sxAPPLE = _extractAddress(json, "sxAPPLE");

        // Load pool addresses (for setTokenOrderBook)
        address wethQuotePool = _extractAddress(json, string.concat("WETH_", quoteSymbol, "_Pool"));
        address wbtcQuotePool = _extractAddress(json, string.concat("WBTC_", quoteSymbol, "_Pool"));
        address goldQuotePool = _extractAddress(json, string.concat("GOLD_", quoteSymbol, "_Pool"));
        address silverQuotePool = _extractAddress(json, string.concat("SILVER_", quoteSymbol, "_Pool"));
        address googleQuotePool = _extractAddress(json, string.concat("GOOGLE_", quoteSymbol, "_Pool"));
        address nvidiaQuotePool = _extractAddress(json, string.concat("NVIDIA_", quoteSymbol, "_Pool"));
        address mntQuotePool = _extractAddress(json, string.concat("MNT_", quoteSymbol, "_Pool"));
        address appleQuotePool = _extractAddress(json, string.concat("APPLE_", quoteSymbol, "_Pool"));

        console.log("Loaded addresses:");
        console.log("  Oracle:", oracle);
        console.log(string.concat("  ", sxQuoteKey, ":"), sxQuote);
        console.log("  sxWETH:", sxWETH);
        console.log("  sxWBTC:", sxWBTC);
        console.log("  sxGOLD:", sxGOLD);
        console.log("  sxSILVER:", sxSILVER);
        console.log("  sxGOOGLE:", sxGOOGLE);
        console.log("  sxNVIDIA:", sxNVIDIA);
        console.log("  sxMNT:", sxMNT);
        console.log("  sxAPPLE:", sxAPPLE);

        // Validate critical addresses
        require(oracle != address(0), "Oracle address is zero");
        require(sxQuote != address(0), string.concat(sxQuoteKey, " address is zero"));
        require(sxWETH != address(0), "sxWETH address is zero");
        require(sxWBTC != address(0), "sxWBTC address is zero");
        require(sxGOLD != address(0), "sxGOLD address is zero");
        require(sxSILVER != address(0), "sxSILVER address is zero");
        require(sxGOOGLE != address(0), "sxGOOGLE address is zero");
        require(sxNVIDIA != address(0), "sxNVIDIA address is zero");
        require(sxMNT != address(0), "sxMNT address is zero");
        require(sxAPPLE != address(0), "sxAPPLE address is zero");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Add all tokens to Oracle
        console.log("");
        console.log("Step 1: Adding tokens to Oracle...");

        _addTokenSafely(oracle, sxQuote, sxQuoteKey);
        _addTokenSafely(oracle, sxWETH, "sxWETH");
        _addTokenSafely(oracle, sxWBTC, "sxWBTC");
        _addTokenSafely(oracle, sxGOLD, "sxGOLD");
        _addTokenSafely(oracle, sxSILVER, "sxSILVER");
        _addTokenSafely(oracle, sxGOOGLE, "sxGOOGLE");
        _addTokenSafely(oracle, sxNVIDIA, "sxNVIDIA");
        _addTokenSafely(oracle, sxMNT, "sxMNT");
        _addTokenSafely(oracle, sxAPPLE, "sxAPPLE");

        // Step 2: Set OrderBooks for each token (if pool exists)
        console.log("");
        console.log("Step 2: Setting OrderBooks for tokens...");

        _setOrderBookSafely(oracle, sxWETH, wethQuotePool, "sxWETH");
        _setOrderBookSafely(oracle, sxWBTC, wbtcQuotePool, "sxWBTC");
        _setOrderBookSafely(oracle, sxGOLD, goldQuotePool, "sxGOLD");
        _setOrderBookSafely(oracle, sxSILVER, silverQuotePool, "sxSILVER");
        _setOrderBookSafely(oracle, sxGOOGLE, googleQuotePool, "sxGOOGLE");
        _setOrderBookSafely(oracle, sxNVIDIA, nvidiaQuotePool, "sxNVIDIA");
        _setOrderBookSafely(oracle, sxMNT, mntQuotePool, "sxMNT");
        _setOrderBookSafely(oracle, sxAPPLE, appleQuotePool, "sxAPPLE");

        // Step 3: Initialize prices
        console.log("");
        console.log("Step 3: Initializing prices...");

        _initializePriceSafely(oracle, sxQuote, 1e6, sxQuoteKey, "$1");
        _initializePriceSafely(oracle, sxWETH, 3000e6, "sxWETH", "$3,000");
        _initializePriceSafely(oracle, sxWBTC, 95000e6, "sxWBTC", "$95,000");
        _initializePriceSafely(oracle, sxGOLD, 2780e6, "sxGOLD", "$2,780");
        _initializePriceSafely(oracle, sxSILVER, 32e6, "sxSILVER", "$32");
        _initializePriceSafely(oracle, sxGOOGLE, 188e6, "sxGOOGLE", "$188");
        _initializePriceSafely(oracle, sxNVIDIA, 145e6, "sxNVIDIA", "$145");
        _initializePriceSafely(oracle, sxMNT, 1e6, "sxMNT", "$1");
        _initializePriceSafely(oracle, sxAPPLE, 235e6, "sxAPPLE", "$235");

        vm.stopBroadcast();

        // Verify configuration
        console.log("");
        console.log("=== VERIFYING CONFIGURATION ===");
        _verifyPrice(oracle, sxQuote, 1e6, sxQuoteKey);
        _verifyPrice(oracle, sxWETH, 3000e6, "sxWETH");
        _verifyPrice(oracle, sxWBTC, 95000e6, "sxWBTC");
        _verifyPrice(oracle, sxGOLD, 2780e6, "sxGOLD");
        _verifyPrice(oracle, sxSILVER, 32e6, "sxSILVER");
        _verifyPrice(oracle, sxGOOGLE, 188e6, "sxGOOGLE");
        _verifyPrice(oracle, sxNVIDIA, 145e6, "sxNVIDIA");
        _verifyPrice(oracle, sxMNT, 1e6, "sxMNT");
        _verifyPrice(oracle, sxAPPLE, 235e6, "sxAPPLE");

        console.log("");
        console.log("=== ALL ORACLE TOKENS CONFIGURED SUCCESSFULLY ===");
    }

    function _addTokenSafely(address oracle, address token, string memory name) internal {
        try IOracle(oracle).addToken(token, 0) {
            console.log(string.concat("  [OK] ", name, " added to oracle"));
        } catch {
            console.log(string.concat("  [INFO] ", name, " already registered"));
        }
    }

    function _setOrderBookSafely(address oracle, address token, address pool, string memory name) internal {
        if (pool == address(0)) {
            console.log(string.concat("  [SKIP] ", name, " - no pool deployed"));
            return;
        }

        try IOracle(oracle).setTokenOrderBook(token, pool) {
            console.log(string.concat("  [OK] ", name, " orderbook set"));
        } catch {
            console.log(string.concat("  [WARN] ", name, " orderbook set failed"));
        }
    }

    function _initializePriceSafely(
        address oracle,
        address token,
        uint256 price,
        string memory name,
        string memory priceLabel
    ) internal {
        try IOracle(oracle).initializePrice(token, price) {
            console.log(string.concat("  [OK] ", name, " price initialized: ", priceLabel));
        } catch {
            console.log(string.concat("  [INFO] ", name, " price already initialized"));
        }
    }

    function _verifyPrice(address oracle, address token, uint256 expectedPrice, string memory name) internal view {
        uint256 actualPrice = IOracle(oracle).getSpotPrice(token);
        console.log(string.concat(name, " spot price: $"), actualPrice / 1e6);
        require(actualPrice == expectedPrice, string.concat(name, " price incorrect"));
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
