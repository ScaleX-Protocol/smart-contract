// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "../src/core/TokenRegistry.sol";

contract VerifyTokenMappings is Script {
    
    function run() public {
        console.log("========== VERIFYING TOKEN MAPPINGS ==========");
        console.log("Checking if all token addresses are correctly mapped after V2 upgrade");
        console.log("");
        
        // STEP 1: Check ChainBalanceManager token mappings (Appchain)
        console.log("=== STEP 1: CHAINBALANCEMANAGER MAPPINGS (APPCHAIN) ===");
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        // Mock token addresses on Appchain (source)
        address mockUSDTAddr = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        address mockWETHAddr = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
        address mockWBTCAddr = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;
        
        // Expected real ERC20 synthetic token addresses on Rari (destination)
        address expectedGsUSDTAddr = 0x6fcf28b801C7116cA8b6460289e259aC8D9131F3;
        address expectedGsWETHAddr = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address expectedGsWBTCAddr = 0xfAcf2E43910f93CE00d95236C23693F73FdA3Dcf;
        
        console.log("Source tokens (Appchain):");
        console.log("- Mock USDT:", mockUSDTAddr);
        console.log("- Mock WETH:", mockWETHAddr);
        console.log("- Mock WBTC:", mockWBTCAddr);
        console.log("");
        
        console.log("Expected synthetic tokens (Rari):");
        console.log("- Real gsUSDT:", expectedGsUSDTAddr);
        console.log("- Real gsWETH:", expectedGsWETHAddr);
        console.log("- Real gsWBTC:", expectedGsWBTCAddr);
        console.log("");
        
        // Check current mappings in ChainBalanceManager
        console.log("Current ChainBalanceManager mappings:");
        
        try cbm.getTokenMapping(mockUSDTAddr) returns (address mappedUSDT) {
            console.log("USDT mapping:", mappedUSDT);
            console.log("USDT correct:", mappedUSDT == expectedGsUSDTAddr ? "YES" : "NO");
        } catch {
            console.log("USDT mapping: NOT FOUND");
        }
        
        try cbm.getTokenMapping(mockWETHAddr) returns (address mappedWETH) {
            console.log("WETH mapping:", mappedWETH);
            console.log("WETH correct:", mappedWETH == expectedGsWETHAddr ? "YES" : "NO");
        } catch {
            console.log("WETH mapping: NOT FOUND");
        }
        
        try cbm.getTokenMapping(mockWBTCAddr) returns (address mappedWBTC) {
            console.log("WBTC mapping:", mappedWBTC);
            console.log("WBTC correct:", mappedWBTC == expectedGsWBTCAddr ? "YES" : "NO");
        } catch {
            console.log("WBTC mapping: NOT FOUND");
        }
        
        console.log("");
        
        // STEP 2: Check TokenRegistry mappings (Rari)
        console.log("=== STEP 2: TOKEN REGISTRY MAPPINGS (RARI) ===");
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address tokenRegistryAddr = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;
        TokenRegistry tokenRegistry = TokenRegistry(tokenRegistryAddr);
        
        console.log("TokenRegistry address:", tokenRegistryAddr);
        console.log("");
        
        // Check reverse mappings (synthetic -> source)
        console.log("TokenRegistry reverse mappings (synthetic -> source):");
        
        try tokenRegistry.getSourceToken(expectedGsUSDTAddr) returns (address sourceUSDT) {
            console.log("gsUSDT -> source:", sourceUSDT);
            console.log("gsUSDT reverse correct:", sourceUSDT == mockUSDTAddr ? "YES" : "NO");
        } catch {
            console.log("gsUSDT reverse mapping: NOT FOUND");
        }
        
        try tokenRegistry.getSourceToken(expectedGsWETHAddr) returns (address sourceWETH) {
            console.log("gsWETH -> source:", sourceWETH);
            console.log("gsWETH reverse correct:", sourceWETH == mockWETHAddr ? "YES" : "NO");
        } catch {
            console.log("gsWETH reverse mapping: NOT FOUND");
        }
        
        try tokenRegistry.getSourceToken(expectedGsWBTCAddr) returns (address sourceWBTC) {
            console.log("gsWBTC -> source:", sourceWBTC);
            console.log("gsWBTC reverse correct:", sourceWBTC == mockWBTCAddr ? "YES" : "NO");
        } catch {
            console.log("gsWBTC reverse mapping: NOT FOUND");
        }
        
        console.log("");
        
        // STEP 3: Check forward mappings (source -> synthetic)
        console.log("=== STEP 3: TOKEN REGISTRY FORWARD MAPPINGS ===");
        
        try tokenRegistry.getSyntheticToken(mockUSDTAddr) returns (address syntheticUSDT) {
            console.log("source USDT -> synthetic:", syntheticUSDT);
            console.log("USDT forward correct:", syntheticUSDT == expectedGsUSDTAddr ? "YES" : "NO");
        } catch {
            console.log("USDT forward mapping: NOT FOUND");
        }
        
        try tokenRegistry.getSyntheticToken(mockWETHAddr) returns (address syntheticWETH) {
            console.log("source WETH -> synthetic:", syntheticWETH);
            console.log("WETH forward correct:", syntheticWETH == expectedGsWETHAddr ? "YES" : "NO");
        } catch {
            console.log("WETH forward mapping: NOT FOUND");
        }
        
        try tokenRegistry.getSyntheticToken(mockWBTCAddr) returns (address syntheticWBTC) {
            console.log("source WBTC -> synthetic:", syntheticWBTC);
            console.log("WBTC forward correct:", syntheticWBTC == expectedGsWBTCAddr ? "YES" : "NO");
        } catch {
            console.log("WBTC forward mapping: NOT FOUND");
        }
        
        console.log("");
        
        // STEP 4: Summary and recommendations
        console.log("=== STEP 4: SUMMARY AND RECOMMENDATIONS ===");
        console.log("Token mapping verification complete.");
        console.log("");
        console.log("What should be correct:");
        console.log("1. ChainBalanceManager should map source -> real ERC20 tokens");
        console.log("2. TokenRegistry should have bidirectional mappings");
        console.log("3. All addresses should point to real deployed ERC20 contracts");
        console.log("");
        console.log("If mappings are incorrect, run:");
        console.log("- UpdateSyntheticTokenAddresses.s.sol for ChainBalanceManager");
        console.log("- Configure TokenRegistry mappings if needed");
        console.log("");
        console.log("========== TOKEN MAPPING VERIFICATION COMPLETE ==========");
    }
}