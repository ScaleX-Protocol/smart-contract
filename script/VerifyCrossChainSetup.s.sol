// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainRegistry} from "../src/core/ChainRegistry.sol";
import {TokenRegistry} from "../src/core/TokenRegistry.sol";
import {SyntheticTokenFactory} from "../src/core/SyntheticTokenFactory.sol";

/**
 * @title VerifyCrossChainSetup
 * @dev Script to verify cross-chain infrastructure deployment and configuration
 */
contract VerifyCrossChainSetup is Script {
    
    function run() external view {
        address chainRegistryAddress = vm.envAddress("CHAIN_REGISTRY_ADDRESS");
        address tokenRegistryAddress = vm.envAddress("TOKEN_REGISTRY_ADDRESS");
        address syntheticTokenFactoryAddress = vm.envAddress("SYNTHETIC_TOKEN_FACTORY_ADDRESS");
        
        console.log("=== CROSS-CHAIN SETUP VERIFICATION ===");
        console.log("");
        
        verifyChainRegistry(chainRegistryAddress);
        verifyTokenRegistry(tokenRegistryAddress);
        verifySyntheticTokenFactory(syntheticTokenFactoryAddress);
        verifyIntegration(chainRegistryAddress, tokenRegistryAddress, syntheticTokenFactoryAddress);
        
        console.log("=== VERIFICATION COMPLETE ===");
    }
    
    function verifyChainRegistry(address chainRegistryAddress) internal view {
        console.log("--- ChainRegistry Verification ---");
        console.log("Address:", chainRegistryAddress);
        
        ChainRegistry chainRegistry = ChainRegistry(chainRegistryAddress);
        console.log("Owner:", chainRegistry.owner());
        
        // Check Espresso testnet chains
        uint32[] memory chains = chainRegistry.getAllChains();
        console.log("Total chains registered:", chains.length);
        
        for (uint256 i = 0; i < chains.length; i++) {
            ChainRegistry.ChainConfig memory config = chainRegistry.getChainConfig(chains[i]);
            console.log(string.concat("Chain ", vm.toString(chains[i]), ": ", config.name));
            console.log("  Domain ID:", config.domainId);
            console.log("  Mailbox:", config.mailbox);
            console.log("  Active:", config.isActive);
        }
        
        console.log("");
    }
    
    function verifyTokenRegistry(address tokenRegistryAddress) internal view {
        console.log("--- TokenRegistry Verification ---");
        console.log("Address:", tokenRegistryAddress);
        
        TokenRegistry tokenRegistry = TokenRegistry(tokenRegistryAddress);
        console.log("Owner:", tokenRegistry.owner());
        
        // Check default Espresso mappings
        uint32 appchainId = 4661;
        uint32 rariId = 1918988905;
        
        // USDT mapping
        address usdtSource = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        address usdtSynthetic = tokenRegistry.getSyntheticToken(appchainId, usdtSource, rariId);
        console.log("USDT mapping (Appchain -> Rari):");
        console.log("  Source:", usdtSource);
        console.log("  Synthetic:", usdtSynthetic);
        console.log("  Active:", tokenRegistry.isTokenMappingActive(appchainId, usdtSource, rariId));
        
        // WETH mapping
        address wethSource = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
        address wethSynthetic = tokenRegistry.getSyntheticToken(appchainId, wethSource, rariId);
        console.log("WETH mapping (Appchain -> Rari):");
        console.log("  Source:", wethSource);
        console.log("  Synthetic:", wethSynthetic);
        console.log("  Active:", tokenRegistry.isTokenMappingActive(appchainId, wethSource, rariId));
        
        // WBTC mapping
        address wbtcSource = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;
        address wbtcSynthetic = tokenRegistry.getSyntheticToken(appchainId, wbtcSource, rariId);
        console.log("WBTC mapping (Appchain -> Rari):");
        console.log("  Source:", wbtcSource);
        console.log("  Synthetic:", wbtcSynthetic);
        console.log("  Active:", tokenRegistry.isTokenMappingActive(appchainId, wbtcSource, rariId));
        
        console.log("");
    }
    
    function verifySyntheticTokenFactory(address factoryAddress) internal view {
        console.log("--- SyntheticTokenFactory Verification ---");
        console.log("Address:", factoryAddress);
        
        SyntheticTokenFactory factory = SyntheticTokenFactory(factoryAddress);
        console.log("Owner:", factory.owner());
        console.log("TokenRegistry:", factory.getTokenRegistry());
        console.log("BridgeReceiver:", factory.getBridgeReceiver());
        
        // Check synthetic tokens created
        address[] memory allTokens = factory.getAllSyntheticTokens();
        console.log("Total synthetic tokens:", allTokens.length);
        
        for (uint256 i = 0; i < allTokens.length; i++) {
            SyntheticTokenFactory.SourceTokenInfo memory info = factory.getSourceTokenInfo(allTokens[i]);
            console.log(string.concat("Synthetic token ", vm.toString(i + 1), ":"));
            console.log("  Address:", allTokens[i]);
            console.log("  Source chain:", info.sourceChainId);
            console.log("  Source token:", info.sourceToken);
            console.log("  Source decimals:", info.sourceDecimals);
            console.log("  Synthetic decimals:", info.syntheticDecimals);
            console.log("  Active:", info.isActive);
        }
        
        console.log("");
    }
    
    function verifyIntegration(
        address chainRegistryAddress,
        address tokenRegistryAddress,
        address factoryAddress
    ) internal view {
        console.log("--- Integration Verification ---");
        
        ChainRegistry chainRegistry = ChainRegistry(chainRegistryAddress);
        TokenRegistry tokenRegistry = TokenRegistry(tokenRegistryAddress);
        SyntheticTokenFactory factory = SyntheticTokenFactory(factoryAddress);
        
        // Verify TokenRegistry is controlled by factory
        if (tokenRegistry.owner() == factoryAddress) {
            console.log("[OK] TokenRegistry ownership correctly transferred to factory");
        } else {
            console.log("[ERROR] TokenRegistry ownership not transferred to factory");
            console.log("  Current owner:", tokenRegistry.owner());
            console.log("  Expected owner:", factoryAddress);
        }
        
        // Verify factory points to correct TokenRegistry
        if (factory.getTokenRegistry() == tokenRegistryAddress) {
            console.log("[OK] Factory correctly configured with TokenRegistry");
        } else {
            console.log("[ERROR] Factory TokenRegistry mismatch");
            console.log("  Factory TokenRegistry:", factory.getTokenRegistry());
            console.log("  Expected:", tokenRegistryAddress);
        }
        
        // Verify Espresso chains are active
        uint32[] memory espressoChains = new uint32[](2);
        espressoChains[0] = 4661;  // Appchain
        espressoChains[1] = 1918988905;  // Rari
        
        bool allChainsActive = true;
        for (uint256 i = 0; i < espressoChains.length; i++) {
            if (!chainRegistry.isChainActive(espressoChains[i])) {
                allChainsActive = false;
                console.log("[ERROR] Chain", espressoChains[i], "is not active");
            }
        }
        if (allChainsActive) {
            console.log("[OK] All Espresso testnet chains are active");
        }
        
        // Verify cross-chain token mappings
        uint32 appchainId = 4661;
        uint32 rariId = 1918988905;
        address[] memory sourceTokens = new address[](3);
        sourceTokens[0] = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516; // USDT
        sourceTokens[1] = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F; // WETH
        sourceTokens[2] = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18; // WBTC
        
        bool allMappingsActive = true;
        for (uint256 i = 0; i < sourceTokens.length; i++) {
            if (!tokenRegistry.isTokenMappingActive(appchainId, sourceTokens[i], rariId)) {
                allMappingsActive = false;
                console.log("[ERROR] Token mapping inactive for:", sourceTokens[i]);
            }
        }
        if (allMappingsActive) {
            console.log("[OK] All Espresso token mappings are active");
        }
        
        console.log("");
        console.log("--- Setup Summary ---");
        console.log("Espresso testnet cross-chain infrastructure is ready for:");
        console.log("- Cross-chain token transfers (Appchain <-> Rari)");
        console.log("- Synthetic token minting/burning");
        console.log("- Multi-chain order book operations");
        console.log("- Cross-chain liquidity management");
        console.log("");
    }
}