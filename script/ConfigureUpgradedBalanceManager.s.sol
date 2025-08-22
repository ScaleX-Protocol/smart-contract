// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

interface IERC20Extended {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

contract ConfigureUpgradedBalanceManager is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== CONFIGURING UPGRADED BALANCE MANAGER ==========");
        console.log("User:", deployer);
        
        // Switch to Rari
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        // Contract addresses
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address tokenRegistryAddr = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;
        address newImpl = 0x465C4A8c43df8fBc9952f28a72a6Ce2c3B57a26d;
        
        // Synthetic token addresses
        address gsUSDT = 0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address gsWBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        
        console.log("=== UPGRADE STATUS ===");
        console.log("BalanceManager Proxy:", balanceManagerAddr);
        console.log("New Implementation:", newImpl);
        console.log("TokenRegistry:", tokenRegistryAddr);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Configure TokenRegistry
        console.log("=== CONFIGURING TOKEN REGISTRY ===");
        try balanceManager.setTokenRegistry(tokenRegistryAddr) {
            console.log("SUCCESS: TokenRegistry configured");
        } catch Error(string memory reason) {
            console.log("TokenRegistry setup failed:", reason);
        } catch {
            console.log("TokenRegistry setup failed with unknown error");
        }
        
        vm.stopBroadcast();
        
        // Test the synthetic tokens
        console.log("");
        console.log("=== TESTING SYNTHETIC TOKENS ===");
        
        // Test gsUSDT
        try IERC20Extended(gsUSDT).name() returns (string memory name) {
            console.log("gsUSDT name:", name);
            try IERC20Extended(gsUSDT).totalSupply() returns (uint256 supply) {
                console.log("gsUSDT total supply:", supply);
            } catch {
                console.log("gsUSDT total supply: Could not read");
            }
        } catch {
            console.log("gsUSDT: Contract does not exist or is not ERC20");
        }
        
        // Test gsWETH
        try IERC20Extended(gsWETH).name() returns (string memory name) {
            console.log("gsWETH name:", name);
            try IERC20Extended(gsWETH).totalSupply() returns (uint256 supply) {
                console.log("gsWETH total supply:", supply);
            } catch {
                console.log("gsWETH total supply: Could not read");
            }
        } catch {
            console.log("gsWETH: Contract does not exist or is not ERC20");
        }
        
        // Check user balances
        console.log("");
        console.log("=== USER BALANCES ===");
        
        Currency usdtCurrency = Currency.wrap(gsUSDT);
        Currency wethCurrency = Currency.wrap(gsWETH);
        Currency wbtcCurrency = Currency.wrap(gsWBTC);
        
        uint256 usdtBalance = balanceManager.getBalance(deployer, usdtCurrency);
        uint256 wethBalance = balanceManager.getBalance(deployer, wethCurrency);
        uint256 wbtcBalance = balanceManager.getBalance(deployer, wbtcCurrency);
        uint256 userNonce = balanceManager.getUserNonce(deployer);
        
        console.log("Internal BalanceManager balances:");
        console.log("- gsUSDT:", usdtBalance);
        console.log("- gsWETH:", wethBalance);
        console.log("- gsWBTC:", wbtcBalance);
        console.log("Cross-chain messages processed:", userNonce);
        console.log("");
        
        // Check ERC20 balances
        console.log("ERC20 token balances:");
        try IERC20Extended(gsUSDT).balanceOf(deployer) returns (uint256 bal) {
            console.log("- gsUSDT ERC20 balance:", bal);
        } catch {
            console.log("- gsUSDT: Not accessible as ERC20");
        }
        
        try IERC20Extended(gsWETH).balanceOf(deployer) returns (uint256 bal) {
            console.log("- gsWETH ERC20 balance:", bal);
        } catch {
            console.log("- gsWETH: Not accessible as ERC20");
        }
        
        console.log("");
        console.log("=== SYSTEM STATUS ===");
        
        if (userNonce > 0) {
            console.log("STATUS: Cross-chain messages have been processed");
            if (usdtBalance > 0) {
                console.log("READY: User has internal balances for trading");
                console.log("NOTE: ERC20 tokens will be minted on NEXT cross-chain deposit");
            }
        } else {
            console.log("STATUS: Waiting for cross-chain messages to process");
        }
        
        console.log("");
        console.log("=== WHAT'S FIXED ===");
        console.log("1. NEW: Real ERC20 token minting on cross-chain deposits");
        console.log("2. NEW: Real ERC20 token burning on cross-chain withdrawals");
        console.log("3. NEW: TokenRegistry integration");
        console.log("4. OLD: Internal balance tracking (still works for CLOB)");
        console.log("");
        console.log("When the next cross-chain deposit arrives:");
        console.log("- Actual gsUSDT ERC20 tokens will be minted");
        console.log("- Total supply will increase");
        console.log("- User will have both internal balance AND ERC20 tokens");
        
        console.log("========== UPGRADE AND CONFIGURATION COMPLETE ==========");
    }
}