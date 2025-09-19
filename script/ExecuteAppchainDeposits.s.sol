// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract ExecuteAppchainDeposits is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== EXECUTE APPCHAIN DEPOSITS ==========");
        console.log("Large deposits to two test addresses");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 4661) {
            console.log("ERROR: This script is for Appchain only");
            return;
        }
        
        // Test recipient addresses
        address recipient1 = 0xdB60b053f540DBFEcCb842D16E174A97E96994fd;
        address recipient2 = 0xfc588D16f75f77C0686B662Bda993b7F1730209C;
        
        // Read deployment data
        string memory appchainData = vm.readFile("deployments/appchain.json");
        
        address chainBalanceManager = vm.parseJsonAddress(appchainData, ".contracts.ChainBalanceManager");
        address sourceUSDT = vm.parseJsonAddress(appchainData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(appchainData, ".contracts.WBTC");
        address sourceWETH = vm.parseJsonAddress(appchainData, ".contracts.WETH");
        
        console.log("");
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Recipients:");
        console.log("  1:", recipient1);
        console.log("  2:", recipient2);
        console.log("");
        console.log("Source tokens:");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        
        // Deposit amounts
        uint256 usdtAmount = 50000 * 10**6; // 50,000 USDT (6 decimals)
        uint256 wbtcAmount = 5 * 10**7; // 0.5 WBTC (8 decimals)  
        uint256 wethAmount = 5 * 10**18; // 5 WETH (18 decimals)
        
        console.log("=== DEPOSIT AMOUNTS ===");
        console.log("USDT: 50,000 USDT (", usdtAmount, ")");
        console.log("WBTC: 0.5 WBTC (", wbtcAmount, ")");
        console.log("WETH: 5 WETH (", wethAmount, ")");
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        // Check balances
        (bool success1, bytes memory data1) = sourceUSDT.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
        uint256 usdtBalance = success1 ? abi.decode(data1, (uint256)) : 0;
        
        (bool success2, bytes memory data2) = sourceWBTC.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
        uint256 wbtcBalance = success2 ? abi.decode(data2, (uint256)) : 0;
        
        (bool success3, bytes memory data3) = sourceWETH.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
        uint256 wethBalance = success3 ? abi.decode(data3, (uint256)) : 0;
        
        console.log("Current balances:");
        console.log("USDT:", usdtBalance);
        console.log("WBTC:", wbtcBalance);
        console.log("WETH:", wethBalance);
        console.log("");
        
        console.log("=== DEPOSITS TO RECIPIENT 1 ===");
        console.log("Recipient:", recipient1);
        
        // Deposit to recipient 1
        if (usdtBalance >= usdtAmount) {
            (bool approveSuccess,) = sourceUSDT.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, usdtAmount));
            if (approveSuccess) {
                try cbm.deposit(sourceUSDT, usdtAmount, recipient1) {
                    console.log("USDT deposit SUCCESS: 50,000 USDT");
                } catch Error(string memory reason) {
                    console.log("USDT deposit FAILED:", reason);
                }
            }
        }
        
        if (wbtcBalance >= wbtcAmount) {
            (bool approveSuccess,) = sourceWBTC.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, wbtcAmount));
            if (approveSuccess) {
                try cbm.deposit(sourceWBTC, wbtcAmount, recipient1) {
                    console.log("WBTC deposit SUCCESS: 0.5 WBTC");
                } catch Error(string memory reason) {
                    console.log("WBTC deposit FAILED:", reason);
                }
            }
        }
        
        if (wethBalance >= wethAmount) {
            (bool approveSuccess,) = sourceWETH.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, wethAmount));
            if (approveSuccess) {
                try cbm.deposit(sourceWETH, wethAmount, recipient1) {
                    console.log("WETH deposit SUCCESS: 5 WETH");
                } catch Error(string memory reason) {
                    console.log("WETH deposit FAILED:", reason);
                }
            }
        }
        
        console.log("");
        console.log("=== DEPOSITS TO RECIPIENT 2 ===");
        console.log("Recipient:", recipient2);
        
        // Deposit to recipient 2
        if (usdtBalance >= (usdtAmount * 2)) {
            (bool approveSuccess,) = sourceUSDT.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, usdtAmount));
            if (approveSuccess) {
                try cbm.deposit(sourceUSDT, usdtAmount, recipient2) {
                    console.log("USDT deposit SUCCESS: 50,000 USDT");
                } catch Error(string memory reason) {
                    console.log("USDT deposit FAILED:", reason);
                }
            }
        }
        
        if (wbtcBalance >= (wbtcAmount * 2)) {
            (bool approveSuccess,) = sourceWBTC.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, wbtcAmount));
            if (approveSuccess) {
                try cbm.deposit(sourceWBTC, wbtcAmount, recipient2) {
                    console.log("WBTC deposit SUCCESS: 0.5 WBTC");
                } catch Error(string memory reason) {
                    console.log("WBTC deposit FAILED:", reason);
                }
            }
        }
        
        if (wethBalance >= (wethAmount * 2)) {
            (bool approveSuccess,) = sourceWETH.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, wethAmount));
            if (approveSuccess) {
                try cbm.deposit(sourceWETH, wethAmount, recipient2) {
                    console.log("WETH deposit SUCCESS: 5 WETH");
                } catch Error(string memory reason) {
                    console.log("WETH deposit FAILED:", reason);
                }
            }
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== APPCHAIN DEPOSITS COMPLETE ===");
        console.log("Total deposited:");
        console.log("- To recipient 1: 50k USDT + 0.5 WBTC + 5 WETH");
        console.log("- To recipient 2: 50k USDT + 0.5 WBTC + 5 WETH"); 
        console.log("These should arrive on Rari since Appchain works");
        console.log("========== APPCHAIN DEPOSITS EXECUTED ==========");
    }
}