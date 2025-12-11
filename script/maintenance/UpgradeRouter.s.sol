// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ScaleXRouter} from "../../src/core/ScaleXRouter.sol";

/**
 * @title UpgradeRouter
 * @dev Upgrade ScaleXRouter to latest implementation via Beacon pattern
 *
 * Usage:
 *   PRIVATE_KEY=<your_key> \
 *   ROUTER_PROXY=<proxy_address> \
 *   RPC_URL=<rpc_url> \
 *   forge script script/maintenance/UpgradeRouter.s.sol:UpgradeRouter --rpc-url $RPC_URL --broadcast
 */
contract UpgradeRouter is Script {
    // EIP1967 beacon storage slot
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address routerProxy = vm.envAddress("ROUTER_PROXY");

        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== ScaleXRouter Upgrade ===");
        console.log("Deployer:", deployer);
        console.log("Router Proxy:", routerProxy);

        // Get beacon address from proxy storage
        address beaconAddress = _getBeacon(routerProxy);
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
        console.log("\nDeploying new ScaleXRouter implementation...");
        ScaleXRouter newImpl = new ScaleXRouter();
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
            console.log("\n[SUCCESS] ScaleXRouter upgraded successfully!");
            console.log("All proxies using this beacon are now updated.");
        } else {
            console.log("\n[ERROR] Upgrade verification failed!");
        }
    }

    function _getBeacon(address proxy) internal view returns (address) {
        bytes32 data = vm.load(proxy, BEACON_SLOT);
        return address(uint160(uint256(data)));
    }
}
