// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";

interface IMintable {
    function mint(address to, uint256 amount) external;
}

contract MintAndDepositIDRX is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address balanceManager = 0x2f14AAC5c339d2Fa664e17174F48f3DB074B6C7B;
        address idrxToken = 0x089B7585B2909D2A0D456acaC12fEA8ea55b71cC;
        address mmBotAddress = 0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a;
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Mint 2M IDRX tokens
        uint256 mintAmount = 2_000_000 * 1e18;
        console.log("Minting", mintAmount / 1e18, "IDRX");
        IMintable(idrxToken).mint(msg.sender, mintAmount);
        
        // Check balance
        uint256 balance = IERC20(idrxToken).balanceOf(msg.sender);
        console.log("IDRX balance after mint:", balance / 1e18);
        
        // Deposit 1M IDRX for MM-bot
        uint256 depositAmount = 1_000_000 * 1e18;
        console.log("Depositing", depositAmount / 1e18, "IDRX for MM-bot at", mmBotAddress);
        
        // Approve BalanceManager
        IERC20(idrxToken).approve(balanceManager, depositAmount);
        
        // Deposit IDRX
        BalanceManager(balanceManager).depositLocal(
            idrxToken,
            depositAmount,
            mmBotAddress
        );
        
        vm.stopBroadcast();
        
        console.log("Successfully deposited IDRX for MM-bot");
    }
}
