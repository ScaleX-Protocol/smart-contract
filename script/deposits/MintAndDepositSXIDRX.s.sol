// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";

interface IMintable {
    function mint(address to, uint256 amount) external;
}

contract MintAndDepositSXIDRX is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address balanceManager = 0x2f14AAC5c339d2Fa664e17174F48f3DB074B6C7B;
        address sxIDRXToken = 0x8c4b9700573B5afcf23406B075a236cd89bCfdf4;
        address mmBotAddress = 0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a;
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Mint 10M sxIDRX tokens for testing
        uint256 mintAmount = 10_000_000 * 1e18;
        console.log("Minting", mintAmount / 1e18, "sxIDRX");
        IMintable(sxIDRXToken).mint(msg.sender, mintAmount);
        
        // Check balance
        uint256 balance = IERC20(sxIDRXToken).balanceOf(msg.sender);
        console.log("sxIDRX balance after mint:", balance / 1e18);
        
        // Deposit 5M sxIDRX for MM-bot
        uint256 depositAmount = 5_000_000 * 1e18;
        console.log("Depositing", depositAmount / 1e18, "sxIDRX for MM-bot at", mmBotAddress);
        
        // Approve BalanceManager
        IERC20(sxIDRXToken).approve(balanceManager, depositAmount);
        
        // Deposit sxIDRX
        BalanceManager(balanceManager).depositLocal(
            sxIDRXToken,
            depositAmount,
            mmBotAddress
        );
        
        vm.stopBroadcast();
        
        console.log("Successfully deposited sxIDRX for MM-bot");
    }
}
