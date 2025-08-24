// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";

contract InitializeBalanceManagerMailbox is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== INITIALIZE BALANCE MANAGER MAILBOX ==========");
        console.log("Fix the 'reinit hell' by using updateCrossChainConfig()");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address balanceManager = vm.parseJsonAddress(deploymentData, ".contracts.BalanceManager");
        address mailbox = vm.parseJsonAddress(deploymentData, ".mailbox");
        uint32 domainId = uint32(vm.parseJsonUint(deploymentData, ".domainId"));
        
        console.log("BalanceManager:", balanceManager);
        console.log("Mailbox:", mailbox);
        console.log("Domain ID:", domainId);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        BalanceManager bm = BalanceManager(balanceManager);
        
        console.log("=== CHECK CURRENT MAILBOX STATUS ===");
        
        // Check current mailbox config
        try bm.getCrossChainConfig() returns (address currentMailbox, uint32 currentDomain) {
            console.log("Current mailbox:", currentMailbox);
            console.log("Current domain:", currentDomain);
            
            if (currentMailbox == address(0)) {
                console.log("Mailbox not initialized - using updateCrossChainConfig()");
                
                console.log("=== INITIALIZE MAILBOX ===");
                try bm.updateCrossChainConfig(mailbox, domainId) {
                    console.log("SUCCESS: Mailbox initialized via updateCrossChainConfig()");
                } catch Error(string memory reason) {
                    console.log("FAILED: updateCrossChainConfig -", reason);
                    
                    // Try the old initializeCrossChain as fallback
                    console.log("Trying initializeCrossChain as fallback...");
                    try bm.initializeCrossChain(mailbox, domainId) {
                        console.log("SUCCESS: Mailbox initialized via initializeCrossChain()");
                    } catch Error(string memory reason2) {
                        console.log("FAILED: initializeCrossChain -", reason2);
                    }
                }
            } else if (currentMailbox != mailbox || currentDomain != domainId) {
                console.log("Mailbox config incorrect - updating...");
                
                try bm.updateCrossChainConfig(mailbox, domainId) {
                    console.log("SUCCESS: Mailbox updated via updateCrossChainConfig()");
                } catch Error(string memory reason) {
                    console.log("FAILED: updateCrossChainConfig -", reason);
                }
            } else {
                console.log("SUCCESS: Mailbox already correctly configured");
            }
        } catch {
            console.log("Could not check current config - trying to initialize...");
            
            try bm.updateCrossChainConfig(mailbox, domainId) {
                console.log("SUCCESS: Mailbox initialized via updateCrossChainConfig()");
            } catch Error(string memory reason) {
                console.log("FAILED: updateCrossChainConfig -", reason);
            }
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== VERIFICATION ===");
        
        // Verify final state
        try bm.getCrossChainConfig() returns (address finalMailbox, uint32 finalDomain) {
            console.log("Final mailbox:", finalMailbox);
            console.log("Final domain:", finalDomain);
            
            bool mailboxCorrect = finalMailbox == mailbox;
            bool domainCorrect = finalDomain == domainId;
            
            console.log("Mailbox correct:", mailboxCorrect ? "YES" : "NO");
            console.log("Domain correct:", domainCorrect ? "YES" : "NO");
            
            if (mailboxCorrect && domainCorrect) {
                console.log("SUCCESS: BalanceManager mailbox fully configured!");
            } else {
                console.log("ERROR: Mailbox configuration incomplete");
            }
        } catch {
            console.log("ERROR: Could not verify final configuration");
        }
        
        console.log("");
        console.log("This fixes the 'reinit hell' - no more manual mailbox setup after upgrades!");
        
        console.log("========== BALANCE MANAGER MAILBOX INITIALIZED ==========");
    }
}