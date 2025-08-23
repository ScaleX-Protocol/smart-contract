// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract CompareChainConfigs is Script {
    
    function run() public {
        console.log("========== COMPARE CHAIN CONFIGS ==========");
        console.log("Compare Arbitrum (failing) vs Appchain (working) configurations");
        console.log("Network:", vm.toString(block.chainid));
        
        // Read deployment data for both chains
        string memory appchainData = vm.readFile("deployments/appchain.json");
        string memory arbitrumData = vm.readFile("deployments/arbitrum-sepolia.json");
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address appchainCBM = vm.parseJsonAddress(appchainData, ".contracts.ChainBalanceManager");
        address arbitrumCBM = vm.parseJsonAddress(arbitrumData, ".contracts.ChainBalanceManager");
        address rariBalanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        uint32 rariDomain = uint32(vm.parseJsonUint(rariData, ".domainId"));
        
        console.log("Appchain ChainBalanceManager:", appchainCBM);
        console.log("Arbitrum ChainBalanceManager:", arbitrumCBM);
        console.log("Rari BalanceManager:", rariBalanceManager);
        console.log("Rari Domain:", rariDomain);
        console.log("");
        
        if (block.chainid == 4661) {
            // Check Appchain configuration (working)
            console.log("=== APPCHAIN CONFIGURATION (WORKING) ===");
            checkChainBalanceManagerConfig(appchainCBM, "APPCHAIN");
        } else if (block.chainid == 421614) {
            // Check Arbitrum configuration (failing)
            console.log("=== ARBITRUM CONFIGURATION (FAILING) ===");
            checkChainBalanceManagerConfig(arbitrumCBM, "ARBITRUM");
        } else {
            console.log("Run this script on Appchain (4661) or Arbitrum (421614) to compare");
            return;
        }
        
        console.log("========== CONFIGURATION COMPARISON COMPLETE ==========");
    }
    
    function checkChainBalanceManagerConfig(address cbm, string memory chainName) internal {
        ChainBalanceManager cbmContract = ChainBalanceManager(cbm);
        
        console.log("Checking", chainName, "ChainBalanceManager:", cbm);
        console.log("");
        
        // Check cross-chain config
        console.log("=== CROSS-CHAIN CONFIG ===");
        try cbmContract.getCrossChainConfig() returns (uint32 destDomain, address destBalanceManager) {
            console.log("Destination domain:", destDomain);
            console.log("Destination BalanceManager:", destBalanceManager);
            
            if (destDomain == 1918988905) {
                console.log("Domain: CORRECT (Rari)");
            } else {
                console.log("Domain: INCORRECT (should be 1918988905)");
            }
            
            if (destBalanceManager == 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5) {
                console.log("BalanceManager: CORRECT");
            } else {
                console.log("BalanceManager: INCORRECT (should be 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5)");
            }
        } catch Error(string memory reason) {
            console.log("FAILED to get cross-chain config:", reason);
        }
        
        console.log("");
        
        // Check token mappings
        console.log("=== TOKEN MAPPINGS ===");
        
        // Get source token addresses based on chain
        address sourceUSDT;
        address sourceWBTC;
        address sourceWETH;
        
        if (block.chainid == 4661) {
            // Appchain
            sourceUSDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
            sourceWBTC = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;
            sourceWETH = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
        } else if (block.chainid == 421614) {
            // Arbitrum
            sourceUSDT = 0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a;
            sourceWBTC = 0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A;
            sourceWETH = 0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7;
        }
        
        address expectedUSDT = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d; // gUSDT (6 decimals)
        address expectedWBTC = 0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748; // gWBTC (8 decimals)  
        address expectedWETH = 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8; // gWETH (18 decimals)
        
        address mappedUSDT = cbmContract.getTokenMapping(sourceUSDT);
        address mappedWBTC = cbmContract.getTokenMapping(sourceWBTC);
        address mappedWETH = cbmContract.getTokenMapping(sourceWETH);
        
        console.log("USDT mapping:");
        console.log("  Source:", sourceUSDT);
        console.log("  Mapped to:", mappedUSDT);
        console.log("  Expected:", expectedUSDT);
        console.log("  Status:", mappedUSDT == expectedUSDT ? "CORRECT" : "INCORRECT");
        console.log("");
        
        console.log("WBTC mapping:");
        console.log("  Source:", sourceWBTC);
        console.log("  Mapped to:", mappedWBTC);
        console.log("  Expected:", expectedWBTC);
        console.log("  Status:", mappedWBTC == expectedWBTC ? "CORRECT" : "INCORRECT");
        console.log("");
        
        console.log("WETH mapping:");
        console.log("  Source:", sourceWETH);
        console.log("  Mapped to:", mappedWETH);
        console.log("  Expected:", expectedWETH);
        console.log("  Status:", mappedWETH == expectedWETH ? "CORRECT" : "INCORRECT");
        console.log("");
        
        // Check owner
        console.log("=== OWNERSHIP ===");
        try cbmContract.owner() returns (address owner) {
            console.log("Owner:", owner);
            
            if (owner == 0x77C037fbF42e85dB1487B390b08f58C00f438812) {
                console.log("Owner: CORRECT");
            } else {
                console.log("Owner: Check if this is correct");
            }
        } catch {
            console.log("Could not get owner");
        }
        
        console.log("");
        console.log("=== SUMMARY FOR", chainName, "===");
        
        bool configOK = (mappedUSDT == expectedUSDT) && (mappedWBTC == expectedWBTC) && (mappedWETH == expectedWETH);
        
        if (configOK) {
            console.log("STATUS: Configuration looks correct");
            console.log("If relay failing, issue might be:");
            console.log("- Message format compatibility");
            console.log("- Hyperlane relayer configuration");  
            console.log("- Gas estimation issues");
            console.log("- Rari BalanceManager processing");
        } else {
            console.log("STATUS: Configuration has issues");
            console.log("Fix token mappings first");
        }
    }
}