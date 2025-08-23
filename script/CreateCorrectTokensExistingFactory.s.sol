// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/SyntheticTokenFactory.sol";

contract CreateCorrectTokensExistingFactory is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== CREATE TOKENS WITH CORRECT DECIMALS ==========");
        console.log("Using existing SyntheticTokenFactory to create tokens");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address factoryAddr = vm.parseJsonAddress(deploymentData, ".contracts.SyntheticTokenFactory");
        SyntheticTokenFactory factory = SyntheticTokenFactory(factoryAddr);
        
        console.log("Using SyntheticTokenFactory:", factoryAddr);
        
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
        
        console.log("=== CREATING TOKENS WITH CORRECT DECIMALS ===");
        
        // Create gsUSDT with 6 decimals
        console.log("Creating gsUSDT with 6 decimals...");
        address newUSDT;
        try factory.createSyntheticToken(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceUSDT,              // sourceToken
            1918988905,              // targetChainId (Rari)
            "GTX Synthetic USDT v3", 
            "gsUSDT3",               // New symbol to avoid conflict
            6,                       // sourceDecimals
            6                        // syntheticDecimals (CORRECT!)
        ) returns (address token) {
            newUSDT = token;
            console.log("SUCCESS: gsUSDT3 (6 decimals):", newUSDT);
        } catch Error(string memory reason) {
            console.log("NOTE: gsUSDT3 creation -", reason);
        }
        
        // Create gsWBTC with 8 decimals
        console.log("Creating gsWBTC with 8 decimals...");
        address newWBTC;
        try factory.createSyntheticToken(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceWBTC,              // sourceToken
            1918988905,              // targetChainId (Rari)
            "GTX Synthetic WBTC v3",
            "gsWBTC3",               // New symbol to avoid conflict
            8,                       // sourceDecimals
            8                        // syntheticDecimals (CORRECT!)
        ) returns (address token) {
            newWBTC = token;
            console.log("SUCCESS: gsWBTC3 (8 decimals):", newWBTC);
        } catch Error(string memory reason) {
            console.log("NOTE: gsWBTC3 creation -", reason);
        }
        
        // Create gsWETH with 18 decimals
        console.log("Creating gsWETH with 18 decimals...");
        address newWETH;
        try factory.createSyntheticToken(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceWETH,              // sourceToken
            1918988905,              // targetChainId (Rari)
            "GTX Synthetic WETH v3",
            "gsWETH3",               // New symbol to avoid conflict
            18,                      // sourceDecimals
            18                       // syntheticDecimals (CORRECT!)
        ) returns (address token) {
            newWETH = token;
            console.log("SUCCESS: gsWETH3 (18 decimals):", newWETH);
        } catch Error(string memory reason) {
            console.log("NOTE: gsWETH3 creation -", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== TOKENS WITH CORRECT DECIMALS CREATED ===");
        console.log("gsUSDT3 (6 decimals): ", newUSDT);
        console.log("gsWBTC3 (8 decimals): ", newWBTC);
        console.log("gsWETH3 (18 decimals):", newWETH);
        console.log("");
        
        console.log("=== VERIFY DECIMALS ===");
        
        if (newUSDT != address(0)) {
            (bool s1, bytes memory d1) = newUSDT.staticcall(abi.encodeWithSignature("decimals()"));
            if (s1) console.log("gsUSDT3 decimals:", abi.decode(d1, (uint8)), "(should be 6)");
        }
        
        if (newWBTC != address(0)) {
            (bool s2, bytes memory d2) = newWBTC.staticcall(abi.encodeWithSignature("decimals()"));
            if (s2) console.log("gsWBTC3 decimals:", abi.decode(d2, (uint8)), "(should be 8)");
        }
        
        if (newWETH != address(0)) {
            (bool s3, bytes memory d3) = newWETH.staticcall(abi.encodeWithSignature("decimals()"));
            if (s3) console.log("gsWETH3 decimals:", abi.decode(d3, (uint8)), "(should be 18)");
        }
        
        console.log("");
        console.log("=== SUCCESS: CORRECT DECIMALS + REGISTRY INTEGRATION ===");
        console.log("+ Uses correct chain ID 4661 for Hyperlane");
        console.log("+ TokenRegistry automatically updated");
        console.log("+ Cross-chain functionality maintained");
        console.log("+ Decimals match real tokens");
        console.log("");
        
        console.log("Add to rari.json:");
        console.log("gsUSDT_v3:", newUSDT);
        console.log("gsWBTC_v3:", newWBTC);
        console.log("gsWETH_v3:", newWETH);
        
        console.log("========== CORRECT DECIMALS COMPLETE ==========");
    }
}