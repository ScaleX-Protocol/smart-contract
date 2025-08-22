// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "../src/core/BalanceManager.sol";

contract FixCrossChainConfig is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========== FIXING CROSS-CHAIN CONFIGURATION ==========");
        
        // Step 1: Fix Appchain ChainBalanceManager configuration
        console.log("Step 1: Updating Appchain ChainBalanceManager...");
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        address correctRariBalanceManager = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        uint32 rariDomainId = 1918988905;
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        try cbm.updateCrossChainConfig(rariDomainId, correctRariBalanceManager) {
            console.log("SUCCESS: Updated Appchain -> Rari mapping");
        } catch Error(string memory reason) {
            console.log("FAILED to update Appchain config:", reason);
        }
        
        vm.stopBroadcast();
        
        // Step 2: Fix Rari BalanceManager configuration
        console.log("Step 2: Updating Rari BalanceManager...");
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address appchainChainBalanceManager = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        uint32 appchainDomainId = 4661;
        
        BalanceManager bm = BalanceManager(balanceManagerAddr);
        
        // Check current mapping
        address currentMapping = bm.getChainBalanceManager(appchainDomainId);
        console.log("Current Rari -> Appchain mapping:", currentMapping);
        
        vm.startBroadcast(deployerPrivateKey);
        
        if (currentMapping != appchainChainBalanceManager) {
            try bm.setChainBalanceManager(appchainDomainId, appchainChainBalanceManager) {
                console.log("SUCCESS: Updated Rari -> Appchain mapping");
            } catch Error(string memory reason) {
                console.log("FAILED to update Rari config:", reason);
            }
        } else {
            console.log("Rari mapping already correct");
        }
        
        vm.stopBroadcast();
        
        // Verify both configurations
        address newMapping = bm.getChainBalanceManager(appchainDomainId);
        console.log("Final Rari -> Appchain mapping:", newMapping);
        
        console.log("========== CROSS-CHAIN CONFIG FIXED ==========");
        console.log("Now retry the deposits - they should work!");
    }
}