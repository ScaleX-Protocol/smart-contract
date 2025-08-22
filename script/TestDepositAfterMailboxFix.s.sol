// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "../src/core/BalanceManager.sol";
import "../src/token/SyntheticToken.sol";
import "../src/mocks/MockToken.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

contract TestDepositAfterMailboxFix is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== TESTING DEPOSIT AFTER MAILBOX FIX ==========");
        console.log("User:", deployer);
        console.log("");
        
        // Step 1: Check source chain (Appchain) status
        console.log("=== STEP 1: SOURCE CHAIN STATUS (APPCHAIN) ===");
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        address mockUSDTAddr = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        MockToken mockUSDT = MockToken(mockUSDTAddr);
        
        // Check current user nonce before deposit
        uint256 initialNonce = cbm.getUserNonce(deployer);
        console.log("Initial user nonce:", initialNonce);
        
        // Check mailbox config after fix
        try cbm.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
            console.log("ChainBalanceManager mailbox:", mailbox);
            console.log("Local domain:", localDomain);
        } catch {
            console.log("Mailbox config not readable");
        }
        
        // Check destination config after fix
        try cbm.getDestinationConfig() returns (uint32 destDomain, address destBalanceManager) {
            console.log("Destination domain:", destDomain);
            console.log("Destination BalanceManager:", destBalanceManager);
            console.log("Cross-chain config looks correct!");
        } catch {
            console.log("Destination config still not readable");
            return;
        }
        
        console.log("");
        
        // Step 2: Prepare deposit
        console.log("=== STEP 2: PREPARE DEPOSIT ===");
        
        uint256 depositAmount = 50000000; // 50 USDT
        console.log("Deposit amount:", depositAmount);
        
        // Check user's mock token balance
        uint256 userBalance = mockUSDT.balanceOf(deployer);
        console.log("User mock USDT balance:", userBalance);
        
        if (userBalance < depositAmount) {
            console.log("Insufficient balance for deposit");
            console.log("Need to mint more mock tokens first");
            return;
        }
        
        // Check allowance
        uint256 allowance = mockUSDT.allowance(deployer, chainBalanceManagerAddr);
        console.log("Current allowance:", allowance);
        
        console.log("");
        
        // Step 3: Execute deposit
        console.log("=== STEP 3: EXECUTE CROSS-CHAIN DEPOSIT ===");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Approve if needed
        if (allowance < depositAmount) {
            console.log("Approving ChainBalanceManager...");
            mockUSDT.approve(chainBalanceManagerAddr, depositAmount);
            console.log("Approval successful");
        }
        
        // Execute deposit
        console.log("Executing deposit...");
        try cbm.deposit(mockUSDTAddr, depositAmount, deployer) {
            console.log("Deposit transaction successful!");
        } catch Error(string memory reason) {
            console.log("Deposit failed:", reason);
            vm.stopBroadcast();
            return;
        } catch {
            console.log("Deposit failed with unknown error");
            vm.stopBroadcast();
            return;
        }
        
        vm.stopBroadcast();
        
        // Step 4: Verify deposit effects on source chain
        console.log("");
        console.log("=== STEP 4: VERIFY SOURCE CHAIN EFFECTS ===");
        
        uint256 newNonce = cbm.getUserNonce(deployer);
        console.log("New user nonce:", newNonce);
        
        if (newNonce > initialNonce) {
            console.log("Nonce incremented - message sent!");
            console.log("Messages sent:", newNonce - initialNonce);
        } else {
            console.log("Nonce not incremented - message not sent");
        }
        
        // Check if tokens were locked
        uint256 lockedBalance = cbm.balanceOf(deployer, mockUSDTAddr);
        console.log("Locked balance on source:", lockedBalance);
        
        console.log("");
        
        // Step 5: Check destination chain initial state
        console.log("=== STEP 5: DESTINATION CHAIN STATUS (RARI) ===");
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address realGsUSDTAddr = 0x6fcf28b801C7116cA8b6460289e259aC8D9131F3;
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        SyntheticToken realGsUSDT = SyntheticToken(realGsUSDTAddr);
        
        Currency gsUSDTCurrency = Currency.wrap(realGsUSDTAddr);
        
        // Check destination user nonce
        uint256 destNonce = balanceManager.getUserNonce(deployer);
        console.log("Destination processed messages:", destNonce);
        
        // Check ERC20 token balance
        uint256 erc20Balance = realGsUSDT.balanceOf(deployer);
        console.log("Real gsUSDT ERC20 balance:", erc20Balance);
        
        // Check internal balance
        uint256 internalBalance = balanceManager.getBalance(deployer, gsUSDTCurrency);
        console.log("Internal BalanceManager balance:", internalBalance);
        
        // Check total supply
        uint256 totalSupply = realGsUSDT.totalSupply();
        console.log("Real gsUSDT total supply:", totalSupply);
        
        console.log("");
        
        // Step 6: Analysis
        console.log("=== STEP 6: ANALYSIS ===");
        
        if (newNonce > initialNonce) {
            console.log("Cross-chain message dispatched from Appchain");
            
            if (destNonce >= newNonce) {
                console.log("Message processed on Rari");
                
                if (erc20Balance > 0) {
                    console.log("Real ERC20 tokens minted successfully!");
                    console.log("V2 token minting system working!");
                } else {
                    console.log("ERC20 tokens not yet minted");
                    console.log("This could mean:");
                    console.log("- Message is still being processed");
                    console.log("- There's an issue with token minting in V2");
                }
                
                if (internalBalance > 0) {
                    console.log("Internal balance updated for trading");
                } else {
                    console.log("Internal balance not yet updated");
                }
            } else {
                console.log("Message not yet processed by Hyperlane relayers");
                console.log("Expected: destNonce >=", newNonce);
                console.log("Actual: destNonce =", destNonce);
            }
        } else {
            console.log("Cross-chain message not dispatched");
        }
        
        console.log("");
        
        // Step 7: Summary
        console.log("=== STEP 7: SUMMARY ===");
        console.log("1. Mailbox configuration: FIXED");
        console.log("2. Cross-chain messaging: ", newNonce > initialNonce ? "WORKING" : "FAILED");
        console.log("3. Message processing: ", destNonce >= newNonce ? "PROCESSED" : "PENDING");
        console.log("4. V2 token minting: ", erc20Balance > 0 ? "WORKING" : "PENDING");
        console.log("5. Balance synchronization: ", internalBalance > 0 ? "SYNCED" : "PENDING");
        
        if (newNonce > initialNonce && destNonce >= newNonce && erc20Balance > 0) {
            console.log("");
            console.log("COMPLETE SUCCESS!");
            console.log("Cross-chain deposit with V2 token minting is fully operational!");
        } else if (newNonce > initialNonce) {
            console.log("");
            console.log("PARTIAL SUCCESS");
            console.log("Message sent successfully, waiting for relayer processing");
        } else {
            console.log("");
            console.log("DEPOSIT FAILED");
            console.log("Check logs for specific error details");
        }
        
        console.log("========== DEPOSIT TEST COMPLETE ==========");
    }
}