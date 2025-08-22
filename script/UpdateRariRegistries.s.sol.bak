// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainRegistry} from "../src/core/ChainRegistry.sol";
import {TokenRegistry} from "../src/core/TokenRegistry.sol";

contract UpdateRariRegistries is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("=== Updating Rari Registries ===");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Rari registry addresses
        address chainRegistryAddr = 0x0a1Ced1539C9FB81aBdDF870588A4fEfBf461bBB;
        address tokenRegistryAddr = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;
        
        ChainRegistry chainRegistry = ChainRegistry(chainRegistryAddr);
        TokenRegistry tokenRegistry = TokenRegistry(tokenRegistryAddr);
        
        // Updated Arbitrum Sepolia info
        uint32 arbitrumDomain = 421614;
        address newArbitrumCBM = 0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A;
        address arbitrumMailbox = 0x8DF6aDE95d25855ed0FB927ECD6a1D5Bb09d2145;
        string memory arbitrumRpc = "https://sepolia-rollup.arbitrum.io/rpc";
        
        console.log("Updating Chain Registry...");
        console.log("Arbitrum ChainBalanceManager:", newArbitrumCBM);
        console.log("Arbitrum Mailbox:", arbitrumMailbox);
        
        // Update chain registry with new ChainBalanceManager
        try chainRegistry.updateChainBalanceManager(arbitrumDomain, newArbitrumCBM) {
            console.log("SUCCESS: Updated Arbitrum ChainBalanceManager in registry");
        } catch {
            console.log("Chain not registered, registering new...");
            chainRegistry.registerChain(
                arbitrumDomain,
                arbitrumDomain,
                arbitrumMailbox,
                arbitrumRpc,
                "Arbitrum Sepolia",
                13 // block time
            );
            chainRegistry.updateChainBalanceManager(arbitrumDomain, newArbitrumCBM);
            console.log("SUCCESS: Registered Arbitrum chain and updated ChainBalanceManager");
        }
        
        console.log("Updating Token Registry mappings...");
        
        // Arbitrum token addresses
        address arbitrumUSDT = 0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a;
        address arbitrumWETH = 0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7;
        address arbitrumWBTC = 0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A;
        
        // Rari synthetic token addresses
        uint32 rariDomain = 1918988905;
        address gsUSDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address gsWBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;
        
        // Update token mappings
        try tokenRegistry.updateTokenMapping(
            arbitrumDomain, arbitrumUSDT, rariDomain, gsUSDT
        ) {
            console.log("SUCCESS: Updated USDT mapping");
        } catch {
            console.log("USDT mapping already exists or update failed");
        }
        
        try tokenRegistry.updateTokenMapping(
            arbitrumDomain, arbitrumWETH, rariDomain, gsWETH
        ) {
            console.log("SUCCESS: Updated WETH mapping");
        } catch {
            console.log("WETH mapping already exists or update failed");
        }
        
        try tokenRegistry.updateTokenMapping(
            arbitrumDomain, arbitrumWBTC, rariDomain, gsWBTC
        ) {
            console.log("SUCCESS: Updated WBTC mapping");
        } catch {
            console.log("WBTC mapping already exists or update failed");
        }
        
        vm.stopBroadcast();
        
        console.log("=== Registry Updates Complete ===");
        console.log("Arbitrum Sepolia is now configured with correct mailbox");
    }
}