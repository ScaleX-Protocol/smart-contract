// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/SyntheticTokenFactory.sol";
import "../src/core/TokenRegistry.sol";

contract FixTokenDecimalsUsingSyntheticFactory is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== FIXING TOKEN DECIMALS USING SYNTHETIC FACTORY ==========");
        console.log("Step 1: Remove existing mappings");
        console.log("Step 2: Create new tokens with correct decimals via Factory");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address syntheticTokenFactory = vm.parseJsonAddress(deploymentData, ".contracts.SyntheticTokenFactory");
        address tokenRegistry = vm.parseJsonAddress(deploymentData, ".contracts.TokenRegistry");
        address balanceManager = vm.parseJsonAddress(deploymentData, ".contracts.BalanceManager");
        
        console.log("SyntheticTokenFactory:", syntheticTokenFactory);
        console.log("TokenRegistry:", tokenRegistry);
        console.log("BalanceManager:", balanceManager);
        
        // Read source token addresses from Appchain
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
        
        TokenRegistry registry = TokenRegistry(tokenRegistry);
        SyntheticTokenFactory factory = SyntheticTokenFactory(syntheticTokenFactory);
        
        console.log("=== STEP 1: REMOVE EXISTING TOKEN MAPPINGS ===");
        
        // Remove existing USDT mapping
        console.log("Removing existing USDT mapping...");
        try registry.removeTokenMapping(4661, sourceUSDT, 1918988905) {
            console.log("SUCCESS: USDT mapping removed");
        } catch Error(string memory reason) {
            console.log("NOTE: USDT mapping removal -", reason);
        }
        
        // Remove existing WBTC mapping  
        console.log("Removing existing WBTC mapping...");
        try registry.removeTokenMapping(4661, sourceWBTC, 1918988905) {
            console.log("SUCCESS: WBTC mapping removed");
        } catch Error(string memory reason) {
            console.log("NOTE: WBTC mapping removal -", reason);
        }
        
        // Remove existing WETH mapping (may not exist)
        console.log("Removing existing WETH mapping...");
        try registry.removeTokenMapping(4661, sourceWETH, 1918988905) {
            console.log("SUCCESS: WETH mapping removed");
        } catch Error(string memory reason) {
            console.log("NOTE: WETH mapping removal -", reason);
        }
        
        console.log("");
        console.log("=== STEP 2: CREATE NEW TOKENS VIA SYNTHETIC FACTORY ===");
        
        // Create gsUSDT with 6 decimals
        console.log("Creating gsUSDT with 6 decimals via Factory...");
        address newUSDT;
        try factory.createSyntheticToken(
            4661,               // sourceChainId (Appchain)
            sourceUSDT,         // sourceToken 
            1918988905,         // targetChainId (Rari)
            "GTX Synthetic USDT v2", 
            "gsUSDT2",          // Different symbol
            6,                  // sourceDecimals (real USDT has 6)
            6                   // syntheticDecimals (correct: 6 not 18!)
        ) returns (address token) {
            newUSDT = token;
            console.log("SUCCESS: gsUSDT2 (6 decimals):", newUSDT);
        } catch Error(string memory reason) {
            console.log("FAILED: gsUSDT creation -", reason);
        }
        
        // Create gsWBTC with 8 decimals
        console.log("Creating gsWBTC with 8 decimals via Factory...");
        address newWBTC;
        try factory.createSyntheticToken(
            4661,               // sourceChainId (Appchain)
            sourceWBTC,         // sourceToken
            1918988905,         // targetChainId (Rari) 
            "GTX Synthetic WBTC v2",
            "gsWBTC2",          // Different symbol
            8,                  // sourceDecimals (real WBTC has 8)
            8                   // syntheticDecimals (correct: 8 not 18!)
        ) returns (address token) {
            newWBTC = token;
            console.log("SUCCESS: gsWBTC2 (8 decimals):", newWBTC);
        } catch Error(string memory reason) {
            console.log("FAILED: gsWBTC creation -", reason);
        }
        
        // Create gsWETH with 18 decimals
        console.log("Creating gsWETH with 18 decimals via Factory...");
        address newWETH;
        try factory.createSyntheticToken(
            4661,               // sourceChainId (Appchain)
            sourceWETH,         // sourceToken
            1918988905,         // targetChainId (Rari)
            "GTX Synthetic WETH v2",
            "gsWETH2",          // Different symbol
            18,                 // sourceDecimals (real WETH has 18)
            18                  // syntheticDecimals (correct: 18)
        ) returns (address token) {
            newWETH = token;
            console.log("SUCCESS: gsWETH2 (18 decimals):", newWETH);
        } catch Error(string memory reason) {
            console.log("FAILED: gsWETH creation -", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== SYNTHETIC FACTORY DEPLOYMENT COMPLETE ===");
        console.log("gsUSDT2 (6 dec): ", newUSDT);
        console.log("gsWBTC2 (8 dec): ", newWBTC);
        console.log("gsWETH2 (18 dec):", newWETH);
        console.log("");
        
        console.log("=== FACTORY BENEFITS ===");
        console.log("+ TokenRegistry automatically updated");
        console.log("+ BalanceManager automatically set as minter");
        console.log("+ Source <-> Synthetic mappings created");
        console.log("+ Factory tracks token relationships");
        console.log("+ Proper decimal conversion built-in");
        console.log("");
        
        console.log("=== NEXT STEPS ===");
        console.log("1. Update deployments/rari.json with new addresses");
        console.log("2. Update ChainBalanceManager to use new synthetic addresses");
        console.log("3. Recreate pools with correct decimal tokens");
        console.log("4. Test deposits with proper decimal handling");
        console.log("");
        
        console.log("Update rari.json contracts:");
        console.log("gsUSDT_v2:", newUSDT);
        console.log("gsWBTC_v2:", newWBTC); 
        console.log("gsWETH_v2:", newWETH);
        
        console.log("========== CORRECT DECIMALS VIA FACTORY COMPLETE ==========");
    }
}