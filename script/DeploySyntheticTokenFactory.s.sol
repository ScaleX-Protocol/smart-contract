// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {SyntheticTokenFactory} from "../src/core/SyntheticTokenFactory.sol";
import {TokenRegistry} from "../src/core/TokenRegistry.sol";

/**
 * @title DeploySyntheticTokenFactory
 * @dev Script to deploy SyntheticTokenFactory with Beacon Proxy pattern
 */
contract DeploySyntheticTokenFactory is Script {
    
    function run() external {
        address owner = msg.sender;
        
        // These should be set as environment variables or script parameters
        address tokenRegistryAddress = vm.envAddress("TOKEN_REGISTRY_ADDRESS");
        address bridgeReceiverAddress = vm.envOr("BRIDGE_RECEIVER_ADDRESS", owner); // Default to owner for testing
        
        vm.startBroadcast();
        
        console.log("Deploying SyntheticTokenFactory...");
        console.log("Owner:", owner);
        console.log("TokenRegistry:", tokenRegistryAddress);
        console.log("BridgeReceiver:", bridgeReceiverAddress);
        
        // Deploy implementation
        address implementation = address(new SyntheticTokenFactory());
        console.log("Implementation deployed at:", implementation);
        
        // Deploy beacon
        UpgradeableBeacon beacon = new UpgradeableBeacon(implementation, owner);
        console.log("Beacon deployed at:", address(beacon));
        
        // Deploy proxy
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeCall(SyntheticTokenFactory.initialize, (
                owner,
                tokenRegistryAddress,
                bridgeReceiverAddress
            ))
        );
        console.log("Proxy deployed at:", address(proxy));
        
        vm.stopBroadcast();
        
        // Verify deployment
        SyntheticTokenFactory factory = SyntheticTokenFactory(address(proxy));
        console.log("Factory owner:", factory.owner());
        console.log("Factory TokenRegistry:", factory.getTokenRegistry());
        console.log("Factory BridgeReceiver:", factory.getBridgeReceiver());
        
        console.log("\nSyntheticTokenFactory deployment complete!");
        console.log("Next step: Transfer TokenRegistry ownership to factory for automated registration");
    }
}