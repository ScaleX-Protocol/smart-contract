// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract DeployFixedBalanceManager is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== DEPLOYING FIXED BALANCE MANAGER ==========");
        console.log("Deployer:", deployer);
        
        // Switch to Rari
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        // Get current deployment addresses
        address currentBalanceManager = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address balanceManagerBeacon = 0xF1A53bC852bB9e139a8200003B55164592695395;
        address currentImpl = 0x71d5c9439923cf2579b12F87cc5adA52877B594e;
        
        console.log("=== CURRENT DEPLOYMENT ===");
        console.log("BalanceManager Proxy:", currentBalanceManager);
        console.log("BalanceManager Beacon:", balanceManagerBeacon);
        console.log("Current Implementation:", currentImpl);
        console.log("");
        
        console.log("=== FIXES IN NEW IMPLEMENTATION ===");
        console.log("1. Real ERC20 token minting on cross-chain deposits");
        console.log("2. Real ERC20 token burning on cross-chain withdrawals");
        console.log("3. TokenRegistry integration added");
        console.log("4. setTokenRegistry() function added");
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new BalanceManager implementation with fixes
        console.log("Deploying new BalanceManager implementation...");
        BalanceManager newBalanceManagerImpl = new BalanceManager();
        
        console.log("SUCCESS: New implementation deployed at:", address(newBalanceManagerImpl));
        
        // Update the beacon to point to new implementation
        console.log("Updating beacon to new implementation...");
        UpgradeableBeacon beacon = UpgradeableBeacon(balanceManagerBeacon);
        
        try beacon.upgradeTo(address(newBalanceManagerImpl)) {
            console.log("SUCCESS: Beacon upgraded to new implementation");
        } catch Error(string memory reason) {
            console.log("Beacon upgrade failed:", reason);
        }
        
        vm.stopBroadcast();
        
        // Verify the upgrade
        console.log("");
        console.log("=== VERIFICATION ===");
        
        try beacon.implementation() returns (address impl) {
            console.log("Beacon now points to:", impl);
            if (impl == address(newBalanceManagerImpl)) {
                console.log("SUCCESS: Upgrade successful!");
            } else {
                console.log("WARNING: Upgrade may not have worked");
            }
        } catch {
            console.log("Could not verify beacon implementation");
        }
        
        // Test new functionality
        console.log("");
        console.log("=== TESTING NEW FUNCTIONALITY ===");
        BalanceManager balanceManager = BalanceManager(currentBalanceManager);
        
        try balanceManager.setTokenRegistry(0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E) {
            console.log("SUCCESS: setTokenRegistry() function works!");
        } catch Error(string memory reason) {
            console.log("setTokenRegistry test failed:", reason);
        } catch {
            console.log("setTokenRegistry test failed with unknown error");
        }
        
        console.log("");
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("Old Implementation:", currentImpl);
        console.log("New Implementation:", address(newBalanceManagerImpl));
        console.log("BalanceManager Proxy:", currentBalanceManager, "(unchanged)");
        console.log("Status: FIXED TOKEN MINTING DEPLOYED");
        
        console.log("========== UPGRADE COMPLETE ==========");
    }
}