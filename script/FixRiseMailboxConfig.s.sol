// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract FixRiseMailboxConfig is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== FIX RISE MAILBOX CONFIG ==========");
        console.log("Fix null mailbox address on Rise ChainBalanceManager");
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
        address correctMailbox = vm.parseJsonAddress(riseData, ".mailbox");
        uint32 rariDomain = uint32(vm.parseJsonUint(rariData, ".domainId"));
        address correctBalanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Correct mailbox:", correctMailbox);
        console.log("Rari domain:", rariDomain);
        console.log("Correct BalanceManager:", correctBalanceManager);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        console.log("=== CHECK CURRENT STATE ===");
        
        try cbm.getMailboxConfig() returns (address currentMailbox, uint32 localDomain) {
            console.log("Current mailbox:", currentMailbox);
            console.log("Current local domain:", localDomain);
            console.log("");
            
            if (currentMailbox == address(0)) {
                console.log("FIXING: Setting mailbox address...");
                
                try cbm.updateCrossChainConfig(correctMailbox, rariDomain, correctBalanceManager) {
                    console.log("SUCCESS: Cross-chain config updated with mailbox!");
                } catch Error(string memory reason) {
                    console.log("FAILED: Could not update config -", reason);
                    vm.stopBroadcast();
                    return;
                }
            } else {
                console.log("Mailbox already set:", currentMailbox);
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not get mailbox config -", reason);
            vm.stopBroadcast();
            return;
        }
        
        console.log("");
        console.log("=== VERIFY FINAL STATE ===");
        
        try cbm.getMailboxConfig() returns (address finalMailbox, uint32 finalDomain) {
            console.log("Final mailbox:", finalMailbox);
            console.log("Final local domain:", finalDomain);
            
            bool mailboxCorrect = (finalMailbox == correctMailbox);
            bool domainCorrect = (finalDomain == block.chainid);
            
            console.log("Mailbox correct:", mailboxCorrect);
            console.log("Local domain correct:", domainCorrect);
            
            if (mailboxCorrect && domainCorrect) {
                console.log("SUCCESS: Rise ChainBalanceManager fully configured!");
            } else {
                console.log("WARNING: Configuration still incomplete");
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not verify final config -", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== WHAT WAS FIXED ===");
        console.log("BEFORE: Mailbox = null, deposits fail at message dispatch");
        console.log("AFTER:  Mailbox = correct address, deposits should work");
        console.log("RESULT: Rise -> Rari cross-chain messages should now process");
        
        console.log("========== RISE MAILBOX CONFIG FIXED ==========");
    }
}