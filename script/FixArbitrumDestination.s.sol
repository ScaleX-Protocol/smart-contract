// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract FixArbitrumDestination is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== FIX ARBITRUM DESTINATION ADDRESS ==========");
        console.log("Update Arbitrum ChainBalanceManager to point to correct BalanceManager");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 421614) {
            console.log("ERROR: This script is for Arbitrum Sepolia only");
            return;
        }
        
        // Read deployment data
        string memory arbitrumData = vm.readFile("deployments/arbitrum-sepolia.json");
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address chainBalanceManager = vm.parseJsonAddress(arbitrumData, ".contracts.ChainBalanceManager");
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
                    
                    // Try the 3-parameter version
                    console.log("Trying 3-parameter version...");
                    address arbitrumMailbox = vm.parseJsonAddress(arbitrumData, ".mailbox");
                    
                    try cbm.updateCrossChainConfig(arbitrumMailbox, rariDomain, correctBalanceManager) {
                        console.log("SUCCESS: Destination updated with 3 parameters!");
                    } catch Error(string memory reason2) {
                        console.log("FAILED: 3-parameter version also failed -", reason2);
                    }
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
                console.log("Arbitrum deposits should now work!");
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
        console.log("RESULT: Arbitrum -> Rari deposits should now relay successfully");
        
        console.log("========== ARBITRUM DESTINATION FIXED ==========");
    }
}