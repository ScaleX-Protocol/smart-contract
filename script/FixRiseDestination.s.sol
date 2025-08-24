// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract FixRiseDestination is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== FIX RISE DESTINATION ADDRESS ==========");
        console.log("Update Rise ChainBalanceManager to point to correct BalanceManager");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 11155931) {
            console.log("ERROR: This script is for Rise Sepolia only");
            return;
        }
        
        // Read deployment data
        string memory riseData = vm.readFile("deployments/rise-sepolia.json");
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address chainBalanceManager = vm.parseJsonAddress(riseData, ".contracts.ChainBalanceManager");
        uint32 rariDomain = uint32(vm.parseJsonUint(rariData, ".domainId"));
        address correctBalanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        
        console.log("");
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Rari Domain:", rariDomain);
        console.log("Correct BalanceManager:", correctBalanceManager);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        console.log("=== CHECK CURRENT CONFIG ===");
        
        try cbm.getCrossChainConfig() returns (uint32 currentDestDomain, address currentDestBalanceManager) {
            console.log("Current destination domain:", currentDestDomain);
            console.log("Current destination BalanceManager:", currentDestBalanceManager);
            console.log("Should be:", correctBalanceManager);
            console.log("");
            
            if (currentDestBalanceManager != correctBalanceManager) {
                console.log("FIXING: Updating destination BalanceManager...");
                
                try cbm.updateCrossChainConfig(rariDomain, correctBalanceManager) {
                    console.log("SUCCESS: Destination BalanceManager updated!");
                } catch Error(string memory reason) {
                    console.log("FAILED: Could not update destination -", reason);
                }
            } else {
                console.log("Destination BalanceManager already correct");
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not get current config -", reason);
        }
        
        console.log("");
        console.log("=== VERIFY FINAL CONFIG ===");
        
        try cbm.getCrossChainConfig() returns (uint32 finalDestDomain, address finalDestBalanceManager) {
            console.log("Final destination domain:", finalDestDomain);
            console.log("Final destination BalanceManager:", finalDestBalanceManager);
            
            if (finalDestBalanceManager == correctBalanceManager) {
                console.log("SUCCESS: Configuration fixed!");
                console.log("Rise deposits should now work!");
            } else {
                console.log("WARNING: Configuration still incorrect");
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not verify final config -", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== WHAT WAS FIXED ===");
        console.log("BEFORE: Messages sent to wrong BalanceManager");
        console.log("AFTER:  Messages sent to correct BalanceManager");
        console.log("RESULT: Rise -> Rari deposits should now relay successfully");
        
        console.log("========== RISE DESTINATION FIXED ==========");
    }
}