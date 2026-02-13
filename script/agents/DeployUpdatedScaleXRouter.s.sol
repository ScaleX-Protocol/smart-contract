// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/core/ScaleXRouter.sol";

contract DeployUpdatedScaleXRouter is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Load deployment addresses
        string memory json = vm.readFile("deployments/84532.json");
        address scaleXRouter = vm.parseJsonAddress(json, ".ScaleXRouter");

        console.log("=== Deploy Updated ScaleXRouter Implementation ===");
        console.log("ScaleXRouter Proxy:", scaleXRouter);
        console.log("");

        // Get current implementation to find beacon
        console.log("Step 1: Finding beacon address...");

        // ScaleXRouter is a BeaconProxy, we need to find its beacon
        // Try reading the beacon address from storage slot
        bytes32 beaconSlot = vm.load(scaleXRouter, bytes32(uint256(0)));
        address beacon = address(uint160(uint256(beaconSlot)));

        console.log("Beacon address:", beacon);
        console.log("");

        vm.startBroadcast(deployerKey);

        // Deploy new ScaleXRouter implementation
        console.log("Step 2: Deploying new ScaleXRouter implementation...");
        ScaleXRouter newImpl = new ScaleXRouter();
        console.log("New implementation:", address(newImpl));
        console.log("");

        // Upgrade beacon
        console.log("Step 3: Upgrading beacon...");
        (bool success, ) = beacon.call(
            abi.encodeWithSignature("upgradeTo(address)", address(newImpl))
        );
        require(success, "Beacon upgrade failed");
        console.log("Beacon upgraded successfully");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Update Complete ===");
        console.log("ScaleXRouter now supports updated OrderBook interface");
    }
}
