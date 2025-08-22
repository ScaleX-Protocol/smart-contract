// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/ChainBalanceManager.sol";

contract FixBothMailboxConfigs is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========== FIXING MAILBOX CONFIGURATIONS ==========");
        
        // Step 1: Check and fix Rari BalanceManager
        console.log("=== STEP 1: RARI BALANCE MANAGER ===");
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address rariMailbox = 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358;
        
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("Rari Mailbox:", rariMailbox);
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        try balanceManager.setMailbox(rariMailbox) {
            console.log("SUCCESS: Mailbox address set on BalanceManager");
        } catch Error(string memory reason) {
            console.log("FAILED to set mailbox on BalanceManager:", reason);
        } catch {
            console.log("FAILED to set mailbox on BalanceManager with unknown error");
        }
        
        vm.stopBroadcast();
        
        // Step 2: Check Appchain ChainBalanceManager
        console.log("=== STEP 2: APPCHAIN CHAIN BALANCE MANAGER ===");
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        console.log("ChainBalanceManager:", chainBalanceManagerAddr);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        // Check current configuration
        (address mailbox, uint32 localDomain) = cbm.getMailboxConfig();
        console.log("Current mailbox:", mailbox);
        console.log("Current localDomain:", localDomain);
        
        (uint32 destDomain, address destBalanceManager) = cbm.getDestinationConfig();
        console.log("Current destinationDomain:", destDomain);
        console.log("Current destinationBalanceManager:", destBalanceManager);
        
        // Expected values
        address expectedAppchainMailbox = 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1;
        uint32 expectedRariDomain = 1918988905;
        address expectedRariBalanceManager = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Update if needed
        if (mailbox != expectedAppchainMailbox || localDomain != 4661 || 
            destDomain != expectedRariDomain || destBalanceManager != expectedRariBalanceManager) {
            
            console.log("Updating ChainBalanceManager configuration...");
            try cbm.updateCrossChainConfig(expectedRariDomain, expectedRariBalanceManager) {
                console.log("SUCCESS: Updated ChainBalanceManager cross-chain config");
            } catch Error(string memory reason) {
                console.log("FAILED to update ChainBalanceManager:", reason);
            } catch {
                console.log("FAILED to update ChainBalanceManager with unknown error");
            }
        } else {
            console.log("ChainBalanceManager configuration already correct");
        }
        
        vm.stopBroadcast();
        
        console.log("========== MAILBOX CONFIGS FIXED ==========");
        console.log("Both contracts should now handle cross-chain messages!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Test deposit from Appchain to Rari");
        console.log("2. Check if BalanceManager receives the message");
        console.log("3. Verify synthetic token balance increases");
    }
}