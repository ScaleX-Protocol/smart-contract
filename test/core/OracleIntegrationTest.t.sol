// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Oracle} from "../../src/core/Oracle.sol";
import {IOracle} from "../../src/core/interfaces/IOracle.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
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

contract MockOrderBook {
    IOracle public oracle;
    bool public shouldAuthorize = true;
    
    function setOracle(IOracle _oracle) external {
        oracle = _oracle;
    }
    
    function setShouldAuthorize(bool _shouldAuthorize) external {
        shouldAuthorize = _shouldAuthorize;
    }
    
    function updatePriceFromTrade(address token, uint128 price, uint256 volume) external {
        // Only update if authorized
        if (shouldAuthorize) {
            oracle.updatePriceFromTrade(token, price, volume);
        }
    }
    
    function getBestPrice(IOrderBook.Side) external pure returns (IOrderBook.PriceVolume memory) {
        return IOrderBook.PriceVolume(2005 * 1e6, 1000 * 1e6);
    }
}

contract OracleIntegrationTest is Test {
    Oracle public oracle;
    MockTokenRegistry public tokenRegistry;
    MockToken public token;
    MockOrderBook public mockOrderBook;
    
    address public owner = address(0x1);
    address public trader = address(0x2);
    
    function setUp() public {
        // Setup token and registry
        token = new MockToken("Test Token", "TEST", 6);
        tokenRegistry = new MockTokenRegistry();
        tokenRegistry.addSupportedToken(address(token));
        
        // Setup Oracle
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
        
        // Setup mock OrderBook
        mockOrderBook = new MockOrderBook();
        mockOrderBook.setOracle(oracle);
        
        // Configure Oracle to trust our mock OrderBook
        vm.startPrank(owner);
        oracle.setTokenOrderBook(address(token), address(mockOrderBook));
        vm.stopPrank();
    }
    
    function testOracleBasicFunctionality() public {
        // Test Oracle setup
        assertTrue(address(oracle) != address(0));
        
        // Test token support
        address[] memory supportedTokens = oracle.getAllSupportedTokens();
        assertEq(supportedTokens.length, 1);
        assertEq(supportedTokens[0], address(token));
        
        // Initially no price
        uint256 spotPrice = oracle.getSpotPrice(address(token));
        assertEq(spotPrice, 0);
        
        console.log("Oracle basic functionality test passed");
    }
    
    function testRealTimeOracleUpdate() public {
        // Verify initial state - no price data
        assertEq(oracle.getSpotPrice(address(token)), 0);
        
        // Simulate a trade from OrderBook
        uint128 tradePrice = 2005 * 1e6;
        uint256 tradeVolume = 1500 * 1e6; // Above MIN_TRADE_VOLUME (1000 * 1e6)
        
        // Mock OrderBook updates Oracle
        mockOrderBook.updatePriceFromTrade(address(token), tradePrice, tradeVolume);
        
        // Oracle should now have the price
        uint256 newSpotPrice = oracle.getSpotPrice(address(token));
        assertEq(newSpotPrice, uint256(tradePrice));
        
        console.log("Real-time Oracle update test passed");
        console.log("Trade price:", tradePrice);
        console.log("Oracle price:", newSpotPrice);
    }
    
    function testVolumeFiltering() public {
        // Try trade below minimum volume (1000 * 1e6)
        uint256 smallVolume = 500 * 1e6;
        
        // This should fail due to insufficient volume
        vm.expectRevert();
        mockOrderBook.updatePriceFromTrade(address(token), 2005 * 1e6, smallVolume);
        
        // Oracle should still have no price
        assertEq(oracle.getSpotPrice(address(token)), 0);
        
        console.log("Volume filtering test passed");
    }
    
    function testUnauthorizedUpdate() public {
        // Direct call to Oracle should fail
        vm.expectRevert();
        oracle.updatePriceFromTrade(address(token), 2005 * 1e6, 1500 * 1e6);
        
        console.log("Unauthorized update test passed");
    }
    
    function testSpecializedPricing() public {
        // Setup price data first
        mockOrderBook.updatePriceFromTrade(address(token), 2000 * 1e6, 1500 * 1e6);
        
        // Test specialized pricing functions
        uint256 collateralPrice = oracle.getPriceForCollateral(address(token));
        uint256 borrowingPrice = oracle.getPriceForBorrowing(address(token));
        uint256 confidence = oracle.getPriceConfidence(address(token));
        
        // All should return valid values
        assertGt(collateralPrice, 0);
        assertGt(borrowingPrice, 0);
        assertGt(confidence, 0);
        
        console.log("Specialized pricing test passed");
        console.log("Collateral price:", collateralPrice);
        console.log("Borrowing price:", borrowingPrice);
        console.log("Confidence:", confidence);
    }
    
    function testOracleHealthCheck() public {
        // Check health when no price data
        (bool healthy, uint256 confidence, bool stale, bool hasHistory, string memory issue) = 
            oracle.getOracleHealth(address(token));
        
        // Should be unhealthy due to no data
        assertFalse(healthy);
        assertEq(confidence, 0);
        assertTrue(stale);
        assertFalse(hasHistory);
        
        // Add initial price data
        mockOrderBook.updatePriceFromTrade(address(token), 2000 * 1e6, 1500 * 1e6);
        
        // Advance time to create sufficient history (15+ minutes)
        vm.warp(block.timestamp + 20 minutes + 1 seconds);
        
        // Add another price data point
        mockOrderBook.updatePriceFromTrade(address(token), 2001 * 1e6, 1500 * 1e6);
        
        // Check health again
        (healthy, confidence, stale, hasHistory, issue) = 
            oracle.getOracleHealth(address(token));
        
        // Should be healthy now
        assertTrue(healthy);
        assertGt(confidence, 0);
        assertFalse(stale);
        
        console.log("Oracle health check test passed");
        console.log("Health status:", healthy ? "HEALTHY" : "UNHEALTHY");
        console.log("Confidence:", confidence);
    }
}