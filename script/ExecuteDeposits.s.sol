// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract ExecuteDeposits is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== EXECUTE REAL DEPOSITS ==========");
        console.log("Executing cross-chain deposits to NEW synthetic tokens");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
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
        
        console.log("");
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Test recipient:", testRecipient);
        console.log("");
        console.log("Source tokens (Appchain):");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        console.log("Target synthetic tokens (Rari - NEW):");
        console.log("gUSDT (6 decimals):", gsUSDT);
        console.log("gWBTC (8 decimals):", gsWBTC);
        console.log("gWETH (18 decimals):", gsWETH);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        // Verify mappings before depositing
        console.log("=== VERIFY TOKEN MAPPINGS ===");
        address usdtMapping = cbm.getTokenMapping(sourceUSDT);
        address wbtcMapping = cbm.getTokenMapping(sourceWBTC);
        address wethMapping = cbm.getTokenMapping(sourceWETH);
        
        console.log("USDT ->", usdtMapping, usdtMapping == gsUSDT ? "(CORRECT)" : "(WRONG)");
        console.log("WBTC ->", wbtcMapping, wbtcMapping == gsWBTC ? "(CORRECT)" : "(WRONG)");
        console.log("WETH ->", wethMapping, wethMapping == gsWETH ? "(CORRECT)" : "(WRONG)");
        console.log("");
        
        if (!(usdtMapping == gsUSDT && wbtcMapping == gsWBTC && wethMapping == gsWETH)) {
            console.log("ERROR: Token mappings are incorrect!");
            vm.stopBroadcast();
            return;
        }
        
        // Check balances
        console.log("=== CHECK BALANCES ===");
        (bool success1, bytes memory data1) = sourceUSDT.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
        (bool success2, bytes memory data2) = sourceWBTC.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
        (bool success3, bytes memory data3) = sourceWETH.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
        
        uint256 usdtBalance = success1 ? abi.decode(data1, (uint256)) : 0;
        uint256 wbtcBalance = success2 ? abi.decode(data2, (uint256)) : 0;
        uint256 wethBalance = success3 ? abi.decode(data3, (uint256)) : 0;
        
        console.log("Deployer balances:");
        console.log("USDT:", usdtBalance, "(6 decimals)");
        console.log("WBTC:", wbtcBalance, "(8 decimals)");
        console.log("WETH:", wethBalance, "(18 decimals)");
        console.log("");
        
        // Deposit amounts
        uint256 usdtAmount = 10 * 10**6;    // 10 USDT (6 decimals)
        uint256 wbtcAmount = 1 * 10**6;     // 0.01 WBTC (8 decimals)  
        uint256 wethAmount = 1 * 10**16;    // 0.01 WETH (18 decimals)
        
        console.log("=== EXECUTE DEPOSITS ===");
        
        // USDT deposit
        if (usdtBalance >= usdtAmount) {
            console.log("1. Depositing USDT (10 USDT)...");
            
            // Approve
            (bool approveSuccess,) = sourceUSDT.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, usdtAmount));
            if (approveSuccess) {
                console.log("   USDT approval: SUCCESS");
            } else {
                console.log("   USDT approval: FAILED");
            }
            
            // Deposit
            try cbm.deposit(sourceUSDT, usdtAmount, testRecipient) {
                console.log("   USDT deposit: SUCCESS -> gUSDT (6 decimals)");
            } catch Error(string memory reason) {
                console.log("   USDT deposit: FAILED -", reason);
            }
        } else {
            console.log("1. SKIP USDT deposit (insufficient balance)");
        }
        
        console.log("");
        
        // WBTC deposit
        if (wbtcBalance >= wbtcAmount) {
            console.log("2. Depositing WBTC (0.01 WBTC)...");
            
            // Approve
            (bool approveSuccess,) = sourceWBTC.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, wbtcAmount));
            if (approveSuccess) {
                console.log("   WBTC approval: SUCCESS");
            } else {
                console.log("   WBTC approval: FAILED");
            }
            
            // Deposit
            try cbm.deposit(sourceWBTC, wbtcAmount, testRecipient) {
                console.log("   WBTC deposit: SUCCESS -> gWBTC (8 decimals)");
            } catch Error(string memory reason) {
                console.log("   WBTC deposit: FAILED -", reason);
            }
        } else {
            console.log("2. SKIP WBTC deposit (insufficient balance)");
        }
        
        console.log("");
        
        // WETH deposit
        if (wethBalance >= wethAmount) {
            console.log("3. Depositing WETH (0.01 WETH)...");
            
            // Approve
            (bool approveSuccess,) = sourceWETH.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, wethAmount));
            if (approveSuccess) {
                console.log("   WETH approval: SUCCESS");
            } else {
                console.log("   WETH approval: FAILED");
            }
            
            // Deposit
            try cbm.deposit(sourceWETH, wethAmount, testRecipient) {
                console.log("   WETH deposit: SUCCESS -> gWETH (18 decimals)");
            } catch Error(string memory reason) {
                console.log("   WETH deposit: FAILED -", reason);
            }
        } else {
            console.log("3. SKIP WETH deposit (insufficient balance)");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== DEPOSITS COMPLETE ===");
        console.log("Check transaction logs for MessageDispatched events");
        console.log("Copy messageIds and track at:");
        console.log("https://hyperlane-explorer.gtxdex.xyz/message/{messageId}");
        console.log("");
        console.log("Expected targets (NEW tokens with correct decimals):");
        console.log("- gUSDT (6 decimals):", gsUSDT);
        console.log("- gWBTC (8 decimals):", gsWBTC);
        console.log("- gWETH (18 decimals):", gsWETH);
        
        console.log("========== REAL DEPOSITS EXECUTED ==========");
    }
}