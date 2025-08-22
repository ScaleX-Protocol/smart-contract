// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/ChainBalanceManager.sol";

contract ConfigureTokenMappings is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== CONFIGURING TOKEN MAPPINGS =========");
        console.log("Deployer:", deployer);
        
        // Token addresses from deployments.json
        address appchainUSDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        address rariSyntheticUSDT = 0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7; // gsUSDT from deployments
        
        console.log("Appchain USDT:", appchainUSDT);
        console.log("Rari gsUSDT:", rariSyntheticUSDT);
        
        // Step 1: Configure ChainBalanceManager on Appchain
        console.log("=== CONFIGURING APPCHAIN CHAIN BALANCE MANAGER ===");
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Add USDT to whitelist
        try cbm.addToken(appchainUSDT) {
            console.log("SUCCESS: Added USDT to whitelist");
        } catch Error(string memory reason) {
            console.log("Failed to add USDT to whitelist:", reason);
        } catch {
            console.log("Failed to add USDT to whitelist with unknown error");
        }
        
        // Set token mapping
        try cbm.setTokenMapping(appchainUSDT, rariSyntheticUSDT) {
            console.log("SUCCESS: Set token mapping USDT -> gsUSDT");
        } catch Error(string memory reason) {
            console.log("Failed to set token mapping:", reason);
        } catch {
            console.log("Failed to set token mapping with unknown error");
        }
        
        vm.stopBroadcast();
        
        // Verify configuration
        bool usdtWhitelisted = cbm.isTokenWhitelisted(appchainUSDT);
        address syntheticToken = cbm.getTokenMapping(appchainUSDT);
        console.log("USDT whitelisted after config:", usdtWhitelisted);
        console.log("USDT -> Synthetic mapping after config:", syntheticToken);
        
        // Step 2: Check BalanceManager on Rari has the ChainBalanceManager registered
        console.log("=== CHECKING RARI BALANCE MANAGER REGISTRATION ===");
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        
        address registeredCBM = balanceManager.getChainBalanceManager(4661);
        console.log("Registered Appchain CBM:", registeredCBM);
        console.log("Expected Appchain CBM:", chainBalanceManagerAddr);
        console.log("Registration correct:", registeredCBM == chainBalanceManagerAddr);
        
        console.log("========== CONFIGURATION COMPLETE =========");
        
        // Step 3: Test small deposit now that everything is configured
        console.log("=== TESTING CONFIGURED DEPOSIT ===");
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Check if user has USDT balance in CBM
        uint256 userBalance = cbm.getBalance(deployer, appchainUSDT);
        console.log("User's current USDT balance in CBM:", userBalance);
        
        if (userBalance == 0) {
            console.log("User needs to deposit USDT first");
            console.log("Need to call: cbm.deposit(USDT, amount, user) first");
        } else {
            uint256 depositAmount = userBalance / 2; // Use half of available balance
            console.log("Attempting deposit of:", depositAmount);
            
            try cbm.deposit(appchainUSDT, depositAmount, deployer) {
                console.log("SUCCESS: Cross-chain deposit initiated!");
                console.log("Check Hyperlane explorer for the message!");
            } catch Error(string memory reason) {
                console.log("Deposit failed:", reason);
            } catch {
                console.log("Deposit failed with unknown error");
            }
        }
        
        vm.stopBroadcast();
        
        console.log("========== DONE =========");
    }
}