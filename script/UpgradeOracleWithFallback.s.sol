// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Oracle} from "@scalexcore/Oracle.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title UpgradeOracleWithFallback
 * @notice Upgrades Oracle to add automatic underlying → synthetic token price fallback
 */
contract UpgradeOracleWithFallback is Script {
    function run() external {
        console.log("=== ORACLE UPGRADE: Auto-Fallback to Synthetic Token Prices ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        // Load addresses from deployment file
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");

        string memory json = vm.readFile(deploymentPath);
        address oracleProxy = vm.parseJsonAddress(json, ".Oracle");
        address syntheticTokenFactory = vm.parseJsonAddress(json, ".SyntheticTokenFactory");

        console.log("Oracle Proxy:", oracleProxy);
        console.log("SyntheticTokenFactory:", syntheticTokenFactory);
        console.log("");

        // Get beacon address from proxy (ERC-1967 beacon slot)
        bytes32 beaconSlot = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
        address beaconAddress = address(uint160(uint256(vm.load(oracleProxy, beaconSlot))));

        console.log("Oracle Beacon:", beaconAddress);
        console.log("");

        // Get current implementation
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);
        address currentImpl = beacon.implementation();
        console.log("Current Implementation:", currentImpl);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new Oracle implementation
        console.log("Step 1: Deploying new Oracle implementation with fallback support...");
        Oracle newOracleImpl = new Oracle();
        console.log("[OK] New implementation deployed:", address(newOracleImpl));
        console.log("");

        // Step 2: Upgrade beacon
        console.log("Step 2: Upgrading beacon to new implementation...");
        beacon.upgradeTo(address(newOracleImpl));
        console.log("[OK] Beacon upgraded");
        console.log("");

        // Step 3: Link Oracle to SyntheticTokenFactory
        console.log("Step 3: Linking Oracle to SyntheticTokenFactory...");
        Oracle oracle = Oracle(oracleProxy);
        oracle.setSyntheticTokenFactory(syntheticTokenFactory);
        console.log("[OK] Factory linked");
        console.log("");

        vm.stopBroadcast();

        // Verification
        address newImpl = beacon.implementation();
        address configuredFactory = address(oracle.syntheticTokenFactory());

        console.log("=== VERIFICATION ===");
        console.log("Old Implementation:", currentImpl);
        console.log("New Implementation:", newImpl);
        console.log("Configured Factory:", configuredFactory);
        console.log("");

        require(newImpl == address(newOracleImpl), "Upgrade failed: implementation mismatch");
        require(configuredFactory == syntheticTokenFactory, "Factory link failed");

        console.log("[SUCCESS] Oracle upgraded and linked!");
        console.log("");
        console.log("Key Features:");
        console.log("- Queries for underlying tokens now automatically return synthetic token prices");
        console.log("- Example: oracle.getSpotPrice(underlying_WETH) returns sxWETH price");
        console.log("- No more manual conversion needed in LendingManager");
        console.log("- Health factor calculations will now use correct prices");
        console.log("");
    }
}
