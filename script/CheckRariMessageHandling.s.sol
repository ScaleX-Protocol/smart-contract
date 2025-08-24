// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";

contract CheckRariMessageHandling is Script {
    
    function run() public view {
        console.log("========== CHECK RARI MESSAGE HANDLING ==========");
        console.log("Verify BalanceManager can handle Rise messages");
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari only");
            return;
        }
        
        // Message details from Hyperlane explorer
        uint32 originDomain = 11155931; // Rise
        address sender = 0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745; // Rise ChainBalanceManager
        address recipient = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
        address token = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d; // gsUSDT
        uint256 amount = 100000000; // 100 USDT (6 decimals)
        
        // Read deployment data
        string memory rariData = vm.readFile("deployments/rari.json");
        address balanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        
        console.log("");
        console.log("BalanceManager:", balanceManager);
        console.log("Message details:");
        console.log("- Origin domain:", originDomain);
        console.log("- Sender:", sender);
        console.log("- Recipient:", recipient);
        console.log("- Token:", token);
        console.log("- Amount:", amount);
        console.log("");
        
        BalanceManager bm = BalanceManager(balanceManager);
        
        console.log("=== CHECK CHAIN REGISTRY ===");
        
        try bm.getChainBalanceManager(originDomain) returns (address registeredCBM) {
            console.log("Registered ChainBalanceManager for domain", originDomain, ":", registeredCBM);
            console.log("Expected sender:", sender);
            console.log("Registry correct:", registeredCBM == sender);
            
            if (registeredCBM == address(0)) {
                console.log("ERROR: No ChainBalanceManager registered for Rise domain!");
                console.log("This will cause message rejection");
            } else if (registeredCBM != sender) {
                console.log("ERROR: Wrong ChainBalanceManager registered!");
                console.log("Expected:", sender);
                console.log("Registered:", registeredCBM);
                console.log("This will cause InvalidSender error");
            } else {
                console.log("SUCCESS: Correct ChainBalanceManager registered");
            }
        } catch Error(string memory reason) {
            console.log("FAILED to get chain registry:", reason);
        }
        
        console.log("");
        console.log("=== CHECK CROSS-CHAIN CONFIG ===");
        
        try bm.getCrossChainConfig() returns (address mailbox, uint32 localDomain) {
            console.log("BalanceManager mailbox:", mailbox);
            console.log("BalanceManager local domain:", localDomain);
            
            bool mailboxSet = (mailbox != address(0));
            bool domainCorrect = (localDomain == block.chainid);
            
            console.log("Mailbox configured:", mailboxSet);
            console.log("Local domain correct:", domainCorrect);
            
            if (!mailboxSet) {
                console.log("ERROR: BalanceManager mailbox not configured!");
            }
            if (!domainCorrect) {
                console.log("ERROR: BalanceManager local domain wrong!");
            }
        } catch Error(string memory reason) {
            console.log("FAILED to get cross-chain config:", reason);
        }
        
        console.log("");
        console.log("=== CHECK TOKEN CONFIGURATION ===");
        
        // Check if token is a valid synthetic token
        console.log("Checking gsUSDT token:", token);
        
        try this.checkTokenDecimals(token) returns (uint8 decimals) {
            console.log("Token decimals:", decimals);
            console.log("Expected decimals: 6");
            console.log("Decimals correct:", decimals == 6);
        } catch {
            console.log("Could not get token decimals");
        }
        
        try this.checkTokenName(token) returns (string memory name) {
            console.log("Token name:", name);
        } catch {
            console.log("Could not get token name");
        }
        
        console.log("");
        console.log("=== CHECK RECIPIENT BALANCE ===");
        
        try bm.getBalance(recipient, Currency.wrap(token)) returns (uint256 currentBalance) {
            console.log("Recipient current balance:", currentBalance);
            console.log("Expected after message: currentBalance + 100000000");
        } catch Error(string memory reason) {
            console.log("Could not get recipient balance:", reason);
        }
        
        console.log("");
        console.log("=== DIAGNOSIS ===");
        console.log("For the message to process successfully:");
        console.log("1. Rise ChainBalanceManager must be registered - CHECK ABOVE");
        console.log("2. BalanceManager mailbox must be configured - CHECK ABOVE");
        console.log("3. Token (gsUSDT) must be valid ERC20 - CHECK ABOVE");
        console.log("4. No revert in handle() function logic");
        console.log("");
        console.log("If all checks pass, the message should process and mint 100 USDT to recipient");
        
        console.log("========== RARI MESSAGE HANDLING CHECK COMPLETE ==========");
    }
    
    function checkTokenDecimals(address token) external view returns (uint8) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
        require(success, "decimals() call failed");
        return abi.decode(data, (uint8));
    }
    
    function checkTokenName(address token) external view returns (string memory) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("name()"));
        require(success, "name() call failed");
        return abi.decode(data, (string));
    }
}