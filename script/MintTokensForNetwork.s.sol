// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MintTokensForNetwork
 * @dev Dynamically mint tokens from deployment files for any network
 */
contract MintTokensForNetwork is Script {
    
    function run() public {
        string memory network = vm.envString("NETWORK");
        
        console.log("Attempting to mint test tokens on", network);
        
        vm.startBroadcast();
        address user = msg.sender;
        
        // Read deployment configuration
        string memory deploymentPath = string.concat("deployments/", network, ".json");
        string memory json = vm.readFile(deploymentPath);
        
        address usdtAddress = vm.parseJsonAddress(json, ".contracts.USDT");
        address wethAddress = vm.parseJsonAddress(json, ".contracts.WETH");
        address wbtcAddress = vm.parseJsonAddress(json, ".contracts.WBTC");
        
        console.log("User address:", user);
        console.log("USDT:", usdtAddress);
        console.log("WETH:", wethAddress);
        console.log("WBTC:", wbtcAddress);
        
        // Try to mint tokens
        tryMintToken(usdtAddress, user, 1000 * 10**6, "USDT");   // 1000 USDT
        tryMintToken(wethAddress, user, 10 * 10**18, "WETH");    // 10 WETH
        tryMintToken(wbtcAddress, user, 5 * 10**8, "WBTC");      // 5 WBTC
        
        vm.stopBroadcast();
        
        // Check final balances
        console.log("=== Final Balances ===");
        console.log("USDT balance:", IERC20(usdtAddress).balanceOf(user));
        console.log("WETH balance:", IERC20(wethAddress).balanceOf(user));
        console.log("WBTC balance:", IERC20(wbtcAddress).balanceOf(user));
    }
    
    function tryMintToken(address token, address to, uint256 amount, string memory symbol) internal {
        console.log("Attempting to mint", symbol, "...");
        
        // Try mint(address,uint256)
        (bool success1,) = token.call(abi.encodeWithSignature("mint(address,uint256)", to, amount));
        if (success1) {
            console.log("SUCCESS:", symbol, "minted with mint(address,uint256)");
            return;
        }
        
        // Try mint(uint256) 
        (bool success2,) = token.call(abi.encodeWithSignature("mint(uint256)", amount));
        if (success2) {
            console.log("SUCCESS:", symbol, "minted with mint(uint256)");
            return;
        }
        
        // Try faucet()
        (bool success3,) = token.call(abi.encodeWithSignature("faucet()"));
        if (success3) {
            console.log("SUCCESS:", symbol, "minted with faucet()");
            return;
        }
        
        // Try drip()
        (bool success4,) = token.call(abi.encodeWithSignature("drip()"));
        if (success4) {
            console.log("SUCCESS:", symbol, "minted with drip()");
            return;
        }
        
        // Try gimmeSome()
        (bool success5,) = token.call(abi.encodeWithSignature("gimmeSome()"));
        if (success5) {
            console.log("SUCCESS:", symbol, "minted with gimmeSome()");
            return;
        }
        
        console.log("ERROR: All mint attempts failed for", symbol);
    }
}