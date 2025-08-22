// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/ChainBalanceManager.sol";

contract FixMailboxConfigsSimple is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========== FIXING MAILBOX CONFIGURATIONS (SIMPLE) ==========");
        
        // Step 1: Fix Rari BalanceManager (already done, but verify)
        console.log("=== STEP 1: RARI BALANCE MANAGER ===");
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address rariMailbox = 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358;
        
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("Rari Mailbox:", rariMailbox);
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        
        // Check current mailbox config
        try balanceManager.getMailboxConfig() returns (address currentMailbox, uint32 currentDomain) {
            console.log("Current BalanceManager mailbox:", currentMailbox);
            console.log("Current BalanceManager domain:", currentDomain);
            
            if (currentMailbox != rariMailbox) {
                console.log("Updating BalanceManager mailbox...");
                vm.startBroadcast(deployerPrivateKey);
                balanceManager.setMailbox(rariMailbox);
                vm.stopBroadcast();
                console.log("SUCCESS: BalanceManager mailbox updated");
            } else {
                console.log("BalanceManager mailbox already correct");
            }
        } catch {
            console.log("BalanceManager mailbox not readable");
        }
        
        // Check ChainBalanceManager registration on Rari
        console.log("=== STEP 1b: VERIFY CHAINBALANCEMANAGER REGISTRATION ===");
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        uint32 appchainDomain = 4661;
        
        try balanceManager.getChainBalanceManager(appchainDomain) returns (address registeredCBM) {
            console.log("Registered ChainBalanceManager for domain", appchainDomain, ":", registeredCBM);
            
            if (registeredCBM != chainBalanceManagerAddr) {
                console.log("Updating ChainBalanceManager registration...");
                vm.startBroadcast(deployerPrivateKey);
                balanceManager.setChainBalanceManager(appchainDomain, chainBalanceManagerAddr);
                vm.stopBroadcast();
                console.log("SUCCESS: ChainBalanceManager registered");
            } else {
                console.log("ChainBalanceManager registration already correct");
            }
        } catch {
            console.log("Registering ChainBalanceManager...");
            vm.startBroadcast(deployerPrivateKey);
            balanceManager.setChainBalanceManager(appchainDomain, chainBalanceManagerAddr);
            vm.stopBroadcast();
            console.log("SUCCESS: ChainBalanceManager registered");
        }
        
        // Step 2: Fix Appchain ChainBalanceManager  
        console.log("=== STEP 2: APPCHAIN CHAIN BALANCE MANAGER ===");
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        console.log("ChainBalanceManager:", chainBalanceManagerAddr);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        // Check current mailbox configuration
        try cbm.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
            console.log("ChainBalanceManager mailbox:", mailbox);
            console.log("ChainBalanceManager localDomain:", localDomain);
        } catch {
            console.log("ChainBalanceManager mailbox config not readable");
        }
        
        // Try to check destination config, handle error gracefully
        console.log("=== STEP 2b: DESTINATION CONFIG ===");
        uint32 expectedRariDomain = 1918988905;
        address expectedRariBalanceManager = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        
        bool needsUpdate = false;
        
        try cbm.getDestinationConfig() returns (uint32 destDomain, address destBalanceManager) {
            console.log("Current destination domain:", destDomain);
            console.log("Current destination BalanceManager:", destBalanceManager);
            
            if (destDomain != expectedRariDomain || destBalanceManager != expectedRariBalanceManager) {
                needsUpdate = true;
            }
        } catch {
            console.log("Destination config not set or not readable - needs initialization");
            needsUpdate = true;
        }
        
        if (needsUpdate) {
            console.log("Updating ChainBalanceManager destination config...");
            vm.startBroadcast(deployerPrivateKey);
            
            try cbm.updateCrossChainConfig(expectedRariDomain, expectedRariBalanceManager) {
                console.log("SUCCESS: ChainBalanceManager destination config updated");
            } catch Error(string memory reason) {
                console.log("FAILED to update ChainBalanceManager:", reason);
            } catch {
                console.log("FAILED to update ChainBalanceManager with unknown error");
            }
            
            vm.stopBroadcast();
        } else {
            console.log("ChainBalanceManager destination config already correct");
        }
        
        console.log("");
        console.log("========== MAILBOX CONFIGS FIXED ==========");
        console.log("Expected behavior after fix:");
        console.log("1. BalanceManager can receive cross-chain messages");
        console.log("2. ChainBalanceManager can send to correct destination");
        console.log("3. Hyperlane relayers should be able to process pending messages");
        console.log("4. V2 token minting will work when messages are delivered");
        console.log("");
        console.log("Pending message IDs that should now be processable:");
        console.log("- 0x085ccdf6f1420f633b39625afc6479543175f102c00afb54c5a636344f899987");
        console.log("- 0xe8b4ee6b7ccf3401080241ea2d3527707d312b4e0daac88d45dfba6c9713b21c");
    }
}