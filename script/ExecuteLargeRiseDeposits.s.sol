// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract ExecuteLargeRiseDeposits is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== EXECUTE LARGE RISE DEPOSITS ==========");
        console.log("Large deposits from Rise to specific recipient");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 11155931) {
            console.log("ERROR: This script is for Rise Sepolia only");
            return;
        }
        
        // Target recipient address
        address recipient = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
        
        // Read deployment data
        string memory riseData = vm.readFile("deployments/rise-sepolia.json");
        
        address chainBalanceManager = vm.parseJsonAddress(riseData, ".contracts.ChainBalanceManager");
        address sourceUSDT = vm.parseJsonAddress(riseData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(riseData, ".contracts.WBTC");
        address sourceWETH = vm.parseJsonAddress(riseData, ".contracts.WETH");
        
        console.log("");
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Target recipient:", recipient);
        console.log("");
        console.log("Source tokens:");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        
        // Large deposit amounts
        uint256 usdtAmount = 50000 * 10**6; // 50,000 USDT (6 decimals)
        uint256 wbtcAmount = 50000000; // 0.5 WBTC (8 decimals)  
        uint256 wethAmount = 5 * 10**18; // 5 WETH (18 decimals)
        
        console.log("=== LARGE DEPOSIT AMOUNTS ===");
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
        
        console.log("=== EXECUTE LARGE DEPOSITS ===");
        console.log("Recipient:", recipient);
        
        // 1. USDT deposit
        if (usdtBalance >= usdtAmount) {
            (bool approveSuccess,) = sourceUSDT.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, usdtAmount));
            if (approveSuccess) {
                try cbm.deposit(sourceUSDT, usdtAmount, recipient) {
                    console.log("USDT deposit SUCCESS: 50,000 USDT");
                } catch Error(string memory reason) {
                    console.log("USDT deposit FAILED:", reason);
                }
            } else {
                console.log("USDT approval FAILED");
            }
        } else {
            console.log("INSUFFICIENT USDT balance");
        }
        
        // 2. WBTC deposit
        if (wbtcBalance >= wbtcAmount) {
            (bool approveSuccess,) = sourceWBTC.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, wbtcAmount));
            if (approveSuccess) {
                try cbm.deposit(sourceWBTC, wbtcAmount, recipient) {
                    console.log("WBTC deposit SUCCESS: 0.5 WBTC");
                } catch Error(string memory reason) {
                    console.log("WBTC deposit FAILED:", reason);
                }
            } else {
                console.log("WBTC approval FAILED");
            }
        } else {
            console.log("INSUFFICIENT WBTC balance");
        }
        
        // 3. WETH deposit
        if (wethBalance >= wethAmount) {
            (bool approveSuccess,) = sourceWETH.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, wethAmount));
            if (approveSuccess) {
                try cbm.deposit(sourceWETH, wethAmount, recipient) {
                    console.log("WETH deposit SUCCESS: 5 WETH");
                } catch Error(string memory reason) {
                    console.log("WETH deposit FAILED:", reason);
                }
            } else {
                console.log("WETH approval FAILED");
            }
        } else {
            console.log("INSUFFICIENT WETH balance");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== LARGE RISE DEPOSITS COMPLETE ===");
        console.log("Recipient:", recipient);
        console.log("Total deposited: 50,000 USDT + 0.5 WBTC + 5 WETH");
        console.log("These should arrive on Rari since Rise route is now working");
        console.log("========== LARGE RISE DEPOSITS EXECUTED ==========");
    }
}