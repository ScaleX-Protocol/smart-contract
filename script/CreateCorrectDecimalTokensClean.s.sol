// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/SyntheticTokenFactory.sol";

contract CreateCorrectDecimalTokensClean is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== CREATING CORRECT DECIMAL TOKENS ==========");
        console.log("Using SyntheticTokenFactory with different source chain");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        address syntheticTokenFactory = vm.parseJsonAddress(deploymentData, ".contracts.SyntheticTokenFactory");
        
        // Read source tokens from Appchain
        string memory appchainData = vm.readFile("deployments/appchain.json");
        address sourceUSDT = vm.parseJsonAddress(appchainData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(appchainData, ".contracts.WBTC");
        address sourceWETH = vm.parseJsonAddress(appchainData, ".contracts.WETH");
        
        console.log("SyntheticTokenFactory:", syntheticTokenFactory);
        console.log("");
        console.log("Source tokens (using as reference):");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        
        // Use different source chain to avoid conflicts with existing mappings
        uint32 newSourceChainId = 421614; // Arbitrum Sepolia (different from existing 4661)
        
        console.log("Using source chain ID:", newSourceChainId, "(Arbitrum Sepolia)");
        console.log("This avoids conflicts with existing chain 4661 mappings");
        console.log("");
        
        SyntheticTokenFactory factory = SyntheticTokenFactory(syntheticTokenFactory);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== CREATING TOKENS WITH CORRECT DECIMALS ===");
        
        // Create gsUSDT with 6 decimals
        console.log("Creating gsUSDT with 6 decimals...");
        address newUSDT = factory.createSyntheticToken(
            newSourceChainId,    // 421614 (different chain to avoid conflicts)
            sourceUSDT,          // source token address (for reference)
            1918988905,          // targetChainId (Rari)
            "GTX Synthetic USDT v2", 
            "gsUSDT2",           // different symbol
            6,                   // sourceDecimals (real USDT = 6)
            6                    // syntheticDecimals (CORRECT: 6 not 18!)
        );
        console.log("SUCCESS: gsUSDT2 (6 decimals):", newUSDT);
        
        // Create gsWBTC with 8 decimals  
        console.log("Creating gsWBTC with 8 decimals...");
        address newWBTC = factory.createSyntheticToken(
            newSourceChainId,    // 421614
            sourceWBTC,          // source token address (for reference)
            1918988905,          // targetChainId (Rari)
            "GTX Synthetic WBTC v2",
            "gsWBTC2",           // different symbol
            8,                   // sourceDecimals (real WBTC = 8)
            8                    // syntheticDecimals (CORRECT: 8 not 18!)
        );
        console.log("SUCCESS: gsWBTC2 (8 decimals):", newWBTC);
        
        // Create gsWETH with 18 decimals
        console.log("Creating gsWETH with 18 decimals...");
        address newWETH = factory.createSyntheticToken(
            newSourceChainId,    // 421614
            sourceWETH,          // source token address (for reference)
            1918988905,          // targetChainId (Rari)
            "GTX Synthetic WETH v2",
            "gsWETH2",           // different symbol
            18,                  // sourceDecimals (real WETH = 18)
            18                   // syntheticDecimals (CORRECT: 18)
        );
        console.log("SUCCESS: gsWETH2 (18 decimals):", newWETH);
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== CORRECT DECIMAL TOKENS CREATED ===");
        console.log("gsUSDT2 (6 decimals): ", newUSDT);
        console.log("gsWBTC2 (8 decimals): ", newWBTC);
        console.log("gsWETH2 (18 decimals):", newWETH);
        console.log("");
        
        console.log("=== VERIFY DECIMALS ===");
        
        // Check decimals
        (bool s1, bytes memory d1) = newUSDT.staticcall(abi.encodeWithSignature("decimals()"));
        if (s1) console.log("gsUSDT2 decimals:", abi.decode(d1, (uint8)));
        
        (bool s2, bytes memory d2) = newWBTC.staticcall(abi.encodeWithSignature("decimals()"));
        if (s2) console.log("gsWBTC2 decimals:", abi.decode(d2, (uint8)));
        
        (bool s3, bytes memory d3) = newWETH.staticcall(abi.encodeWithSignature("decimals()"));
        if (s3) console.log("gsWETH2 decimals:", abi.decode(d3, (uint8)));
        
        console.log("");
        console.log("=== FACTORY BENEFITS ===");
        console.log("+ TokenRegistry automatically updated");
        console.log("+ BalanceManager set as minter");
        console.log("+ Source <-> Synthetic mappings created");
        console.log("+ Decimal conversion built-in");
        console.log("");
        
        console.log("=== NEXT STEPS ===");
        console.log("1. Update deployments/rari.json");
        console.log("2. Update ChainBalanceManager mappings");
        console.log("3. Create new pools with correct tokens");
        console.log("4. Test deposits with proper decimals");
        console.log("");
        
        console.log("Add to rari.json contracts:");
        console.log('gsUSDT_v2:', newUSDT);
        console.log('gsWBTC_v2:', newWBTC);
        console.log('gsWETH_v2:', newWETH);
        
        console.log("========== CORRECT DECIMALS COMPLETE ==========");
    }
}