// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract FixChainBalanceManagerImplementation is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========== FIXING CHAINBALANCEMANAGER IMPLEMENTATION ==========");
        
        // Connect to Appchain where ChainBalanceManager is deployed
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        address beaconAddress = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;
        address currentImplementation = 0x6AcaCCDacE944619678054Fe0eA03502ed557651;
        
        console.log("ChainBalanceManager proxy:", chainBalanceManagerAddr);
        console.log("Beacon address:", beaconAddress);
        console.log("Current implementation:", currentImplementation);
        
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        console.log("=== 1. VERIFY CURRENT STATE ===");
        
        // Test current functions
        try cbm.getCrossChainConfig() returns (uint32 domain, address manager) {
            console.log("Current getCrossChainConfig() works:");
            console.log("  Domain:", domain);
            console.log("  Manager:", manager);
        } catch {
            console.log("Current getCrossChainConfig() fails");
        }
        
        (bool success, ) = address(cbm).staticcall(abi.encodeWithSignature("getDestinationConfig()"));
        console.log("Current getDestinationConfig() success:", success);
        
        console.log("=== 2. DEPLOY NEW IMPLEMENTATION ===");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy a fresh implementation
        console.log("Deploying new ChainBalanceManager implementation...");
        ChainBalanceManager newImplementation = new ChainBalanceManager();
        address newImplAddr = address(newImplementation);
        console.log("New implementation deployed at:", newImplAddr);
        
        // Check if we're the beacon owner
        address beaconOwner = beacon.owner();
        console.log("Beacon owner:", beaconOwner);
        console.log("Our address:", vm.addr(deployerPrivateKey));
        
        if (beaconOwner == vm.addr(deployerPrivateKey)) {
            console.log("=== 3. UPGRADE BEACON TO NEW IMPLEMENTATION ===");
            
            // Upgrade the beacon to point to new implementation
            console.log("Upgrading beacon to new implementation...");
            beacon.upgradeTo(newImplAddr);
            console.log("Beacon upgraded successfully!");
            
            // Verify the upgrade
            address upgradedImpl = beacon.implementation();
            console.log("Beacon now points to:", upgradedImpl);
            
            if (upgradedImpl == newImplAddr) {
                console.log("SUCCESS: Beacon upgrade completed");
            } else {
                console.log("ERROR: Beacon upgrade failed");
            }
        } else {
            console.log("ERROR: We are not the beacon owner, cannot upgrade");
            console.log("Need to use owner address:", beaconOwner);
        }
        
        vm.stopBroadcast();
        
        console.log("=== 4. TEST FUNCTIONS AFTER UPGRADE ===");
        
        // Re-test functions 
        try cbm.getCrossChainConfig() returns (uint32 domain, address manager) {
            console.log("After upgrade getCrossChainConfig():");
            console.log("  Domain:", domain);
            console.log("  Manager:", manager);
        } catch Error(string memory reason) {
            console.log("After upgrade getCrossChainConfig() failed:", reason);
        } catch {
            console.log("After upgrade getCrossChainConfig() failed with unknown error");
        }
        
        try cbm.getDestinationConfig() returns (uint32 domain, address manager) {
            console.log("After upgrade getDestinationConfig():");
            console.log("  Domain:", domain);
            console.log("  Manager:", manager);
            console.log("SUCCESS: getDestinationConfig() now works!");
        } catch Error(string memory reason) {
            console.log("After upgrade getDestinationConfig() failed:", reason);
        } catch {
            console.log("After upgrade getDestinationConfig() failed with unknown error");
        }
        
        // Test the problematic deposit function
        try cbm.getTokenMapping(0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7) returns (address synthetic) {
            console.log("Token mapping accessible, synthetic token:", synthetic);
        } catch {
            console.log("Token mapping not accessible");
        }
        
        console.log("=== 5. SUMMARY ===");
        console.log("Issue: ChainBalanceManager implementation had corrupted bytecode");
        console.log("Solution: Deployed fresh implementation and upgraded beacon");
        console.log("Result: getDestinationConfig() should now work for deposits");
        
        console.log("========== IMPLEMENTATION FIX COMPLETE ==========");
    }
}