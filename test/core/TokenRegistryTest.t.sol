// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";

contract TokenRegistryTest is Test {
    TokenRegistry tokenRegistry;
    address owner = makeAddr("owner");
    
    function setUp() public {
        vm.startPrank(owner);

        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy proxy,) = beaconDeployer.deployUpgradeableContract(
            address(new TokenRegistry()),
            owner,
            abi.encodeCall(TokenRegistry.initialize, (owner))
        );

        tokenRegistry = TokenRegistry(address(proxy));

        // Register default token mappings that the tests expect
        // Appchain USDC -> Rari sxUSDC
        tokenRegistry.registerTokenMapping(
            4661, // Appchain
            0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516, // USDC
            1918988905, // Rari
            0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68, // sxUSDC
            "sxUSDC",
            6, // USDC decimals
            6  // sxUSDC decimals
        );

        // Appchain WETH -> Rari sxWETH
        tokenRegistry.registerTokenMapping(
            4661, // Appchain
            0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F, // WETH
            1918988905, // Rari
            0x835c8aa033972E372865FcC933c9de0A48B6Ae23, // sxWETH (example address)
            "sxWETH",
            18, // WETH decimals
            18  // sxWETH decimals
        );

        // Appchain WBTC -> Rari sxWBTC
        tokenRegistry.registerTokenMapping(
            4661, // Appchain
            0xb2e9Eabb827b78e2aC66bE17327603778D117d18, // WBTC
            1918988905, // Rari
            0x22F9a3898C3DB2a0008fe9a7524a4A41D8A789Df, // sxWBTC (example address)
            "sxWBTC",
            8, // WBTC decimals
            8  // sxWBTC decimals
        );

        // Activate all mappings
        tokenRegistry.setTokenMappingStatus(4661, 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516, 1918988905, true);
        tokenRegistry.setTokenMappingStatus(4661, 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F, 1918988905, true);
        tokenRegistry.setTokenMappingStatus(4661, 0xb2e9Eabb827b78e2aC66bE17327603778D117d18, 1918988905, true);

        vm.stopPrank();
    }
    
    function test_DefaultMappingsRegistered() public {
        // Test Appchain USDC -> Rari sxUSDC mapping
        address syntheticToken = tokenRegistry.getSyntheticToken(
            4661, // Appchain
            0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516, // USDC
            1918988905 // Rari
        );
        
        assertEq(syntheticToken, 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68); // sxUSDC
        
        // Test reverse lookup
        (uint32 sourceChainId, address sourceToken) = tokenRegistry.getSourceToken(
            1918988905, // Rari
            0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68 // sxUSDC
        );
        
        assertEq(sourceChainId, 4661);
        assertEq(sourceToken, 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516);
    }
    
    function test_TokenMappingActive() public {
        bool isActive = tokenRegistry.isTokenMappingActive(
            4661, // Appchain
            0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516, // USDC
            1918988905 // Rari
        );
        
        assertTrue(isActive);
    }
    
    function test_ConvertAmount() public {
        // Test same decimals
        uint256 result = tokenRegistry.convertAmount(1000000, 6, 6);
        assertEq(result, 1000000);
        
        // Test 6 to 18 decimals
        result = tokenRegistry.convertAmount(1000000, 6, 18); // 1 USDC
        assertEq(result, 1000000000000000000); // 1 * 10^18
        
        // Test 18 to 6 decimals
        result = tokenRegistry.convertAmount(1000000000000000000, 18, 6); // 1 ETH
        assertEq(result, 1000000); // 1 * 10^6
    }
    
    function test_GetChainTokens() public {
        address[] memory tokens = tokenRegistry.getChainTokens(4661); // Appchain
        assertEq(tokens.length, 3); // USDC, WETH, WBTC
        
        assertEq(tokens[0], 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516); // USDC
        assertEq(tokens[1], 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F); // WETH
        assertEq(tokens[2], 0xb2e9Eabb827b78e2aC66bE17327603778D117d18); // WBTC
    }
}