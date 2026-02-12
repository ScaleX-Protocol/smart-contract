// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title UpgradeOrderBookBeacon
 * @notice Upgrades OrderBook beacon to new implementation
 */
contract UpgradeOrderBookBeacon is Script {
    function run() external {
        console.log("=== UPGRADE ORDERBOOK BEACON ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("");

        // OrderBook beacon address
        address beaconAddr = 0xF756457e5CB37EB69A36cb62326Ae0FeE20f0765;
        address newImpl = 0xDf48572279F835a331E503A9a4a369eA029E9744;

        console.log("OrderBook Beacon:", beaconAddr);
        console.log("New Implementation:", newImpl);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddr);
        beacon.upgradeTo(newImpl);

        console.log("[OK] OrderBook beacon upgraded!");

        vm.stopBroadcast();
    }
}
