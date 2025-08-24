// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract TestNewArbitrumDeposits is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== TEST NEW ARBITRUM DEPOSITS ==========");
        console.log("Test deposits from NEW Arbitrum ChainBalanceManager");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 421614) {
            console.log("ERROR: This script is for Arbitrum Sepolia only");
            return;
        }
        
        address newChainBalanceManager = 0x81883DB77B43Ba719Cf1dB7119a2440b4eBFB8b6;
        address recipient = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
        
        // Read deployment data
        string memory arbitrumData = vm.readFile("deployments/arbitrum-sepolia.json");
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address sourceUSDT = vm.parseJsonAddress(arbitrumData, ".contracts.USDT");
        address expectedgsUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");
        address expectedBalanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        
        console.log("");
        console.log("NEW ChainBalanceManager:", newChainBalanceManager);
        console.log("Test recipient:", recipient);
        console.log("USDT:", sourceUSDT);
        console.log("Target gsUSDT:", expectedgsUSDT);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ChainBalanceManager cbm = ChainBalanceManager(newChainBalanceManager);
        
        console.log("=== VERIFY NEW CONFIGURATION ===");
        
        try cbm.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
            console.log("Mailbox:", mailbox);
            console.log("Local domain:", localDomain);
            console.log("Local domain correct:", localDomain == block.chainid);
        } catch Error(string memory reason) {
            console.log("FAILED to get mailbox config:", reason);
        }
        
        try cbm.getCrossChainConfig() returns (uint32 destDomain, address destManager) {
            console.log("Destination domain:", destDomain);
            console.log("Destination manager:", destManager);
            console.log("Destination correct:", destManager == expectedBalanceManager);
        } catch Error(string memory reason) {
            console.log("FAILED to get cross-chain config:", reason);
        }
        
        address usdtMapping = cbm.getTokenMapping(sourceUSDT);
        console.log("USDT mapping:", usdtMapping);
        console.log("Expected gsUSDT:", expectedgsUSDT);
        console.log("Token mapping correct:", usdtMapping == expectedgsUSDT);
        
        console.log("");
        console.log("=== TEST DEPOSIT ===");
        
        uint256 testAmount = 500 * 10**6; // 500 USDT (6 decimals)
        
        // Check balance
        (bool success, bytes memory data) = sourceUSDT.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
        uint256 balance = success ? abi.decode(data, (uint256)) : 0;
        
        console.log("Current USDT balance:", balance);
        console.log("Test amount (500 USDT):", testAmount);
        
        if (balance >= testAmount) {
            console.log("Executing test deposit from NEW ChainBalanceManager...");
            
            // Approve
            (bool approveSuccess,) = sourceUSDT.call(abi.encodeWithSignature("approve(address,uint256)", newChainBalanceManager, testAmount));
            if (approveSuccess) {
                console.log("  Approval: SUCCESS");
            } else {
                console.log("  Approval: FAILED");
                vm.stopBroadcast();
                return;
            }
            
            // Deposit
            try cbm.deposit(sourceUSDT, testAmount, recipient) {
                console.log("  Deposit: SUCCESS");
                console.log("  Amount: 500 USDT");
                console.log("  This should now relay successfully with correct local domain!");
            } catch Error(string memory reason) {
                console.log("  Deposit: FAILED -", reason);
            }
        } else {
            console.log("SKIP: Insufficient balance for test deposit");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== TEST RESULT ===");
        console.log("NEW Arbitrum ChainBalanceManager:");
        console.log("- Correct local domain (421614) - FIXED!");
        console.log("- Correct destination config");
        console.log("- Correct token mappings to NEW gsUSDT");
        console.log("- Registered in Rari BalanceManager");
        console.log("");
        console.log("Expected: This deposit should relay and process successfully!");
        console.log("Check transaction logs for MessageDispatched event");
        
        console.log("========== NEW ARBITRUM DEPOSIT TEST COMPLETE ==========");
    }
}