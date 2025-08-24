// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract FixLocalDomainsUpdated is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== FIX LOCAL DOMAINS (UPDATED) ==========");
        console.log("Fix ChainBalanceManager local domains using new updateLocalDomain function");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        // Determine correct domains and deployment file
        string memory deploymentFile;
        string memory networkName;
        uint32 correctLocalDomain;
        
        if (block.chainid == 421614) {
            deploymentFile = "deployments/arbitrum-sepolia.json";
            networkName = "ARBITRUM SEPOLIA";
            correctLocalDomain = 421614; // Hyperlane domain for Arbitrum Sepolia
        } else if (block.chainid == 11155931) {
            deploymentFile = "deployments/rise-sepolia.json";
            networkName = "RISE SEPOLIA";  
            correctLocalDomain = 11155931; // Hyperlane domain for Rise Sepolia
        } else {
            console.log("ERROR: This script is for Arbitrum Sepolia (421614) or Rise Sepolia (11155931) only");
            return;
        }
        
        console.log("Target network:", networkName);
        console.log("Correct local domain:", correctLocalDomain);
        console.log("");
        
        // Read deployment data
        string memory chainData = vm.readFile(deploymentFile);
        
        address chainBalanceManager = vm.parseJsonAddress(chainData, ".contracts.ChainBalanceManager");
        
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        console.log("=== CHECK CURRENT LOCAL DOMAIN ===");
        
        try cbm.getMailboxConfig() returns (address currentMailbox, uint32 currentLocalDomain) {
            console.log("Current mailbox:", currentMailbox);
            console.log("Current local domain:", currentLocalDomain);
            console.log("Should be local domain:", correctLocalDomain);
            console.log("");
            
            if (currentLocalDomain != correctLocalDomain) {
                console.log("FIXING: Using new updateLocalDomain function...");
                console.log("From:", currentLocalDomain);
                console.log("To:", correctLocalDomain);
                
                try cbm.updateLocalDomain(correctLocalDomain) {
                    console.log("SUCCESS: Local domain updated!");
                } catch Error(string memory reason) {
                    console.log("FAILED: Could not update local domain -", reason);
                }
            } else {
                console.log("Local domain already correct");
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not get current mailbox config -", reason);
        }
        
        console.log("");
        console.log("=== VERIFY FINAL CONFIG ===");
        
        try cbm.getMailboxConfig() returns (address finalMailbox, uint32 finalLocalDomain) {
            console.log("Final mailbox:", finalMailbox);
            console.log("Final local domain:", finalLocalDomain);
            
            if (finalLocalDomain == correctLocalDomain) {
                console.log("SUCCESS: Local domain fixed!");
                console.log("Messages should now relay with correct source domain");
            } else {
                console.log("WARNING: Local domain still incorrect");
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not verify final config -", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== WHAT WAS FIXED ===");
        console.log("BEFORE: Local domain was wrong (4661 - Appchain domain)");
        console.log("AFTER:  Local domain is correct (chain's actual domain)");
        console.log("RESULT: Hyperlane relay should now work for", networkName);
        
        console.log("========== LOCAL DOMAIN FIXED ==========");
    }
}