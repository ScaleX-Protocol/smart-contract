// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "../src/core/BalanceManager.sol";

contract DebugCrossChainConfig is Script {
    
    function run() public {
        console.log("========== DEBUG CROSS-CHAIN CONFIG ==========");
        console.log("Debug ChainBalanceManager and BalanceManager configuration");
        console.log("Network:", vm.toString(block.chainid));
        
        // Determine deployment file based on chain
        string memory deploymentFile;
        string memory networkName;
        
        if (block.chainid == 421614) {
            deploymentFile = "deployments/arbitrum-sepolia.json";
            networkName = "ARBITRUM SEPOLIA";
        } else if (block.chainid == 11155931) {
            deploymentFile = "deployments/rise-sepolia.json";
            networkName = "RISE SEPOLIA";
        } else if (block.chainid == 1918988905) {
            deploymentFile = "deployments/rari.json";
            networkName = "RARI";
        } else {
            console.log("ERROR: Unsupported network");
            return;
        }
        
        console.log("Target network:", networkName);
        console.log("");
        
        // Read deployment data
        string memory chainData = vm.readFile(deploymentFile);
        string memory rariData = vm.readFile("deployments/rari.json");
        
        if (block.chainid == 1918988905) {
            // Debug Rari BalanceManager
            debugRariBalanceManager(chainData, rariData);
        } else {
            // Debug source chain ChainBalanceManager
            debugSourceChainBalanceManager(chainData, rariData, networkName);
        }
        
        console.log("========== DEBUG COMPLETE ==========");
    }
    
    function debugRariBalanceManager(string memory rariData, string memory rariData2) internal view {
        console.log("=== DEBUGGING RARI BALANCE MANAGER ===");
        
        address balanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        console.log("BalanceManager:", balanceManager);
        
        BalanceManager bm = BalanceManager(balanceManager);
        
        // Check cross-chain config
        try bm.getCrossChainConfig() returns (address mailbox, uint32 localDomain) {
            console.log("Mailbox:", mailbox);
            console.log("Local domain:", localDomain);
            
            if (mailbox == address(0)) {
                console.log("ERROR: Mailbox not set!");
            }
            if (localDomain == 0) {
                console.log("ERROR: Local domain not set!");
            }
        } catch Error(string memory reason) {
            console.log("FAILED to get cross-chain config:", reason);
        }
        
        // Check if it can receive messages
        console.log("");
        console.log("BalanceManager should be able to receive cross-chain messages");
        console.log("Check if handle function exists and works");
    }
    
    function debugSourceChainBalanceManager(
        string memory chainData, 
        string memory rariData, 
        string memory networkName
    ) internal view {
        console.log("=== DEBUGGING SOURCE CHAIN BALANCE MANAGER ===");
        console.log("Network:", networkName);
        
        address chainBalanceManager = vm.parseJsonAddress(chainData, ".contracts.ChainBalanceManager");
        address correctBalanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        uint32 rariDomain = uint32(vm.parseJsonUint(rariData, ".domainId"));
        
        console.log("");
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Expected Rari BalanceManager:", correctBalanceManager);
        console.log("Expected Rari domain:", rariDomain);
        console.log("");
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        // Check cross-chain config
        console.log("=== CROSS-CHAIN CONFIG ===");
        try cbm.getCrossChainConfig() returns (uint32 destDomain, address destBalanceManager) {
            console.log("Configured destination domain:", destDomain);
            console.log("Configured destination BalanceManager:", destBalanceManager);
            console.log("Expected domain:", rariDomain);
            console.log("Expected BalanceManager:", correctBalanceManager);
            console.log("");
            
            bool domainCorrect = destDomain == rariDomain;
            bool addressCorrect = destBalanceManager == correctBalanceManager;
            
            console.log("Domain correct:", domainCorrect ? "YES" : "NO");
            console.log("Address correct:", addressCorrect ? "YES" : "NO");
            
            if (!domainCorrect || !addressCorrect) {
                console.log("ERROR: Configuration is wrong!");
                if (!domainCorrect) {
                    console.log("  Wrong domain:", destDomain, "should be", rariDomain);
                }
                if (!addressCorrect) {
                    console.log("  Wrong address:", destBalanceManager);
                    console.log("  Should be:", correctBalanceManager);
                }
            } else {
                console.log("SUCCESS: Configuration is correct!");
            }
        } catch Error(string memory reason) {
            console.log("FAILED to get cross-chain config:", reason);
        }
        
        // Check mailbox config
        console.log("");
        console.log("=== MAILBOX CONFIG ===");
        try cbm.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
            console.log("Mailbox:", mailbox);
            console.log("Local domain:", localDomain);
            
            if (mailbox == address(0)) {
                console.log("ERROR: Mailbox not set!");
            } else {
                console.log("Mailbox is set correctly");
            }
            if (localDomain == 0) {
                console.log("ERROR: Local domain not set!");
            } else {
                console.log("Local domain is set correctly");
            }
        } catch Error(string memory reason) {
            console.log("FAILED to get mailbox config:", reason);
        }
        
        // Check token mappings
        console.log("");
        console.log("=== TOKEN MAPPINGS ===");
        
        address sourceUSDT = vm.parseJsonAddress(chainData, ".contracts.USDT");
        address gsUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");
        
        address usdtMapping = cbm.getTokenMapping(sourceUSDT);
        console.log("USDT mapping:");
        console.log("  Source:", sourceUSDT);
        console.log("  Maps to:", usdtMapping);
        console.log("  Expected:", gsUSDT);
        console.log("  Correct:", usdtMapping == gsUSDT ? "YES" : "NO");
        
        if (usdtMapping != gsUSDT) {
            console.log("ERROR: Token mapping is wrong!");
        }
        
        console.log("");
        console.log("=== DIAGNOSIS ===");
        if (block.chainid == 421614) {
            console.log("ARBITRUM DIAGNOSIS:");
        } else if (block.chainid == 11155931) {
            console.log("RISE DIAGNOSIS:");
        }
        console.log("1. Check if configuration is correct");
        console.log("2. Check if mailbox is working");
        console.log("3. Check if messages are being sent");
        console.log("4. Check if Hyperlane relay is processing messages");
    }
}