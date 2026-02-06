// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PoolManager} from "../../src/core/PoolManager.sol";

/**
 * @title GetOrderBookBeacon
 * @dev Get OrderBook Beacon address from PoolManager
 */
contract GetOrderBookBeacon is Script {
    function run() external view {
        address poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");

        console.log("PoolManager:", poolManager);

        // Access storage directly
        bytes32 storageLocation = 0x3ba269338da0272c8c8ec2d2a5422e5b03f10c20a7fc80782a7f7c3e1b189600;

        // orderBookBeacon is at offset 2 in the storage struct
        // balanceManager at slot + 0
        // router at slot + 1
        // orderBookBeacon at slot + 2
        bytes32 beaconSlot = bytes32(uint256(storageLocation) + 2);

        bytes32 beaconAddress = vm.load(poolManager, beaconSlot);
        address orderBookBeacon = address(uint160(uint256(beaconAddress)));

        console.log("OrderBook Beacon:", orderBookBeacon);
    }
}
