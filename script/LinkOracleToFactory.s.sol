// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/core/Oracle.sol";
import "../src/core/SyntheticTokenFactory.sol";

/**
 * @title LinkOracleToFactory
 * @notice Script to link Oracle to SyntheticTokenFactory for automatic underlying → synthetic token resolution
 * @dev Run this after deploying both Oracle and SyntheticTokenFactory
 */
contract LinkOracleToFactory is Script {
    function run() external {
        // Load environment variables
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        address factoryAddress = vm.envAddress("SYNTHETIC_TOKEN_FACTORY_ADDRESS");

        console.log("=== Linking Oracle to SyntheticTokenFactory ===");
        console.log("Oracle:", oracleAddress);
        console.log("SyntheticTokenFactory:", factoryAddress);

        // Start broadcasting transactions
        vm.startBroadcast();

        // Get Oracle contract
        Oracle oracle = Oracle(oracleAddress);

        // Link factory to oracle
        oracle.setSyntheticTokenFactory(factoryAddress);

        vm.stopBroadcast();

        console.log("\n=== Link Complete ===");
        console.log("Oracle.syntheticTokenFactory() now returns:", address(oracle.syntheticTokenFactory()));
    }
}
