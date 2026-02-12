// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @title VerifyAgentConfiguration
 * @notice Comprehensive verification of AI Agent Infrastructure configuration
 * @dev Checks all critical authorizations and configurations for ERC-8004 agent system
 */
contract VerifyAgentConfiguration is Script {
    // ANSI color codes for terminal output
    string constant GREEN = "\x1b[32m";
    string constant RED = "\x1b[31m";
    string constant YELLOW = "\x1b[33m";
    string constant BLUE = "\x1b[34m";
    string constant RESET = "\x1b[0m";

    struct VerificationResult {
        bool success;
        uint256 passedChecks;
        uint256 totalChecks;
        uint256 warnings;
    }

    function run() external view returns (VerificationResult memory result) {
        console.log("=== AI AGENT CONFIGURATION VERIFICATION ===");
        console.log("");

        // Load deployment addresses
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");

        if (!vm.exists(deploymentPath)) {
            console.log(RED, "[FAIL] Deployment file not found", RESET);
            return VerificationResult(false, 0, 1, 0);
        }

        string memory json = vm.readFile(deploymentPath);

        // Extract addresses
        address agentRouter = _extractAddress(json, "AgentRouter");
        address policyFactory = _extractAddress(json, "PolicyFactory");
        address identityRegistry = _extractAddress(json, "IdentityRegistry");
        address reputationRegistry = _extractAddress(json, "ReputationRegistry");
        address validationRegistry = _extractAddress(json, "ValidationRegistry");
        address balanceManager = _extractAddress(json, "BalanceManager");
        address poolManager = _extractAddress(json, "PoolManager");

        result.totalChecks = 0;
        result.passedChecks = 0;
        result.warnings = 0;

        console.log(BLUE, "Deployment Addresses:", RESET);
        console.log("  AgentRouter:", agentRouter);
        console.log("  PolicyFactory:", policyFactory);
        console.log("  IdentityRegistry:", identityRegistry);
        console.log("  ReputationRegistry:", reputationRegistry);
        console.log("  ValidationRegistry:", validationRegistry);
        console.log("  BalanceManager:", balanceManager);
        console.log("  PoolManager:", poolManager);
        console.log("");

        // Verify Phase 5 deployments exist
        console.log(BLUE, "=== Phase 5 Deployment Check ===", RESET);
        result.totalChecks++;
        if (
            agentRouter != address(0) && policyFactory != address(0) && identityRegistry != address(0)
                && reputationRegistry != address(0) && validationRegistry != address(0)
        ) {
            console.log(GREEN, "[PASS] All Phase 5 contracts deployed", RESET);
            result.passedChecks++;
        } else {
            console.log(RED, "[FAIL] Some Phase 5 contracts missing", RESET);
        }
        console.log("");

        // Check 1: AgentRouter authorization in BalanceManager
        console.log(BLUE, "=== BalanceManager Authorization ===", RESET);
        result.totalChecks++;
        bool bmAuth = _checkAuthorization(
            balanceManager, "isAuthorizedOperator(address)", agentRouter, "BalanceManager -> AgentRouter"
        );
        if (bmAuth) {
            result.passedChecks++;
        }
        console.log("");

        // Check 2: AgentRouter authorization in PolicyFactory
        console.log(BLUE, "=== PolicyFactory Authorization ===", RESET);
        result.totalChecks++;
        bool pfAuth =
            _checkAuthorization(policyFactory, "authorizedRouters(address)", agentRouter, "PolicyFactory -> AgentRouter");
        if (pfAuth) {
            result.passedChecks++;
        }
        console.log("");

        // Check 3: AgentRouter authorization on all OrderBooks
        console.log(BLUE, "=== OrderBook Authorizations ===", RESET);
        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");

        string[] memory pools = new string[](8);
        pools[0] = string.concat("WETH_", quoteSymbol, "_Pool");
        pools[1] = string.concat("WBTC_", quoteSymbol, "_Pool");
        pools[2] = string.concat("GOLD_", quoteSymbol, "_Pool");
        pools[3] = string.concat("SILVER_", quoteSymbol, "_Pool");
        pools[4] = string.concat("GOOGLE_", quoteSymbol, "_Pool");
        pools[5] = string.concat("NVIDIA_", quoteSymbol, "_Pool");
        pools[6] = string.concat("MNT_", quoteSymbol, "_Pool");
        pools[7] = string.concat("APPLE_", quoteSymbol, "_Pool");

        string[] memory poolNames = new string[](8);
        poolNames[0] = "WETH";
        poolNames[1] = "WBTC";
        poolNames[2] = "GOLD";
        poolNames[3] = "SILVER";
        poolNames[4] = "GOOGLE";
        poolNames[5] = "NVIDIA";
        poolNames[6] = "MNT";
        poolNames[7] = "APPLE";

        uint256 poolAuthCount = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            address poolAddr = _extractAddress(json, pools[i]);
            if (poolAddr == address(0)) {
                console.log(YELLOW, string.concat("  [SKIP] ", poolNames[i], " pool not deployed"), RESET);
                continue;
            }

            result.totalChecks++;
            bool authorized = _checkAuthorization(
                poolAddr,
                "isAuthorizedRouter(address)",
                agentRouter,
                string.concat(poolNames[i], " OrderBook -> AgentRouter")
            );
            if (authorized) {
                result.passedChecks++;
                poolAuthCount++;
            }
        }
        console.log("");

        // Check 4: ChainlinkMetricsConsumer (optional)
        console.log(BLUE, "=== Optional Components ===", RESET);
        try vm.envAddress("CHAINLINK_METRICS_CONSUMER") returns (address metricsConsumer) {
            if (metricsConsumer != address(0)) {
                console.log(GREEN, "[INFO] ChainlinkMetricsConsumer configured:", vm.toString(metricsConsumer), RESET);
            }
        } catch {
            console.log(
                YELLOW, "[WARN] ChainlinkMetricsConsumer not configured (optional - advanced metrics)", RESET
            );
            result.warnings++;
        }
        console.log("");

        // Check 5: Verify AgentRouter can access core contracts
        console.log(BLUE, "=== AgentRouter Integration Check ===", RESET);
        result.totalChecks++;
        address arPoolManager = _getImmutableAddress(agentRouter, "poolManager()");
        address arBalanceManager = _getImmutableAddress(agentRouter, "balanceManager()");
        address arLendingManager = _getImmutableAddress(agentRouter, "lendingManager()");
        address arPolicyFactory = _getImmutableAddress(agentRouter, "policyFactory()");

        if (
            arPoolManager == poolManager && arBalanceManager == balanceManager && arPolicyFactory == policyFactory
                && arLendingManager != address(0)
        ) {
            console.log(GREEN, "[PASS] AgentRouter integrated with all core contracts", RESET);
            console.log("  PoolManager:", arPoolManager);
            console.log("  BalanceManager:", arBalanceManager);
            console.log("  LendingManager:", arLendingManager);
            console.log("  PolicyFactory:", arPolicyFactory);
            result.passedChecks++;
        } else {
            console.log(RED, "[FAIL] AgentRouter integration mismatch", RESET);
        }
        console.log("");

        // Final summary
        console.log(BLUE, "=== VERIFICATION SUMMARY ===", RESET);
        console.log("Total Checks:", result.totalChecks);
        console.log("Passed:", result.passedChecks);
        console.log("Failed:", result.totalChecks - result.passedChecks);
        console.log("Warnings:", result.warnings);
        console.log("");

        if (result.passedChecks == result.totalChecks) {
            console.log(GREEN, "[SUCCESS] Agent configuration is FULLY OPERATIONAL! \xE2\x9C\x94", RESET);
            result.success = true;
        } else {
            console.log(RED, "[FAIL] Agent configuration has issues that need fixing", RESET);
            result.success = false;
        }

        return result;
    }

    function _checkAuthorization(address target, string memory signature, address authorized, string memory description)
        internal
        view
        returns (bool)
    {
        bytes memory callData = abi.encodeWithSignature(signature, authorized);
        (bool success, bytes memory returnData) = target.staticcall(callData);

        if (!success || returnData.length == 0) {
            console.log(RED, string.concat("  [FAIL] ", description, " - call failed"), RESET);
            return false;
        }

        bool isAuthorized = abi.decode(returnData, (bool));
        if (isAuthorized) {
            console.log(GREEN, string.concat("  [PASS] ", description, " \xE2\x9C\x94"), RESET);
            return true;
        } else {
            console.log(RED, string.concat("  [FAIL] ", description, " - not authorized"), RESET);
            return false;
        }
    }

    function _getImmutableAddress(address target, string memory signature) internal view returns (address) {
        bytes memory callData = abi.encodeWithSignature(signature);
        (bool success, bytes memory returnData) = target.staticcall(callData);

        if (!success || returnData.length == 0) {
            return address(0);
        }

        return abi.decode(returnData, (address));
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes.concat('"', bytes(key), '": "');

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
