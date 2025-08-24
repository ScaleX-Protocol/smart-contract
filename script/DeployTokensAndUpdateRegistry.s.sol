// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/token/SyntheticToken.sol";
import "../src/core/TokenRegistry.sol";

contract DeployTokensAndUpdateRegistry is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== DEPLOY TOKENS + UPDATE REGISTRY ==========");
        console.log("Step 1: Deploy tokens with correct decimals");
        console.log("Step 2: Update TokenRegistry mappings");
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
        
        console.log("TokenRegistry:", tokenRegistry);
        console.log("BalanceManager (minter):", balanceManager);
        
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
        
        console.log("=== STEP 1: DEPLOY NEW TOKENS WITH CORRECT DECIMALS ===");
        
        // Deploy gsUSDT with 6 decimals
        console.log("Deploying gsUSDT with 6 decimals...");
        SyntheticToken newUSDT = new SyntheticToken(
            "GTX Synthetic USDT v3",
            "gsUSDT3",
            6,              // CORRECT: 6 decimals like real USDT
            balanceManager  // minter = BalanceManager
        );
        console.log("gsUSDT3 (6 decimals):", address(newUSDT));
        
        // Deploy gsWBTC with 8 decimals
        console.log("Deploying gsWBTC with 8 decimals...");
        SyntheticToken newWBTC = new SyntheticToken(
            "GTX Synthetic WBTC v3",
            "gsWBTC3",
            8,              // CORRECT: 8 decimals like real WBTC
            balanceManager  // minter = BalanceManager
        );
        console.log("gsWBTC3 (8 decimals):", address(newWBTC));
        
        // Deploy gsWETH with 18 decimals
        console.log("Deploying gsWETH with 18 decimals...");
        SyntheticToken newWETH = new SyntheticToken(
            "GTX Synthetic WETH v3",
            "gsWETH3",
            18,             // CORRECT: 18 decimals like real WETH
            balanceManager  // minter = BalanceManager
        );
        console.log("gsWETH3 (18 decimals):", address(newWETH));
        
        console.log("");
        console.log("=== STEP 2: UPDATE TOKEN REGISTRY MAPPINGS ===");
        console.log("NOTE: TokenRegistry is owned by SyntheticTokenFactory");
        console.log("Need to update through owner or transfer ownership temporarily");
        console.log("");
        
        TokenRegistry registry = TokenRegistry(tokenRegistry);
        
        // Check current owner
        address currentOwner = registry.owner();
        console.log("TokenRegistry owner:", currentOwner);
        
        if (currentOwner == deployer) {
            // If deployer owns registry, update directly
            console.log("Deployer owns registry - updating mappings directly...");
            
            // Update USDT mapping
            console.log("Updating USDT mapping...");
            try registry.updateTokenMapping(
                4661,                    // sourceChainId (CORRECT: Appchain)
                sourceUSDT,              // sourceToken
                1918988905,              // targetChainId (Rari)
                address(newUSDT),        // newSyntheticToken
                6                        // newSyntheticDecimals
            ) {
                console.log("SUCCESS: USDT mapping updated");
            } catch Error(string memory reason) {
                console.log("FAILED: USDT mapping -", reason);
            }
            
            // Update WBTC mapping
            console.log("Updating WBTC mapping...");
            try registry.updateTokenMapping(
                4661,                    // sourceChainId (CORRECT: Appchain)
                sourceWBTC,              // sourceToken
                1918988905,              // targetChainId (Rari)
                address(newWBTC),        // newSyntheticToken
                8                        // newSyntheticDecimals
            ) {
                console.log("SUCCESS: WBTC mapping updated");
            } catch Error(string memory reason) {
                console.log("FAILED: WBTC mapping -", reason);
            }
            
            // Update WETH mapping
            console.log("Updating WETH mapping...");
            try registry.updateTokenMapping(
                4661,                    // sourceChainId (CORRECT: Appchain)
                sourceWETH,              // sourceToken
                1918988905,              // targetChainId (Rari)
                address(newWETH),        // newSyntheticToken
                18                       // newSyntheticDecimals
            ) {
                console.log("SUCCESS: WETH mapping updated");
            } catch Error(string memory reason) {
                console.log("FAILED: WETH mapping -", reason);
            }
        } else {
            console.log("Deployer does not own TokenRegistry");
            console.log("Current owner is:", currentOwner);
            console.log("Cannot update mappings without ownership");
            console.log("");
            console.log("MANUAL STEP REQUIRED:");
            console.log("1. Transfer TokenRegistry ownership to deployer, OR");
            console.log("2. Call updateTokenMapping from current owner");
            console.log("");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("gsUSDT3 (6 decimals): ", address(newUSDT));
        console.log("gsWBTC3 (8 decimals): ", address(newWBTC));
        console.log("gsWETH3 (18 decimals):", address(newWETH));
        console.log("");
        
        console.log("=== VERIFY DECIMALS ===");
        console.log("gsUSDT3 decimals:", newUSDT.decimals(), "(should be 6)");
        console.log("gsWBTC3 decimals:", newWBTC.decimals(), "(should be 8)");
        console.log("gsWETH3 decimals:", newWETH.decimals(), "(should be 18)");
        console.log("");
        
        console.log("=== NEXT STEPS ===");
        console.log("1. Update TokenRegistry mappings (may need owner)");
        console.log("2. Update ChainBalanceManager token mappings");
        console.log("3. Create new pools with correct decimal tokens");
        console.log("4. Test cross-chain deposits");
        console.log("");
        
        console.log("Add to rari.json:");
        console.log("gsUSDT_v3:", address(newUSDT));
        console.log("gsWBTC_v3:", address(newWBTC));
        console.log("gsWETH_v3:", address(newWETH));
        
        console.log("========== TOKENS DEPLOYED WITH CORRECT DECIMALS ==========");
    }
}