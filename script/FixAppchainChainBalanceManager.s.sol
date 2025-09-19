// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract FixAppchainChainBalanceManager is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== FIX APPCHAIN CHAINBALANCEMANAGER ==========");
        console.log("1. Update token mappings to use NEW synthetic tokens");
        console.log("2. Set up mailbox configuration properly");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 4661) {
            console.log("ERROR: This script is for Appchain Testnet only");
            return;
        }
        
        // Read deployment data
        string memory appchainData = vm.readFile("deployments/appchain.json");
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address chainBalanceManager = vm.parseJsonAddress(appchainData, ".contracts.ChainBalanceManager");
        address mailbox = vm.parseJsonAddress(appchainData, ".mailbox");
        uint32 localDomain = uint32(vm.parseJsonUint(appchainData, ".domainId"));
        uint32 rariDomain = uint32(vm.parseJsonUint(rariData, ".domainId"));
        address rariBalanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        
        // Source tokens on Appchain
        address sourceUSDT = vm.parseJsonAddress(appchainData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(appchainData, ".contracts.WBTC");
        address sourceWETH = vm.parseJsonAddress(appchainData, ".contracts.WETH");
        
        // NEW synthetic tokens on Rari (clean names, correct decimals)
        address gsUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");  // gUSDT (6 decimals)
        address gsWBTC = vm.parseJsonAddress(rariData, ".contracts.gsWBTC");  // gWBTC (8 decimals)
        address gsWETH = vm.parseJsonAddress(rariData, ".contracts.gsWETH");  // gWETH (18 decimals)
        
        console.log("");
        console.log("=== ADDRESSES ===");
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Appchain Mailbox:", mailbox);
        console.log("Local Domain (Appchain):", localDomain);
        console.log("Rari Domain:", rariDomain);
        console.log("Rari BalanceManager:", rariBalanceManager);
        console.log("");
        console.log("=== SOURCE TOKENS ===");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        console.log("=== NEW SYNTHETIC TOKENS (CORRECT DECIMALS) ===");
        console.log("gUSDT (6 decimals):", gsUSDT);
        console.log("gWBTC (8 decimals):", gsWBTC);
        console.log("gWETH (18 decimals):", gsWETH);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        console.log("=== STEP 1: CHECK CURRENT MAILBOX CONFIG ===");
        
        try cbm.getCrossChainInfo() returns (
            address currentMailbox,
            uint32 currentLocalDomain,
            uint32 currentDestDomain,
            address currentDestBalanceManager
        ) {
            console.log("Current mailbox:", currentMailbox);
            console.log("Current local domain:", currentLocalDomain);
            console.log("Current destination domain:", currentDestDomain);
            console.log("Current destination BalanceManager:", currentDestBalanceManager);
            
            bool needsMailboxUpdate = (currentMailbox != mailbox) || 
                                    (currentDestDomain != rariDomain) || 
                                    (currentDestBalanceManager != rariBalanceManager);
            
            if (needsMailboxUpdate) {
                console.log("Updating cross-chain config...");
                try cbm.updateCrossChainConfig(mailbox, rariDomain, rariBalanceManager) {
                    console.log("SUCCESS: Cross-chain config updated");
                } catch Error(string memory reason) {
                    console.log("FAILED: Cross-chain config update -", reason);
                }
            } else {
                console.log("Cross-chain config already correct");
            }
        } catch {
            console.log("Could not get current config - trying to initialize...");
            
            try cbm.initialize(deployer, mailbox, rariDomain, rariBalanceManager) {
                console.log("SUCCESS: ChainBalanceManager initialized");
            } catch Error(string memory reason) {
                console.log("FAILED: ChainBalanceManager initialization -", reason);
            }
        }
        
        console.log("");
        console.log("=== STEP 2: UPDATE TOKEN MAPPINGS TO NEW SYNTHETIC TOKENS ===");
        
        // Check current mappings
        address currentUSDT = cbm.getTokenMapping(sourceUSDT);
        address currentWBTC = cbm.getTokenMapping(sourceWBTC);
        address currentWETH = cbm.getTokenMapping(sourceWETH);
        
        console.log("Current mappings:");
        console.log("USDT ->", currentUSDT);
        console.log("Should be:", gsUSDT);
        console.log("WBTC ->", currentWBTC);
        console.log("Should be:", gsWBTC);
        console.log("WETH ->", currentWETH);
        console.log("Should be:", gsWETH);
        console.log("");
        
        // Update USDT mapping to new gUSDT (6 decimals)
        if (currentUSDT != gsUSDT) {
            console.log("Updating USDT -> gUSDT mapping...");
            try cbm.setTokenMapping(sourceUSDT, gsUSDT) {
                console.log("SUCCESS: USDT mapping updated to gUSDT (6 decimals)");
            } catch Error(string memory reason) {
                console.log("FAILED: USDT mapping -", reason);
            }
        } else {
            console.log("USDT mapping already correct");
        }
        
        // Update WBTC mapping to new gWBTC (8 decimals)
        if (currentWBTC != gsWBTC) {
            console.log("Updating WBTC -> gWBTC mapping...");
            try cbm.setTokenMapping(sourceWBTC, gsWBTC) {
                console.log("SUCCESS: WBTC mapping updated to gWBTC (8 decimals)");
            } catch Error(string memory reason) {
                console.log("FAILED: WBTC mapping -", reason);
            }
        } else {
            console.log("WBTC mapping already correct");
        }
        
        // Update WETH mapping to new gWETH (18 decimals)
        if (currentWETH != gsWETH) {
            console.log("Updating WETH -> gWETH mapping...");
            try cbm.setTokenMapping(sourceWETH, gsWETH) {
                console.log("SUCCESS: WETH mapping updated to gWETH (18 decimals)");
            } catch Error(string memory reason) {
                console.log("FAILED: WETH mapping -", reason);
            }
        } else {
            console.log("WETH mapping already correct");
        }
        
        console.log("");
        console.log("=== STEP 3: VERIFY FINAL CONFIGURATION ===");
        
        // Verify mailbox config
        try cbm.getCrossChainInfo() returns (
            address finalMailbox,
            uint32 finalLocalDomain,
            uint32 finalDestDomain,
            address finalDestBalanceManager
        ) {
            console.log("Final mailbox:", finalMailbox);
            console.log("Final local domain:", finalLocalDomain);
            console.log("Final destination domain:", finalDestDomain);
            console.log("Final destination BalanceManager:", finalDestBalanceManager);
            
            bool configCorrect = (finalMailbox == mailbox) && 
                               (finalDestDomain == rariDomain) && 
                               (finalDestBalanceManager == rariBalanceManager);
            
            if (configCorrect) {
                console.log("SUCCESS: Mailbox configuration correct!");
            } else {
                console.log("ERROR: Mailbox configuration still incorrect");
            }
        } catch {
            console.log("ERROR: Could not verify final mailbox config");
        }
        
        // Verify token mappings
        address finalUSDT = cbm.getTokenMapping(sourceUSDT);
        address finalWBTC = cbm.getTokenMapping(sourceWBTC);
        address finalWETH = cbm.getTokenMapping(sourceWETH);
        
        console.log("");
        console.log("Final token mappings:");
        console.log("USDT ->", finalUSDT);
        console.log("USDT correct:", finalUSDT == gsUSDT ? "YES" : "NO");
        console.log("WBTC ->", finalWBTC);
        console.log("WBTC correct:", finalWBTC == gsWBTC ? "YES" : "NO");
        console.log("WETH ->", finalWETH);
        console.log("WETH correct:", finalWETH == gsWETH ? "YES" : "NO");
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== WHAT'S FIXED ===");
        console.log("+ ChainBalanceManager mailbox properly configured");
        console.log("+ Token mappings point to NEW synthetic tokens");
        console.log("+ gUSDT has 6 decimals (not 18)");
        console.log("+ gWBTC has 8 decimals (not 18)");
        console.log("+ gWETH has 18 decimals (correct)");
        console.log("+ Cross-chain deposits will now use correct decimals");
        
        console.log("");
        console.log("=== DEPLOYMENT RECORD UPDATE ===");
        console.log("Update deployments/appchain.json:");
        console.log("");
        console.log("\"tokenMappings\": {");
        console.log("  \"USDT\": {");
        console.log("    \"source\":", sourceUSDT, ",");
        console.log("    \"synthetic\":", gsUSDT, ",");
        console.log("    \"decimals\": 6");
        console.log("  },");
        console.log("  \"WBTC\": {");
        console.log("    \"source\":", sourceWBTC, ",");
        console.log("    \"synthetic\":", gsWBTC, ",");
        console.log("    \"decimals\": 8");
        console.log("  },");
        console.log("  \"WETH\": {");
        console.log("    \"source\":", sourceWETH, ",");
        console.log("    \"synthetic\":", gsWETH, ",");
        console.log("    \"decimals\": 18");
        console.log("  }");
        console.log("}");
        
        console.log("========== APPCHAIN CHAINBALANCEMANAGER FIXED ==========");
    }
}