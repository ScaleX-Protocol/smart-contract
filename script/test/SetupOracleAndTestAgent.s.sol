// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IOracle {
    function addToken(address token, uint256 priceId) external;
    function setPrice(address token, uint256 price) external;
    function getSpotPrice(address token) external view returns (uint256);
    function tokenPriceData(address token) external view returns (
        uint256 lastUpdateTime,
        uint256 lastCumulativePrice,
        uint256 oldestTimestamp,
        uint256 maxHistorySize,
        bool supported
    );
}

contract SetupOracleAndTestAgent is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== SETUP ORACLE FOR AGENT TESTING ===");
        console.log("Deployer:", deployer);
        console.log("");

        // Load addresses
        string memory root = vm.projectRoot();
        string memory deploymentPath = string.concat(root, "/deployments/84532.json");
        string memory json = vm.readFile(deploymentPath);

        address oracle = _extractAddress(json, "Oracle");
        address idrx = _extractAddress(json, "IDRX");
        address weth = _extractAddress(json, "WETH");

        console.log("Oracle:", oracle);
        console.log("IDRX:", idrx);
        console.log("WETH:", weth);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Add IDRX to Oracle
        console.log("Step 1: Adding IDRX to Oracle...");
        try IOracle(oracle).addToken(idrx, 0) {
            console.log("  IDRX added to Oracle");
        } catch Error(string memory reason) {
            console.log("  Failed to add IDRX:", reason);
        } catch {
            console.log("  Failed to add IDRX (no reason)");
        }

        // Step 2: Set IDRX price ($1.00 with 8 decimals)
        console.log("Step 2: Setting IDRX price to $1.00...");
        try IOracle(oracle).setPrice(idrx, 100_000_000) {
            console.log("  IDRX price set successfully");
        } catch Error(string memory reason) {
            console.log("  Failed to set IDRX price:", reason);
        } catch {
            console.log("  Failed to set IDRX price (no reason)");
        }

        // Step 3: Add WETH to Oracle
        console.log("Step 3: Adding WETH to Oracle...");
        try IOracle(oracle).addToken(weth, 0) {
            console.log("  WETH added to Oracle");
        } catch Error(string memory reason) {
            console.log("  Failed to add WETH:", reason);
        } catch {
            console.log("  Failed to add WETH (no reason)");
        }

        // Step 4: Set WETH price ($3000.00 with 8 decimals)
        console.log("Step 4: Setting WETH price to $3000.00...");
        try IOracle(oracle).setPrice(weth, 300_000_000_000) {
            console.log("  WETH price set successfully");
        } catch Error(string memory reason) {
            console.log("  Failed to set WETH price:", reason);
        } catch {
            console.log("  Failed to set WETH price (no reason)");
        }

        vm.stopBroadcast();

        // Verify prices
        console.log("");
        console.log("=== VERIFICATION ===");
        try IOracle(oracle).getSpotPrice(idrx) returns (uint256 price) {
            console.log("IDRX price:", price);
        } catch {
            console.log("IDRX: Failed to get price");
        }

        try IOracle(oracle).getSpotPrice(weth) returns (uint256 price) {
            console.log("WETH price:", price);
        } catch {
            console.log("WETH: Failed to get price");
        }

        console.log("");
        console.log("Oracle setup complete! Now run TestAgentOrderExecution.s.sol");
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
