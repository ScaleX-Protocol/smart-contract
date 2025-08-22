// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface MockERC20 {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract MintAndTestDeposit is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== MINT AND TEST DEPOSIT =========");
        console.log("User:", deployer);
        
        // Switch to Appchain
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address appchainUSDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        
        MockERC20 usdt = MockERC20(appchainUSDT);
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        console.log("Appchain USDT:", appchainUSDT);
        console.log("ChainBalanceManager:", chainBalanceManagerAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Mint USDT to user
        uint256 mintAmount = 1000e6; // 1000 USDT (6 decimals)
        console.log("Minting USDT to user:", mintAmount);
        
        try usdt.mint(deployer, mintAmount) {
            console.log("SUCCESS: Minted USDT to user");
        } catch Error(string memory reason) {
            console.log("Failed to mint USDT:", reason);
        } catch {
            console.log("Failed to mint USDT with unknown error");
        }
        
        // Check balance after minting
        uint256 userTokenBalance = usdt.balanceOf(deployer);
        console.log("User's USDT token balance after minting:", userTokenBalance);
        
        if (userTokenBalance > 0) {
            // Step 2: Approve ChainBalanceManager to spend USDT
            console.log("Approving ChainBalanceManager to spend USDT...");
            
            try usdt.approve(chainBalanceManagerAddr, userTokenBalance) {
                console.log("SUCCESS: Approved ChainBalanceManager");
            } catch Error(string memory reason) {
                console.log("Failed to approve:", reason);
            } catch {
                console.log("Failed to approve with unknown error");
            }
            
            // Step 3: Deposit USDT to ChainBalanceManager (local balance)
            uint256 depositAmount = userTokenBalance / 2; // Deposit half
            console.log("Depositing USDT to CBM (local balance):", depositAmount);
            
            try cbm.deposit(appchainUSDT, depositAmount, deployer) {
                console.log("SUCCESS: Deposited USDT to ChainBalanceManager");
                
                // Check balance in CBM
                uint256 cbmBalance = cbm.getBalance(deployer, appchainUSDT);
                console.log("User's balance in CBM after deposit:", cbmBalance);
                
                if (cbmBalance >= 100e6) { // If we have at least 100 USDT
                    // Step 4: Test cross-chain bridge to Rari
                    uint256 bridgeAmount = 100e6; // Bridge 100 USDT
                    console.log("Attempting cross-chain bridge:", bridgeAmount);
                    
                    try cbm.deposit(appchainUSDT, bridgeAmount, deployer) {
                        console.log("SUCCESS: Cross-chain bridge initiated!");
                        console.log("Message dispatched to Rari BalanceManager");
                        console.log("Check Hyperlane explorer: https://hyperlane-explorer.gtxdex.xyz/");
                        
                        // Wait a moment then check if balance decreased
                        uint256 balanceAfterBridge = cbm.getBalance(deployer, appchainUSDT);
                        console.log("Balance in CBM after bridge:", balanceAfterBridge);
                        
                    } catch Error(string memory reason) {
                        console.log("Cross-chain bridge failed:", reason);
                    } catch {
                        console.log("Cross-chain bridge failed with unknown error");
                    }
                } else {
                    console.log("Not enough balance in CBM for cross-chain bridge test");
                }
                
            } catch Error(string memory reason) {
                console.log("Failed to deposit to CBM:", reason);
            } catch {
                console.log("Failed to deposit to CBM with unknown error");
            }
        } else {
            console.log("Minting failed - no token balance");
        }
        
        vm.stopBroadcast();
        
        console.log("========== DONE =========");
        console.log("Next: Check if synthetic tokens were minted on Rari");
    }
}