// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/token/SyntheticToken.sol";
import "../src/core/SyntheticTokenFactory.sol";

contract DeployCleanTokenNames is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== DEPLOY TOKENS WITH CLEAN NAMES ==========");
        console.log("Deploy tokens without suffix (gsUSDT, gsWBTC, gsWETH)");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address balanceManager = vm.parseJsonAddress(deploymentData, ".contracts.BalanceManager");
        address factoryProxy = vm.parseJsonAddress(deploymentData, ".contracts.SyntheticTokenFactory");
        
        console.log("BalanceManager (minter):", balanceManager);
        console.log("SyntheticTokenFactory:", factoryProxy);
        
        // Read source tokens from Appchain
        string memory appchainData = vm.readFile("deployments/appchain.json");
        address sourceUSDT = vm.parseJsonAddress(appchainData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(appchainData, ".contracts.WBTC");
        address sourceWETH = vm.parseJsonAddress(appchainData, ".contracts.WETH");
        
        console.log("");
        console.log("=== SOURCE TOKENS (Appchain 4661) ===");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== DEPLOY NEW TOKENS WITH CLEAN NAMES ===");
        
        // Deploy gsUSDT with 6 decimals (clean name)
        console.log("Deploying gsUSDT with 6 decimals...");
        SyntheticToken cleanUSDT = new SyntheticToken(
            "GTX Synthetic USDT",
            "gsUSDT",            // Clean symbol
            6,                   // CORRECT: 6 decimals like real USDT
            balanceManager       // minter = BalanceManager
        );
        console.log("gsUSDT (6 decimals):", address(cleanUSDT));
        
        // Deploy gsWBTC with 8 decimals (clean name)
        console.log("Deploying gsWBTC with 8 decimals...");
        SyntheticToken cleanWBTC = new SyntheticToken(
            "GTX Synthetic WBTC",
            "gsWBTC",            // Clean symbol
            8,                   // CORRECT: 8 decimals like real WBTC
            balanceManager       // minter = BalanceManager
        );
        console.log("gsWBTC (8 decimals):", address(cleanWBTC));
        
        // Deploy gsWETH with 18 decimals (clean name)
        console.log("Deploying gsWETH with 18 decimals...");
        SyntheticToken cleanWETH = new SyntheticToken(
            "GTX Synthetic WETH",
            "gsWETH",            // Clean symbol
            18,                  // CORRECT: 18 decimals like real WETH
            balanceManager       // minter = BalanceManager
        );
        console.log("gsWETH (18 decimals):", address(cleanWETH));
        
        console.log("");
        console.log("=== UPDATE TOKEN REGISTRY MAPPINGS ===");
        
        SyntheticTokenFactory factory = SyntheticTokenFactory(factoryProxy);
        
        // Update USDT mapping to clean token
        console.log("Updating USDT mapping to clean token...");
        try factory.updateTokenMapping(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceUSDT,              // sourceToken
            1918988905,              // targetChainId (Rari)
            address(cleanUSDT),      // newSyntheticToken
            6                        // newSyntheticDecimals
        ) {
            console.log("SUCCESS: USDT mapping updated to clean token");
        } catch Error(string memory reason) {
            console.log("FAILED: USDT mapping -", reason);
        }
        
        // Update WBTC mapping to clean token
        console.log("Updating WBTC mapping to clean token...");
        try factory.updateTokenMapping(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceWBTC,              // sourceToken
            1918988905,              // targetChainId (Rari)
            address(cleanWBTC),      // newSyntheticToken
            8                        // newSyntheticDecimals
        ) {
            console.log("SUCCESS: WBTC mapping updated to clean token");
        } catch Error(string memory reason) {
            console.log("FAILED: WBTC mapping -", reason);
        }
        
        // Update WETH mapping to clean token
        console.log("Updating WETH mapping to clean token...");
        try factory.updateTokenMapping(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceWETH,              // sourceToken
            1918988905,              // targetChainId (Rari)
            address(cleanWETH),      // newSyntheticToken
            18                       // newSyntheticDecimals
        ) {
            console.log("SUCCESS: WETH mapping updated to clean token");
        } catch Error(string memory reason) {
            console.log("FAILED: WETH mapping -", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("gsUSDT (6 decimals): ", address(cleanUSDT));
        console.log("gsWBTC (8 decimals): ", address(cleanWBTC));
        console.log("gsWETH (18 decimals):", address(cleanWETH));
        console.log("");
        
        console.log("=== VERIFY DECIMALS ===");
        console.log("gsUSDT decimals:", cleanUSDT.decimals(), "(should be 6)");
        console.log("gsWBTC decimals:", cleanWBTC.decimals(), "(should be 8)");
        console.log("gsWETH decimals:", cleanWETH.decimals(), "(should be 18)");
        console.log("");
        
        console.log("Add to rari.json:");
        console.log("gsUSDT_clean:", address(cleanUSDT));
        console.log("gsWBTC_clean:", address(cleanWBTC));
        console.log("gsWETH_clean:", address(cleanWETH));
        
        console.log("========== CLEAN TOKENS DEPLOYED + MAPPED ==========");
    }
}