// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";

contract UpdateRariRegistryArbitrum is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPDATE RARI REGISTRY FOR ARBITRUM ==========");
        console.log("Update BalanceManager registry with new Arbitrum ChainBalanceManager");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari only");
            return;
        }
        
        // Addresses
        address oldArbitrumCBM = 0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A;
        address newArbitrumCBM = 0x81883DB77B43Ba719Cf1dB7119a2440b4eBFB8b6;
        uint32 arbitrumDomain = 421614;
        
        // Read deployment data
        string memory rariData = vm.readFile("deployments/rari.json");
        address balanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        
        console.log("");
        console.log("BalanceManager:", balanceManager);
        console.log("Arbitrum domain:", arbitrumDomain);
        console.log("OLD ChainBalanceManager:", oldArbitrumCBM);
        console.log("NEW ChainBalanceManager:", newArbitrumCBM);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        BalanceManager bm = BalanceManager(balanceManager);
        
        console.log("=== CHECK CURRENT REGISTRY ===");
        
        try bm.getChainBalanceManager(arbitrumDomain) returns (address currentCBM) {
            console.log("Current registered address:", currentCBM);
            console.log("Expected old address:", oldArbitrumCBM);
            console.log("Is current address the old one:", currentCBM == oldArbitrumCBM);
        } catch Error(string memory reason) {
            console.log("FAILED to get current registry:", reason);
        }
        
        console.log("");
        console.log("=== UPDATE REGISTRY ===");
        
        try bm.setChainBalanceManager(arbitrumDomain, newArbitrumCBM) {
            console.log("SUCCESS: Registry updated!");
            console.log("Arbitrum domain", arbitrumDomain, "now points to", newArbitrumCBM);
        } catch Error(string memory reason) {
            console.log("FAILED to update registry:", reason);
            vm.stopBroadcast();
            return;
        }
        
        console.log("");
        console.log("=== VERIFY UPDATE ===");
        
        try bm.getChainBalanceManager(arbitrumDomain) returns (address finalCBM) {
            console.log("Final registered address:", finalCBM);
            console.log("Expected new address:", newArbitrumCBM);
            console.log("Update successful:", finalCBM == newArbitrumCBM);
            
            if (finalCBM == newArbitrumCBM) {
                console.log("SUCCESS: Rari BalanceManager will now accept messages from new Arbitrum ChainBalanceManager");
            } else {
                console.log("ERROR: Registry update did not take effect");
            }
        } catch Error(string memory reason) {
            console.log("FAILED to verify update:", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== WHAT WAS UPDATED ===");
        console.log("BEFORE: Messages from", oldArbitrumCBM, "were accepted");
        console.log("AFTER:  Messages from", newArbitrumCBM, "will be accepted");
        console.log("RESULT: Arbitrum -> Rari cross-chain deposits should now work");
        
        console.log("========== RARI REGISTRY UPDATE COMPLETE ==========");
    }
}