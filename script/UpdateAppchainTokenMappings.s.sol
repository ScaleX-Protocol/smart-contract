// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract UpdateAppchainTokenMappings is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPDATE APPCHAIN TOKEN MAPPINGS ==========");
        console.log("Update ChainBalanceManager to use new synthetic tokens");
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
        
        // New synthetic tokens on Rari (clean names)
        address gsUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");
        address gsWBTC = vm.parseJsonAddress(rariData, ".contracts.gsWBTC");
        address gsWETH = vm.parseJsonAddress(rariData, ".contracts.gsWETH");
        
        console.log("");
        console.log("=== APPCHAIN SOURCE TOKENS ===");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        console.log("=== RARI SYNTHETIC TOKENS (NEW) ===");
        console.log("gsUSDT (6 decimals):", gsUSDT);
        console.log("gsWBTC (8 decimals):", gsWBTC);
        console.log("gsWETH (18 decimals):", gsWETH);
        console.log("");
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        console.log("=== UPDATE TOKEN MAPPINGS ===");
        
        // Update USDT mapping
        console.log("Updating USDT -> gsUSDT mapping...");
        try cbm.setTokenMapping(sourceUSDT, gsUSDT) {
            console.log("SUCCESS: USDT mapping updated");
        } catch Error(string memory reason) {
            console.log("FAILED: USDT mapping -", reason);
        }
        
        // Update WBTC mapping
        console.log("Updating WBTC -> gsWBTC mapping...");
        try cbm.setTokenMapping(sourceWBTC, gsWBTC) {
            console.log("SUCCESS: WBTC mapping updated");
        } catch Error(string memory reason) {
            console.log("FAILED: WBTC mapping -", reason);
        }
        
        // Update WETH mapping
        console.log("Updating WETH -> gsWETH mapping...");
        try cbm.setTokenMapping(sourceWETH, gsWETH) {
            console.log("SUCCESS: WETH mapping updated");
        } catch Error(string memory reason) {
            console.log("FAILED: WETH mapping -", reason);
        }
        
        console.log("");
        console.log("=== VERIFICATION ===");
        
        // Verify mappings
        address usdtMapping = cbm.getTokenMapping(sourceUSDT);
        address wbtcMapping = cbm.getTokenMapping(sourceWBTC);
        address wethMapping = cbm.getTokenMapping(sourceWETH);
        
        console.log("USDT ->", usdtMapping, "(expected:", gsUSDT, ")");
        console.log("WBTC ->", wbtcMapping, "(expected:", gsWBTC, ")");
        console.log("WETH ->", wethMapping, "(expected:", gsWETH, ")");
        
        bool usdtCorrect = usdtMapping == gsUSDT;
        bool wbtcCorrect = wbtcMapping == gsWBTC;
        bool wethCorrect = wethMapping == gsWETH;
        
        console.log("");
        console.log("USDT mapping correct:", usdtCorrect ? "YES" : "NO");
        console.log("WBTC mapping correct:", wbtcCorrect ? "YES" : "NO");
        console.log("WETH mapping correct:", wethCorrect ? "YES" : "NO");
        
        if (usdtCorrect && wbtcCorrect && wethCorrect) {
            console.log("");
            console.log("SUCCESS: All token mappings updated to new synthetic tokens!");
        } else {
            console.log("");
            console.log("WARNING: Some mappings need manual correction");
        }
        
        vm.stopBroadcast();
        
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
        
        console.log("========== APPCHAIN MAPPINGS UPDATED ==========");
    }
}