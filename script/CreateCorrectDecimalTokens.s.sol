// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/SyntheticTokenFactory.sol";

contract CreateCorrectDecimalTokens is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== CREATING TOKENS WITH CORRECT DECIMALS ==========");
        console.log("Using SyntheticTokenFactory for proper deployment");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address syntheticTokenFactory = vm.parseJsonAddress(deploymentData, ".contracts.SyntheticTokenFactory");
        address balanceManager = vm.parseJsonAddress(deploymentData, ".contracts.BalanceManager");
        
        console.log("SyntheticTokenFactory:", syntheticTokenFactory);
        console.log("BalanceManager (bridge receiver):", balanceManager);
        console.log("");
        
        // Read Appchain deployment for source token addresses
        string memory appchainData = vm.readFile("deployments/appchain.json");
        
        address sourceUSDT = vm.parseJsonAddress(appchainData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(appchainData, ".contracts.WBTC");  
        address sourceWETH = vm.parseJsonAddress(appchainData, ".contracts.WETH");
        
        console.log("=== SOURCE TOKENS (Appchain) ===");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        
        SyntheticTokenFactory factory = SyntheticTokenFactory(syntheticTokenFactory);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== CREATING SYNTHETIC TOKENS WITH CORRECT DECIMALS ===");
        
        // Create gsUSDT with 6 decimals (matching real USDT)
        console.log("Creating gsUSDT with 6 decimals...");
        address newUSDT = factory.createSyntheticToken(
            4661,               // sourceChainId (Appchain)
            sourceUSDT,         // sourceToken 
            1918988905,         // targetChainId (Rari)
            "GTX Synthetic USDT v2", 
            "gsUSDT",
            6,                  // sourceDecimals (real USDT has 6)
            6                   // syntheticDecimals (correct: 6 not 18!)
        );
        console.log("NEW gsUSDT (6 decimals):", newUSDT);
        
        // Create gsWBTC with 8 decimals (matching real WBTC)
        console.log("Creating gsWBTC with 8 decimals...");
        address newWBTC = factory.createSyntheticToken(
            4661,               // sourceChainId (Appchain)
            sourceWBTC,         // sourceToken
            1918988905,         // targetChainId (Rari) 
            "GTX Synthetic WBTC v2",
            "gsWBTC", 
            8,                  // sourceDecimals (real WBTC has 8)
            8                   // syntheticDecimals (correct: 8 not 18!)
        );
        console.log("NEW gsWBTC (8 decimals):", newWBTC);
        
        // Create gsWETH with 18 decimals (already correct)
        console.log("Creating gsWETH with 18 decimals...");
        address newWETH = factory.createSyntheticToken(
            4661,               // sourceChainId (Appchain)
            sourceWETH,         // sourceToken
            1918988905,         // targetChainId (Rari)
            "GTX Synthetic WETH v2",
            "gsWETH",
            18,                 // sourceDecimals (real WETH has 18)
            18                  // syntheticDecimals (correct: 18)
        );
        console.log("NEW gsWETH (18 decimals):", newWETH);
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== TOKENS CREATED WITH CORRECT DECIMALS ===");
        console.log("gsUSDT v2 (6 decimals): ", newUSDT);
        console.log("gsWBTC v2 (8 decimals): ", newWBTC);
        console.log("gsWETH v2 (18 decimals):", newWETH);
        console.log("");
        
        console.log("=== AUTOMATIC INTEGRATIONS COMPLETED ===");
        console.log("TokenRegistry automatically updated");
        console.log("Source -> Synthetic mappings created");
        console.log("BalanceManager set as minter (bridge receiver)");
        console.log("Factory tracks all token relationships");
        console.log("");
        
        console.log("=== VERIFICATION ===");
        
        // Verify decimals
        (bool success1, bytes memory data1) = newUSDT.staticcall(abi.encodeWithSignature("decimals()"));
        if (success1 && data1.length >= 32) {
            uint8 decimals1 = abi.decode(data1, (uint8));
            console.log("gsUSDT decimals:", decimals1, "(should be 6)");
        }
        
        (bool success2, bytes memory data2) = newWBTC.staticcall(abi.encodeWithSignature("decimals()"));
        if (success2 && data2.length >= 32) {
            uint8 decimals2 = abi.decode(data2, (uint8));
            console.log("gsWBTC decimals:", decimals2, "(should be 8)");
        }
        
        (bool success3, bytes memory data3) = newWETH.staticcall(abi.encodeWithSignature("decimals()"));
        if (success3 && data3.length >= 32) {
            uint8 decimals3 = abi.decode(data3, (uint8));
            console.log("gsWETH decimals:", decimals3, "(should be 18)");
        }
        
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Update ChainBalanceManager token mappings on Appchain");
        console.log("2. Set new token mappings (old -> new addresses)");
        console.log("3. Recreate trading pools with new tokens");
        console.log("4. Test cross-chain deposits with correct decimals");
        console.log("");
        
        console.log("=== MANUAL UPDATES FOR RARI.JSON ===");
        console.log("Add new tokens to contracts section:");
        console.log("gsUSDT_v2:", newUSDT);
        console.log("gsWBTC_v2:", newWBTC);
        console.log("gsWETH_v2:", newWETH);
        
        console.log("========== CORRECT DECIMAL TOKENS CREATED ==========");
    }
}