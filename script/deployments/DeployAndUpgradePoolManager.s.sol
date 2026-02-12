// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PoolManager} from "@scalexcore/PoolManager.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title DeployAndUpgradePoolManager
 * @notice Deploys new PoolManager implementation and upgrades beacon
 */
contract DeployAndUpgradePoolManager is Script {
    function run() external {
        console.log("=== DEPLOY & UPGRADE POOLMANAGER ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("");

        // PoolManager beacon address
        address beaconAddr = 0x2122F7Afef5D7E921482C0c55d4F975c50577D90;

        vm.startBroadcast(deployerPrivateKey);

        console.log("Step 1: Deploying new PoolManager implementation...");
        PoolManager newPoolManagerImpl = new PoolManager();
        console.log("[OK] New PoolManager implementation:", address(newPoolManagerImpl));
        console.log("");

        console.log("Step 2: Upgrading PoolManager beacon...");
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddr);
        beacon.upgradeTo(address(newPoolManagerImpl));
        console.log("[OK] PoolManager beacon upgraded!");

        vm.stopBroadcast();

        console.log("");
        console.log("[SUCCESS] PoolManager deployed and beacon upgraded!");
        console.log("New implementation:", address(newPoolManagerImpl));
    }
}
