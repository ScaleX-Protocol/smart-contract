// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {OrderBook} from "@scalexcore/OrderBook.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title DeployAndUpgradeOrderBook
 * @notice Deploys new OrderBook implementation and upgrades beacon
 */
contract DeployAndUpgradeOrderBook is Script {
    function run() external {
        console.log("=== DEPLOY & UPGRADE ORDERBOOK ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("");

        // OrderBook beacon address
        address beaconAddr = 0xF756457e5CB37EB69A36cb62326Ae0FeE20f0765;

        vm.startBroadcast(deployerPrivateKey);

        console.log("Step 1: Deploying new OrderBook implementation...");
        OrderBook newOrderBookImpl = new OrderBook();
        console.log("[OK] New OrderBook implementation:", address(newOrderBookImpl));
        console.log("");

        console.log("Step 2: Upgrading OrderBook beacon...");
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddr);
        beacon.upgradeTo(address(newOrderBookImpl));
        console.log("[OK] OrderBook beacon upgraded!");

        vm.stopBroadcast();

        console.log("");
        console.log("[SUCCESS] OrderBook deployed and beacon upgraded!");
        console.log("New implementation:", address(newOrderBookImpl));
    }
}
