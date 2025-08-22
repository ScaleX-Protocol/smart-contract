// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";

/**
 * @title TestDirectDeposit
 * @dev Test the deposit function that auto-bridges to synthetic tokens
 */
contract TestDirectDeposit is Script {
    
    // Appchain addresses
    address constant APPCHAIN_USDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
    address constant APPCHAIN_CBM = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
    
    function run() public {
        console.log("=== Testing Direct Deposit (Auto-Bridge) ===");
        
        vm.startBroadcast();
        address user = msg.sender;
        console.log("User:", user);
        
        ChainBalanceManager cbm = ChainBalanceManager(APPCHAIN_CBM);
        
        // Step 1: Mint USDT
        console.log("Minting USDT...");
        (bool mintSuccess,) = APPCHAIN_USDT.call(
            abi.encodeWithSignature("mint(address,uint256)", user, 100 * 10**6)
        );
        require(mintSuccess, "Failed to mint USDT");
        
        uint256 balance = IERC20(APPCHAIN_USDT).balanceOf(user);
        console.log("USDT balance after mint:", balance);
        
        // Step 2: Approve ChainBalanceManager
        console.log("Approving ChainBalanceManager...");
        IERC20(APPCHAIN_USDT).approve(address(cbm), 100 * 10**6);
        
        // Step 3: Deposit with recipient (should auto-bridge)
        console.log("Depositing 100 USDT for recipient:", user);
        cbm.deposit(APPCHAIN_USDT, 100 * 10**6, user);
        
        console.log("SUCCESS: Deposit completed! Cross-chain message should be sent.");
        console.log("Check Rari BalanceManager for minted synthetic tokens for recipient:", user);
        
        vm.stopBroadcast();
    }
}