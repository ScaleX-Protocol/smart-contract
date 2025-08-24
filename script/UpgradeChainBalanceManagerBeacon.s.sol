// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../src/core/ChainBalanceManager.sol";

contract UpgradeChainBalanceManagerBeacon is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPGRADE CHAIN BALANCE MANAGER BEACON ==========");
        console.log("Upgrade beacon to new implementation with updateLocalDomain");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        // Get network-specific addresses
        address beaconAddress;
        address newImplementation;
        string memory networkName;
        
        if (block.chainid == 421614) {
            beaconAddress = 0xB7b9994Cba82150b874828bEdA2871E9d189b04c;
            newImplementation = 0xf70BF960B4546faF96d24afddbB627F5130A6C10;
            networkName = "ARBITRUM SEPOLIA";
        } else if (block.chainid == 11155931) {
            // Read from deployment file for Rise
            string memory riseData = vm.readFile("deployments/rise-sepolia.json");
            beaconAddress = vm.parseJsonAddress(riseData, ".contracts.BEACON_CHAINBALANCEMANAGER");
            newImplementation = 0xcA4dFb2A848b551Baee6410fB75270B2815BFDA8;
            networkName = "RISE SEPOLIA";
        } else {
            console.log("ERROR: This script is for Arbitrum Sepolia (421614) or Rise Sepolia (11155931) only");
            return;
        }
        
        console.log("Target network:", networkName);
        console.log("Beacon address:", beaconAddress);
        console.log("New implementation:", newImplementation);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);
        
        console.log("=== CHECK CURRENT BEACON STATE ===");
        
        address currentImpl = beacon.implementation();
        address beaconOwner = beacon.owner();
        
        console.log("Current implementation:", currentImpl);
        console.log("Beacon owner:", beaconOwner);
        console.log("Deployer:", deployer);
        console.log("Is deployer owner?", beaconOwner == deployer);
        console.log("");
        
        if (beaconOwner != deployer) {
            console.log("ERROR: Deployer is not beacon owner, cannot upgrade");
            vm.stopBroadcast();
            return;
        }
        
        if (currentImpl == newImplementation) {
            console.log("Already using new implementation");
        } else {
            console.log("=== UPGRADING BEACON ===");
            console.log("From:", currentImpl);
            console.log("To:", newImplementation);
            
            try beacon.upgradeTo(newImplementation) {
                console.log("SUCCESS: Beacon upgraded!");
            } catch Error(string memory reason) {
                console.log("FAILED: Beacon upgrade failed -", reason);
                vm.stopBroadcast();
                return;
            }
        }
        
        console.log("");
        console.log("=== VERIFY UPGRADE ===");
        
        address finalImpl = beacon.implementation();
        console.log("Final implementation:", finalImpl);
        
        if (finalImpl == newImplementation) {
            console.log("SUCCESS: Upgrade verified!");
        } else {
            console.log("WARNING: Implementation mismatch after upgrade");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== UPGRADE COMPLETE ===");
        console.log("Network:", networkName);
        console.log("Beacon now points to new implementation with updateLocalDomain function");
        console.log("Next: Call updateLocalDomain to fix domain issues");
        
        console.log("========== BEACON UPGRADE COMPLETE ==========");
    }
}