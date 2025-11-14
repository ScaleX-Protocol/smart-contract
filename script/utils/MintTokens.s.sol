// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DeployHelpers.s.sol";

/**
 * @title Mint Tokens
 * @dev Mint mock tokens to the deployer account for testing
 * 
 * Usage:
 *   TOKEN_SYMBOL=USDC AMOUNT=1000000000 forge script script/utils/MintTokens.s.sol --broadcast
 */
contract MintTokens is DeployHelpers {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        loadDeployments();
        
        // Get parameters
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");
        uint256 amount = vm.envUint("AMOUNT");
        
        // Get recipient (optional, defaults to deployer)
        address recipient = vm.addr(deployerPrivateKey);
        if (vm.envExists("RECIPIENT")) {
            recipient = vm.envAddress("RECIPIENT");
        }
        
        console.log("=== MINTING TOKENS ===");
        console.log("To:", recipient);
        console.log("Token:", tokenSymbol);
        console.log("Amount:", amount);
        
        // Get token address
        require(deployed[tokenSymbol].isSet, string.concat("Token ", tokenSymbol, " not found"));
        address tokenAddress = deployed[tokenSymbol].addr;
        
        console.log("Token address:", tokenAddress);
        
        // Check balance before
        uint256 balanceBefore = IERC20(tokenAddress).balanceOf(recipient);
        console.log("Balance before:", balanceBefore);
        
        // Mint tokens (assuming MockToken interface)
        MockToken(tokenAddress).mint(recipient, amount);
        
        console.log("Mint successful!");
        
        // Check final balance
        uint256 balanceAfter = IERC20(tokenAddress).balanceOf(recipient);
        console.log("Balance after:", balanceAfter);
        
        vm.stopBroadcast();
    }
}

interface MockToken is IERC20 {
    function mint(address to, uint256 amount) external;
}