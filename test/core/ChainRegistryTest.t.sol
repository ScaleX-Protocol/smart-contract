// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import {ChainRegistry} from "../../src/core/ChainRegistry.sol";

contract ChainRegistryTest is Test {
    ChainRegistry chainRegistry;
    address owner = makeAddr("owner");
    
    function setUp() public {
        vm.startPrank(owner);
        
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy proxy,) = beaconDeployer.deployUpgradeableContract(
            address(new ChainRegistry()),
            owner,
            abi.encodeCall(ChainRegistry.initialize, (owner))
        );
        
        chainRegistry = ChainRegistry(address(proxy));
        
        vm.stopPrank();
    }
    
    function test_DefaultChainsRegistered() public {
        // Test Rari Testnet
        uint32[] memory chains = chainRegistry.getAllChains();
        assertEq(chains.length, 4); // 4 default chains
        
        // Check Rari configuration
        ChainRegistry.ChainConfig memory rariConfig = chainRegistry.getChainConfig(1918988905);
        assertEq(rariConfig.domainId, 1918988905);
        assertEq(rariConfig.mailbox, 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358);
        assertEq(rariConfig.name, "Rari Testnet");
        assertTrue(rariConfig.isActive);
        
        // Check Appchain configuration
        ChainRegistry.ChainConfig memory appchainConfig = chainRegistry.getChainConfig(4661);
        assertEq(appchainConfig.domainId, 4661);
        assertEq(appchainConfig.mailbox, 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1);
        assertEq(appchainConfig.name, "Appchain Testnet");
    }
    
    function test_RegisterNewChain() public {
        vm.startPrank(owner);
        
        uint32 newChainId = 999;
        uint32 newDomainId = 999;
        address newMailbox = makeAddr("newMailbox");
        
        chainRegistry.registerChain(
            newChainId,
            newDomainId,
            newMailbox,
            "https://new-chain.example.com",
            "New Chain",
            3
        );
        
        ChainRegistry.ChainConfig memory config = chainRegistry.getChainConfig(newChainId);
        assertEq(config.domainId, newDomainId);
        assertEq(config.mailbox, newMailbox);
        assertEq(config.name, "New Chain");
        assertTrue(config.isActive);
        
        vm.stopPrank();
    }
    
    function test_GetMailboxAndDomain() public {
        // Test mailbox retrieval
        address rariMailbox = chainRegistry.getMailbox(1918988905);
        assertEq(rariMailbox, 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358);
        
        // Test domain retrieval
        uint32 appchainDomain = chainRegistry.getDomainId(4661);
        assertEq(appchainDomain, 4661);
        
        // Test reverse lookup
        uint32 chainByDomain = chainRegistry.getChainByDomain(1918988905);
        assertEq(chainByDomain, 1918988905);
    }
    
    function test_ActiveChains() public {
        uint32[] memory activeChains = chainRegistry.getActiveChains();
        assertEq(activeChains.length, 4); // All default chains are active
        
        vm.startPrank(owner);
        
        // Deactivate one chain
        chainRegistry.setChainStatus(4661, false);
        
        activeChains = chainRegistry.getActiveChains();
        assertEq(activeChains.length, 3); // One less active
        
        assertFalse(chainRegistry.isChainActive(4661));
        
        vm.stopPrank();
    }
}