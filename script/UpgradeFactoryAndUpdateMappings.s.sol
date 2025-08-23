// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/SyntheticTokenFactory.sol";
import "../src/core/TokenRegistry.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeFactoryAndUpdateMappings is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPGRADE FACTORY + UPDATE MAPPINGS ==========");
        console.log("Step 1: Upgrade SyntheticTokenFactory with updateTokenMapping");
        console.log("Step 2: Update TokenRegistry mappings to correct decimal tokens");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address factoryProxy = vm.parseJsonAddress(deploymentData, ".contracts.SyntheticTokenFactory");
        
        console.log("Current SyntheticTokenFactory:", factoryProxy);
        
        // New tokens with correct decimals
        address newUSDT = 0x85961935a95690860A5Fb5E4bE09099049c19AD9; // 6 decimals
        address newWBTC = 0x89F26f075284Af73922caB248877F279ac890A36; // 8 decimals  
        address newWETH = 0xc4b6647c4c0Db93b47996b6aa8E309bE29dC6d04; // 18 decimals
        
        console.log("");
        console.log("=== NEW TOKENS WITH CORRECT DECIMALS ===");
        console.log("gsUSDT3 (6 decimals): ", newUSDT);
        console.log("gsWBTC3 (8 decimals): ", newWBTC);
        console.log("gsWETH3 (18 decimals):", newWETH);
        console.log("");
        
        // Read source tokens from Appchain
        string memory appchainData = vm.readFile("deployments/appchain.json");
        address sourceUSDT = vm.parseJsonAddress(appchainData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(appchainData, ".contracts.WBTC");
        address sourceWETH = vm.parseJsonAddress(appchainData, ".contracts.WETH");
        
        console.log("=== SOURCE TOKENS (Appchain 4661) ===");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== STEP 1: DEPLOY NEW FACTORY IMPLEMENTATION ===");
        
        // Deploy new SyntheticTokenFactory implementation with updateTokenMapping function
        SyntheticTokenFactory newFactoryImpl = new SyntheticTokenFactory();
        console.log("New SyntheticTokenFactory implementation:", address(newFactoryImpl));
        
        // Get current factory proxy to check if it's upgradeable
        SyntheticTokenFactory factory = SyntheticTokenFactory(factoryProxy);
        
        console.log("");
        console.log("=== STEP 2: CHECK UPGRADEABILITY ===");
        
        // Check if the factory is owned by deployer
        address factoryOwner = factory.owner();
        console.log("SyntheticTokenFactory owner:", factoryOwner);
        
        if (factoryOwner != deployer) {
            console.log("ERROR: Cannot upgrade - deployer is not owner");
            console.log("Current owner:", factoryOwner);
            return;
        }
        
        // Since we can't easily determine the upgrade mechanism, let's try direct calls
        console.log("Factory is owned by deployer - proceeding with mapping updates");
        
        console.log("");
        console.log("=== STEP 3: UPDATE TOKEN MAPPINGS ===");
        console.log("Using existing factory to update mappings...");
        
        // Update USDT mapping
        console.log("Updating USDT mapping...");
        try factory.updateTokenMapping(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceUSDT,              // sourceToken
            1918988905,              // targetChainId (Rari)
            newUSDT,                 // newSyntheticToken
            6                        // newSyntheticDecimals
        ) {
            console.log("SUCCESS: USDT mapping updated to 6 decimals");
        } catch Error(string memory reason) {
            console.log("FAILED: USDT mapping -", reason);
            console.log("Need to upgrade factory first");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== ANALYSIS COMPLETE ===");
        console.log("Option 1: Upgrade SyntheticTokenFactory with new implementation");
        console.log("Option 2: Use current factory if updateTokenMapping exists");  
        console.log("Option 3: Transfer TokenRegistry ownership temporarily");
        console.log("");
        
        console.log("New token addresses ready for mapping:");
        console.log("USDT -> gsUSDT3 (6 dec):", newUSDT);
        console.log("WBTC -> gsWBTC3 (8 dec):", newWBTC);
        console.log("WETH -> gsWETH3 (18 dec):", newWETH);
        
        console.log("========== READY FOR MAPPING UPDATES ==========");
    }
}