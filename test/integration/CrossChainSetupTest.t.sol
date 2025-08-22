// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {BeaconDeployer} from "../core/helpers/BeaconDeployer.t.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {ChainRegistry} from "../../src/core/ChainRegistry.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {SyntheticTokenFactory} from "../../src/core/SyntheticTokenFactory.sol";

/**
 * @title CrossChainSetupTest
 * @dev Test basic deployment and configuration of cross-chain infrastructure
 */
contract CrossChainSetupTest is Test {
    
    BalanceManager balanceManager;
    ChainRegistry chainRegistry;
    TokenRegistry tokenRegistry;
    SyntheticTokenFactory factory;
    
    address owner = makeAddr("owner");
    
    // Espresso testnet constants
    uint32 constant RARI_CHAIN_ID = 1918988905;
    uint32 constant RARI_DOMAIN_ID = 1918988905;
    address constant RARI_MAILBOX = 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358;
    
    uint32 constant APPCHAIN_CHAIN_ID = 4661;
    uint32 constant APPCHAIN_DOMAIN_ID = 4661;
    address constant APPCHAIN_MAILBOX = 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1;
    
    function setUp() public {
        vm.startPrank(owner);
        
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        
        // Deploy BalanceManager
        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, owner, 5, 10))
        );
        balanceManager = BalanceManager(address(balanceManagerProxy));
        
        // Deploy ChainRegistry
        (BeaconProxy chainRegistryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new ChainRegistry()),
            owner,
            abi.encodeCall(ChainRegistry.initialize, (owner))
        );
        chainRegistry = ChainRegistry(address(chainRegistryProxy));
        
        // Deploy TokenRegistry
        (BeaconProxy tokenRegistryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new TokenRegistry()),
            owner,
            abi.encodeCall(TokenRegistry.initialize, (owner))
        );
        tokenRegistry = TokenRegistry(address(tokenRegistryProxy));
        
        // Deploy SyntheticTokenFactory with BalanceManager as bridge receiver
        (BeaconProxy factoryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new SyntheticTokenFactory()),
            owner,
            abi.encodeCall(SyntheticTokenFactory.initialize, (
                owner,
                address(tokenRegistry),
                address(balanceManager)
            ))
        );
        factory = SyntheticTokenFactory(address(factoryProxy));
        
        // Transfer TokenRegistry ownership to Factory
        tokenRegistry.transferOwnership(address(factory));
        
        vm.stopPrank();
    }
    
    function test_ContractsDeployedCorrectly() public {
        assertNotEq(address(balanceManager), address(0));
        assertNotEq(address(chainRegistry), address(0));
        assertNotEq(address(tokenRegistry), address(0));
        assertNotEq(address(factory), address(0));
        
        // Verify ownership setup
        assertEq(balanceManager.owner(), owner);
        assertEq(chainRegistry.owner(), owner);
        assertEq(tokenRegistry.owner(), address(factory));
        assertEq(factory.owner(), owner);
    }
    
    function test_BridgeReceiverConfiguration() public {
        // Verify BalanceManager is set as bridge receiver
        assertEq(factory.getBridgeReceiver(), address(balanceManager));
        assertEq(factory.getTokenRegistry(), address(tokenRegistry));
    }
    
    function test_CrossChainConfiguration() public {
        vm.startPrank(owner);
        
        // Initialize cross-chain functionality
        balanceManager.initializeCrossChain(RARI_MAILBOX, RARI_DOMAIN_ID);
        
        // Verify configuration
        (address mailbox, uint32 localDomain) = balanceManager.getMailboxConfig();
        assertEq(mailbox, RARI_MAILBOX);
        assertEq(localDomain, RARI_DOMAIN_ID);
        
        vm.stopPrank();
    }
    
    function test_ChainRegistryFunctionality() public {
        vm.startPrank(owner);
        
        // Test chain registration (if not already exists)
        uint32[] memory existingChains = chainRegistry.getAllChains();
        bool rariExists = false;
        for (uint256 i = 0; i < existingChains.length; i++) {
            if (existingChains[i] == RARI_CHAIN_ID) {
                rariExists = true;
                break;
            }
        }
        
        if (!rariExists) {
            chainRegistry.registerChain(
                RARI_CHAIN_ID,
                RARI_DOMAIN_ID,
                RARI_MAILBOX,
                "https://rari.caff.testnet.espresso.network",
                "Rari Testnet",
                2
            );
        }
        
        // Verify chain is active
        assertTrue(chainRegistry.isChainActive(RARI_CHAIN_ID));
        
        vm.stopPrank();
    }
}