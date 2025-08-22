// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IMailbox} from "../src/core/interfaces/IMailbox.sol";

contract GetMessageId is Script {
    
    function run() public {
        console.log("========== GETTING MESSAGE ID =========");
        
        // Switch to Appchain
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address appchainMailbox = 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1;
        string memory txHash = "0xeb810504308b791d9a4b3bf833cf8cbd4f6d68da5a01194d6a2ae4c424532f09";
        
        console.log("Appchain Mailbox:", appchainMailbox);
        console.log("Transaction Hash:", txHash);
        
        // Get the logs from the transaction to find the Dispatch event
        // We need to check what events were emitted
        
        console.log("Message ID would be in the Dispatch event logs");
        console.log("Check the transaction logs at:");
        console.log("https://appchain.caff.testnet.espresso.network");
        
        // Let's try to get current message count to understand what's happening
        try this.externalNonce(appchainMailbox) returns (uint32 nonce) {
            console.log("Current nonce (message count):", nonce);
        } catch {
            console.log("Failed to get nonce");
        }
        
        console.log("========== DONE =========");
        console.log("To debug further:");
        console.log("1. Check transaction logs for Dispatch event");
        console.log("2. Look for messageId in the logs");  
        console.log("3. Check Hyperlane explorer: https://hyperlane-explorer.gtxdex.xyz/");
    }
    
    function externalNonce(address mailbox) external view returns (uint32) {
        return IMailbox(mailbox).nonce();
    }
}