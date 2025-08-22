// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "../src/core/TokenRegistry.sol";

contract UpdateSyntheticTokenAddresses is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========== UPDATING SYNTHETIC TOKEN ADDRESSES ==========");
        
        // Dynamic chain detection - no need to switch, use current network
        
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
        
        console.log("Updating mappings for:", chainName);
        console.log("Chain ID:", chainId);
        
        // NEW real ERC20 synthetic token addresses on Rari
        address realGsUSDTAddr = 0x6fcf28b801C7116cA8b6460289e259aC8D9131F3;
        address realGsWETHAddr = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address realGsWBTCAddr = 0xfAcf2E43910f93CE00d95236C23693F73FdA3Dcf;
        
        console.log("ChainBalanceManager:", chainBalanceManagerAddr);
        console.log("");
        
        console.log("=== OLD vs NEW ADDRESSES ===");
        console.log("OLD gsUSDT (placeholder):", 0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7);
        console.log("NEW gsUSDT (real ERC20): ", realGsUSDTAddr);
        console.log("");
        console.log("OLD gsWETH (existing):   ", 0xC7A1777e80982E01e07406e6C6E8B30F5968F836);
        console.log("NEW gsWETH (real ERC20): ", realGsWETHAddr);
        console.log("");
        console.log("OLD gsWBTC (placeholder):", 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF);
        console.log("NEW gsWBTC (real ERC20): ", realGsWBTCAddr);
        console.log("");
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Update token mappings in ChainBalanceManager
        console.log("=== UPDATING TOKEN MAPPINGS ===");
        
        try cbm.setTokenMapping(mockUSDTAddr, realGsUSDTAddr) {
            console.log("SUCCESS: Updated USDT mapping");
        } catch Error(string memory reason) {
            console.log("FAILED to update USDT mapping:", reason);
        } catch {
            console.log("FAILED to update USDT mapping with unknown error");
        }
        
        try cbm.setTokenMapping(mockWETHAddr, realGsWETHAddr) {
            console.log("SUCCESS: Updated WETH mapping");
        } catch Error(string memory reason) {
            console.log("FAILED to update WETH mapping:", reason);
        } catch {
            console.log("FAILED to update WETH mapping with unknown error");
        }
        
        try cbm.setTokenMapping(mockWBTCAddr, realGsWBTCAddr) {
            console.log("SUCCESS: Updated WBTC mapping");
        } catch Error(string memory reason) {
            console.log("FAILED to update WBTC mapping:", reason);
        } catch {
            console.log("FAILED to update WBTC mapping with unknown error");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== VERIFICATION ===");
        
        // Verify mappings were updated
        try cbm.getTokenMapping(mockUSDTAddr) returns (address syntheticUSDT) {
            console.log("USDT synthetic token:", syntheticUSDT);
            if (syntheticUSDT == realGsUSDTAddr) {
                console.log("SUCCESS: USDT mapping updated correctly");
            } else {
                console.log("WARNING: USDT mapping not updated");
            }
        } catch {
            console.log("Could not verify USDT mapping");
        }
        
        try cbm.getTokenMapping(mockWETHAddr) returns (address syntheticWETH) {
            console.log("WETH synthetic token:", syntheticWETH);
            if (syntheticWETH == realGsWETHAddr) {
                console.log("SUCCESS: WETH mapping updated correctly");
            } else {
                console.log("WARNING: WETH mapping not updated");
            }
        } catch {
            console.log("Could not verify WETH mapping");
        }
        
        try cbm.getTokenMapping(mockWBTCAddr) returns (address syntheticWBTC) {
            console.log("WBTC synthetic token:", syntheticWBTC);
            if (syntheticWBTC == realGsWBTCAddr) {
                console.log("SUCCESS: WBTC mapping updated correctly");
            } else {
                console.log("WARNING: WBTC mapping not updated");
            }
        } catch {
            console.log("Could not verify WBTC mapping");
        }
        
        console.log("");
        console.log("========== TOKEN ADDRESSES UPDATED ==========");
        console.log("Next cross-chain deposits will:");
        console.log("1. Send messages with correct real ERC20 addresses");
        console.log("2. Trigger V2 token minting on destination");
        console.log("3. Mint actual ERC20 tokens to users");
        console.log("4. Update internal balances for trading");
    }
}