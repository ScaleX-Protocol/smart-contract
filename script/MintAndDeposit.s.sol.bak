// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";

/**
 * @title MintAndDeposit
 * @dev Mint tokens and immediately test cross-chain deposit in one transaction
 */
contract MintAndDeposit is Script {
    
    // Appchain addresses
    address constant APPCHAIN_USDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
    address constant APPCHAIN_WETH = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
    address constant APPCHAIN_WBTC = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;
    address constant APPCHAIN_CBM = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
    
    function run() public {
        console.log("=== Mint and Deposit Test on Appchain ===");
        
        vm.startBroadcast();
        address user = msg.sender;
        console.log("User:", user);
        
        // Mint and deposit USDT
        console.log("1. Testing USDT...");
        mintAndDeposit(APPCHAIN_USDT, user, 100 * 10**6, "USDT"); // 100 USDT
        
        // Mint and deposit WETH  
        console.log("2. Testing WETH...");
        mintAndDeposit(APPCHAIN_WETH, user, 1 * 10**18, "WETH"); // 1 WETH
        
        // Mint and deposit WBTC
        console.log("3. Testing WBTC...");
        mintAndDeposit(APPCHAIN_WBTC, user, 1 * 10**8, "WBTC"); // 1 WBTC
        
        vm.stopBroadcast();
        
        console.log("=== All deposits completed! ===");
        console.log("Check Rari balances after Hyperlane relay processes the messages");
    }
    
    function mintAndDeposit(address token, address user, uint256 amount, string memory symbol) internal {
        ChainBalanceManager cbm = ChainBalanceManager(APPCHAIN_CBM);
        
        // Step 1: Mint tokens
        console.log("Minting", symbol, "...");
        (bool mintSuccess,) = token.call(abi.encodeWithSignature("mint(address,uint256)", user, amount));
        require(mintSuccess, string(abi.encodePacked("Failed to mint ", symbol)));
        
        // Step 2: Check balance
        uint256 balance = IERC20(token).balanceOf(user);
        console.log("Balance after mint:", balance);
        require(balance >= amount, "Insufficient balance after mint");
        
        // Step 3: Approve ChainBalanceManager
        console.log("Approving ChainBalanceManager for", symbol, "...");
        IERC20(token).approve(address(cbm), amount);
        
        // Step 4: Check allowance
        uint256 allowance = IERC20(token).allowance(user, address(cbm));
        console.log("Allowance:", allowance);
        require(allowance >= amount, "Insufficient allowance");
        
        // Step 5: Deposit to trigger cross-chain message
        console.log("Depositing", amount, symbol, "to ChainBalanceManager...");
        cbm.bridgeToSynthetic(token, amount);
        
        console.log("Deposit transaction completed!");
        
        console.log("SUCCESS:", symbol, "deposit completed! Cross-chain message sent.");
        console.log("---");
    }
}