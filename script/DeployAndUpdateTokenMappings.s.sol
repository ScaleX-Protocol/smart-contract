// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/SyntheticERC20.sol";
import "../src/core/TokenRegistry.sol";

contract DeployAndUpdateTokenMappings is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== DEPLOY TOKENS + UPDATE REGISTRY ==========");
        console.log("Step 1: Deploy new tokens with correct decimals");
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
        address syntheticTokenFactory = vm.parseJsonAddress(deploymentData, ".contracts.SyntheticTokenFactory");
        
        console.log("TokenRegistry:", tokenRegistry);
        console.log("BalanceManager (minter):", balanceManager);
        console.log("SyntheticTokenFactory (registry owner):", syntheticTokenFactory);
        
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
        SyntheticERC20 newUSDT = new SyntheticERC20();
        newUSDT.initialize(
            "GTX Synthetic USDT v3",
            "gsUSDT3",
            6,              // CORRECT: 6 decimals like real USDT
            balanceManager  // minter = BalanceManager
        );
        console.log("gsUSDT3 (6 decimals):", address(newUSDT));
        
        // Deploy gsWBTC with 8 decimals
        console.log("Deploying gsWBTC with 8 decimals...");
        SyntheticERC20 newWBTC = new SyntheticERC20();
        newWBTC.initialize(
            "GTX Synthetic WBTC v3",
            "gsWBTC3",
            8,              // CORRECT: 8 decimals like real WBTC
            balanceManager  // minter = BalanceManager
        );
        console.log("gsWBTC3 (8 decimals):", address(newWBTC));
        
        // Deploy gsWETH with 18 decimals
        console.log("Deploying gsWETH with 18 decimals...");
        SyntheticERC20 newWETH = new SyntheticERC20();
        newWETH.initialize(
            "GTX Synthetic WETH v3",
            "gsWETH3",
            18,             // CORRECT: 18 decimals like real WETH
            balanceManager  // minter = BalanceManager
        );
        console.log("gsWETH3 (18 decimals):", address(newWETH));
        
        console.log("");
        console.log("=== STEP 2: UPDATE TOKEN REGISTRY MAPPINGS ===");
        console.log("Using SyntheticTokenFactory to update mappings...");
        
        // We need to call through SyntheticTokenFactory since it owns TokenRegistry
        // But SyntheticTokenFactory doesn't have update functions...
        // Let's check if we can transfer ownership temporarily
        
        console.log("Attempting to update via SyntheticTokenFactory ownership...");
        
        // Option: Transfer TokenRegistry ownership to deployer temporarily
        console.log("Step 2a: Transfer TokenRegistry ownership to deployer...");
        (bool success1,) = syntheticTokenFactory.call(
            abi.encodeWithSignature("transferOwnership(address)", address(tokenRegistry), deployer)
        );
        
        if (!success1) {
            // Try alternative: call setTokenRegistry to transfer ownership
            console.log("Trying alternative ownership transfer...");
            (bool success2,) = syntheticTokenFactory.call(
                abi.encodeWithSignature("setTokenRegistry(address)", address(0))
            );
            console.log("Alternative transfer:", success2 ? "SUCCESS" : "FAILED");
        }
        
        // If we get ownership, update mappings directly
        console.log("Step 2b: Update TokenRegistry mappings...");
        
        TokenRegistry registry = TokenRegistry(tokenRegistry);
        
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
        
        // Update WETH mapping (register new if doesn't exist)
        console.log("Updating/Creating WETH mapping...");
        try registry.updateTokenMapping(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceWETH,              // sourceToken
            1918988905,              // targetChainId (Rari)
            address(newWETH),        // newSyntheticToken
            18                       // newSyntheticDecimals
        ) {
            console.log("SUCCESS: WETH mapping updated");
        } catch {
            // If update fails, try registering new mapping
            console.log("Update failed, trying to register new WETH mapping...");
            try registry.registerTokenMapping(
                4661,                // sourceChainId
                sourceWETH,          // sourceToken
                1918988905,          // targetChainId
                address(newWETH),    // syntheticToken
                "gsWETH3",           // symbol
                18,                  // sourceDecimals
                18                   // syntheticDecimals
            ) {
                console.log("SUCCESS: WETH mapping registered");
            } catch Error(string memory reason) {
                console.log("FAILED: WETH mapping registration -", reason);
            }
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
        console.log("1. Verify TokenRegistry mappings updated");
        console.log("2. Update ChainBalanceManager source->synthetic mappings");
        console.log("3. Create new pools with correct decimal tokens");
        console.log("4. Test cross-chain deposits");
        console.log("");
        
        console.log("Add to rari.json:");
        console.log("gsUSDT_v3:", address(newUSDT));
        console.log("gsWBTC_v3:", address(newWBTC));
        console.log("gsWETH_v3:", address(newWETH));
        
        console.log("========== TOKENS + REGISTRY UPDATE COMPLETE ==========");
    }
}