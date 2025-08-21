// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MintTestTokens
 * @dev Try to mint tokens from existing Appchain contracts
 */
contract MintTestTokens is Script {
    
    // Appchain token addresses
    address constant APPCHAIN_USDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
    address constant APPCHAIN_WETH = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
    address constant APPCHAIN_WBTC = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;
    
    function run() public {
        console.log("Attempting to mint test tokens on Appchain...");
        
        vm.startBroadcast();
        address user = msg.sender;
        
        console.log("User address:", user);
        
        // Try to mint USDT
        console.log("Attempting to mint USDT...");
        try this.mintToken(APPCHAIN_USDT, user, 1000 * 10**6) {
            console.log("USDT mint successful");
        } catch {
            console.log("USDT mint failed - trying direct call");
            this.tryDirectMint(APPCHAIN_USDT, user, 1000 * 10**6, "USDT");
        }
        
        // Try to mint WETH
        console.log("Attempting to mint WETH...");
        try this.mintToken(APPCHAIN_WETH, user, 10 * 10**18) {
            console.log("WETH mint successful");
        } catch {
            console.log("WETH mint failed - trying direct call");
            this.tryDirectMint(APPCHAIN_WETH, user, 10 * 10**18, "WETH");
        }
        
        // Try to mint WBTC
        console.log("Attempting to mint WBTC...");
        try this.mintToken(APPCHAIN_WBTC, user, 5 * 10**8) {
            console.log("WBTC mint successful");
        } catch {
            console.log("WBTC mint failed - trying direct call");
            this.tryDirectMint(APPCHAIN_WBTC, user, 5 * 10**8, "WBTC");
        }
        
        vm.stopBroadcast();
        
        // Check final balances
        console.log("=== Final Balances ===");
        console.log("USDT balance:", IERC20(APPCHAIN_USDT).balanceOf(user));
        console.log("WETH balance:", IERC20(APPCHAIN_WETH).balanceOf(user));
        console.log("WBTC balance:", IERC20(APPCHAIN_WBTC).balanceOf(user));
    }
    
    function mintToken(address token, address to, uint256 amount) external {
        // Try standard mint function
        (bool success,) = token.call(abi.encodeWithSignature("mint(address,uint256)", to, amount));
        require(success, "Mint failed");
    }
    
    function tryDirectMint(address token, address to, uint256 amount, string memory symbol) external {
        console.log("Trying different mint signatures for", symbol);
        
        // Try mint(address,uint256)
        (bool success1,) = token.call(abi.encodeWithSignature("mint(address,uint256)", to, amount));
        if (success1) {
            console.log("Success with mint(address,uint256)");
            return;
        }
        
        // Try mint(uint256)
        (bool success2,) = token.call(abi.encodeWithSignature("mint(uint256)", amount));
        if (success2) {
            console.log("Success with mint(uint256)");
            return;
        }
        
        // Try faucet()
        (bool success3,) = token.call(abi.encodeWithSignature("faucet()"));
        if (success3) {
            console.log("Success with faucet()");
            return;
        }
        
        // Try drip()
        (bool success4,) = token.call(abi.encodeWithSignature("drip()"));
        if (success4) {
            console.log("Success with drip()");
            return;
        }
        
        console.log("All mint attempts failed for", symbol);
    }
}