// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Oracle} from "../../src/core/Oracle.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockTokenRegistry {
    address[] public supportedTokens;
    mapping(address => bool) public isSupported;
    
    function addSupportedToken(address token) external {
        if (!isSupported[token]) {
            supportedTokens.push(token);
            isSupported[token] = true;
        }
    }
    
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }
    
    function isTokenSupported(address token) external view returns (bool) {
        return isSupported[token];
    }
    
    function getChainTokens(uint32) external pure returns (address[] memory) {
        return new address[](0);
    }
    
    function getSyntheticToken(uint32, address, uint32) external pure returns (address) {
        return address(0);
    }
    
    function getSyntheticTokenForUser(uint32, address, uint32, address) external pure returns (address) {
        return address(0);
    }
}

contract BasicOracleTest is Test {
    Oracle public oracle;
    MockTokenRegistry public tokenRegistry;
    MockToken public token;
    
    address public owner = address(0x1);
    
    function setUp() public {
        token = new MockToken("Test Token", "TEST", 6);
        tokenRegistry = new MockTokenRegistry();
        tokenRegistry.addSupportedToken(address(token));
        
        vm.startPrank(owner);
        // Deploy Oracle implementation
        address oracleImpl = address(new Oracle());
        
        // Deploy proxy with initialization data
        ERC1967Proxy proxy = new ERC1967Proxy(
            oracleImpl,
            abi.encodeWithSelector(
                Oracle.initialize.selector,
                owner,
                address(tokenRegistry)
            )
        );
        oracle = Oracle(address(proxy));
        
        oracle.addToken(address(token), 1);
        vm.stopPrank();
    }
    
    function testOracleInitialization() public {
        // Test basic Oracle functionality
        assertTrue(address(oracle) != address(0));
        
        // Test token support
        address[] memory supportedTokens = oracle.getAllSupportedTokens();
        assertEq(supportedTokens.length, 1);
        assertEq(supportedTokens[0], address(token));
        
        console.log("Oracle initialized successfully with 1 token");
    }
    
    function testBasicPriceFunctions() public {
        // Test that price functions work (even if they return 0 initially)
        uint256 spotPrice = oracle.getSpotPrice(address(token));
        
        // Should return 0 since no OrderBook is configured
        assertEq(spotPrice, 0);
        
        // Test TWAP functions
        uint256 twap5m = oracle.getTWAP(address(token), 5 minutes);
        assertEq(twap5m, 0);
        
        // Test specialized pricing
        uint256 collateralPrice = oracle.getPriceForCollateral(address(token));
        uint256 borrowingPrice = oracle.getPriceForBorrowing(address(token));
        
        assertEq(collateralPrice, 0);
        assertEq(borrowingPrice, 0);
        
        console.log("All price functions working correctly");
    }
    
    function testOracleHealthCheck() public {
        // Test Oracle health functions
        (bool healthy, uint256 confidence, bool stale, bool hasHistory, string memory issue) = 
            oracle.getOracleHealth(address(token));
        
        // Should be unhealthy due to no price history
        assertFalse(healthy);
        assertEq(confidence, 0);
        assertTrue(stale); // No updates, so considered stale
        assertFalse(hasHistory);
        
        console.log("Oracle health check working:", issue);
    }
    
    function testUnauthorizedUpdate() public {
        // Try to update price from unauthorized address
        vm.prank(address(0x999));
        vm.expectRevert();
        oracle.updatePriceFromTrade(address(token), 2000 * 1e6, 1000 * 1e6);
        
        console.log("Unauthorized update correctly rejected");
    }
}