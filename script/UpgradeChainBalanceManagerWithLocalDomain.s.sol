// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract UpgradeChainBalanceManagerWithLocalDomain is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPGRADE CHAIN BALANCE MANAGER ==========");
        console.log("Deploy new implementation with updateLocalDomain function");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        // Determine deployment file based on chain
        string memory deploymentFile;
        string memory networkName;
        
        if (block.chainid == 421614) {
            deploymentFile = "deployments/arbitrum-sepolia.json";
            networkName = "ARBITRUM SEPOLIA";
        } else if (block.chainid == 11155931) {
            deploymentFile = "deployments/rise-sepolia.json";
            networkName = "RISE SEPOLIA";
        } else {
            console.log("ERROR: This script is for Arbitrum Sepolia (421614) or Rise Sepolia (11155931) only");
            return;
        }
        
        console.log("Target network:", networkName);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== DEPLOY NEW IMPLEMENTATION ===");
        
        // Deploy new implementation with updateLocalDomain function
        ChainBalanceManager newImpl = new ChainBalanceManager();
        console.log("New ChainBalanceManager implementation:", address(newImpl));
        
        // Read current deployment data
        string memory chainData = vm.readFile(deploymentFile);
        address proxyAddress = vm.parseJsonAddress(chainData, ".contracts.ChainBalanceManager");
        
        console.log("ChainBalanceManager proxy:", proxyAddress);
        console.log("");
        console.log("=== UPGRADE PROXY ===");
        console.log("NOTE: This requires beacon upgrade or direct proxy upgrade");
        console.log("Implementation deployed at:", address(newImpl));
        console.log("You may need to upgrade via beacon or owner functions");
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Upgrade proxy to use new implementation");
        console.log("2. Call updateLocalDomain function to fix domain issues");
        console.log("3. Test deposits from this chain to verify Hyperlane relay works");
        
        console.log("========== IMPLEMENTATION DEPLOYED ==========");
    }
}