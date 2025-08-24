// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract UpdateAppchainTokenMappingsOnly is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPDATE APPCHAIN TOKEN MAPPINGS ==========");
        console.log("Update ChainBalanceManager to use NEW synthetic tokens with correct decimals");
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
        
        // Source tokens on Appchain
        address sourceUSDT = vm.parseJsonAddress(appchainData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(appchainData, ".contracts.WBTC");
        address sourceWETH = vm.parseJsonAddress(appchainData, ".contracts.WETH");
        
        // NEW synthetic tokens on Rari (clean names, correct decimals)
        address gsUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");  // gUSDT (6 decimals)
        address gsWBTC = vm.parseJsonAddress(rariData, ".contracts.gsWBTC");  // gWBTC (8 decimals)
        address gsWETH = vm.parseJsonAddress(rariData, ".contracts.gsWETH");  // gWETH (18 decimals)
        
        console.log("");
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("");
        console.log("=== SOURCE TOKENS (APPCHAIN) ===");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        console.log("=== NEW SYNTHETIC TOKENS (RARI - CORRECT DECIMALS) ===");
        console.log("gUSDT (6 decimals):", gsUSDT);
        console.log("gWBTC (8 decimals):", gsWBTC);
        console.log("gWETH (18 decimals):", gsWETH);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        console.log("=== CHECK CURRENT MAPPINGS ===");
        
        address currentUSDT = cbm.getTokenMapping(sourceUSDT);
        address currentWBTC = cbm.getTokenMapping(sourceWBTC);
        address currentWETH = cbm.getTokenMapping(sourceWETH);
        
        console.log("Current USDT ->", currentUSDT);
        console.log("Current WBTC ->", currentWBTC);
        console.log("Current WETH ->", currentWETH);
        console.log("");
        console.log("Should be:");
        console.log("USDT ->", gsUSDT);
        console.log("WBTC ->", gsWBTC);
        console.log("WETH ->", gsWETH);
        console.log("");
        
        console.log("=== UPDATE TOKEN MAPPINGS ===");
        
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
        console.log("=== VERIFY FINAL MAPPINGS ===");
        
        address finalUSDT = cbm.getTokenMapping(sourceUSDT);
        address finalWBTC = cbm.getTokenMapping(sourceWBTC);
        address finalWETH = cbm.getTokenMapping(sourceWETH);
        
        console.log("Final mappings:");
        console.log("USDT ->", finalUSDT);
        console.log("WBTC ->", finalWBTC);
        console.log("WETH ->", finalWETH);
        console.log("");
        console.log("Verification:");
        console.log("USDT correct:", finalUSDT == gsUSDT ? "YES" : "NO");
        console.log("WBTC correct:", finalWBTC == gsWBTC ? "YES" : "NO");
        console.log("WETH correct:", finalWETH == gsWETH ? "YES" : "NO");
        
        vm.stopBroadcast();
        
        bool allCorrect = (finalUSDT == gsUSDT) && (finalWBTC == gsWBTC) && (finalWETH == gsWETH);
        
        console.log("");
        if (allCorrect) {
            console.log("SUCCESS: All token mappings updated to correct decimals!");
        } else {
            console.log("WARNING: Some mappings still incorrect");
        }
        
        console.log("");
        console.log("=== WHAT'S FIXED ===");
        console.log("+ USDT -> gUSDT (6 decimals instead of 18)");
        console.log("+ WBTC -> gWBTC (8 decimals instead of 18)");
        console.log("+ WETH -> gWETH (18 decimals - correct)");
        console.log("+ Cross-chain deposits now use correct decimal tokens");
        console.log("+ Clean token names (gUSDT, gWBTC, gWETH)");
        
        console.log("========== APPCHAIN TOKEN MAPPINGS UPDATED ==========");
    }
}