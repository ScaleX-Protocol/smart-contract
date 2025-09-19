// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

interface IBalanceManager {
    function getBalance(address user, Currency currency) external view returns (uint256);
    function getLockedBalance(address user, address operator, Currency currency) external view returns (uint256);
}

contract CheckBalanceManagerBalances is Script {
    // Rari testnet addresses
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    address constant RECIPIENT = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
    
    // Synthetic token addresses
    address constant gUSDT = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d;
    address constant gWETH = 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8;
    address constant gWBTC = 0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748;

    function run() external view {
        IBalanceManager balanceManager = IBalanceManager(BALANCE_MANAGER);
        
        console.log("=== BalanceManager Balance Check ===");
        console.log("BalanceManager:", BALANCE_MANAGER);
        console.log("Recipient:", RECIPIENT);
        console.log("Chain ID:", block.chainid);
        console.log("");
        
        // Check gUSDT balance in BalanceManager
        console.log("=== gUSDT Balance ===");
        console.log("Token Address:", gUSDT);
        Currency gUSDTCurrency = Currency.wrap(gUSDT);
        uint256 usdtBalance = balanceManager.getBalance(RECIPIENT, gUSDTCurrency);
        console.log("BalanceManager Balance (raw):", usdtBalance);
        console.log("BalanceManager Balance (readable):", usdtBalance / 1e6, "USDT");
        console.log("");
        
        // Check gWETH balance in BalanceManager
        console.log("=== gWETH Balance ===");
        console.log("Token Address:", gWETH);
        Currency gWETHCurrency = Currency.wrap(gWETH);
        uint256 wethBalance = balanceManager.getBalance(RECIPIENT, gWETHCurrency);
        console.log("BalanceManager Balance (raw):", wethBalance);
        console.log("BalanceManager Balance (readable):", wethBalance / 1e18, "WETH");
        console.log("");
        
        // Check gWBTC balance in BalanceManager
        console.log("=== gWBTC Balance ===");
        console.log("Token Address:", gWBTC);
        Currency gWBTCCurrency = Currency.wrap(gWBTC);
        uint256 wbtcBalance = balanceManager.getBalance(RECIPIENT, gWBTCCurrency);
        console.log("BalanceManager Balance (raw):", wbtcBalance);
        console.log("BalanceManager Balance (readable):", wbtcBalance / 1e8, "WBTC");
        console.log("");
        
        // Summary
        console.log("=== Summary ===");
        console.log("Expected from Appchain deposits:");
        console.log("- 200 USDT total (2 x 100 USDT deposits)");
        console.log("- 0 WETH");
        console.log("- 0 WBTC");
        console.log("");
        
        bool hasUsdtBalance = usdtBalance > 0;
        bool hasWethBalance = wethBalance > 0;
        bool hasWbtcBalance = wbtcBalance > 0;
        
        if (hasUsdtBalance) {
            console.log("SUCCESS: USDT deposits received!");
        } else {
            console.log("ISSUE: No USDT balance found");
        }
        
        if (hasWethBalance) {
            console.log("SUCCESS: WETH deposits received!");
        }
        
        if (hasWbtcBalance) {
            console.log("SUCCESS: WBTC deposits received!");
        }
        
        if (!hasUsdtBalance && !hasWethBalance && !hasWbtcBalance) {
            console.log("");
            console.log("No deposits found in BalanceManager.");
            console.log("This suggests:");
            console.log("1. Messages are not being relayed successfully");
            console.log("2. Message execution is failing on destination");
            console.log("3. TokenRegistry configuration issues");
        }
    }
}