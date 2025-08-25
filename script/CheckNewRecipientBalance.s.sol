// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

interface IBalanceManager {
    function getBalance(address user, Currency currency) external view returns (uint256);
}

contract CheckNewRecipientBalance is Script {
    // Rari testnet addresses
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    address constant NEW_RECIPIENT = 0x84d437fFC072a2c9E7E16d688D46b4Dbc95dd5e2;
    
    // Synthetic token addresses
    address constant gUSDT = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d;
    address constant gWETH = 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8;
    address constant gWBTC = 0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748;

    function run() external view {
        IBalanceManager balanceManager = IBalanceManager(BALANCE_MANAGER);
        
        console.log("=== New Recipient Balance Check ===");
        console.log("BalanceManager:", BALANCE_MANAGER);
        console.log("New Recipient:", NEW_RECIPIENT);
        console.log("Chain ID:", block.chainid);
        console.log("");
        
        // Check gUSDT balance in BalanceManager
        console.log("=== gUSDT Balance ===");
        Currency gUSDTCurrency = Currency.wrap(gUSDT);
        uint256 usdtBalance = balanceManager.getBalance(NEW_RECIPIENT, gUSDTCurrency);
        console.log("BalanceManager Balance (raw):", usdtBalance);
        console.log("BalanceManager Balance (readable):", usdtBalance / 1e6, "USDT");
        console.log("");
        
        // Check gWETH balance in BalanceManager
        console.log("=== gWETH Balance ===");
        Currency gWETHCurrency = Currency.wrap(gWETH);
        uint256 wethBalance = balanceManager.getBalance(NEW_RECIPIENT, gWETHCurrency);
        console.log("BalanceManager Balance (raw):", wethBalance);
        console.log("BalanceManager Balance (readable):", wethBalance / 1e18, "WETH");
        console.log("");
        
        // Check gWBTC balance in BalanceManager
        console.log("=== gWBTC Balance ===");
        Currency gWBTCCurrency = Currency.wrap(gWBTC);
        uint256 wbtcBalance = balanceManager.getBalance(NEW_RECIPIENT, gWBTCCurrency);
        console.log("BalanceManager Balance (raw):", wbtcBalance);
        console.log("BalanceManager Balance (readable):", wbtcBalance / 1e8, "WBTC");
        console.log("");
        
        // Summary
        console.log("=== Summary ===");
        console.log("Expected: 100 USDT from latest Appchain deposit");
        
        if (usdtBalance >= 100 * 1e6) {
            console.log("SUCCESS: USDT deposit was relayed!");
        } else if (usdtBalance > 0) {
            console.log("PARTIAL: Some USDT received, might still be processing");
        } else {
            console.log("PENDING: No USDT balance yet - message may still be relaying");
        }
        
        console.log("");
        console.log("Message to track: 0xab82c80525105d6e4c81dcbc2184a16467c3a8fd6a4b2ae7a7780a043db3bb90");
        console.log("https://hyperlane-explorer.gtxdex.xyz/message/0xab82c80525105d6e4c81dcbc2184a16467c3a8fd6a4b2ae7a7780a043db3bb90");
    }
}