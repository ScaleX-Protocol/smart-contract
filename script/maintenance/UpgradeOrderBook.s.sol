// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {OrderBook} from "../../src/core/OrderBook.sol";

/**
 * @title UpgradeOrderBook
 * @dev Upgrade OrderBook to latest implementation via Beacon pattern
 *
 * Usage:
 *   PRIVATE_KEY=<your_key> \
 *   ORDERBOOK_BEACON=<beacon_address> \
 *   RPC_URL=<rpc_url> \
 *   forge script script/maintenance/UpgradeOrderBook.s.sol:UpgradeOrderBook --rpc-url $RPC_URL --broadcast
 */
contract UpgradeOrderBook is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address orderBookBeacon = vm.envAddress("ORDERBOOK_BEACON");

        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== OrderBook Upgrade ===");
        console.log("Deployer:", deployer);
        console.log("OrderBook Beacon:", orderBookBeacon);

        // Get current implementation
        UpgradeableBeacon beacon = UpgradeableBeacon(orderBookBeacon);
        address currentImpl = beacon.implementation();
        console.log("Current Implementation:", currentImpl);

        // Verify ownership
        address beaconOwner = beacon.owner();
        console.log("Beacon Owner:", beaconOwner);
        require(beaconOwner == deployer, "Not beacon owner");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        console.log("\nDeploying new OrderBook implementation...");
        OrderBook newImpl = new OrderBook();
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
            console.log("\n[SUCCESS] OrderBook upgraded successfully!");
            console.log("All OrderBook proxies using this beacon are now updated.");
        } else {
            console.log("\n[ERROR] Upgrade verification failed!");
        }
    }
}
