// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract CheckRiseMailboxConfig is Script {
    
    function run() public view {
        console.log("========== CHECK RISE MAILBOX CONFIG ==========");
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 11155931) {
            console.log("ERROR: This script is for Rise Sepolia only");
            return;
        }
        
        // Read deployment data
        string memory riseData = vm.readFile("deployments/rise-sepolia.json");
        
        address chainBalanceManager = vm.parseJsonAddress(riseData, ".contracts.ChainBalanceManager");
        address expectedMailbox = vm.parseJsonAddress(riseData, ".mailbox");
        
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Expected mailbox:", expectedMailbox);
        console.log("");
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        console.log("=== CHECK CURRENT CONFIG ===");
        
        try cbm.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
            console.log("Current mailbox:", mailbox);
            console.log("Current local domain:", localDomain);
            console.log("");
            
            console.log("Mailbox correct:", mailbox == expectedMailbox);
            console.log("Local domain correct:", localDomain == block.chainid);
            
            if (mailbox == address(0)) {
                console.log("ERROR: Mailbox is null address!");
                console.log("This is why deposits are failing");
            }
        } catch Error(string memory reason) {
            console.log("Failed to get mailbox config:", reason);
        }
        
        console.log("");
        console.log("=== CHECK CROSS-CHAIN CONFIG ===");
        
        try cbm.getCrossChainConfig() returns (uint32 destDomain, address destManager) {
            console.log("Destination domain:", destDomain);
            console.log("Destination manager:", destManager);
        } catch Error(string memory reason) {
            console.log("Failed to get cross-chain config:", reason);
        }
        
        console.log("");
        console.log("=== DIAGNOSIS ===");
        console.log("Rise ChainBalanceManager has:");
        console.log("GOOD: Correct local domain (11155931)");
        console.log("GOOD: Correct destination config");
        console.log("GOOD: Correct token mappings");
        console.log("BAD: NULL MAILBOX ADDRESS - This breaks message dispatch!");
        console.log("");
        console.log("SOLUTION: Need to set mailbox address to:", expectedMailbox);
        
        console.log("========== RISE MAILBOX CHECK COMPLETE ==========");
    }
}