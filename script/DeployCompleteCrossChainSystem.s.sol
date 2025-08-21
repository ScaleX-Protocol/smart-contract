// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {BalanceManager} from "../src/core/BalanceManager.sol";
import {ChainRegistry} from "../src/core/ChainRegistry.sol";
import {TokenRegistry} from "../src/core/TokenRegistry.sol";
import {SyntheticTokenFactory} from "../src/core/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../src/token/SyntheticToken.sol";

/**
 * @title DeployCompleteCrossChainSystem
 * @dev Deploy complete cross-chain CLOB DEX system with proper BalanceManager integration
 */
contract DeployCompleteCrossChainSystem is Script {
    
    struct DeploymentResult {
        address balanceManager;
        address chainRegistry;
        address tokenRegistry;
        address syntheticTokenFactory;
        address gsUSDT;
        address gsWETH;
        address gsWBTC;
    }
    
    struct EspressoConfig {
        uint32 rariChainId;
        uint32 rariDomainId;
        address rariMailbox;
        
        uint32 appchainChainId;
        uint32 appchainDomainId;
        address appchainMailbox;
        
        // Token addresses on Appchain
        address appchainUSDT;
        address appchainWETH;
        address appchainWBTC;
    }
    
    function run() external {
        address owner = msg.sender;
        
        vm.startBroadcast();
        
        DeploymentResult memory result = deployCompleteSystem(owner);
        configureEspressoIntegration(result);
        
        vm.stopBroadcast();
        
        logDeployment(result);
    }
    
    function deployCompleteSystem(address owner) public returns (DeploymentResult memory result) {
        console.log("=== DEPLOYING COMPLETE CROSS-CHAIN CLOB DEX ===");
        
        // 1. Deploy BalanceManager (Core trading engine)
        console.log("1. Deploying BalanceManager...");
        address balanceManagerImpl = address(new BalanceManager());
        UpgradeableBeacon balanceManagerBeacon = new UpgradeableBeacon(balanceManagerImpl, owner);
        BeaconProxy balanceManagerProxy = new BeaconProxy(
            address(balanceManagerBeacon),
            abi.encodeCall(BalanceManager.initialize, (
                owner,      // owner
                owner,      // feeReceiver (can be changed later)
                5,          // feeMaker (0.5%)
                10          // feeTaker (1.0%)
            ))
        );
        result.balanceManager = address(balanceManagerProxy);
        console.log("   BalanceManager deployed at:", result.balanceManager);
        
        // 2. Deploy ChainRegistry
        console.log("2. Deploying ChainRegistry...");
        address chainRegistryImpl = address(new ChainRegistry());
        UpgradeableBeacon chainRegistryBeacon = new UpgradeableBeacon(chainRegistryImpl, owner);
        BeaconProxy chainRegistryProxy = new BeaconProxy(
            address(chainRegistryBeacon),
            abi.encodeCall(ChainRegistry.initialize, (owner))
        );
        result.chainRegistry = address(chainRegistryProxy);
        console.log("   ChainRegistry deployed at:", result.chainRegistry);
        
        // 3. Deploy TokenRegistry
        console.log("3. Deploying TokenRegistry...");
        address tokenRegistryImpl = address(new TokenRegistry());
        UpgradeableBeacon tokenRegistryBeacon = new UpgradeableBeacon(tokenRegistryImpl, owner);
        BeaconProxy tokenRegistryProxy = new BeaconProxy(
            address(tokenRegistryBeacon),
            abi.encodeCall(TokenRegistry.initialize, (owner))
        );
        result.tokenRegistry = address(tokenRegistryProxy);
        console.log("   TokenRegistry deployed at:", result.tokenRegistry);
        
        // 4. Deploy SyntheticTokenFactory with BalanceManager as bridge receiver
        console.log("4. Deploying SyntheticTokenFactory...");
        address factoryImpl = address(new SyntheticTokenFactory());
        UpgradeableBeacon factoryBeacon = new UpgradeableBeacon(factoryImpl, owner);
        BeaconProxy factoryProxy = new BeaconProxy(
            address(factoryBeacon),
            abi.encodeCall(SyntheticTokenFactory.initialize, (
                owner,
                result.tokenRegistry,
                result.balanceManager  // ✅ BalanceManager is the bridge receiver
            ))
        );
        result.syntheticTokenFactory = address(factoryProxy);
        console.log("   SyntheticTokenFactory deployed at:", result.syntheticTokenFactory);
        
        // 5. Transfer TokenRegistry ownership to Factory for automated registration
        console.log("5. Transferring TokenRegistry ownership to Factory...");
        TokenRegistry(result.tokenRegistry).transferOwnership(result.syntheticTokenFactory);
        
        // 6. Create Espresso synthetic tokens
        console.log("6. Creating Espresso synthetic tokens...");
        EspressoConfig memory config = getEspressoConfig();
        
        SyntheticTokenFactory factory = SyntheticTokenFactory(result.syntheticTokenFactory);
        
        // Create gsUSDT (6 decimals to match USDT)
        result.gsUSDT = factory.createSyntheticToken(
            config.appchainChainId,     // source: Appchain
            config.appchainUSDT,        // source token
            config.rariChainId,         // target: Rari
            "Green Synthetic USDT",     // name
            "gsUSDT",                   // symbol
            6,                          // source decimals (USDT)
            6                           // synthetic decimals (keep same)
        );
        console.log("   gsUSDT created at:", result.gsUSDT);
        
        // Create gsWETH (18 decimals)
        result.gsWETH = factory.createSyntheticToken(
            config.appchainChainId,
            config.appchainWETH,
            config.rariChainId,
            "Green Synthetic WETH",
            "gsWETH",
            18,  // source decimals (WETH)
            18   // synthetic decimals (keep same)
        );
        console.log("   gsWETH created at:", result.gsWETH);
        
        // Create gsWBTC (8 decimals)
        result.gsWBTC = factory.createSyntheticToken(
            config.appchainChainId,
            config.appchainWBTC,
            config.rariChainId,
            "Green Synthetic WBTC",
            "gsWBTC",
            8,   // source decimals (WBTC)
            8    // synthetic decimals (keep same)
        );
        console.log("   gsWBTC created at:", result.gsWBTC);
        
        return result;
    }
    
    function configureEspressoIntegration(DeploymentResult memory deployment) public {
        console.log("=== CONFIGURING ESPRESSO INTEGRATION ===");
        
        EspressoConfig memory config = getEspressoConfig();
        
        // 1. Initialize BalanceManager cross-chain functionality
        console.log("1. Initializing BalanceManager cross-chain...");
        BalanceManager balanceManager = BalanceManager(deployment.balanceManager);
        balanceManager.initializeCrossChain(
            config.rariMailbox,
            config.rariDomainId
        );
        console.log("   BalanceManager configured for Hyperlane messaging");
        
        // 2. Register Espresso chains in ChainRegistry
        console.log("2. Registering Espresso chains...");
        ChainRegistry chainRegistry = ChainRegistry(deployment.chainRegistry);
        
        // Register Rari (current chain)
        chainRegistry.registerChain(
            config.rariChainId,
            config.rariDomainId,
            config.rariMailbox,
            "https://rari.caff.testnet.espresso.network",
            "Rari Testnet",
            2  // 2 second block time
        );
        
        // Register Appchain
        chainRegistry.registerChain(
            config.appchainChainId,
            config.appchainDomainId,
            config.appchainMailbox,
            "https://appchain.caff.testnet.espresso.network",
            "Appchain Testnet",
            2  // 2 second block time
        );
        
        console.log("   Espresso chains registered");
        
        // 3. Synthetic tokens are automatically ready for trading
        console.log("3. Synthetic tokens ready for CLOB trading...");
        console.log("   Tokens can be used in BalanceManager deposit/withdraw/trading functions");
        console.log("   Bridge receiver (BalanceManager) can mint/burn as needed for cross-chain operations");
    }
    
    function getEspressoConfig() internal pure returns (EspressoConfig memory) {
        return EspressoConfig({
            rariChainId: 1918988905,
            rariDomainId: 1918988905,
            rariMailbox: 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358,
            
            appchainChainId: 4661,
            appchainDomainId: 4661,
            appchainMailbox: 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1,
            
            // Appchain testnet token addresses
            appchainUSDT: 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516,
            appchainWETH: 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F,
            appchainWBTC: 0xb2e9Eabb827b78e2aC66bE17327603778D117d18
        });
    }
    
    function logDeployment(DeploymentResult memory result) internal view {
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("Network: Rari Testnet (Chain ID: 1918988905)");
        console.log("");
        console.log("Core Contracts:");
        console.log("  BalanceManager (Trading):", result.balanceManager);
        console.log("  ChainRegistry (Chains):", result.chainRegistry);
        console.log("  TokenRegistry (Mappings):", result.tokenRegistry);
        console.log("  SyntheticTokenFactory:", result.syntheticTokenFactory);
        console.log("");
        console.log("Synthetic Tokens:");
        console.log("  gsUSDT:", result.gsUSDT);
        console.log("  gsWETH:", result.gsWETH);
        console.log("  gsWBTC:", result.gsWBTC);
        console.log("");
        console.log("Bridge Configuration:");
        console.log("  Bridge Receiver: BalanceManager (handles cross-chain messages)");
        console.log("  Source Chains: Appchain Testnet (Chain ID: 4661)");
        console.log("  Message Protocol: Hyperlane");
        console.log("");
        console.log("Next Steps:");
        console.log("1. Deploy ChainBalanceManager on Appchain testnet");
        console.log("2. Configure ChainBalanceManager to send messages to this BalanceManager");
        console.log("3. Test cross-chain deposit flow: Appchain -> Rari");
        console.log("4. Test CLOB trading with synthetic tokens");
        console.log("5. Test cross-chain withdrawal flow: Rari -> Appchain");
        console.log("");
        console.log("Environment Variables for Testing:");
        console.log("export BALANCE_MANAGER=", result.balanceManager);
        console.log("export TOKEN_REGISTRY=", result.tokenRegistry);
        console.log("export SYNTHETIC_FACTORY=", result.syntheticTokenFactory);
        console.log("export GS_USDT=", result.gsUSDT);
        console.log("export GS_WETH=", result.gsWETH);
        console.log("export GS_WBTC=", result.gsWBTC);
    }
}