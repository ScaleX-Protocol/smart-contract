// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {LendingManager} from "../src/yield/LendingManager.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title UpgradeLendingManager
 * @notice Upgrades LendingManager to use simplified price queries with Oracle auto-fallback
 */
contract UpgradeLendingManager is Script {
    function run() external {
        console.log("=== LENDING MANAGER UPGRADE: Simplified Price Queries ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        // Load addresses
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");

        string memory json = vm.readFile(deploymentPath);
        address lendingManagerProxy = vm.parseJsonAddress(json, ".LendingManager");

        console.log("LendingManager Proxy:", lendingManagerProxy);
        console.log("");

        // Get beacon address (ERC-1967 beacon slot)
        bytes32 beaconSlot = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
        address beaconAddress = address(uint160(uint256(vm.load(lendingManagerProxy, beaconSlot))));

        console.log("LendingManager Beacon:", beaconAddress);
        console.log("");

        // Get current implementation
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);
        address currentImpl = beacon.implementation();
        console.log("Current Implementation:", currentImpl);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new LendingManager implementation
        console.log("Step 1: Deploying new LendingManager implementation...");
        LendingManager newImpl = new LendingManager();
        console.log("[OK] New implementation deployed:", address(newImpl));
        console.log("");

        // Upgrade beacon
        console.log("Step 2: Upgrading beacon to new implementation...");
        beacon.upgradeTo(address(newImpl));
        console.log("[OK] Beacon upgraded");
        console.log("");

        vm.stopBroadcast();

        // Verification
        address newImplAddress = beacon.implementation();

        console.log("=== VERIFICATION ===");
        console.log("Old Implementation:", currentImpl);
        console.log("New Implementation:", newImplAddress);
        console.log("");

        require(newImplAddress == address(newImpl), "Upgrade failed: implementation mismatch");

        console.log("[SUCCESS] LendingManager upgraded!");
        console.log("");
        console.log("Key Changes:");
        console.log("- Removed manual underlying -> synthetic token conversion");
        console.log("- Now passes underlying tokens directly to Oracle");
        console.log("- Oracle handles conversion automatically via factory fallback");
        console.log("- Health factor calculations will now use correct prices");
        console.log("");
    }
}
