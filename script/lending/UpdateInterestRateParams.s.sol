// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {LendingManager} from "../../src/yield/LendingManager.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title UpdateInterestRateParams
 * @dev Update interest rate parameters for lending markets
 *
 * Environment Variables:
 *   PRIVATE_KEY - Owner private key
 *   TOKENS - Comma-separated list of tokens (default: ALL)
 *
 *   For each token (TOKEN = IDRX, WETH, WBTC, GOLD, SILVER, GOOGL, NVDA, AAPL, MNT):
 *   - TOKEN_BASE_RATE - Base borrow rate in bps (e.g., 200 = 2%)
 *   - TOKEN_OPTIMAL_UTIL - Optimal utilization in bps (e.g., 8000 = 80%)
 *   - TOKEN_RATE_SLOPE1 - Rate slope before kink in bps (e.g., 1000 = 10%)
 *   - TOKEN_RATE_SLOPE2 - Rate slope after kink in bps (e.g., 5000 = 50%)
 *
 * Usage:
 *   PRIVATE_KEY=0x... forge script script/lending/UpdateInterestRateParams.s.sol:UpdateInterestRateParams \
 *     --rpc-url http://127.0.0.1:8545 --broadcast
 */
contract UpdateInterestRateParams is Script, DeployHelpers {

    LendingManager public lendingManager;

    // Token configuration
    struct TokenConfig {
        string symbol;
        address tokenAddress;
        uint256 baseRate;
        uint256 optimalUtilization;
        uint256 rateSlope1;
        uint256 rateSlope2;
    }

    // List of tokens to update
    string[] public selectedTokens;

    function run() external {
        loadDeployments();
        uint256 deployerPrivateKey = getDeployerKey();

        console.log("=== UPDATING LENDING INTEREST RATE PARAMETERS ===");
        console.log("Owner:", vm.addr(deployerPrivateKey));
        console.log("");

        _loadContracts();
        _parseSelectedTokens();

        vm.startBroadcast(deployerPrivateKey);

        _updateInterestRateParameters();

        vm.stopBroadcast();

        console.log("\n=== INTEREST RATE PARAMETER UPDATE COMPLETE ===");
    }

    function _loadContracts() internal {
        console.log("=== Loading Contracts ===");

        require(deployed["LendingManager"].isSet, "LendingManager not found");
        lendingManager = LendingManager(deployed["LendingManager"].addr);

        console.log("LendingManager:", address(lendingManager));
        console.log("");
    }

    function _parseSelectedTokens() internal {
        string memory tokensEnv = vm.envOr("TOKENS", string("ALL"));

        if (keccak256(bytes(tokensEnv)) == keccak256(bytes("ALL"))) {
            // Add all supported tokens
            selectedTokens.push("IDRX");
            selectedTokens.push("WETH");
            selectedTokens.push("WBTC");
            selectedTokens.push("GOLD");
            selectedTokens.push("SILVER");
            selectedTokens.push("GOOGL");
            selectedTokens.push("NVDA");
            selectedTokens.push("AAPL");
            selectedTokens.push("MNT");
        } else {
            // Parse comma-separated list
            // Note: Solidity doesn't have great string parsing, so we'll just try all tokens
            // and check if they're in the TOKENS env var using vm.envOr
            string[9] memory allTokens = ["IDRX", "WETH", "WBTC", "GOLD", "SILVER", "GOOGL", "NVDA", "AAPL", "MNT"];

            for (uint i = 0; i < allTokens.length; i++) {
                // Try to get token-specific env var - if it exists, token is selected
                string memory baseRateKey = string.concat(allTokens[i], "_BASE_RATE");
                try vm.envUint(baseRateKey) returns (uint256) {
                    selectedTokens.push(allTokens[i]);
                } catch {
                    // Token not explicitly configured, skip
                }
            }

            // If no tokens were explicitly selected with env vars, use all
            if (selectedTokens.length == 0) {
                for (uint i = 0; i < allTokens.length; i++) {
                    selectedTokens.push(allTokens[i]);
                }
            }
        }

        console.log("Selected tokens for update:", selectedTokens.length);
        for (uint i = 0; i < selectedTokens.length; i++) {
            console.log("-", selectedTokens[i]);
        }
        console.log("");
    }

    function _updateInterestRateParameters() internal {
        console.log("=== Updating Interest Rate Parameters ===");

        for (uint i = 0; i < selectedTokens.length; i++) {
            string memory tokenSymbol = selectedTokens[i];

            // Get token address from deployments
            if (!deployed[tokenSymbol].isSet) {
                console.log("[SKIP]", tokenSymbol, "- not found in deployments");
                continue;
            }

            address tokenAddress = deployed[tokenSymbol].addr;

            // Get interest rate parameters from environment variables
            TokenConfig memory config = _getTokenConfig(tokenSymbol, tokenAddress);

            // Set interest rate parameters
            try lendingManager.setInterestRateParams(
                config.tokenAddress,
                config.baseRate,
                config.optimalUtilization,
                config.rateSlope1,
                config.rateSlope2
            ) {
                console.log("[OK] Interest rate parameters set for", tokenSymbol);
                console.log("     Token:", config.tokenAddress);
                console.log("     Base Rate:", _formatBps(config.baseRate));
                console.log("     Optimal Utilization:", _formatBps(config.optimalUtilization));
                console.log("     Rate Slope 1:", _formatBps(config.rateSlope1));
                console.log("     Rate Slope 2:", _formatBps(config.rateSlope2));
            } catch Error(string memory reason) {
                console.log("[ERROR]", tokenSymbol, "- Failed:", reason);
            } catch {
                console.log("[ERROR]", tokenSymbol, "- Failed with unknown error");
            }

            console.log("");
        }
    }

    function _getTokenConfig(string memory tokenSymbol, address tokenAddress) internal view returns (TokenConfig memory) {
        // Build environment variable keys
        string memory baseRateKey = string.concat(tokenSymbol, "_BASE_RATE");
        string memory optimalUtilKey = string.concat(tokenSymbol, "_OPTIMAL_UTIL");
        string memory slope1Key = string.concat(tokenSymbol, "_RATE_SLOPE1");
        string memory slope2Key = string.concat(tokenSymbol, "_RATE_SLOPE2");

        // Get values from environment variables with defaults
        uint256 baseRate = vm.envOr(baseRateKey, uint256(300));           // 3% default
        uint256 optimalUtil = vm.envOr(optimalUtilKey, uint256(8000));    // 80% default
        uint256 rateSlope1 = vm.envOr(slope1Key, uint256(1000));          // 10% default
        uint256 rateSlope2 = vm.envOr(slope2Key, uint256(5000));          // 50% default

        return TokenConfig({
            symbol: tokenSymbol,
            tokenAddress: tokenAddress,
            baseRate: baseRate,
            optimalUtilization: optimalUtil,
            rateSlope1: rateSlope1,
            rateSlope2: rateSlope2
        });
    }

    function _formatBps(uint256 bps) internal pure returns (string memory) {
        // Convert basis points to percentage string
        uint256 whole = bps / 100;
        uint256 decimal = bps % 100;

        if (decimal == 0) {
            return string.concat(vm.toString(whole), "%");
        } else if (decimal < 10) {
            return string.concat(vm.toString(whole), ".0", vm.toString(decimal), "%");
        } else {
            return string.concat(vm.toString(whole), ".", vm.toString(decimal), "%");
        }
    }
}
