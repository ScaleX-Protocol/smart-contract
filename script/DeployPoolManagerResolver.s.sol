// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/resolvers/PoolManagerResolver.sol";

contract DeployPoolManagerResolver is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== DEPLOYING POOL MANAGER RESOLVER ==========");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        // Detect network and read existing deployments
        string memory networkFile;
        bool hasExistingDeployments = false;
        
        if (block.chainid == 1918988905) {
            // Rari
            networkFile = "deployments/rari.json";
            hasExistingDeployments = true;
            console.log("Detected: Rari Testnet");
        } else if (block.chainid == 11155931) {
            // Rise Sepolia
            networkFile = "deployments/11155931.json";  
            hasExistingDeployments = true;
            console.log("Detected: Rise Sepolia");
        } else if (block.chainid == 4661) {
            // Appchain
            networkFile = "deployments/appchain.json";
            hasExistingDeployments = true;
            console.log("Detected: Appchain Testnet");
        } else if (block.chainid == 421614) {
            // Arbitrum Sepolia
            networkFile = "deployments/arbitrum-sepolia.json";
            hasExistingDeployments = true;
            console.log("Detected: Arbitrum Sepolia");
        } else {
            console.log("Unknown network - deploying standalone");
        }
        
        address existingPoolManager = address(0);
        
        if (hasExistingDeployments) {
            try vm.readFile(networkFile) returns (string memory deploymentData) {
                console.log("Reading existing deployments from:", networkFile);
                
                // Try to get existing PoolManager
                try vm.parseJsonAddress(deploymentData, ".contracts.PoolManager") returns (address poolMgr) {
                    existingPoolManager = poolMgr;
                } catch {
                    try vm.parseJsonAddress(deploymentData, ".PROXY_POOLMANAGER") returns (address poolMgr) {
                        existingPoolManager = poolMgr;
                    } catch {
                        console.log("No existing PoolManager found in deployment file");
                    }
                }
                
                // Check if resolver already exists
                try vm.parseJsonAddress(deploymentData, ".contracts.PoolManagerResolver") returns (address existingResolver) {
                    console.log("WARNING: PoolManagerResolver already exists at:", existingResolver);
                    console.log("Skipping deployment. Use existing resolver or delete entry to redeploy.");
                    return;
                } catch {
                    try vm.parseJsonAddress(deploymentData, ".RESOLVER_POOLMANAGER") returns (address existingResolver) {
                        console.log("WARNING: PoolManagerResolver already exists at:", existingResolver);
                        console.log("Skipping deployment. Use existing resolver or delete entry to redeploy.");
                        return;
                    } catch {
                        console.log("No existing PoolManagerResolver found - proceeding with deployment");
                    }
                }
            } catch {
                console.log("Could not read deployment file - proceeding with standalone deployment");
            }
        }
        
        if (existingPoolManager != address(0)) {
            console.log("Found existing PoolManager at:", existingPoolManager);
        } else {
            console.log("No existing PoolManager found - resolver will work with any PoolManager address");
        }
        
        console.log("");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy PoolManagerResolver - it's stateless so just deploy
        console.log("Deploying PoolManagerResolver...");
        PoolManagerResolver resolver = new PoolManagerResolver();
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("PoolManagerResolver deployed at:", address(resolver));
        
        // Test resolver functionality if we have a PoolManager
        if (existingPoolManager != address(0)) {
            console.log("");
            console.log("=== TESTING RESOLVER ===");
            console.log("Testing with PoolManager:", existingPoolManager);
            
            // Test with mock currencies (you can replace with real ones)
            address mockCurrency1 = address(0x1);
            address mockCurrency2 = address(0x2);
            
            try resolver.getPoolKey(
                Currency.wrap(mockCurrency1), 
                Currency.wrap(mockCurrency2), 
                existingPoolManager
            ) returns (PoolKey memory poolKey) {
                console.log("SUCCESS: Resolver working - can create pool keys");
                console.log("Pool key base:", Currency.unwrap(poolKey.baseCurrency));
                console.log("Pool key quote:", Currency.unwrap(poolKey.quoteCurrency));
            } catch {
                console.log("WARNING: Resolver deployed but couldn't test with existing PoolManager");
            }
        }
        
        console.log("");
        console.log("=== USAGE INSTRUCTIONS ===");
        console.log("1. PoolManagerResolver is stateless - works with any PoolManager");
        console.log("2. Call resolver.getPool(baseCurrency, quoteCurrency, poolManagerAddress)");
        console.log("3. Call resolver.getPoolKey(baseCurrency, quoteCurrency, poolManagerAddress)");
        console.log("4. Add to deployment JSON manually if needed:");
        console.log("   \"PoolManagerResolver\": \"", address(resolver), "\"");
        
        console.log("========== POOL MANAGER RESOLVER READY ==========");
    }
}