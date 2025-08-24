// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";

contract CheckDestinationBalances is Script {
    
    function run() public {
        console.log("========== CHECK DESTINATION BALANCES ==========");
        console.log("Check if deposits from Arbitrum + Rise have been received");
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari (1918988905) only");
            return;
        }
        
        // Read deployment data
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address balanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        address recipient = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
        
        // NEW synthetic tokens with correct decimals
        address gsUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");
        address gsWBTC = vm.parseJsonAddress(rariData, ".contracts.gsWBTC");
        address gsWETH = vm.parseJsonAddress(rariData, ".contracts.gsWETH");
        
        console.log("");
        console.log("BalanceManager:", balanceManager);
        console.log("Recipient:", recipient);
        console.log("");
        console.log("Synthetic tokens (NEW - correct decimals):");
        console.log("gsUSDT (6 decimals):", gsUSDT);
        console.log("gsWBTC (8 decimals):", gsWBTC);
        console.log("gsWETH (18 decimals):", gsWETH);
        console.log("");
        
        BalanceManager bm = BalanceManager(balanceManager);
        
        console.log("=== CHECK SYNTHETIC TOKEN BALANCES (CUSTODIAL) ===");
        
        // Check synthetic token balances (should be held by BalanceManager)
        (bool success1, bytes memory data1) = gsUSDT.staticcall(abi.encodeWithSignature("balanceOf(address)", balanceManager));
        uint256 gsUSDTBalance = success1 ? abi.decode(data1, (uint256)) : 0;
        
        (bool success2, bytes memory data2) = gsWBTC.staticcall(abi.encodeWithSignature("balanceOf(address)", balanceManager));
        uint256 gsWBTCBalance = success2 ? abi.decode(data2, (uint256)) : 0;
        
        (bool success3, bytes memory data3) = gsWETH.staticcall(abi.encodeWithSignature("balanceOf(address)", balanceManager));
        uint256 gsWETHBalance = success3 ? abi.decode(data3, (uint256)) : 0;
        
        console.log("BalanceManager synthetic token holdings:");
        console.log("gsUSDT balance:", gsUSDTBalance, "(should show deposited amounts)");
        console.log("gsWBTC balance:", gsWBTCBalance, "(should show deposited amounts)");
        console.log("gsWETH balance:", gsWETHBalance, "(should show deposited amounts)");
        console.log("");
        
        console.log("=== CHECK USER INTERNAL BALANCES ===");
        
        // Check user internal balances in BalanceManager
        try bm.getBalance(recipient, Currency.wrap(gsUSDT)) returns (uint256 userUSDT) {
            console.log("User gsUSDT balance:", userUSDT);
        } catch {
            console.log("User gsUSDT balance: FAILED TO READ");
        }
        
        try bm.getBalance(recipient, Currency.wrap(gsWBTC)) returns (uint256 userWBTC) {
            console.log("User gsWBTC balance:", userWBTC);
        } catch {
            console.log("User gsWBTC balance: FAILED TO READ");
        }
        
        try bm.getBalance(recipient, Currency.wrap(gsWETH)) returns (uint256 userWETH) {
            console.log("User gsWETH balance:", userWETH);
        } catch {
            console.log("User gsWETH balance: FAILED TO READ");
        }
        
        console.log("");
        console.log("=== EXPECTED AMOUNTS ===");
        console.log("From previous deposits + new large deposits:");
        console.log("- gsUSDT: ~200,010 USDT (6 decimals) = ~200010000000");
        console.log("- gsWBTC: ~2.01 WBTC (8 decimals) = ~201000000");
        console.log("- gsWETH: ~20.01 WETH (18 decimals) = ~20010000000000000000");
        console.log("");
        console.log("If balances match expected, deposits are working!");
        
        console.log("========== BALANCE CHECK COMPLETE ==========");
    }
}