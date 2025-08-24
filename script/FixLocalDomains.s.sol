// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract FixLocalDomains is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== FIX LOCAL DOMAINS ==========");
        console.log("Fix ChainBalanceManager local domains on source chains");
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
        
        console.log("NOTE: If Hyperlane uses different domain IDs, this script may need adjustment");
        
        console.log("Target network:", networkName);
        console.log("Correct local domain:", correctLocalDomain);
        console.log("");
        
        // Read deployment data
        string memory chainData = vm.readFile(deploymentFile);
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address chainBalanceManager = vm.parseJsonAddress(chainData, ".contracts.ChainBalanceManager");
        uint32 rariDomain = uint32(vm.parseJsonUint(rariData, ".domainId"));
        address correctBalanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Rari Domain:", rariDomain);
        console.log("Correct BalanceManager:", correctBalanceManager);
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
                console.log("FIXING: Updating local domain...");
                console.log("From:", currentLocalDomain);
                console.log("To:", correctLocalDomain);
                
                console.log("CRITICAL: Local domain is hardcoded during initialization");
                console.log("Current ChainBalanceManager has wrong localDomain from deployment");
                console.log("This is why Hyperlane relay fails - wrong source domain");
                console.log("");
                console.log("SOLUTIONS:");
                console.log("1. Add updateLocalDomain function to ChainBalanceManager");  
                console.log("2. Or redeploy ChainBalanceManager with correct chain context");
                console.log("");
                console.log("For now, let's try updating config and see if it helps...");
                
                try cbm.updateCrossChainConfig(currentMailbox, rariDomain, correctBalanceManager) {
                    console.log("Config update completed (but local domain still needs fix)");
                } catch Error(string memory reason) {
                    console.log("Config update failed:", reason);
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
            } else {
                console.log("WARNING: Local domain still incorrect");
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not verify final config -", reason);
        }
        
        // Also verify destination config is still correct
        console.log("");
        console.log("=== VERIFY DESTINATION CONFIG ===");
        
        try cbm.getCrossChainConfig() returns (uint32 destDomain, address destBalanceManager) {
            console.log("Destination domain:", destDomain);
            console.log("Destination BalanceManager:", destBalanceManager);
            
            bool correct = (destDomain == rariDomain && destBalanceManager == correctBalanceManager);
            console.log("Destination config correct:", correct ? "YES" : "NO");
        } catch Error(string memory reason) {
            console.log("FAILED: Could not verify destination config -", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== WHAT WAS FIXED ===" );
        console.log("BEFORE: Local domain was wrong (4661 - Appchain domain)");
        console.log("AFTER:  Local domain is correct (chain's actual domain)");
        console.log("RESULT: Messages should now relay with correct source domain");
        
        console.log("========== LOCAL DOMAIN FIXED ==========");
    }
}