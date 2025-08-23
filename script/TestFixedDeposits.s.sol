// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract TestFixedDeposits is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== TEST FIXED DEPOSITS ==========");
        console.log("Test small deposits with FIXED destination address");
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
        address correctBalanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        
        // NEW synthetic tokens on Rari (clean names, correct decimals)
        address gsUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");
        
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Test recipient:", testRecipient);
        console.log("USDT:", sourceUSDT);
        console.log("Target gUSDT:", gsUSDT);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        // Verify fixed configuration
        console.log("=== VERIFY FIXED CONFIG ===");
        
        try cbm.getCrossChainConfig() returns (uint32 destDomain, address destBalanceManager) {
            console.log("Destination domain:", destDomain);
            console.log("Destination BalanceManager:", destBalanceManager);
            console.log("Expected BalanceManager:", correctBalanceManager);
            
            if (destBalanceManager == correctBalanceManager) {
                console.log("CONFIG: CORRECT - pointing to fixed BalanceManager");
            } else {
                console.log("CONFIG: STILL WRONG - not fixed yet!");
                vm.stopBroadcast();
                return;
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not get config -", reason);
            vm.stopBroadcast();
            return;
        }
        
        // Verify token mapping
        address usdtMapping = cbm.getTokenMapping(sourceUSDT);
        console.log("USDT mapping:", usdtMapping);
        console.log("Expected:", gsUSDT);
        console.log("Token mapping:", usdtMapping == gsUSDT ? "CORRECT" : "WRONG");
        console.log("");
        
        // Test small deposit to verify fix
        console.log("=== TEST SMALL DEPOSIT WITH FIXED CONFIG ===");
        
        uint256 testAmount = 100 * 10**6; // 100 USDT (6 decimals)
        
        // Check balance
        (bool success, bytes memory data) = sourceUSDT.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
        uint256 balance = success ? abi.decode(data, (uint256)) : 0;
        
        console.log("Current USDT balance:", balance);
        console.log("Test amount (100 USDT):", testAmount);
        
        if (balance >= testAmount) {
            console.log("Executing test deposit...");
            
            // Approve
            (bool approveSuccess,) = sourceUSDT.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, testAmount));
            if (approveSuccess) {
                console.log("  Approval: SUCCESS");
            } else {
                console.log("  Approval: FAILED");
                vm.stopBroadcast();
                return;
            }
            
            // Deposit
            try cbm.deposit(sourceUSDT, testAmount, testRecipient) {
                console.log("  Deposit: SUCCESS");
                console.log("  Amount: 100 USDT");
                console.log("  This should now relay successfully!");
            } catch Error(string memory reason) {
                console.log("  Deposit: FAILED -", reason);
            }
        } else {
            console.log("SKIP: Insufficient balance for test deposit");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== TEST RESULT ===");
        console.log("Network:", networkName);
        console.log("Destination: FIXED to correct BalanceManager");
        console.log("Token mapping: NEW gUSDT with 6 decimals");
        console.log("Expected: This deposit should relay and process successfully");
        console.log("");
        console.log("Check transaction logs for new MessageDispatched event");
        console.log("New messageId should process without relay failures");
        
        console.log("========== FIXED DEPOSIT TEST COMPLETE ==========");
    }
}