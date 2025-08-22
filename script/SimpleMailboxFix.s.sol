// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/ChainBalanceManager.sol";

contract SimpleMailboxFix is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== SIMPLE MAILBOX FIX =========");
        console.log("Deployer:", deployer);
        
        // Step 1: Fix BalanceManager on Rari
        console.log("=== FIXING RARI BALANCE MANAGER ===");
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address rariMailbox = 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358;
        
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("Rari Mailbox:", rariMailbox);
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        
        // Check current owner
        address currentOwner = balanceManager.owner();
        console.log("Current owner:", currentOwner);
        console.log("Deployer:", deployer);
        console.log("Owner matches deployer:", currentOwner == deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Check current mailbox config
        try balanceManager.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
            console.log("Current mailbox config:");
            console.log("  Mailbox:", mailbox);
            console.log("  LocalDomain:", localDomain);
        } catch {
            console.log("getMailboxConfig() failed - mailbox not configured");
        }
        
        // Try to set mailbox
        try balanceManager.setMailbox(rariMailbox) {
            console.log("SUCCESS: Mailbox set on BalanceManager");
            
            // Verify
            try balanceManager.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
                console.log("After setting mailbox:");
                console.log("  Mailbox:", mailbox);
                console.log("  LocalDomain:", localDomain);
            } catch {
                console.log("Still can't read mailbox config after setting");
            }
            
        } catch Error(string memory reason) {
            console.log("FAILED to set mailbox:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Low-level error setting mailbox");
            console.logBytes(lowLevelData);
        }
        
        vm.stopBroadcast();
        
        console.log("========== DONE =========");
    }
}