// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {BeaconDeployer} from "../core/helpers/BeaconDeployer.t.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {SyntheticTokenFactory} from "../../src/core/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";

/**
 * @title SyntheticTokenIntegrationTest
 * @dev Test synthetic token creation and management
 */
contract SyntheticTokenIntegrationTest is Test {
    
    TokenRegistry tokenRegistry;
    SyntheticTokenFactory factory;
    address bridgeReceiver = makeAddr("bridgeReceiver");
    address owner = makeAddr("owner");
    
    // Test constants (avoid conflicts with default mappings)
    uint32 constant SOURCE_CHAIN_ID = 5000;
    uint32 constant TARGET_CHAIN_ID = 6000;
    address testToken = makeAddr("testToken");
    
    function setUp() public {
        vm.startPrank(owner);
        
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        
        // Deploy TokenRegistry
        (BeaconProxy tokenRegistryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new TokenRegistry()),
            owner,
            abi.encodeCall(TokenRegistry.initialize, (owner))
        );
        tokenRegistry = TokenRegistry(address(tokenRegistryProxy));
        
        // Deploy SyntheticTokenFactory
        (BeaconProxy factoryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new SyntheticTokenFactory()),
            owner,
            abi.encodeCall(SyntheticTokenFactory.initialize, (
                owner,
                address(tokenRegistry),
                bridgeReceiver
            ))
        );
        factory = SyntheticTokenFactory(address(factoryProxy));
        
        // Transfer TokenRegistry ownership to Factory
        tokenRegistry.transferOwnership(address(factory));
        
        vm.stopPrank();
    }
    
    function test_CreateSyntheticToken() public {
        vm.startPrank(owner);
        
        address syntheticToken = factory.createSyntheticToken(
            SOURCE_CHAIN_ID,
            testToken,
            TARGET_CHAIN_ID,
            "Test Synthetic Token",
            "tsTOKEN",
            18,  // source decimals
            18   // synthetic decimals
        );
        
        // Verify token was created
        assertNotEq(syntheticToken, address(0));
        
        // Verify mapping was registered
        address retrievedToken = tokenRegistry.getSyntheticToken(
            SOURCE_CHAIN_ID,
            testToken,
            TARGET_CHAIN_ID
        );
        assertEq(retrievedToken, syntheticToken);
        
        // Verify token configuration
        SyntheticToken token = SyntheticToken(syntheticToken);
        assertEq(token.name(), "Test Synthetic Token");
        assertEq(token.symbol(), "tsTOKEN");
        assertEq(token.decimals(), 18);
        assertEq(token.bridgeSyntheticTokenReceiver(), bridgeReceiver);
        
        vm.stopPrank();
    }
    
    function test_TokenRegistryIntegration() public {
        vm.startPrank(owner);
        
        // Create token
        address syntheticToken = factory.createSyntheticToken(
            SOURCE_CHAIN_ID,
            testToken,
            TARGET_CHAIN_ID,
            "Test Token",
            "tTOKEN",
            18, 18
        );
        
        // Test reverse lookup
        (uint32 sourceChain, address sourceToken) = tokenRegistry.getSourceToken(
            TARGET_CHAIN_ID,
            syntheticToken
        );
        assertEq(sourceChain, SOURCE_CHAIN_ID);
        assertEq(sourceToken, testToken);
        
        // Test mapping is active
        bool isActive = tokenRegistry.isTokenMappingActive(
            SOURCE_CHAIN_ID,
            testToken,
            TARGET_CHAIN_ID
        );
        assertTrue(isActive);
        
        vm.stopPrank();
    }
    
    function test_DecimalConversion() public {
        // Test decimal conversions
        uint256 amount6 = 1000000; // 1 token with 6 decimals
        uint256 converted18 = tokenRegistry.convertAmount(amount6, 6, 18);
        assertEq(converted18, 1000000000000000000); // 1 * 10^18
        
        uint256 amount18 = 1 ether; // 1 token with 18 decimals  
        uint256 converted6 = tokenRegistry.convertAmount(amount18, 18, 6);
        assertEq(converted6, 1000000); // 1 * 10^6
        
        // Test same decimals
        uint256 sameDecimal = tokenRegistry.convertAmount(1000000, 6, 6);
        assertEq(sameDecimal, 1000000);
    }
    
    function test_FactoryConfiguration() public {
        assertEq(factory.getBridgeReceiver(), bridgeReceiver);
        assertEq(factory.getTokenRegistry(), address(tokenRegistry));
        assertEq(factory.owner(), owner);
        assertEq(tokenRegistry.owner(), address(factory));
    }
}