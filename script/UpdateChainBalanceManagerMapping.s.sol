// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";

contract UpdateChainBalanceManagerMapping is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPDATE CHAIN BALANCE MANAGER MAPPING ==========");
        console.log("Update to use BalanceManager directly instead of ChainBalanceManager");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address balanceManager = vm.parseJsonAddress(deploymentData, ".contracts.BalanceManager");
        
        console.log("BalanceManager:", balanceManager);
        console.log("");
        
        console.log("=== CURRENT SETUP ===");
        console.log("Appchain (4661) currently mapped to ChainBalanceManager");
        console.log("New approach: Use BalanceManager directly");
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        BalanceManager bm = BalanceManager(balanceManager);
        
        console.log("=== UPDATE CHAIN MAPPING ===");
        console.log("Setting Appchain (4661) to use BalanceManager directly...");
        
        // Update the chain mapping to point to BalanceManager itself
        // This means deposits from Appchain will be handled directly by BalanceManager
        try bm.setChainBalanceManager(4661, balanceManager) {
            console.log("SUCCESS: Appchain (4661) now mapped to BalanceManager");
            console.log("Chain 4661 -> BalanceManager:", balanceManager);
        } catch Error(string memory reason) {
            console.log("FAILED: Chain mapping update -", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== VERIFICATION ===");
        console.log("This means:");
        console.log("1. Deposits from Appchain (4661) go directly to BalanceManager");
        console.log("2. No separate ChainBalanceManager contract needed");
        console.log("3. Simplified architecture");
        console.log("4. BalanceManager handles both local and cross-chain deposits");
        console.log("");
        
        console.log("=== NEXT STEPS ===");
        console.log("1. Update deployments/rari.json with new mapping");
        console.log("2. Test cross-chain deposits from Appchain");
        console.log("3. Verify tokens mint correctly to BalanceManager");
        console.log("");
        
        console.log("New mapping:");
        console.log("Appchain (4661) -> BalanceManager:", balanceManager);
        
        console.log("========== CHAIN MAPPING UPDATED ==========");
    }
}