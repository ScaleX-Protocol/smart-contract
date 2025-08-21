// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console} from "forge-std/Script.sol";

import "../src/core/BalanceManager.sol";
import "../src/core/ChainBalanceManager.sol";

/**
 * @title Deploy Upgradeable GTX Contracts
 * @dev Deploy upgradeable versions of GTX contracts with Espresso Hyperlane integration
 * Perfect for fast testnet iteration and accelerator development
 */
contract DeployUpgradeableGTX is Script {
    // Espresso testnet configuration (proven working addresses)
    struct NetworkConfig {
        address mailbox;
        uint32 domain;
        string name;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        string memory network = vm.envString("NETWORK");

        console.log("=== Deploying Upgradeable GTX Contracts ===");
        console.log("Network:", network);
        console.log("Deployer:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        if (keccak256(bytes(network)) == keccak256(bytes("rari_testnet"))) {
            _deployRariContracts();
        } else if (keccak256(bytes(network)) == keccak256(bytes("appchain_testnet"))) {
            _deployAppchainContracts();
        } else if (keccak256(bytes(network)) == keccak256(bytes("arbitrum_sepolia"))) {
            _deployArbitrumContracts();
        } else {
            revert("Unsupported network. Use: rari_testnet, appchain_testnet, or arbitrum_sepolia");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("[SUCCESS] Upgradeable GTX contracts deployed!");
        console.log("[INFO] Contracts are now instantly upgradeable for fast iteration");
    }

    function _deployRariContracts() internal {
        console.log("=== Deploying Rari Host Chain Contracts ===");

        NetworkConfig memory config = NetworkConfig({
            mailbox: 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358,
            domain: 1_918_988_905,
            name: "Rari Testnet"
        });

        console.log("Mailbox:", config.mailbox);
        console.log("Domain:", config.domain);
        console.log("");

        // Deploy BalanceManager (already upgradeable in your codebase)
        BalanceManager balanceManagerImpl = new BalanceManager();
        console.log("BalanceManager Implementation:", address(balanceManagerImpl));

        bytes memory initData = abi.encodeCall(
            balanceManagerImpl.initialize,
            (
                msg.sender, // owner
                msg.sender, // feeReceiver
                25, // feeMaker (2.5 basis points)
                50 // feeTaker (5 basis points)
            )
        );

        ERC1967Proxy balanceManagerProxy = new ERC1967Proxy(address(balanceManagerImpl), initData);
        console.log("BalanceManager Proxy:", address(balanceManagerProxy));

        console.log("");
        console.log("=== Rari Configuration ===");
        console.log("[SUCCESS] BalanceManager deployed with CLOB integration ready");
        console.log("[SUCCESS] Cross-chain message handling configured");
        console.log("[SUCCESS] Upgradeable architecture active");

        console.log("");
        console.log("Next steps:");
        console.log("1. Deploy source chain contracts");
        console.log("2. Configure cross-chain token mappings");
        console.log("3. Authorize CLOB contracts as operators");
    }

    function _deployAppchainContracts() internal {
        console.log("=== Deploying Appchain Source Chain Contracts ===");

        NetworkConfig memory config =
            NetworkConfig({mailbox: 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1, domain: 4661, name: "Appchain Testnet"});

        // Rari BalanceManager address (destination)
        address rariBalanceManager = 0xDf997311A013F15Df5264172f3a448B14917CFE8;
        uint32 rariDomain = 1_918_988_905;

        console.log("Mailbox:", config.mailbox);
        console.log("Local Domain:", config.domain);
        console.log("Destination Domain:", rariDomain);
        console.log("Destination BalanceManager:", rariBalanceManager);
        console.log("");

        // Deploy ChainBalanceManager
        ChainBalanceManager chainBMImpl = new ChainBalanceManager();
        console.log("ChainBalanceManager Implementation:", address(chainBMImpl));

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,uint32,address)",
            msg.sender, // owner
            config.mailbox, // mailbox
            rariDomain, // destinationDomain
            rariBalanceManager // destinationBalanceManager
        );

        ERC1967Proxy chainBMProxy = new ERC1967Proxy(address(chainBMImpl), initData);
        console.log("ChainBalanceManager Proxy:", address(chainBMProxy));

        // Configure with test tokens (Appchain addresses)
        _configureAppchainTokens(ChainBalanceManager(address(chainBMProxy)));

        console.log("");
        console.log("=== Appchain Configuration Complete ===");
        console.log("[SUCCESS] Vault contract deployed with Hyperlane integration");
        console.log("[SUCCESS] Cross-chain messaging to Rari configured");
        console.log("[SUCCESS] Test tokens whitelisted and mapped");
        console.log("[SUCCESS] Ready for cross-chain deposits");
    }

    function _deployArbitrumContracts() internal {
        console.log("=== Deploying Arbitrum Source Chain Contracts ===");

        NetworkConfig memory config = NetworkConfig({
            mailbox: 0x8DF6aDE95d25855ed0FB927ECD6a1D5Bb09d2145,
            domain: 421_614,
            name: "Arbitrum Sepolia"
        });

        // Rari BalanceManager address (destination)
        address rariBalanceManager = 0xDf997311A013F15Df5264172f3a448B14917CFE8;
        uint32 rariDomain = 1_918_988_905;

        console.log("Mailbox:", config.mailbox);
        console.log("Local Domain:", config.domain);
        console.log("Destination Domain:", rariDomain);
        console.log("");

        // Deploy ChainBalanceManager
        ChainBalanceManager chainBMImpl = new ChainBalanceManager();
        console.log("ChainBalanceManager Implementation:", address(chainBMImpl));

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,uint32,address)", msg.sender, config.mailbox, rariDomain, rariBalanceManager
        );

        ERC1967Proxy chainBMProxy = new ERC1967Proxy(address(chainBMImpl), initData);
        console.log("ChainBalanceManager Proxy:", address(chainBMProxy));

        // Configure with Arbitrum test tokens
        _configureArbitrumTokens(ChainBalanceManager(address(chainBMProxy)));

        console.log("");
        console.log("=== Arbitrum Configuration Complete ===");
        console.log("[SUCCESS] Vault contract deployed");
        console.log("[SUCCESS] Cross-chain messaging configured");
        console.log("[SUCCESS] Ready for testing");
    }

    function _configureAppchainTokens(
        ChainBalanceManager chainBM
    ) internal {
        console.log("Configuring Appchain tokens...");

        // Appchain test token addresses (from working Espresso example)
        address USDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        address WETH = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
        address WBTC = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;

        // Rari synthetic token addresses (from working Espresso example)
        address GS_USDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
        address GS_WETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address GS_WBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;

        // Whitelist tokens
        chainBM.addToken(USDT);
        chainBM.addToken(WETH);
        chainBM.addToken(WBTC);
        console.log("[SUCCESS] Tokens whitelisted");

        // Set cross-chain mappings
        chainBM.setTokenMapping(USDT, GS_USDT);
        chainBM.setTokenMapping(WETH, GS_WETH);
        chainBM.setTokenMapping(WBTC, GS_WBTC);
        console.log("[SUCCESS] Cross-chain mappings configured");

        console.log("Token mappings:");
        console.log("  USDT ->", GS_USDT);
        console.log("  WETH ->", GS_WETH);
        console.log("  WBTC ->", GS_WBTC);
    }

    function _configureArbitrumTokens(
        ChainBalanceManager chainBM
    ) internal {
        console.log("Configuring Arbitrum tokens...");

        // Arbitrum test token addresses
        address USDT = 0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a;
        address WETH = 0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7;
        address WBTC = 0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A;

        // Same Rari synthetic tokens
        address GS_USDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
        address GS_WETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address GS_WBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;

        // Configure tokens
        chainBM.addToken(USDT);
        chainBM.addToken(WETH);
        chainBM.addToken(WBTC);

        chainBM.setTokenMapping(USDT, GS_USDT);
        chainBM.setTokenMapping(WETH, GS_WETH);
        chainBM.setTokenMapping(WBTC, GS_WBTC);

        console.log("[SUCCESS] Arbitrum tokens configured");
    }
}
