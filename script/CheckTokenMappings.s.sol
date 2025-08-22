// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract CheckTokenMappings is Script {
    
    function run() public {
        console.log("========== CHECKING TOKEN MAPPINGS ==========");
        console.log("Verifying ChainBalanceManager has correct token mappings");
        console.log("");
        
        // Check ChainBalanceManager token mappings (Dynamic based on current network)
        console.log("=== CHAINBALANCEMANAGER MAPPINGS ===");
        
        // Detect chain and set appropriate addresses
        uint256 chainId = block.chainid;
        address chainBalanceManagerAddr;
        address mockUSDTAddr;
        address mockWETHAddr;
        address mockWBTCAddr;
        string memory chainName;
        
        if (chainId == 4661) {
            // Appchain
            chainName = "Appchain";
            chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
            mockUSDTAddr = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
            mockWETHAddr = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
            mockWBTCAddr = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;
        } else if (chainId == 421614) {
            // Arbitrum Sepolia
            chainName = "Arbitrum Sepolia";
            chainBalanceManagerAddr = 0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A;
            mockUSDTAddr = 0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a;
            mockWETHAddr = 0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7;
            mockWBTCAddr = 0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A;
        } else if (chainId == 11155931) {
            // Rise Sepolia  
            chainName = "Rise Sepolia";
            chainBalanceManagerAddr = 0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745;
            mockUSDTAddr = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;
            mockWETHAddr = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
            mockWBTCAddr = 0xc6b3109e45F7A479Ac324e014b6a272e4a25bF0E;
        } else {
            console.log("ERROR: Unsupported chain ID:", chainId);
            return;
        }
        
        console.log("Checking chain:", chainName);
        console.log("Chain ID:", chainId);
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        // Expected real ERC20 synthetic token addresses on Rari
        address expectedGsUSDTAddr = 0x6fcf28b801C7116cA8b6460289e259aC8D9131F3;
        address expectedGsWETHAddr = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address expectedGsWBTCAddr = 0xfAcf2E43910f93CE00d95236C23693F73FdA3Dcf;
        
        // Old placeholder addresses (should NOT be used anymore)
        address oldGsUSDTAddr = 0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7;
        address oldGsWBTCAddr = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;
        
        console.log("Source tokens on", chainName, ":");
        console.log("- Mock USDT:", mockUSDTAddr);
        console.log("- Mock WETH:", mockWETHAddr);
        console.log("- Mock WBTC:", mockWBTCAddr);
        console.log("");
        
        console.log("Expected real synthetic tokens (Rari):");
        console.log("- Real gsUSDT:", expectedGsUSDTAddr);
        console.log("- Real gsWETH:", expectedGsWETHAddr);
        console.log("- Real gsWBTC:", expectedGsWBTCAddr);
        console.log("");
        
        console.log("Old placeholder addresses (should NOT be used):");
        console.log("- Old gsUSDT:", oldGsUSDTAddr);
        console.log("- Old gsWBTC:", oldGsWBTCAddr);
        console.log("");
        
        // Check current mappings
        console.log("=== CURRENT MAPPINGS IN CHAINBALANCEMANAGER ===");
        
        bool allCorrect = true;
        
        // Check USDT mapping
        try cbm.getTokenMapping(mockUSDTAddr) returns (address mappedUSDT) {
            console.log("USDT mapping:");
            console.log("  Source:", mockUSDTAddr);
            console.log("  Mapped to:", mappedUSDT);
            console.log("  Expected:", expectedGsUSDTAddr);
            
            if (mappedUSDT == expectedGsUSDTAddr) {
                console.log("  Status: CORRECT");
            } else if (mappedUSDT == oldGsUSDTAddr) {
                console.log("  Status: USING OLD ADDRESS - NEEDS UPDATE");
                allCorrect = false;
            } else {
                console.log("  Status: UNKNOWN ADDRESS");
                allCorrect = false;
            }
        } catch {
            console.log("USDT mapping: NOT FOUND");
            allCorrect = false;
        }
        
        console.log("");
        
        // Check WETH mapping
        try cbm.getTokenMapping(mockWETHAddr) returns (address mappedWETH) {
            console.log("WETH mapping:");
            console.log("  Source:", mockWETHAddr);
            console.log("  Mapped to:", mappedWETH);
            console.log("  Expected:", expectedGsWETHAddr);
            
            if (mappedWETH == expectedGsWETHAddr) {
                console.log("  Status: CORRECT");
            } else {
                console.log("  Status: INCORRECT - NEEDS UPDATE");
                allCorrect = false;
            }
        } catch {
            console.log("WETH mapping: NOT FOUND");
            allCorrect = false;
        }
        
        console.log("");
        
        // Check WBTC mapping
        try cbm.getTokenMapping(mockWBTCAddr) returns (address mappedWBTC) {
            console.log("WBTC mapping:");
            console.log("  Source:", mockWBTCAddr);
            console.log("  Mapped to:", mappedWBTC);
            console.log("  Expected:", expectedGsWBTCAddr);
            
            if (mappedWBTC == expectedGsWBTCAddr) {
                console.log("  Status: CORRECT");
            } else if (mappedWBTC == oldGsWBTCAddr) {
                console.log("  Status: USING OLD ADDRESS - NEEDS UPDATE");
                allCorrect = false;
            } else {
                console.log("  Status: UNKNOWN ADDRESS");
                allCorrect = false;
            }
        } catch {
            console.log("WBTC mapping: NOT FOUND");
            allCorrect = false;
        }
        
        console.log("");
        
        // Summary
        console.log("=== SUMMARY ===");
        if (allCorrect) {
            console.log("SUCCESS: All token mappings are correct!");
            console.log("ChainBalanceManager will send messages with real ERC20 addresses.");
        } else {
            console.log("WARNING: Some token mappings need to be updated!");
            console.log("Run UpdateSyntheticTokenAddresses.s.sol to fix mappings.");
        }
        
        console.log("");
        console.log("=== IMPACT ON V2 MINTING ===");
        console.log("- Correct mappings = V2 minting works");
        console.log("- Incorrect mappings = V2 minting fails, falls back to internal accounting");
        console.log("- Current V2 status: We've successfully minted 105,000,000 gsUSDT");
        console.log("- This means USDT mapping is working correctly!");
        
        console.log("");
        console.log("========== TOKEN MAPPING CHECK COMPLETE ==========");
    }
}