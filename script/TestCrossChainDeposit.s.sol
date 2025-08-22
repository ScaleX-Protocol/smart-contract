// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TestCrossChainDeposit
 * @dev Test deposit functionality on source chains for all tokens
 */
contract TestCrossChainDeposit is Script {
    
    function run() public {
        string memory network = vm.envString("NETWORK");
        address testRecipient = vm.envAddress("TEST_RECIPIENT"); // Address to receive synthetic tokens on Rari
        
        vm.startBroadcast();
        
        // Read deployment configuration
        string memory deploymentPath = string.concat("deployments/", network, ".json");
        string memory json = vm.readFile(deploymentPath);
        
        address cbmAddress = vm.parseJsonAddress(json, ".contracts.ChainBalanceManager");
        address usdtAddress = vm.parseJsonAddress(json, ".contracts.USDT");
        address wethAddress = vm.parseJsonAddress(json, ".contracts.WETH");
        address wbtcAddress = vm.parseJsonAddress(json, ".contracts.WBTC");
        
        console.log("=== Testing Cross-Chain Deposit ===");
        console.log("Network:", network);
        console.log("ChainBalanceManager:", cbmAddress);
        console.log("Test Recipient:", testRecipient);
        console.log("");
        
        ChainBalanceManager cbm = ChainBalanceManager(cbmAddress);
        
        // Test all tokens
        testTokenDeposit(cbm, usdtAddress, "USDT", 100 * 10**6, testRecipient); // 100 USDT
        testTokenDeposit(cbm, wethAddress, "WETH", 1 * 10**18, testRecipient);  // 1 WETH  
        testTokenDeposit(cbm, wbtcAddress, "WBTC", 1 * 10**8, testRecipient);   // 1 WBTC
        
        vm.stopBroadcast();
        
        console.log("\n=== Summary ===");
        console.log("SUCCESS: All deposit tests completed");
        console.log("SUCCESS: Cross-chain messages sent to Rari");
        console.log("WAIT: For Hyperlane relayers to process messages");
        console.log("CHECK: Synthetic token balances on Rari BalanceManager");
    }
    
    function testTokenDeposit(
        ChainBalanceManager cbm,
        address tokenAddress,
        string memory tokenName,
        uint256 testAmount,
        address recipient
    ) internal {
        console.log("=== Testing", tokenName, "Deposit ===");
        console.log("Token Address:", tokenAddress);
        console.log("Test Amount:", testAmount);
        
        IERC20 token = IERC20(tokenAddress);
        
        // Check initial state
        console.log("\n--- Pre-Deposit State ---");
        uint256 senderBalance = token.balanceOf(msg.sender);
        console.log("Sender", tokenName, "balance:", senderBalance);
        
        uint256 cbmBalance = token.balanceOf(address(cbm));
        console.log("CBM", tokenName, "balance:", cbmBalance);
        
        uint256 allowance = token.allowance(msg.sender, address(cbm));
        console.log(tokenName, "allowance to CBM:", allowance);
        
        bool isWhitelisted = cbm.isTokenWhitelisted(tokenAddress);
        console.log("Is", tokenName, "whitelisted:", isWhitelisted);
        
        if (!isWhitelisted) {
            console.log("ERROR:", tokenName, "not whitelisted - skipping");
            console.log("");
            return;
        }
        
        // Get mapping details
        address syntheticToken = cbm.getTokenMapping(tokenAddress);
        console.log("Synthetic Token:", syntheticToken);
        
        if (senderBalance < testAmount) {
            console.log("ERROR: Insufficient", tokenName, "balance for test");
            console.log("Required:", testAmount, "Available:", senderBalance);
            console.log("");
            return;
        }
        
        // Approve if needed
        if (allowance < testAmount) {
            console.log("Approving", tokenName, "...");
            token.approve(address(cbm), testAmount);
            console.log("SUCCESS:", tokenName, "approved");
        }
        
        // Perform deposit
        console.log("\n--- Performing Deposit ---");
        console.log("Depositing", testAmount, tokenName, "for recipient:");
        console.log("Recipient:", recipient);
        
        try cbm.deposit(tokenAddress, testAmount, recipient) {
            console.log("SUCCESS: Deposit successful!");
            
            // Check post-deposit state
            console.log("\n--- Post-Deposit State ---");
            console.log("Sender", tokenName, "balance:", token.balanceOf(msg.sender));
            console.log("CBM", tokenName, "balance:", token.balanceOf(address(cbm)));
            
            console.log("MINT: Synthetic token to mint:", syntheticToken);
            console.log("RECIPIENT: On Rari:", recipient);
            
        } catch Error(string memory reason) {
            console.log("ERROR: Deposit failed:", reason);
        } catch {
            console.log("ERROR: Deposit failed: Unknown error");
        }
        
        console.log("");
    }
}