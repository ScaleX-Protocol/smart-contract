// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract ManualDeposit is Script {
    
    function run() public {
        console.log("========== MANUAL DEPOSIT TO NEW SYNTHETIC TOKENS ==========");
        console.log("Execute these commands manually with your wallet:");
        console.log("");
        
        if (block.chainid != 4661) {
            console.log("ERROR: This script is for Appchain Testnet only");
            return;
        }
        
        // Read deployment data
        string memory appchainData = vm.readFile("deployments/appchain.json");
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address chainBalanceManager = vm.parseJsonAddress(appchainData, ".contracts.ChainBalanceManager");
        address sourceUSDT = vm.parseJsonAddress(appchainData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(appchainData, ".contracts.WBTC");
        address sourceWETH = vm.parseJsonAddress(appchainData, ".contracts.WETH");
        
        // NEW synthetic tokens on Rari (clean names, correct decimals)
        address gsUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");
        address gsWBTC = vm.parseJsonAddress(rariData, ".contracts.gsWBTC");
        address gsWETH = vm.parseJsonAddress(rariData, ".contracts.gsWETH");
        
        address testRecipient = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
        
        console.log("=== ADDRESSES ===");
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Test recipient:", testRecipient);
        console.log("");
        console.log("Source tokens (Appchain):");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        console.log("Target synthetic tokens (Rari):");
        console.log("gUSDT (6 decimals):", gsUSDT);
        console.log("gWBTC (8 decimals):", gsWBTC);
        console.log("gWETH (18 decimals):", gsWETH);
        console.log("");
        
        // Verify current mappings
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        console.log("=== VERIFY TOKEN MAPPINGS ===");
        address usdtMapping = cbm.getTokenMapping(sourceUSDT);
        address wbtcMapping = cbm.getTokenMapping(sourceWBTC);
        address wethMapping = cbm.getTokenMapping(sourceWETH);
        
        console.log("USDT ->", usdtMapping, usdtMapping == gsUSDT ? "(CORRECT)" : "(WRONG)");
        console.log("WBTC ->", wbtcMapping, wbtcMapping == gsWBTC ? "(CORRECT)" : "(WRONG)");
        console.log("WETH ->", wethMapping, wethMapping == gsWETH ? "(CORRECT)" : "(WRONG)");
        console.log("");
        
        if (usdtMapping == gsUSDT && wbtcMapping == gsWBTC && wethMapping == gsWETH) {
            console.log("SUCCESS: All mappings point to NEW synthetic tokens with correct decimals!");
        } else {
            console.log("ERROR: Some mappings are still incorrect");
        }
        
        console.log("");
        console.log("=== MANUAL DEPOSIT COMMANDS ===");
        console.log("Run these cast commands with your wallet:");
        console.log("");
        
        // USDT deposit (10 USDT = 10 * 10^6)
        console.log("# 1. Approve USDT");
        console.log("cast send", sourceUSDT, "\\");
        console.log("  'approve(address,uint256)'", chainBalanceManager, "10000000", "\\");
        console.log("  --rpc-url https://appchain.caff.testnet.espresso.network", "\\");
        console.log("  --private-key $PRIVATE_KEY");
        console.log("");
        
        console.log("# 2. Deposit USDT (10 USDT)");
        console.log("cast send", chainBalanceManager, "\\");
        console.log("  'deposit(address,uint256,address)'", sourceUSDT, "10000000", "\\");
        console.log("  ", testRecipient, "\\");
        console.log("  --rpc-url https://appchain.caff.testnet.espresso.network", "\\");
        console.log("  --private-key $PRIVATE_KEY");
        console.log("");
        
        // WBTC deposit (0.01 WBTC = 1 * 10^6)
        console.log("# 3. Approve WBTC");
        console.log("cast send", sourceWBTC, "\\");
        console.log("  'approve(address,uint256)'", chainBalanceManager, "1000000", "\\");
        console.log("  --rpc-url https://appchain.caff.testnet.espresso.network", "\\");
        console.log("  --private-key $PRIVATE_KEY");
        console.log("");
        
        console.log("# 4. Deposit WBTC (0.01 WBTC)");
        console.log("cast send", chainBalanceManager, "\\");
        console.log("  'deposit(address,uint256,address)'", sourceWBTC, "1000000", "\\");
        console.log("  ", testRecipient, "\\");
        console.log("  --rpc-url https://appchain.caff.testnet.espresso.network", "\\");
        console.log("  --private-key $PRIVATE_KEY");
        console.log("");
        
        // WETH deposit (0.01 WETH = 1 * 10^16)
        console.log("# 5. Approve WETH");
        console.log("cast send", sourceWETH, "\\");
        console.log("  'approve(address,uint256)'", chainBalanceManager, "10000000000000000", "\\");
        console.log("  --rpc-url https://appchain.caff.testnet.espresso.network", "\\");
        console.log("  --private-key $PRIVATE_KEY");
        console.log("");
        
        console.log("# 6. Deposit WETH (0.01 WETH)");
        console.log("cast send", chainBalanceManager, "\\");
        console.log("  'deposit(address,uint256,address)'", sourceWETH, "10000000000000000", "\\");
        console.log("  ", testRecipient, "\\");
        console.log("  --rpc-url https://appchain.caff.testnet.espresso.network", "\\");
        console.log("  --private-key $PRIVATE_KEY");
        console.log("");
        
        console.log("=== WHAT WILL HAPPEN ===");
        console.log("+ Deposits will go to NEW synthetic tokens with CORRECT decimals");
        console.log("+ USDT -> gUSDT (6 decimals)");
        console.log("+ WBTC -> gWBTC (8 decimals)");
        console.log("+ WETH -> gWETH (18 decimals)");
        console.log("+ Each deposit will generate a messageId for Hyperlane tracking");
        console.log("+ Look for 'MessageDispatched' events in transaction logs");
        console.log("");
        
        console.log("=== TRACKING DEPOSITS ===");
        console.log("After each deposit:");
        console.log("1. Note the transaction hash");
        console.log("2. Look for 'MessageDispatched' event in the logs");
        console.log("3. Copy the messageId from the event");
        console.log("4. Track at: https://hyperlane-explorer.gtxdex.xyz/message/{messageId}");
        
        console.log("========== READY FOR MANUAL DEPOSITS ==========");
    }
}