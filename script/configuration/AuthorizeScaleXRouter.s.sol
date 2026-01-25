// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";

/**
 * @title AuthorizeScaleXRouter
 * @notice Script to authorize ScaleXRouter as an operator in BalanceManager
 * @dev This is required for ScaleXRouter.borrow() to work properly
 */
contract AuthorizeScaleXRouter is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;

        // Load deployment file
        string memory deploymentPath = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        console.log("Loading deployment from:", deploymentPath);

        string memory json = vm.readFile(deploymentPath);
        address balanceManager = _extractAddress(json, "BalanceManager");
        address scaleXRouter = _extractAddress(json, "ScaleXRouter");

        console.log("BalanceManager:", balanceManager);
        console.log("ScaleXRouter:", scaleXRouter);

        require(balanceManager != address(0), "BalanceManager address is zero");
        require(scaleXRouter != address(0), "ScaleXRouter address is zero");

        vm.startBroadcast(deployerPrivateKey);

        // Authorize ScaleXRouter in BalanceManager
        console.log("Authorizing ScaleXRouter as operator in BalanceManager...");
        BalanceManager(balanceManager).setAuthorizedOperator(scaleXRouter, true);
        console.log("[OK] ScaleXRouter authorized");

        vm.stopBroadcast();

        console.log("Authorization complete!");
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        string memory searchKey = string(abi.encodePacked('"', key, '":"'));
        bytes memory jsonBytes = bytes(json);
        bytes memory searchBytes = bytes(searchKey);

        for (uint256 i = 0; i < jsonBytes.length - searchBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < searchBytes.length; j++) {
                if (jsonBytes[i + j] != searchBytes[j]) {
                    found = false;
                    break;
                }
            }

            if (found) {
                uint256 start = i + searchBytes.length;
                uint256 end = start;

                while (end < jsonBytes.length && jsonBytes[end] != '"') {
                    end++;
                }

                bytes memory addrBytes = new bytes(end - start);
                for (uint256 k = 0; k < end - start; k++) {
                    addrBytes[k] = jsonBytes[start + k];
                }

                return _parseAddress(string(addrBytes));
            }
        }

        return address(0);
    }

    function _parseAddress(string memory str) internal pure returns (address) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 42, "Invalid address length");
        require(strBytes[0] == '0' && strBytes[1] == 'x', "Invalid address prefix");

        uint160 result = 0;
        for (uint256 i = 2; i < 42; i++) {
            result *= 16;
            uint8 digit = uint8(strBytes[i]);

            if (digit >= 48 && digit <= 57) {
                result += digit - 48;
            } else if (digit >= 65 && digit <= 70) {
                result += digit - 55;
            } else if (digit >= 97 && digit <= 102) {
                result += digit - 87;
            } else {
                revert("Invalid hex character");
            }
        }

        return address(result);
    }
}
