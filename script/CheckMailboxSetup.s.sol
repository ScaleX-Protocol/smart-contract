// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/interfaces/IBalanceManager.sol";

contract CheckMailboxSetup is Script {
    
    function run() public view {
        console.log("========== CHECKING MAILBOX SETUP ==========");
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: Must run on Rari network");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address balanceManager = vm.parseJsonAddress(deploymentData, ".contracts.BalanceManager");
        address expectedMailbox = vm.parseJsonAddress(deploymentData, ".mailbox");
        uint32 expectedDomain = uint32(vm.parseJsonUint(deploymentData, ".domainId"));
        
        console.log("BalanceManager:", balanceManager);
        console.log("Expected Mailbox:", expectedMailbox);
        console.log("Expected Domain:", expectedDomain);
        console.log("");
        
        // Check current mailbox config - direct call since not in interface
        (bool success, bytes memory data) = balanceManager.staticcall(
            abi.encodeWithSignature("getMailboxConfig()")
        );
        
        if (success && data.length >= 64) {
            (address mailbox, uint32 localDomain) = abi.decode(data, (address, uint32));
            console.log("=== CURRENT MAILBOX CONFIG ===");
            console.log("Current Mailbox:", mailbox);
            console.log("Current Domain:", localDomain);
            
            if (mailbox == expectedMailbox) {
                console.log("SUCCESS: Mailbox address is CORRECT");
            } else {
                console.log("ERROR: Mailbox address is WRONG");
                console.log("  Expected:", expectedMailbox);
                console.log("  Current: ", mailbox);
            }
            
            if (localDomain == expectedDomain) {
                console.log("SUCCESS: Domain is CORRECT");
            } else {
                console.log("ERROR: Domain is WRONG");
                console.log("  Expected:", expectedDomain);
                console.log("  Current: ", localDomain);
            }
        } catch {
            console.log("ERROR: FAILED to read mailbox config");
        }
        
        // Check ChainBalanceManager mapping
        console.log("");
        console.log("=== CHAIN BALANCE MANAGERS ===");
        
        // Check Appchain mapping (4661) - direct call
        (bool success2, bytes memory data2) = balanceManager.staticcall(
            abi.encodeWithSignature("getChainBalanceManager(uint32)", 4661)
        );
        
        if (success2 && data2.length >= 32) {
            address cbm = abi.decode(data2, (address));
            console.log("Appchain (4661) CBM:", cbm);
            if (cbm != address(0)) {
                console.log("SUCCESS: Appchain mapping exists");
            } else {
                console.log("ERROR: Appchain mapping missing");
            }
        } else {
            console.log("ERROR: Could not read Appchain mapping");
        }
        
        console.log("");
        console.log("=== RECOMMENDATIONS ===");
        console.log("1. Re-initialize mailbox after every upgrade");
        console.log("2. Set ChainBalanceManager mappings after upgrade");
        console.log("3. Consider adding these to upgrade script automatically");
        
        console.log("========== MAILBOX CHECK COMPLETE ==========");
    }
}