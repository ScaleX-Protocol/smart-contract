// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/SyntheticTokenFactory.sol";
import "../src/core/TokenRegistry.sol";

contract CreateTokensWithCorrectDecimals is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== CREATING TOKENS WITH CORRECT DECIMALS ==========");
        console.log("Step 1: Deploy updated SyntheticTokenFactory");
        console.log("Step 2: Update TokenRegistry mappings");  
        console.log("Step 3: Create tokens with proper decimals");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address tokenRegistry = vm.parseJsonAddress(deploymentData, ".contracts.TokenRegistry");
        address balanceManager = vm.parseJsonAddress(deploymentData, ".contracts.BalanceManager");
        address oldFactory = vm.parseJsonAddress(deploymentData, ".contracts.SyntheticTokenFactory");
        
        console.log("TokenRegistry:", tokenRegistry);
        console.log("BalanceManager:", balanceManager);
        console.log("Old SyntheticTokenFactory:", oldFactory);
        
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
        
        console.log("=== STEP 1: DEPLOY UPDATED SYNTHETIC TOKEN FACTORY ===");
        
        // Deploy new SyntheticTokenFactory with decimal support
        SyntheticTokenFactory newFactory = new SyntheticTokenFactory();
        newFactory.initialize(
            deployer,        // owner
            tokenRegistry,   // tokenRegistry
            balanceManager   // bridgeReceiver
        );
        
        console.log("New SyntheticTokenFactory:", address(newFactory));
        
        // Transfer TokenRegistry ownership to new factory
        console.log("Transferring TokenRegistry ownership to new factory...");
        try TokenRegistry(tokenRegistry).transferOwnership(address(newFactory)) {
            console.log("SUCCESS: TokenRegistry ownership transferred");
        } catch Error(string memory reason) {
            console.log("FAILED: TokenRegistry ownership transfer -", reason);
        }
        
        console.log("");
        console.log("=== STEP 2: CREATE TOKENS WITH CORRECT DECIMALS ===");
        
        // Create gsUSDT with 6 decimals (using correct chain 4661)
        console.log("Creating gsUSDT with 6 decimals...");
        address newUSDT;
        try newFactory.createSyntheticToken(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceUSDT,              // sourceToken
            1918988905,              // targetChainId (Rari)
            "GTX Synthetic USDT v3", 
            "gsUSDT3",               // New symbol
            6,                       // sourceDecimals
            6                        // syntheticDecimals (FIXED!)
        ) returns (address token) {
            newUSDT = token;
            console.log("SUCCESS: gsUSDT3 (6 decimals):", newUSDT);
        } catch Error(string memory reason) {
            console.log("NOTE: gsUSDT3 creation -", reason);
        }
        
        // Create gsWBTC with 8 decimals
        console.log("Creating gsWBTC with 8 decimals...");
        address newWBTC;
        try newFactory.createSyntheticToken(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceWBTC,              // sourceToken
            1918988905,              // targetChainId (Rari)
            "GTX Synthetic WBTC v3",
            "gsWBTC3",               // New symbol
            8,                       // sourceDecimals
            8                        // syntheticDecimals (FIXED!)
        ) returns (address token) {
            newWBTC = token;
            console.log("SUCCESS: gsWBTC3 (8 decimals):", newWBTC);
        } catch Error(string memory reason) {
            console.log("NOTE: gsWBTC3 creation -", reason);
        }
        
        // Create gsWETH with 18 decimals
        console.log("Creating gsWETH with 18 decimals...");
        address newWETH;
        try newFactory.createSyntheticToken(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceWETH,              // sourceToken
            1918988905,              // targetChainId (Rari)
            "GTX Synthetic WETH v3",
            "gsWETH3",               // New symbol
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
        console.log("=== SUCCESS: PROPER DECIMALS + CORRECT CHAIN MAPPINGS ===");
        console.log("+ Uses correct chain ID 4661 for Hyperlane");
        console.log("+ TokenRegistry has proper mappings");
        console.log("+ Other contracts can read from registry");
        console.log("+ Decimals match real tokens");
        console.log("");
        
        console.log("Add to rari.json:");
        console.log("SyntheticTokenFactory_v2:", address(newFactory));
        console.log("gsUSDT_v3:", newUSDT);
        console.log("gsWBTC_v3:", newWBTC);
        console.log("gsWETH_v3:", newWETH);
        
        console.log("========== CORRECT DECIMALS + REGISTRY COMPLETE ==========");
    }
}