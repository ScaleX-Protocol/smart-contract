// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/ChainBalanceManager.sol";
import {IMailbox} from "../src/core/interfaces/IMailbox.sol";

contract TestCrossChainFlow is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== TESTING CROSS CHAIN FLOW =========");
        console.log("User:", deployer);
        
        // Step 1: Check Rari BalanceManager configuration
        console.log("=== CHECKING RARI BALANCE MANAGER ===");
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        
        console.log("BalanceManager:", balanceManagerAddr);
        
        // Check mailbox config
        (address rariMailbox, uint32 rariLocalDomain) = balanceManager.getMailboxConfig();
        console.log("Rari Mailbox:", rariMailbox);
        console.log("Rari LocalDomain:", rariLocalDomain);
        
        // Check ChainBalanceManager mapping for Appchain
        address appchainCBM = balanceManager.getChainBalanceManager(4661);
        console.log("Registered Appchain CBM:", appchainCBM);
        
        // Step 2: Check Appchain ChainBalanceManager configuration
        console.log("=== CHECKING APPCHAIN CHAIN BALANCE MANAGER ===");
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        console.log("ChainBalanceManager:", chainBalanceManagerAddr);
        
        // Check mailbox config
        (address appchainMailbox, uint32 appchainLocalDomain) = cbm.getMailboxConfig();
        console.log("Appchain Mailbox:", appchainMailbox);
        console.log("Appchain LocalDomain:", appchainLocalDomain);
        
        // Check cross-chain config
        (uint32 destDomain, address destBalanceManager) = cbm.getCrossChainConfig();
        console.log("Destination Domain:", destDomain);
        console.log("Destination BalanceManager:", destBalanceManager);
        
        // Check token whitelist
        bool usdtWhitelisted = cbm.isTokenWhitelisted(0x05bFe17e3c96E2b0c19F8aE8E7A36b2E2c3B6E2a);
        console.log("USDT whitelisted:", usdtWhitelisted);
        
        // Check token mapping
        address syntheticToken = cbm.getTokenMapping(0x05bFe17e3c96E2b0c19F8aE8E7A36b2E2c3B6E2a);
        console.log("USDT -> Synthetic mapping:", syntheticToken);
        
        // Step 3: Test deposit
        console.log("=== TESTING DEPOSIT ===");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Check if we have required configurations
        if (appchainCBM == address(0)) {
            console.log("ERROR: BalanceManager doesn't know about Appchain CBM");
            console.log("Need to call: balanceManager.setChainBalanceManager(4661, chainBalanceManagerAddr)");
        }
        
        if (destDomain == 0 || destBalanceManager == address(0)) {
            console.log("ERROR: ChainBalanceManager doesn't have destination config");
            console.log("Need to call: cbm.updateCrossChainConfig(1918988905, balanceManagerAddr)");
        }
        
        if (!usdtWhitelisted) {
            console.log("ERROR: USDT not whitelisted on ChainBalanceManager");
        }
        
        if (syntheticToken == address(0)) {
            console.log("ERROR: No synthetic token mapping for USDT");
        }
        
        // If everything looks good, try a small deposit
        if (appchainCBM != address(0) && destDomain != 0 && destBalanceManager != address(0) && usdtWhitelisted && syntheticToken != address(0)) {
            console.log("All configurations look good! Testing deposit...");
            
            address usdtAddr = 0x05bFe17e3c96E2b0c19F8aE8E7A36b2E2c3B6E2a;
            uint256 depositAmount = 100e6; // 100 USDT (6 decimals)
            
            // Check user's USDT balance first
            uint256 userBalance = cbm.getBalance(deployer, usdtAddr);
            console.log("User's current USDT balance in CBM:", userBalance);
            
            if (userBalance >= depositAmount) {
                console.log("User has sufficient balance, attempting deposit...");
                
                try cbm.deposit(usdtAddr, depositAmount, deployer) {
                    console.log("SUCCESS: Cross-chain deposit initiated!");
                    
                    console.log("Check Hyperlane explorer for the message!");
                    
                } catch Error(string memory reason) {
                    console.log("Deposit failed:", reason);
                } catch {
                    console.log("Deposit failed with unknown error");
                }
            } else {
                console.log("User needs more USDT balance. Current:", userBalance, "Required:", depositAmount);
            }
        }
        
        vm.stopBroadcast();
        
        console.log("========== DONE =========");
    }
}