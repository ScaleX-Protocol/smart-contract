// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/core/OrderBook.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeOrderBook is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address beaconAddress = vm.envAddress("ORDERBOOK_BEACON");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new OrderBook implementation
        OrderBook newImplementation = new OrderBook();
        console.log("New OrderBook implementation deployed at:", address(newImplementation));

        // Upgrade beacon to point to new implementation
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);
        beacon.upgradeTo(address(newImplementation));
        console.log("Beacon upgraded to new implementation");

        vm.stopBroadcast();
    }
}
