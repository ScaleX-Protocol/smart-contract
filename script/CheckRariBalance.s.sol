// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

contract CheckRariBalance is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== CHECKING RARI BALANCE =========");
        console.log("User:", deployer);
        
        // Switch to Rari
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address rariSyntheticUSDT = 0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7; // gsUSDT
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("Synthetic USDT (gsUSDT):", rariSyntheticUSDT);
        
        // Check user's synthetic USDT balance in BalanceManager
        Currency gsUSDT = Currency.wrap(rariSyntheticUSDT);
        uint256 syntheticBalance = balanceManager.getBalance(deployer, gsUSDT);
        
        console.log("User's gsUSDT balance in BalanceManager:", syntheticBalance);
        
        if (syntheticBalance > 0) {
            console.log("SUCCESS: Cross-chain message was received and processed!");
            console.log("Synthetic tokens were minted on Rari!");
            
            // Check user's nonce to see if messages were processed
            uint256 userNonce = balanceManager.getUserNonce(deployer);
            console.log("User's nonce (number of processed messages):", userNonce);
            
        } else {
            console.log("No synthetic tokens found. Checking diagnostics...");
            
            // Check if BalanceManager has the ChainBalanceManager registered
            address registeredCBM = balanceManager.getChainBalanceManager(4661);
            console.log("Registered Appchain CBM:", registeredCBM);
            console.log("Expected CBM:", 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7);
            
            if (registeredCBM == address(0)) {
                console.log("ERROR: BalanceManager doesn't know about Appchain CBM");
                console.log("Run: balanceManager.setChainBalanceManager(4661, 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7)");
                
                vm.startBroadcast(deployerPrivateKey);
                
                try balanceManager.setChainBalanceManager(4661, 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7) {
                    console.log("SUCCESS: Registered Appchain CBM");
                } catch Error(string memory reason) {
                    console.log("Failed to register CBM:", reason);
                } catch {
                    console.log("Failed to register CBM with unknown error");
                }
                
                vm.stopBroadcast();
                
            } else {
                console.log("ChainBalanceManager registration looks correct");
                console.log("Message may not have been relayed yet, or there may be another issue");
                
                // Check user's nonce
                uint256 userNonce = balanceManager.getUserNonce(deployer);
                console.log("User's nonce:", userNonce);
                console.log("If nonce is 0, no messages have been processed for this user");
            }
        }
        
        console.log("========== DONE =========");
        console.log("If balance is still 0, check Hyperlane explorer:");
        console.log("https://hyperlane-explorer.gtxdex.xyz/");
    }
}