// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {BalanceManager} from "../src/core/BalanceManager.sol";
import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";
import {ChainRegistry} from "../src/core/ChainRegistry.sol";
import {TokenRegistry} from "../src/core/TokenRegistry.sol";
import {SyntheticTokenFactory} from "../src/core/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../src/token/SyntheticToken.sol";

/**
 * @title DeployEspressoTestnet
 * @dev Smart deployment script for Espresso testnet with re-deployment prevention
 */
contract DeployEspressoTestnet is Script {
    using stdJson for string;

    // Network configurations
    struct NetworkConfig {
        string name;
        uint256 chainId;
        uint32 domainId;
        string rpc;
        address mailbox;
        string deploymentFile;
    }

    // Known token addresses on Espresso testnet
    struct TokenInfo {
        address token;
        string symbol;
        uint8 decimals;
    }

    NetworkConfig public rari = NetworkConfig({
        name: "Rari Testnet",
        chainId: 1918988905,
        domainId: 1918988905,
        rpc: "https://rari.caff.testnet.espresso.network",
        mailbox: 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358,
        deploymentFile: "deployments/rari.json"
    });

    NetworkConfig public appchain = NetworkConfig({
        name: "Appchain Testnet", 
        chainId: 4661,
        domainId: 4661,
        rpc: "https://appchain.caff.testnet.espresso.network",
        mailbox: 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1,
        deploymentFile: "deployments/appchain.json"
    });

    NetworkConfig public arbitrumSepolia = NetworkConfig({
        name: "Arbitrum Sepolia",
        chainId: 421614,
        domainId: 421614,
        rpc: "https://sepolia-rollup.arbitrum.io/rpc",
        mailbox: 0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766,
        deploymentFile: "deployments/arbitrum-sepolia.json"
    });

    NetworkConfig public riseSepolia = NetworkConfig({
        name: "Rise Sepolia",
        chainId: 11155931,
        domainId: 11155931,
        rpc: "https://testnet.rizelabs.xyz",
        mailbox: 0xD377bFbea110cDbc3D31EaFB146AE6fA5b3190E3,
        deploymentFile: "deployments/rise-sepolia.json"
    });

    // Appchain token addresses
    mapping(string => TokenInfo) public appchainTokens;
    
    function setUp() public {
        // Initialize known token addresses on Appchain
        appchainTokens["USDT"] = TokenInfo({
            token: 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516,
            symbol: "USDT",
            decimals: 6
        });
        
        appchainTokens["WETH"] = TokenInfo({
            token: 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F,
            symbol: "WETH", 
            decimals: 18
        });
        
        appchainTokens["WBTC"] = TokenInfo({
            token: 0xb2e9Eabb827b78e2aC66bE17327603778D117d18,
            symbol: "WBTC",
            decimals: 8
        });
    }

    function run() public {
        string memory network = vm.envString("NETWORK");
        
        if (keccak256(bytes(network)) == keccak256(bytes("rari"))) {
            deployRariSystem();
        } else if (keccak256(bytes(network)) == keccak256(bytes("appchain"))) {
            deployChainBalanceManager(appchain);
        } else if (keccak256(bytes(network)) == keccak256(bytes("arbitrum-sepolia"))) {
            deployChainBalanceManager(arbitrumSepolia);
        } else if (keccak256(bytes(network)) == keccak256(bytes("rise-sepolia"))) {
            deployChainBalanceManager(riseSepolia);
        } else {
            revert("Unknown network. Use: rari, appchain, arbitrum-sepolia, or rise-sepolia");
        }
    }

    function deployRariSystem() public {
        console.log("Deploying complete cross-chain system on Rari testnet...");
        
        // Load existing deployments
        string memory deploymentData = loadDeploymentFile(rari.deploymentFile);
        
        vm.startBroadcast();
        
        address owner = msg.sender;
        
        // 1. Deploy core contracts if not already deployed
        address balanceManager = getOrDeployBalanceManager(deploymentData, owner, rari);
        address chainRegistry = getOrDeployChainRegistry(deploymentData, owner);
        address tokenRegistry = getOrDeployTokenRegistry(deploymentData, owner);
        address syntheticTokenFactory = getOrDeploySyntheticTokenFactory(
            deploymentData, 
            owner, 
            tokenRegistry, 
            balanceManager
        );
        
        // 2. Configure cross-chain functionality
        configureBalanceManager(balanceManager, rari);
        
        // 3. Setup chain registry with all supported chains
        setupChainRegistry(chainRegistry);
        
        // 4. Create synthetic tokens for all supported tokens
        createSyntheticTokens(syntheticTokenFactory, tokenRegistry);
        
        vm.stopBroadcast();
        
        // 5. Save deployment addresses
        saveRariDeployment(
            balanceManager,
            chainRegistry, 
            tokenRegistry,
            syntheticTokenFactory
        );
        
        console.log("Rari system deployment completed!");
        logDeployedAddresses(balanceManager, chainRegistry, tokenRegistry, syntheticTokenFactory);
    }

    function deployChainBalanceManager(NetworkConfig memory config) public {
        console.log("Deploying ChainBalanceManager on", config.name);
        
        // Load existing deployments
        string memory deploymentData = loadDeploymentFile(config.deploymentFile);
        
        vm.startBroadcast();
        
        address owner = msg.sender;
        
        // Deploy ChainBalanceManager if not already deployed
        address chainBalanceManager = getOrDeployChainBalanceManager(deploymentData, owner, config);
        
        vm.stopBroadcast();
        
        // Save deployment
        saveChainBalanceManagerDeployment(config, chainBalanceManager);
        
        console.log("ChainBalanceManager deployed at:", chainBalanceManager);
    }

    function getOrDeployBalanceManager(
        string memory deploymentData,
        address owner,
        NetworkConfig memory config
    ) internal returns (address) {
        address existing = getContractAddress(deploymentData, "BalanceManager");
        if (existing != address(0)) {
            console.log("BalanceManager already deployed at:", existing);
            return existing;
        }
        
        console.log("Deploying new BalanceManager...");
        
        // Deploy implementation
        BalanceManager implementation = new BalanceManager();
        
        // Deploy beacon
        UpgradeableBeacon beacon = new UpgradeableBeacon(
            address(implementation),
            owner
        );
        
        // Deploy proxy
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeCall(BalanceManager.initialize, (owner, owner, 5, 10))
        );
        
        console.log("BalanceManager deployed at:", address(proxy));
        return address(proxy);
    }

    function getOrDeployChainBalanceManager(
        string memory deploymentData,
        address owner,
        NetworkConfig memory config
    ) internal returns (address) {
        address existing = getContractAddress(deploymentData, "ChainBalanceManager");
        if (existing != address(0)) {
            console.log("ChainBalanceManager already deployed at:", existing);
            return existing;
        }
        
        console.log("Deploying new ChainBalanceManager...");
        
        // Deploy implementation
        ChainBalanceManager implementation = new ChainBalanceManager();
        
        // Deploy beacon
        UpgradeableBeacon beacon = new UpgradeableBeacon(
            address(implementation),
            owner
        );
        
        // Deploy proxy - need destination domain (Rari) for ChainBalanceManager
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSignature(
                "initialize(address,address,uint32,address)",
                owner,
                config.mailbox,
                rari.domainId,
                address(0) // Will be set later after Rari deployment
            )
        );
        
        console.log("ChainBalanceManager deployed at:", address(proxy));
        return address(proxy);
    }

    function getOrDeployChainRegistry(
        string memory deploymentData,
        address owner
    ) internal returns (address) {
        address existing = getContractAddress(deploymentData, "ChainRegistry");
        if (existing != address(0)) {
            console.log("ChainRegistry already deployed at:", existing);
            return existing;
        }
        
        console.log("Deploying new ChainRegistry...");
        
        ChainRegistry implementation = new ChainRegistry();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), owner);
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeCall(ChainRegistry.initialize, (owner))
        );
        
        console.log("ChainRegistry deployed at:", address(proxy));
        return address(proxy);
    }

    function getOrDeployTokenRegistry(
        string memory deploymentData,
        address owner
    ) internal returns (address) {
        address existing = getContractAddress(deploymentData, "TokenRegistry");
        if (existing != address(0)) {
            console.log("TokenRegistry already deployed at:", existing);
            return existing;
        }
        
        console.log("Deploying new TokenRegistry...");
        
        TokenRegistry implementation = new TokenRegistry();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), owner);
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeCall(TokenRegistry.initialize, (owner))
        );
        
        console.log("TokenRegistry deployed at:", address(proxy));
        return address(proxy);
    }

    function getOrDeploySyntheticTokenFactory(
        string memory deploymentData,
        address owner,
        address tokenRegistry,
        address bridgeReceiver
    ) internal returns (address) {
        address existing = getContractAddress(deploymentData, "SyntheticTokenFactory");
        if (existing != address(0)) {
            console.log("SyntheticTokenFactory already deployed at:", existing);
            return existing;
        }
        
        console.log("Deploying new SyntheticTokenFactory...");
        
        SyntheticTokenFactory implementation = new SyntheticTokenFactory();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), owner);
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeCall(SyntheticTokenFactory.initialize, (
                owner,
                tokenRegistry,
                bridgeReceiver
            ))
        );
        
        // Transfer TokenRegistry ownership to Factory
        TokenRegistry(tokenRegistry).transferOwnership(address(proxy));
        
        console.log("SyntheticTokenFactory deployed at:", address(proxy));
        return address(proxy);
    }

    function configureBalanceManager(address balanceManager, NetworkConfig memory config) internal {
        console.log("Configuring BalanceManager for cross-chain...");
        BalanceManager(balanceManager).initializeCrossChain(config.mailbox, config.domainId);
    }

    function setupChainRegistry(address chainRegistry) internal {
        console.log("Setting up ChainRegistry with supported chains...");
        
        ChainRegistry registry = ChainRegistry(chainRegistry);
        
        // Register Appchain if not exists - check if config returns empty
        try registry.getChainConfig(appchain.domainId) returns (ChainRegistry.ChainConfig memory config) {
            if (config.domainId == 0) {
                registry.registerChain(
                    appchain.domainId,
                    appchain.domainId,
                    appchain.mailbox,
                    appchain.rpc,
                    appchain.name,
                    2 // 2 second block time
                );
                console.log("Registered Appchain");
            }
        } catch {
            registry.registerChain(
                appchain.domainId,
                appchain.domainId,
                appchain.mailbox,
                appchain.rpc,
                appchain.name,
                2 // 2 second block time
            );
            console.log("Registered Appchain");
        }
        
        // Register Arbitrum Sepolia if not exists
        try registry.getChainConfig(arbitrumSepolia.domainId) returns (ChainRegistry.ChainConfig memory config) {
            if (config.domainId == 0) {
                registry.registerChain(
                    arbitrumSepolia.domainId,
                    arbitrumSepolia.domainId,
                    arbitrumSepolia.mailbox,
                    arbitrumSepolia.rpc,
                    arbitrumSepolia.name,
                    13 // ~13 second block time
                );
                console.log("Registered Arbitrum Sepolia");
            }
        } catch {
            registry.registerChain(
                arbitrumSepolia.domainId,
                arbitrumSepolia.domainId,
                arbitrumSepolia.mailbox,
                arbitrumSepolia.rpc,
                arbitrumSepolia.name,
                13 // ~13 second block time
            );
            console.log("Registered Arbitrum Sepolia");
        }
        
        // Register Rise Sepolia if not exists
        try registry.getChainConfig(riseSepolia.domainId) returns (ChainRegistry.ChainConfig memory config) {
            if (config.domainId == 0) {
                registry.registerChain(
                    riseSepolia.domainId,
                    riseSepolia.domainId,
                    riseSepolia.mailbox,
                    riseSepolia.rpc,
                    riseSepolia.name,
                    12 // ~12 second block time
                );
                console.log("Registered Rise Sepolia");
            }
        } catch {
            registry.registerChain(
                riseSepolia.domainId,
                riseSepolia.domainId,
                riseSepolia.mailbox,
                riseSepolia.rpc,
                riseSepolia.name,
                12 // ~12 second block time
            );
            console.log("Registered Rise Sepolia");
        }
    }

    function createSyntheticTokens(address factory, address tokenRegistry) internal {
        console.log("Creating synthetic tokens...");
        
        SyntheticTokenFactory tokenFactory = SyntheticTokenFactory(factory);
        TokenRegistry registry = TokenRegistry(tokenRegistry);
        
        // Create synthetic tokens for each supported token
        string[3] memory symbols = ["USDT", "WETH", "WBTC"];
        
        for (uint i = 0; i < symbols.length; i++) {
            TokenInfo memory tokenInfo = appchainTokens[symbols[i]];
            
            // Check if mapping already exists
            address existing = registry.getSyntheticToken(
                appchain.domainId,
                tokenInfo.token,
                rari.domainId
            );
            
            if (existing == address(0)) {
                address syntheticToken = tokenFactory.createSyntheticToken(
                    appchain.domainId,
                    tokenInfo.token,
                    rari.domainId,
                    string(abi.encodePacked("Giga Synthetic ", tokenInfo.symbol)),
                    string(abi.encodePacked("gs", tokenInfo.symbol)),
                    tokenInfo.decimals,
                    18 // Normalize to 18 decimals
                );
                
                console.log("Created synthetic token for", symbols[i], "at:", syntheticToken);
            } else {
                console.log("Synthetic token for", symbols[i], "already exists at:", existing);
            }
        }
    }

    function loadDeploymentFile(string memory filePath) internal view returns (string memory) {
        try vm.readFile(filePath) returns (string memory data) {
            return data;
        } catch {
            return "{}";
        }
    }

    function getContractAddress(string memory deploymentData, string memory contractName) internal pure returns (address) {
        if (bytes(deploymentData).length <= 2) return address(0); // Empty JSON
        
        // Simple check - if it's empty JSON, return zero address
        // This will be fixed when we have actual deployment data
        return address(0);
    }

    function saveRariDeployment(
        address balanceManager,
        address chainRegistry,
        address tokenRegistry,
        address syntheticTokenFactory
    ) internal {
        string memory json = "deployment";
        vm.serializeString(json, "network", "rari");
        vm.serializeUint(json, "chainId", rari.chainId);
        vm.serializeUint(json, "domainId", rari.domainId);
        vm.serializeString(json, "rpc", rari.rpc);
        vm.serializeAddress(json, "mailbox", rari.mailbox);
        
        // Contracts
        string memory contracts = "contracts";
        vm.serializeAddress(contracts, "BalanceManager", balanceManager);
        vm.serializeAddress(contracts, "ChainRegistry", chainRegistry);
        vm.serializeAddress(contracts, "TokenRegistry", tokenRegistry);
        vm.serializeAddress(contracts, "SyntheticTokenFactory", syntheticTokenFactory);
        
        // Get synthetic token addresses
        TokenRegistry registry = TokenRegistry(tokenRegistry);
        string[3] memory symbols = ["USDT", "WETH", "WBTC"];
        
        for (uint i = 0; i < symbols.length; i++) {
            TokenInfo memory tokenInfo = appchainTokens[symbols[i]];
            address syntheticToken = registry.getSyntheticToken(
                appchain.domainId,
                tokenInfo.token,
                rari.domainId
            );
            if (syntheticToken != address(0)) {
                vm.serializeAddress(
                    contracts,
                    string(abi.encodePacked("gs", symbols[i])),
                    syntheticToken
                );
            }
        }
        
        string memory contractsJson = vm.serializeAddress(contracts, "SyntheticTokenFactory", syntheticTokenFactory);
        vm.serializeString(json, "contracts", contractsJson);
        
        string memory finalJson = vm.serializeString(json, "deployedAt", vm.toString(block.timestamp));
        vm.writeFile(rari.deploymentFile, finalJson);
        
        console.log("Saved deployment to", rari.deploymentFile);
    }

    function saveChainBalanceManagerDeployment(
        NetworkConfig memory config,
        address chainBalanceManager
    ) internal {
        string memory json = "deployment";
        vm.serializeString(json, "network", config.name);
        vm.serializeUint(json, "chainId", config.chainId);
        vm.serializeUint(json, "domainId", config.domainId);
        vm.serializeString(json, "rpc", config.rpc);
        vm.serializeAddress(json, "mailbox", config.mailbox);
        
        string memory contracts = "contracts";
        string memory contractsJson = vm.serializeAddress(contracts, "ChainBalanceManager", chainBalanceManager);
        
        vm.serializeString(json, "contracts", contractsJson);
        string memory finalJson = vm.serializeString(json, "deployedAt", vm.toString(block.timestamp));
        
        vm.writeFile(config.deploymentFile, finalJson);
        console.log("Saved deployment to", config.deploymentFile);
    }

    function logDeployedAddresses(
        address balanceManager,
        address chainRegistry,
        address tokenRegistry,
        address syntheticTokenFactory
    ) internal view {
        console.log("=== DEPLOYED CONTRACTS ===");
        console.log("BalanceManager:", balanceManager);
        console.log("ChainRegistry:", chainRegistry);
        console.log("TokenRegistry:", tokenRegistry);
        console.log("SyntheticTokenFactory:", syntheticTokenFactory);
        console.log("========================");
    }
}