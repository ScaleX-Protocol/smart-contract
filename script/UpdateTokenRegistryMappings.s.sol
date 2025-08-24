// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/TokenRegistry.sol";
import "../src/core/SyntheticTokenFactory.sol";

contract UpdateTokenRegistryMappings is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPDATE TOKEN REGISTRY MAPPINGS ==========");
        console.log("Update mappings to point to correctly-decimaled tokens");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address tokenRegistry = vm.parseJsonAddress(deploymentData, ".contracts.TokenRegistry");
        address factoryAddr = vm.parseJsonAddress(deploymentData, ".contracts.SyntheticTokenFactory");
        
        console.log("TokenRegistry:", tokenRegistry);
        console.log("SyntheticTokenFactory:", factoryAddr);
        
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
        
        SyntheticTokenFactory factory = SyntheticTokenFactory(factoryAddr);
        TokenRegistry registry = TokenRegistry(tokenRegistry);
        
        console.log("=== STEP 1: TRANSFER OWNERSHIP TO UPDATE MAPPINGS ===");
        
        // Check current owner
        address currentOwner = registry.owner();
        console.log("Current TokenRegistry owner:", currentOwner);
        
        if (currentOwner != factoryAddr) {
            console.log("ERROR: TokenRegistry owner is not SyntheticTokenFactory");
            return;
        }
        
        // Use SyntheticTokenFactory to transfer ownership to deployer temporarily
        console.log("Transferring TokenRegistry ownership to deployer...");
        try factory.setTokenRegistry(deployer) {
            console.log("ERROR: setTokenRegistry expects registry address, not owner");
        } catch {
            console.log("setTokenRegistry failed as expected");
        }
        
        // Alternative: Check if we can call TokenRegistry functions through the factory
        console.log("Attempting to update mappings through SyntheticTokenFactory...");
        
        // Since SyntheticTokenFactory owns TokenRegistry, we might need to add
        // an update function to the factory, or use a different approach
        
        console.log("");
        console.log("=== ALTERNATIVE APPROACH: DIRECT REGISTRY CALLS ===");
        console.log("Since SyntheticTokenFactory doesn't expose update functions,");
        console.log("we need to either:");
        console.log("1. Add updateTokenMapping function to SyntheticTokenFactory");
        console.log("2. Temporarily transfer ownership");
        console.log("3. Use low-level calls");
        console.log("");
        
        // Try low-level call approach
        console.log("=== STEP 2: UPDATE MAPPINGS VIA LOW-LEVEL CALLS ===");
        
        // Update USDT mapping via factory (if it has the right interface)
        console.log("Updating USDT mapping...");
        
        // We need to call updateTokenMapping on the TokenRegistry through the factory
        // But the factory doesn't expose this. Let's try a different approach.
        
        console.log("Current approach won't work without factory update function.");
        console.log("");
        console.log("=== SOLUTION: UPGRADE SYNTHETICTOKENFACTORY ===");
        console.log("Need to add updateTokenMapping function to SyntheticTokenFactory");
        console.log("that calls TokenRegistry.updateTokenMapping()");
        console.log("");
        
        vm.stopBroadcast();
        
        console.log("=== NEXT STEPS ===");
        console.log("1. Add updateTokenMapping to SyntheticTokenFactory");
        console.log("2. Upgrade SyntheticTokenFactory");
        console.log("3. Call updateTokenMapping for all 3 tokens");
        console.log("4. Verify mappings point to correct decimal tokens");
        console.log("");
        
        console.log("New token addresses to map:");
        console.log("USDT -> gsUSDT3:", newUSDT);
        console.log("WBTC -> gsWBTC3:", newWBTC);
        console.log("WETH -> gsWETH3:", newWETH);
        
        console.log("========== MAPPING UPDATE ANALYSIS COMPLETE ==========");
    }
}