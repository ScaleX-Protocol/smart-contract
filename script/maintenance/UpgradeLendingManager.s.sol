// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {LendingManager} from "../../src/yield/LendingManager.sol";

/**
 * @title UpgradeLendingManager
 * @dev Upgrade LendingManager to latest implementation via Beacon pattern
 */
contract UpgradeLendingManager is Script {
    // EIP1967 beacon storage slot
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address lendingManagerProxy = vm.envAddress("LENDING_MANAGER_PROXY");

        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== LendingManager Upgrade ===");
        console.log("Deployer:", deployer);
        console.log("LendingManager Proxy:", lendingManagerProxy);

        // Get beacon address from proxy storage
        address beaconAddress = _getBeacon(lendingManagerProxy);
        console.log("Beacon Address:", beaconAddress);

        // Get current implementation
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);
        address currentImpl = beacon.implementation();
        console.log("Current Implementation:", currentImpl);

        // Verify ownership
        address beaconOwner = beacon.owner();
        console.log("Beacon Owner:", beaconOwner);
        require(beaconOwner == deployer, "Not beacon owner");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        console.log("\nDeploying new LendingManager implementation...");
        LendingManager newImpl = new LendingManager();
        console.log("New Implementation:", address(newImpl));

        // Upgrade beacon
        console.log("\nUpgrading beacon...");
        beacon.upgradeTo(address(newImpl));

        vm.stopBroadcast();

        // Verify upgrade
        address verifiedImpl = beacon.implementation();
        console.log("\n=== Verification ===");
        console.log("Implementation after upgrade:", verifiedImpl);

        if (verifiedImpl == address(newImpl)) {
            console.log("\n[SUCCESS] LendingManager upgraded successfully!");
        } else {
            console.log("\n[ERROR] Upgrade verification failed!");
        }
    }

    function _getBeacon(address proxy) internal view returns (address) {
        bytes32 data = vm.load(proxy, BEACON_SLOT);
        return address(uint160(uint256(data)));
    }
}
