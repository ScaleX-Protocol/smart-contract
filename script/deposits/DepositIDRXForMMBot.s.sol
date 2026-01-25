// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";

contract DepositIDRXForMMBot is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address balanceManager = vm.envAddress("PROXY_BALANCE_MANAGER");
        address idrxToken = vm.envAddress("IDRX_TOKEN_ADDRESS");
        address mmBotAddress = vm.envAddress("MM_BOT_ADDRESS");
        
        console.log("Balance Manager:", balanceManager);
        console.log("IDRX Token:", idrxToken);
        console.log("MM Bot Address:", mmBotAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Check deployer's IDRX balance
        uint256 deployerBalance = IERC20(idrxToken).balanceOf(msg.sender);
        console.log("Deployer IDRX balance:", deployerBalance / 1e18, "IDRX");
        
        // Deposit 1,000,000 IDRX (1M IDRX with 18 decimals)
        uint256 depositAmount = 1_000_000 * 1e18;
        require(deployerBalance >= depositAmount, "Insufficient IDRX balance");
        
        console.log("Depositing", depositAmount / 1e18, "IDRX for MM-bot");
        
        // Approve BalanceManager
        IERC20(idrxToken).approve(balanceManager, depositAmount);
        
        // Deposit IDRX for MM-bot
        BalanceManager(balanceManager).depositLocal(
            idrxToken,
            depositAmount,
            mmBotAddress
        );
        
        vm.stopBroadcast();
        
        console.log("Successfully deposited IDRX for MM-bot");
    }
}
