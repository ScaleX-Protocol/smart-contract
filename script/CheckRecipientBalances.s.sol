// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract CheckRecipientBalances is Script {
    // Recipient address
    address constant RECIPIENT = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
    
    // Synthetic tokens on Rari
    address constant RARI_gUSDT = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d;
    address constant RARI_gWETH = 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8;
    address constant RARI_gWBTC = 0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748;

    function run() external view {
        console.log("=== Check Recipient Balances After Deposits ===");
        console.log("Recipient:", RECIPIENT);
        console.log("Checking synthetic token balances on Rari...");
        console.log("");
        
        // Check gUSDT balance
        IERC20 gUSDT = IERC20(RARI_gUSDT);
        uint256 usdtBalance = gUSDT.balanceOf(RECIPIENT);
        console.log("gUSDT Balance:", usdtBalance);
        console.log("gUSDT Address:", RARI_gUSDT);
        console.log("Expected from deposits: 200 USDT (Rise + Arbitrum = 200 * 1e6)");
        console.log("Actual balance readable:", usdtBalance / 1e6, "USDT");
        console.log("");
        
        // Check gWETH balance
        IERC20 gWETH = IERC20(RARI_gWETH);
        uint256 wethBalance = gWETH.balanceOf(RECIPIENT);
        console.log("gWETH Balance:", wethBalance);
        console.log("gWETH Address:", RARI_gWETH);
        console.log("Expected from deposits: 0.2 WETH (Rise + Arbitrum = 2 * 1e17)");
        console.log("Actual balance readable (WETH):", wethBalance / 1e18);
        console.log("");
        
        // Check gWBTC balance
        IERC20 gWBTC = IERC20(RARI_gWBTC);
        uint256 wbtcBalance = gWBTC.balanceOf(RECIPIENT);
        console.log("gWBTC Balance:", wbtcBalance);
        console.log("gWBTC Address:", RARI_gWBTC);
        console.log("Expected from deposits: 0.02 WBTC (Rise + Arbitrum = 2 * 1e6)");
        console.log("Actual balance readable (WBTC):", wbtcBalance / 1e6); // Show in 0.01 units
        console.log("");
        
        // Summary
        console.log("=== Relay Status Analysis ===");
        
        bool usdtReceived = usdtBalance >= 200 * 1e6; // Should have at least 200 USDT
        bool wethReceived = wethBalance >= 2 * 1e17;  // Should have at least 0.2 WETH  
        bool wbtcReceived = wbtcBalance >= 2 * 1e6;   // Should have at least 0.02 WBTC
        
        console.log("USDT deposits relayed:", usdtReceived ? "YES" : "NO");
        console.log("WETH deposits relayed:", wethReceived ? "YES" : "NO");
        console.log("WBTC deposits relayed:", wbtcReceived ? "YES" : "NO");
        console.log("");
        
        if (usdtReceived && wethReceived && wbtcReceived) {
            console.log("SUCCESS: All deposits from Rise and Arbitrum relayed successfully!");
            console.log("The TokenRegistry fix is working perfectly!");
        } else {
            console.log("PARTIAL SUCCESS: Some deposits may still be relaying or failed");
            console.log("Check Hyperlane explorer for message status:");
            console.log("https://hyperlane-explorer.gtxdex.xyz/");
        }
        
        console.log("");
        console.log("=== Token Details ===");
        console.log("Each chain deposited:");
        console.log("- 100 USDT (100,000,000 units with 6 decimals)");
        console.log("- 0.1 WETH (100,000,000,000,000,000 units with 18 decimals)");  
        console.log("- 0.01 WBTC (1,000,000 units with 8 decimals)");
        console.log("");
        console.log("Total expected if both chains relayed:");
        console.log("- 200 USDT from Rise + Arbitrum");
        console.log("- 0.2 WETH from Rise + Arbitrum");
        console.log("- 0.02 WBTC from Rise + Arbitrum");
    }
}