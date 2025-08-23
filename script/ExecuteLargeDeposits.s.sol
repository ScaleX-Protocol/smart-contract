// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract ExecuteLargeDeposits is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== EXECUTE LARGE DEPOSITS ==========");
        console.log("100,000 USDT + 1 WBTC + 10 WETH to NEW synthetic tokens");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        address testRecipient = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
        
        // Determine deployment file based on chain
        string memory deploymentFile;
        string memory networkName;
        
        if (block.chainid == 421614) {
            deploymentFile = "deployments/arbitrum-sepolia.json";
            networkName = "ARBITRUM SEPOLIA";
        } else if (block.chainid == 11155931) {
            deploymentFile = "deployments/rise-sepolia.json";
            networkName = "RISE SEPOLIA";
        } else {
            console.log("ERROR: This script is for Arbitrum Sepolia (421614) or Rise Sepolia (11155931) only");
            return;
        }
        
        console.log("Target network:", networkName);
        console.log("");
        
        // Read deployment data
        string memory chainData = vm.readFile(deploymentFile);
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address chainBalanceManager = vm.parseJsonAddress(chainData, ".contracts.ChainBalanceManager");
        address sourceUSDT = vm.parseJsonAddress(chainData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(chainData, ".contracts.WBTC");
        address sourceWETH = vm.parseJsonAddress(chainData, ".contracts.WETH");
        
        // NEW synthetic tokens on Rari (clean names, correct decimals)
        address gsUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");
        address gsWBTC = vm.parseJsonAddress(rariData, ".contracts.gsWBTC");
        address gsWETH = vm.parseJsonAddress(rariData, ".contracts.gsWETH");
        
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Test recipient:", testRecipient);
        console.log("");
        console.log("Source tokens:");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        console.log("Target synthetic tokens (NEW - correct decimals):");
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
        
        // Large deposit amounts as requested
        uint256 usdtAmount = 100000 * 10**6;    // 100,000 USDT (6 decimals)
        uint256 wbtcAmount = 1 * 10**8;         // 1 WBTC (8 decimals)  
        uint256 wethAmount = 10 * 10**18;       // 10 WETH (18 decimals)
        
        console.log("=== LARGE DEPOSIT AMOUNTS ===");
        console.log("USDT: 100,000 USDT (", usdtAmount, ")");
        console.log("WBTC: 1 WBTC (", wbtcAmount, ")");
        console.log("WETH: 10 WETH (", wethAmount, ")");
        console.log("");
        
        // Mint tokens if needed
        console.log("=== MINT TOKENS IF NEEDED ===");
        
        // Mint USDT if balance insufficient
        if (usdtBalance < usdtAmount) {
            console.log("Minting USDT for large deposit...");
            (bool mintSuccess,) = sourceUSDT.call(abi.encodeWithSignature("mint(address,uint256)", deployer, usdtAmount));
            if (mintSuccess) {
                console.log("USDT minted successfully");
                (bool success, bytes memory data) = sourceUSDT.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
                usdtBalance = success ? abi.decode(data, (uint256)) : 0;
                console.log("New USDT balance:", usdtBalance);
            } else {
                console.log("USDT minting failed - might not have mint function");
            }
        }
        
        // Mint WBTC if balance insufficient
        if (wbtcBalance < wbtcAmount) {
            console.log("Minting WBTC for large deposit...");
            (bool mintSuccess,) = sourceWBTC.call(abi.encodeWithSignature("mint(address,uint256)", deployer, wbtcAmount));
            if (mintSuccess) {
                console.log("WBTC minted successfully");
                (bool success, bytes memory data) = sourceWBTC.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
                wbtcBalance = success ? abi.decode(data, (uint256)) : 0;
                console.log("New WBTC balance:", wbtcBalance);
            } else {
                console.log("WBTC minting failed - might not have mint function");
            }
        }
        
        // Mint WETH if balance insufficient
        if (wethBalance < wethAmount) {
            console.log("Minting WETH for large deposit...");
            (bool mintSuccess,) = sourceWETH.call(abi.encodeWithSignature("mint(address,uint256)", deployer, wethAmount));
            if (mintSuccess) {
                console.log("WETH minted successfully");
                (bool success, bytes memory data) = sourceWETH.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
                wethBalance = success ? abi.decode(data, (uint256)) : 0;
                console.log("New WETH balance:", wethBalance);
            } else {
                console.log("WETH minting failed - might not have mint function");
            }
        }
        
        console.log("");
        console.log("=== EXECUTE LARGE DEPOSITS ===");
        
        // USDT deposit - 100,000 USDT
        if (usdtBalance >= usdtAmount) {
            console.log("1. Depositing 100,000 USDT...");
            
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
                console.log("   Amount: 100,000 USDT");
            } catch Error(string memory reason) {
                console.log("   USDT deposit: FAILED -", reason);
            }
        } else {
            console.log("1. SKIP USDT deposit (insufficient balance)");
        }
        
        console.log("");
        
        // WBTC deposit - 1 WBTC
        if (wbtcBalance >= wbtcAmount) {
            console.log("2. Depositing 1 WBTC...");
            
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
                console.log("   Amount: 1 WBTC");
            } catch Error(string memory reason) {
                console.log("   WBTC deposit: FAILED -", reason);
            }
        } else {
            console.log("2. SKIP WBTC deposit (insufficient balance)");
        }
        
        console.log("");
        
        // WETH deposit - 10 WETH
        if (wethBalance >= wethAmount) {
            console.log("3. Depositing 10 WETH...");
            
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
                console.log("   Amount: 10 WETH");
            } catch Error(string memory reason) {
                console.log("   WETH deposit: FAILED -", reason);
            }
        } else {
            console.log("3. SKIP WETH deposit (insufficient balance)");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== LARGE DEPOSITS COMPLETE ===");
        console.log("Chain:", networkName);
        console.log("Recipient:", testRecipient);
        console.log("Check transaction logs for MessageDispatched events");
        console.log("Copy messageIds and track at:");
        console.log("https://hyperlane-explorer.gtxdex.xyz/message/{messageId}");
        console.log("");
        console.log("Expected targets (NEW tokens with correct decimals):");
        console.log("- gUSDT (6 decimals):", gsUSDT);
        console.log("- gWBTC (8 decimals):", gsWBTC);
        console.log("- gWETH (18 decimals):", gsWETH);
        
        console.log("========== LARGE DEPOSITS EXECUTED ==========");
    }
}