// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

interface SyntheticToken {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract MintTestTokensForTrading is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== MINTING TEST TOKENS FOR TRADING =========");
        console.log("User:", deployer);
        
        // Switch to Rari
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        // Contract addresses
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address gsUSDT = 0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address gsWBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        SyntheticToken usdtToken = SyntheticToken(gsUSDT);
        SyntheticToken wethToken = SyntheticToken(gsWETH);
        SyntheticToken wbtcToken = SyntheticToken(gsWBTC);
        
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("gsUSDT:", gsUSDT);
        console.log("gsWETH:", gsWETH);
        console.log("gsWBTC:", gsWBTC);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Try to mint tokens directly (if we have minter role)
        console.log("=== STEP 1: MINTING TEST TOKENS ===");
        
        uint256 usdtAmount = 1000e18; // 1000 gsUSDT (assuming 18 decimals)
        uint256 wethAmount = 1e18;    // 1 gsWETH
        uint256 wbtcAmount = 1e8;     // 1 gsWBTC (8 decimals)
        
        // Try to mint gsUSDT
        try usdtToken.mint(deployer, usdtAmount) {
            console.log("SUCCESS: Minted", usdtAmount, "gsUSDT");
        } catch Error(string memory reason) {
            console.log("Failed to mint gsUSDT:", reason);
        } catch {
            console.log("Failed to mint gsUSDT with unknown error");
        }
        
        // Try to mint gsWETH  
        try wethToken.mint(deployer, wethAmount) {
            console.log("SUCCESS: Minted", wethAmount, "gsWETH");
        } catch Error(string memory reason) {
            console.log("Failed to mint gsWETH:", reason);
        } catch {
            console.log("Failed to mint gsWETH with unknown error");
        }
        
        // Try to mint gsWBTC
        try wbtcToken.mint(deployer, wbtcAmount) {
            console.log("SUCCESS: Minted", wbtcAmount, "gsWBTC");
        } catch Error(string memory reason) {
            console.log("Failed to mint gsWBTC:", reason);
        } catch {
            console.log("Failed to mint gsWBTC with unknown error");
        }
        
        // Step 2: Check token balances
        console.log("=== STEP 2: CHECKING TOKEN BALANCES ===");
        
        uint256 usdtBalance = usdtToken.balanceOf(deployer);
        uint256 wethBalance = wethToken.balanceOf(deployer);
        uint256 wbtcBalance = wbtcToken.balanceOf(deployer);
        
        console.log("gsUSDT token balance:", usdtBalance);
        console.log("gsWETH token balance:", wethBalance);
        console.log("gsWBTC token balance:", wbtcBalance);
        
        // Step 3: Deposit tokens to BalanceManager for trading
        if (usdtBalance > 0) {
            console.log("=== STEP 3: DEPOSITING TO BALANCE MANAGER ===");
            
            // Approve BalanceManager to spend tokens
            Currency usdtCurrency = Currency.wrap(gsUSDT);
            Currency wethCurrency = Currency.wrap(gsWETH);
            Currency wbtcCurrency = Currency.wrap(gsWBTC);
            
            if (usdtBalance > 0) {
                try usdtToken.approve(balanceManagerAddr, usdtBalance) {
                    console.log("Approved gsUSDT for BalanceManager");
                    
                    try balanceManager.deposit(usdtCurrency, usdtBalance, deployer, deployer) {
                        console.log("SUCCESS: Deposited gsUSDT to BalanceManager");
                    } catch Error(string memory reason) {
                        console.log("Failed to deposit gsUSDT:", reason);
                    }
                } catch {
                    console.log("Failed to approve gsUSDT");
                }
            }
            
            if (wethBalance > 0) {
                try wethToken.approve(balanceManagerAddr, wethBalance) {
                    console.log("Approved gsWETH for BalanceManager");
                    
                    try balanceManager.deposit(wethCurrency, wethBalance, deployer, deployer) {
                        console.log("SUCCESS: Deposited gsWETH to BalanceManager");
                    } catch Error(string memory reason) {
                        console.log("Failed to deposit gsWETH:", reason);
                    }
                } catch {
                    console.log("Failed to approve gsWETH");
                }
            }
            
            if (wbtcBalance > 0) {
                try wbtcToken.approve(balanceManagerAddr, wbtcBalance) {
                    console.log("Approved gsWBTC for BalanceManager");
                    
                    try balanceManager.deposit(wbtcCurrency, wbtcBalance, deployer, deployer) {
                        console.log("SUCCESS: Deposited gsWBTC to BalanceManager");
                    } catch Error(string memory reason) {
                        console.log("Failed to deposit gsWBTC:", reason);
                    }
                } catch {
                    console.log("Failed to approve gsWBTC");
                }
            }
            
            // Check final balances in BalanceManager
            console.log("=== FINAL BALANCE MANAGER BALANCES ===");
            uint256 bmUsdtBalance = balanceManager.getBalance(deployer, usdtCurrency);
            uint256 bmWethBalance = balanceManager.getBalance(deployer, wethCurrency);
            uint256 bmWbtcBalance = balanceManager.getBalance(deployer, wbtcCurrency);
            
            console.log("BalanceManager gsUSDT balance:", bmUsdtBalance);
            console.log("BalanceManager gsWETH balance:", bmWethBalance);
            console.log("BalanceManager gsWBTC balance:", bmWbtcBalance);
            
            if (bmUsdtBalance > 0 || bmWethBalance > 0 || bmWbtcBalance > 0) {
                console.log("SUCCESS: Ready for trading!");
                console.log("Now run TestCLOBTrading.s.sol to test trading functionality");
            }
        }
        
        vm.stopBroadcast();
        
        console.log("========== MINTING COMPLETE =========");
    }
}