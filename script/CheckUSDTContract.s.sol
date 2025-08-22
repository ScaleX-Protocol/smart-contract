// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckUSDTContract is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== CHECKING USDT CONTRACT =========");
        console.log("User:", deployer);
        
        // Switch to Appchain
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address appchainUSDT = 0x05bFe17e3c96E2b0c19F8aE8E7A36b2E2c3B6E2a;
        console.log("Checking USDT contract:", appchainUSDT);
        
        // Check if contract exists and what we can see about it
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(appchainUSDT)
        }
        console.log("Contract code size:", codeSize);
        
        if (codeSize > 0) {
            console.log("Contract exists!");
            
            // Try to call standard ERC20 functions
            try this.externalBalanceOf(appchainUSDT, deployer) returns (uint256 balance) {
                console.log("User's USDT balance:", balance);
            } catch {
                console.log("Failed to check balance");
            }
            
            try this.externalTotalSupply(appchainUSDT) returns (uint256 totalSupply) {
                console.log("Total supply:", totalSupply);
            } catch {
                console.log("Failed to check total supply");
            }
            
            try this.externalName(appchainUSDT) returns (string memory name) {
                console.log("Token name:", name);
            } catch {
                console.log("Failed to get name");
            }
            
        } else {
            console.log("Contract does not exist at this address!");
        }
        
        console.log("========== DONE =========");
    }
    
    // External functions to avoid try/catch issues with direct calls
    function externalBalanceOf(address token, address account) external view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }
    
    function externalTotalSupply(address token) external view returns (uint256) {
        return IERC20(token).totalSupply();
    }
    
    function externalName(address token) external view returns (string memory) {
        return IERC20Metadata(token).name();
    }
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IERC20Metadata {
    function name() external view returns (string memory);
}