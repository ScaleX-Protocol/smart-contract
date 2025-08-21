// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";

/**
 * @title ConfigureChainBalanceManagers
 * @dev Configure ChainBalanceManagers with proper destination addresses
 */
contract ConfigureChainBalanceManagers is Script {
    
    // Deployed addresses
    address constant RARI_BALANCE_MANAGER = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    uint32 constant RARI_DOMAIN_ID = 1918988905;
    
    address constant APPCHAIN_CBM = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
    address constant ARBITRUM_CBM = 0x288D991A64Ed02171d0beC0DC788ad76421e1169;
    address constant RISE_CBM = 0xB1a78eeF392baa3bD244E32625F9C1b5b04a8cdB;
    
    function run() public {
        string memory network = vm.envString("NETWORK");
        
        vm.startBroadcast();
        
        if (keccak256(bytes(network)) == keccak256(bytes("appchain"))) {
            configureChainBalanceManager(APPCHAIN_CBM, "Appchain");
        } else if (keccak256(bytes(network)) == keccak256(bytes("arbitrum-sepolia"))) {
            configureChainBalanceManager(ARBITRUM_CBM, "Arbitrum Sepolia");
        } else if (keccak256(bytes(network)) == keccak256(bytes("rise-sepolia"))) {
            configureChainBalanceManager(RISE_CBM, "Rise Sepolia");
        } else {
            revert("Unknown network. Use: appchain, arbitrum-sepolia, or rise-sepolia");
        }
        
        vm.stopBroadcast();
    }
    
    function configureChainBalanceManager(address cbmAddress, string memory networkName) internal {
        console.log("Configuring ChainBalanceManager on", networkName);
        console.log("CBM Address:", cbmAddress);
        
        ChainBalanceManager cbm = ChainBalanceManager(cbmAddress);
        
        // Set destination domain and balance manager
        console.log("Setting destination to Rari BalanceManager...");
        console.log("Destination Domain:", RARI_DOMAIN_ID);
        console.log("Destination BalanceManager:", RARI_BALANCE_MANAGER);
        
        cbm.updateCrossChainConfig(RARI_DOMAIN_ID, RARI_BALANCE_MANAGER);
        
        // Verify configuration
        (uint32 destDomain, address destBM) = cbm.getCrossChainConfig();
        console.log("Configured destination domain:", destDomain);
        console.log("Configured destination BalanceManager:", destBM);
        
        require(destDomain == RARI_DOMAIN_ID, "Destination domain mismatch");
        require(destBM == RARI_BALANCE_MANAGER, "Destination BalanceManager mismatch");
        
        console.log("SUCCESS: ChainBalanceManager configured correctly!");
    }
}