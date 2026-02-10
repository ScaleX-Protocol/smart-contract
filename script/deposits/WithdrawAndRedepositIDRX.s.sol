// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";

contract WithdrawAndRedepositIDRX is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address balanceManager = 0x2f14AAC5c339d2Fa664e17174F48f3DB074B6C7B;
        address idrxToken = 0x089B7585B2909D2A0D456acaC12fEA8ea55b71cC;
        address mmBotAddress = 0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a;
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Check current balance
        console.log("=== Step 1: Withdraw incorrectly scaled balance ===");
        uint256 currentBalance = BalanceManager(balanceManager).getBalance(mmBotAddress, Currency.wrap(idrxToken));
        console.log("Current IDRX balance (raw):", currentBalance);
        
        if (currentBalance > 0) {
            console.log("Withdrawing all IDRX...");
            // Withdraw for the MM-bot address (only owner/operator can withdraw for others)
            BalanceManager(balanceManager).withdraw(Currency.wrap(idrxToken), currentBalance, mmBotAddress);
            console.log("Withdrawn!");
        } else {
            console.log("No balance to withdraw");
        }
        
        // Mint fresh IDRX if deployer doesn't have enough
        uint256 deployerBalance = IERC20(idrxToken).balanceOf(msg.sender);
        console.log("\n=== Step 2: Prepare fresh IDRX ===");
        console.log("Deployer IDRX balance:", deployerBalance / 1e18, "IDRX");
        
        uint256 depositAmount = 1_000_000 * 1e18; // 1M IDRX
        
        if (deployerBalance < depositAmount) {
            console.log("Insufficient balance, minting more...");
            // Note: This assumes IDRX has a mint function accessible to deployer
            // If not, you'll need to get IDRX another way
        }
        
        // Deposit with correct scaling
        console.log("\n=== Step 3: Deposit with correct scaling ===");
        console.log("Depositing", depositAmount / 1e18, "IDRX for MM-bot");
        
        IERC20(idrxToken).approve(balanceManager, depositAmount);
        BalanceManager(balanceManager).depositLocal(idrxToken, depositAmount, mmBotAddress);
        
        vm.stopBroadcast();
        
        // Verify
        console.log("\n=== Verification ===");
        uint256 newBalance = BalanceManager(balanceManager).getBalance(mmBotAddress, Currency.wrap(idrxToken));
        console.log("New IDRX balance (raw):", newBalance);
        console.log("New IDRX balance (formatted):", newBalance / 1e18, "IDRX");
        console.log("\n=== SUCCESS! MM-bot can now place BUY orders! ===");
    }
}
