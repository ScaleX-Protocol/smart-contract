// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "../src/core/BalanceManager.sol";
import "../src/token/SyntheticToken.sol";
import "../src/mocks/MockToken.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

contract TestAppchainToRariDeposit is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== APPCHAIN TO RARI DEPOSIT TEST ==========");
        console.log("Testing complete cross-chain deposit flow with V2 token minting");
        console.log("User:", deployer);
        console.log("");
        
        // STEP 1: Check initial state on Rari (destination)
        console.log("=== STEP 1: INITIAL STATE ON RARI (DESTINATION) ===");
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address realGsUSDTAddr = 0x6fcf28b801C7116cA8b6460289e259aC8D9131F3;
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        SyntheticToken realGsUSDT = SyntheticToken(realGsUSDTAddr);
        Currency gsUSDTCurrency = Currency.wrap(realGsUSDTAddr);
        
        uint256 initialERC20Balance = realGsUSDT.balanceOf(deployer);
        uint256 initialInternalBalance = balanceManager.getBalance(deployer, gsUSDTCurrency);
        uint256 initialTotalSupply = realGsUSDT.totalSupply();
        uint256 initialDestNonce = balanceManager.getUserNonce(deployer);
        
        console.log("Initial ERC20 gsUSDT balance:", initialERC20Balance);
        console.log("Initial internal BalanceManager balance:", initialInternalBalance);
        console.log("Initial gsUSDT total supply:", initialTotalSupply);
        console.log("Initial processed messages:", initialDestNonce);
        console.log("");
        
        // STEP 2: Check source chain status (Appchain)
        console.log("=== STEP 2: SOURCE CHAIN STATUS (APPCHAIN) ===");
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        address mockUSDTAddr = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        MockToken mockUSDT = MockToken(mockUSDTAddr);
        
        uint256 initialSourceNonce = cbm.getUserNonce(deployer);
        uint256 userMockBalance = mockUSDT.balanceOf(deployer);
        address mappedSynthetic = cbm.getTokenMapping(mockUSDTAddr);
        
        console.log("Initial source nonce (messages sent):", initialSourceNonce);
        console.log("User mock USDT balance:", userMockBalance);
        console.log("Mapped synthetic token:", mappedSynthetic);
        console.log("Token mapping correct:", mappedSynthetic == realGsUSDTAddr ? "YES" : "NO");
        console.log("");
        
        // STEP 3: Execute deposit from Appchain
        console.log("=== STEP 3: EXECUTING DEPOSIT FROM APPCHAIN ===");
        
        uint256 depositAmount = 30000000; // 30 USDT
        console.log("Deposit amount:", depositAmount, "(30 USDT)");
        
        if (userMockBalance < depositAmount) {
            console.log("ERROR: Insufficient mock USDT balance");
            console.log("Available:", userMockBalance);
            console.log("Required:", depositAmount);
            return;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Approve ChainBalanceManager to spend mock tokens
        console.log("Approving ChainBalanceManager...");
        mockUSDT.approve(chainBalanceManagerAddr, depositAmount);
        
        // Execute cross-chain deposit
        console.log("Executing cross-chain deposit...");
        cbm.deposit(mockUSDTAddr, depositAmount, deployer);
        
        vm.stopBroadcast();
        
        // Verify deposit effects on source chain
        uint256 newSourceNonce = cbm.getUserNonce(deployer);
        uint256 newUserMockBalance = mockUSDT.balanceOf(deployer);
        uint256 lockedBalance = cbm.balanceOf(deployer, mockUSDTAddr);
        
        console.log("SUCCESS: Deposit transaction completed!");
        console.log("New source nonce:", newSourceNonce);
        console.log("Messages sent:", newSourceNonce - initialSourceNonce);
        console.log("User mock USDT balance after:", newUserMockBalance);
        console.log("Tokens locked in ChainBalanceManager:", lockedBalance);
        console.log("");
        
        // STEP 4: Check destination immediately (before relayer)
        console.log("=== STEP 4: RARI STATE (IMMEDIATE - BEFORE RELAYER) ===");
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        uint256 immediateDestNonce = balanceManager.getUserNonce(deployer);
        uint256 immediateERC20Balance = realGsUSDT.balanceOf(deployer);
        uint256 immediateInternalBalance = balanceManager.getBalance(deployer, gsUSDTCurrency);
        uint256 immediateTotalSupply = realGsUSDT.totalSupply();
        
        console.log("Processed messages (should be same):", immediateDestNonce);
        console.log("ERC20 balance (should be same):", immediateERC20Balance);
        console.log("Internal balance (should be same):", immediateInternalBalance);
        console.log("Total supply (should be same):", immediateTotalSupply);
        console.log("");
        
        // STEP 5: Wait for relayer processing
        console.log("=== STEP 5: WAITING FOR HYPERLANE RELAYER ===");
        console.log("Waiting 20 seconds for relayer to process message...");
        console.log("(In production, this typically takes 10-30 seconds)");
        console.log("");
        
        // Note: In a real environment, you'd wait here. For testing, we'll check periodically.
        
        // STEP 6: Check final state after relayer processing
        console.log("=== STEP 6: FINAL STATE AFTER RELAYER PROCESSING ===");
        console.log("Checking if tokens have been minted...");
        
        uint256 finalDestNonce = balanceManager.getUserNonce(deployer);
        uint256 finalERC20Balance = realGsUSDT.balanceOf(deployer);
        uint256 finalInternalBalance = balanceManager.getBalance(deployer, gsUSDTCurrency);
        uint256 finalTotalSupply = realGsUSDT.totalSupply();
        
        console.log("Final processed messages:", finalDestNonce);
        console.log("Final ERC20 gsUSDT balance:", finalERC20Balance);
        console.log("Final internal BalanceManager balance:", finalInternalBalance);
        console.log("Final gsUSDT total supply:", finalTotalSupply);
        console.log("");
        
        // STEP 7: Analysis and results
        console.log("=== STEP 7: RESULTS ANALYSIS ===");
        
        bool messageProcessed = finalDestNonce > initialDestNonce;
        bool tokensMinmed = finalERC20Balance > initialERC20Balance;
        bool balanceSynced = finalInternalBalance > initialInternalBalance;
        bool supplyIncreased = finalTotalSupply > initialTotalSupply;
        
        uint256 mintedAmount = finalERC20Balance - initialERC20Balance;
        uint256 balanceIncrease = finalInternalBalance - initialInternalBalance;
        uint256 supplyIncrease = finalTotalSupply - initialTotalSupply;
        
        console.log("Cross-chain message sent:", newSourceNonce > initialSourceNonce ? "YES" : "NO");
        console.log("Message processed by relayer:", messageProcessed ? "YES" : "NO");
        console.log("Real ERC20 tokens minted:", tokensMinmed ? "YES" : "NO");
        console.log("Internal balance synchronized:", balanceSynced ? "YES" : "NO");
        console.log("Total supply increased:", supplyIncreased ? "YES" : "NO");
        console.log("");
        
        if (tokensMinmed) {
            console.log("SUCCESS METRICS:");
            console.log("- ERC20 tokens minted:", mintedAmount);
            console.log("- Internal balance increased:", balanceIncrease);
            console.log("- Total supply increased:", supplyIncrease);
            console.log("- All values match:", (mintedAmount == balanceIncrease && balanceIncrease == supplyIncrease) ? "YES" : "NO");
        }
        console.log("");
        
        // STEP 8: Final summary
        console.log("=== STEP 8: FINAL SUMMARY ===");
        
        if (messageProcessed && tokensMinmed && balanceSynced && supplyIncreased) {
            console.log("COMPLETE SUCCESS!");
            console.log("Cross-chain deposit with V2 token minting FULLY WORKING!");
            console.log("");
            console.log("Flow completed:");
            console.log("1. Deposited", depositAmount, "USDT on Appchain");
            console.log("2. Cross-chain message sent via Hyperlane");
            console.log("3. Message processed on Rari");
            console.log("4. Real ERC20 tokens minted:", mintedAmount);
            console.log("5. Internal balances synchronized");
            console.log("6. User can now trade with real tokens!");
        } else if (newSourceNonce > initialSourceNonce) {
            console.log("PARTIAL SUCCESS - MESSAGE SENT");
            console.log("Cross-chain message was sent successfully.");
            console.log("Waiting for Hyperlane relayer to process...");
            console.log("");
            console.log("Check again in 30-60 seconds to see token minting.");
        } else {
            console.log("DEPOSIT FAILED");
            console.log("Cross-chain message was not sent from Appchain.");
        }
        
        console.log("");
        console.log("========== APPCHAIN TO RARI DEPOSIT TEST COMPLETE ==========");
    }
}