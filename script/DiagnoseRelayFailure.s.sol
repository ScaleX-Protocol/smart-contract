// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";

contract DiagnoseRelayFailure is Script {
    
    function run() public {
        console.log("========== DIAGNOSE RELAY FAILURE ==========");
        console.log("Check why Arbitrum -> Rari messages are failing to relay");
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory rariData = vm.readFile("deployments/rari.json");
        string memory arbitrumData = vm.readFile("deployments/arbitrum-sepolia.json");
        
        address balanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        address mailbox = vm.parseJsonAddress(rariData, ".mailbox");
        address arbitrumChainBalanceManager = vm.parseJsonAddress(arbitrumData, ".contracts.ChainBalanceManager");
        uint32 arbitrumDomain = uint32(vm.parseJsonUint(arbitrumData, ".domainId"));
        
        address gUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");
        address gWBTC = vm.parseJsonAddress(rariData, ".contracts.gsWBTC");
        address gWETH = vm.parseJsonAddress(rariData, ".contracts.gsWETH");
        
        console.log("BalanceManager:", balanceManager);
        console.log("Mailbox:", mailbox);
        console.log("Arbitrum ChainBalanceManager:", arbitrumChainBalanceManager);
        console.log("Arbitrum Domain:", arbitrumDomain);
        console.log("");
        console.log("New synthetic tokens:");
        console.log("gUSDT (6 decimals):", gUSDT);
        console.log("gWBTC (8 decimals):", gWBTC);
        console.log("gWETH (18 decimals):", gWETH);
        console.log("");
        
        BalanceManager bm = BalanceManager(balanceManager);
        
        console.log("=== CHECK BALANCE MANAGER CONFIGURATION ===");
        
        // Check if BalanceManager has mailbox configured
        try bm.getCrossChainConfig() returns (address currentMailbox, uint32 currentDomain) {
            console.log("BalanceManager mailbox:", currentMailbox);
            console.log("BalanceManager domain:", currentDomain);
            
            if (currentMailbox == address(0)) {
                console.log("ERROR: BalanceManager mailbox not configured!");
            } else if (currentMailbox != mailbox) {
                console.log("WARNING: BalanceManager mailbox mismatch!");
                console.log("Expected:", mailbox);
                console.log("Actual:", currentMailbox);
            } else {
                console.log("SUCCESS: BalanceManager mailbox configured correctly");
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not get BalanceManager cross-chain config -", reason);
        }
        
        console.log("");
        console.log("=== CHECK CHAIN REGISTRATION ===");
        
        // Check if Arbitrum chain is registered with BalanceManager
        try bm.isChainRegistered(arbitrumDomain) returns (bool registered) {
            console.log("Arbitrum chain registered:", registered ? "YES" : "NO");
            
            if (!registered) {
                console.log("ERROR: Arbitrum chain not registered with BalanceManager!");
                console.log("Need to register chain", arbitrumDomain, "with ChainBalanceManager", arbitrumChainBalanceManager);
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not check chain registration -", reason);
        }
        
        // Try to get chain info
        try bm.getChainInfo(arbitrumDomain) returns (address registeredCBM, bool isRegistered) {
            console.log("Registered ChainBalanceManager:", registeredCBM);
            console.log("Is registered:", isRegistered ? "YES" : "NO");
            
            if (registeredCBM != arbitrumChainBalanceManager) {
                console.log("WARNING: Registered CBM mismatch!");
                console.log("Expected:", arbitrumChainBalanceManager);
                console.log("Registered:", registeredCBM);
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not get chain info -", reason);
        }
        
        console.log("");
        console.log("=== CHECK TOKEN REGISTRY ===");
        
        // Check if BalanceManager has TokenRegistry set
        try bm.getTokenRegistry() returns (address tokenRegistry) {
            console.log("TokenRegistry:", tokenRegistry);
            
            if (tokenRegistry == address(0)) {
                console.log("ERROR: BalanceManager TokenRegistry not set!");
            } else {
                console.log("SUCCESS: TokenRegistry configured");
            }
        } catch Error(string memory reason) {
            console.log("FAILED: Could not get TokenRegistry -", reason);
        }
        
        console.log("");
        console.log("=== CHECK SYNTHETIC TOKENS ===");
        
        // Check if synthetic tokens are properly configured
        (bool dec1, bytes memory decData1) = gUSDT.staticcall(abi.encodeWithSignature("decimals()"));
        (bool dec2, bytes memory decData2) = gWBTC.staticcall(abi.encodeWithSignature("decimals()"));
        (bool dec3, bytes memory decData3) = gWETH.staticcall(abi.encodeWithSignature("decimals()"));
        
        console.log("Synthetic token decimals:");
        if (dec1) console.log("gUSDT:", abi.decode(decData1, (uint8)), "(should be 6)");
        if (dec2) console.log("gWBTC:", abi.decode(decData2, (uint8)), "(should be 8)");
        if (dec3) console.log("gWETH:", abi.decode(decData3, (uint8)), "(should be 18)");
        
        // Check if BalanceManager can mint these tokens
        console.log("");
        console.log("=== CHECK MINTING PERMISSIONS ===");
        
        // Check if BalanceManager is the minter for synthetic tokens
        try vm.call(gUSDT, abi.encodeWithSignature("bridgeSyntheticTokenReceiver()")) returns (bytes memory data) {
            address minter = abi.decode(data, (address));
            console.log("gUSDT minter:", minter);
            console.log("BalanceManager is minter:", minter == balanceManager ? "YES" : "NO");
            
            if (minter != balanceManager) {
                console.log("ERROR: BalanceManager cannot mint gUSDT!");
            }
        } catch {
            console.log("Could not check gUSDT minter");
        }
        
        console.log("");
        console.log("=== POTENTIAL FIXES ===");
        
        console.log("If relay is failing, check:");
        console.log("1. BalanceManager mailbox configuration");
        console.log("2. Chain registration for domain", arbitrumDomain);
        console.log("3. TokenRegistry configuration");
        console.log("4. Synthetic token minting permissions");
        console.log("5. Message format compatibility");
        console.log("");
        
        console.log("=== MESSAGE IDS TO INVESTIGATE ===");
        console.log("Failed messages:");
        console.log("- 0xdec22af83b7eeee6e1d274c6a13c6092ab70425808dc90388bc9e65eb34a3cc0");
        console.log("- 0x99635413cce631ee37adea39d25723e0b574cee47e3236e67523b336f7b6c975");
        console.log("");
        console.log("Check these on Hyperlane explorer:");
        console.log("- https://hyperlane-explorer.gtxdex.xyz/message/0xdec22af83b7eeee6e1d274c6a13c6092ab70425808dc90388bc9e65eb34a3cc0");
        console.log("- https://hyperlane-explorer.gtxdex.xyz/message/0x99635413cce631ee37adea39d25723e0b574cee47e3236e67523b336f7b6c975");
        
        console.log("========== DIAGNOSIS COMPLETE ==========");
    }
}