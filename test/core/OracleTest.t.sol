// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Oracle} from "../../src/core/Oracle.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Real OrderBook mock that implements the IOrderBook interface
contract MockOrderBook {
    struct MockPriceVolume {
        uint128 price;
        uint256 volume;
    }
    
    mapping(uint8 => MockPriceVolume) public bestPrices; // 0=BUY, 1=SELL
    
    function setBestPrice(uint8 side, uint128 price, uint256 volume) external {
        bestPrices[side] = MockPriceVolume(price, volume);
    }
    
    // Implement IOrderBook interface
    function getBestPrice(IOrderBook.Side side) external view returns (IOrderBook.PriceVolume memory) {
        MockPriceVolume memory mockPrice = bestPrices[uint8(side)];
        return IOrderBook.PriceVolume(mockPrice.price, mockPrice.volume);
    }
    
    function getOrderQueue(uint8 side, uint128 price) external pure returns (uint48 orderCount, uint256 totalVolume) {
        return (1, 1000 * 1e6); // Mock values
    }
    
    // Minimal implementations for other required functions
    function initialize(address, address, address, address, address) external pure {}
    function placeOrder(address, uint128, uint128, uint128, uint8, uint8, uint48, address) external pure returns (uint48) { return 1; }
    function cancelOrder(uint48, address) external pure {}
    function placeMarketOrder(uint128, uint8, address) external pure returns (uint48, uint128) { return (1, 1); }
    function getNextBestPrices(uint8, uint128, uint8) external pure returns (IOrderBook.PriceVolume[] memory) { return new IOrderBook.PriceVolume[](0); }
    function getTradingRules() external pure returns (IOrderBook.TradingRules memory) { 
        return IOrderBook.TradingRules(1, 1, 100, 100); 
    }
}

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
}

contract OracleTest is Test {
    Oracle public oracle;
    MockOrderBook public mockOrderBook;
    MockTokenRegistry public mockTokenRegistry;
    MockToken public token1;
    MockToken public token2;
    
    address public owner = address(0x1);
    
    function setUp() public {
        mockOrderBook = new MockOrderBook();
        mockTokenRegistry = new MockTokenRegistry();
        
        token1 = new MockToken("Token1", "T1", 18);
        token2 = new MockToken("Token2", "T2", 6);
        
        mockTokenRegistry.addSupportedToken(address(token1));
        mockTokenRegistry.addSupportedToken(address(token2));
        
        vm.startPrank(owner);
        // Deploy Oracle implementation
        address oracleImpl = address(new Oracle());
        
        // Deploy proxy with initialization data
        ERC1967Proxy proxy = new ERC1967Proxy(
            oracleImpl,
            abi.encodeWithSelector(
                Oracle.initialize.selector,
                owner,
                address(mockTokenRegistry)
            )
        );
        oracle = Oracle(address(proxy));
        
        // Add tokens to oracle
        oracle.addToken(address(token1), 1);
        oracle.addToken(address(token2), 2);
        
        // Set up OrderBooks for each token
        oracle.setTokenOrderBook(address(token1), address(mockOrderBook));
        oracle.setTokenOrderBook(address(token2), address(mockOrderBook));
        
        vm.stopPrank();
    }
    
    function testDeployment() public view {
        assertEq(address(oracle.tokenRegistry()), address(mockTokenRegistry));
        assertEq(oracle.owner(), owner);
        
        address[] memory supportedTokens = oracle.getAllSupportedTokens();
        assertEq(supportedTokens.length, 2);
        assertEq(supportedTokens[0], address(token1));
        assertEq(supportedTokens[1], address(token2));
    }
    
    function testSpotPrice() public {
        // Set real OrderBook prices
        mockOrderBook.setBestPrice(0, uint128(2000 * 1e6), 1000 * 1e6); // BID: $2000
        mockOrderBook.setBestPrice(1, uint128(2010 * 1e6), 1000 * 1e6); // ASK: $2010
        
        uint256 currentPrice = oracle.getCurrentPrice(address(token1));
        // Should return mid-price: ($2000 + $2010) / 2 = $2005
        assertEq(currentPrice, 2005 * 1e6);
    }
    
    function testUpdatePrice() public {
        // Set real OrderBook prices
        mockOrderBook.setBestPrice(0, uint128(2000 * 1e6), 1000 * 1e6); // BID
        mockOrderBook.setBestPrice(1, uint128(2010 * 1e6), 1000 * 1e6); // ASK
        
        vm.startPrank(owner);
        oracle.updatePrice(address(token1));
        vm.stopPrank();
        
        // Verify price was updated
        uint256 spotPrice = oracle.getSpotPrice(address(token1));
        assertEq(spotPrice, 2005 * 1e6); // Stored price from update
    }
    
    function testBasicPricing() public {
        // Set real OrderBook prices
        mockOrderBook.setBestPrice(0, uint128(2000 * 1e6), 1000 * 1e6); // BID
        mockOrderBook.setBestPrice(1, uint128(2010 * 1e6), 1000 * 1e6); // ASK
        
        vm.startPrank(owner);
        oracle.updatePrice(address(token1));
        vm.stopPrank();
        
        // Test specialized pricing
        uint256 collateralPrice = oracle.getPriceForCollateral(address(token1));
        uint256 borrowingPrice = oracle.getPriceForBorrowing(address(token1));
        uint256 confidence = oracle.getPriceConfidence(address(token1));
        
        assertEq(collateralPrice, 2005 * 1e6); // Mid-price
        assertEq(borrowingPrice, 2005 * 1e6); // Mid-price
        assertEq(confidence, 100); // Default high confidence for single price point
    }
    
    function testStalePriceDetection() public {
        // Set up real OrderBook prices
        mockOrderBook.setBestPrice(0, uint128(2000 * 1e6), 1000 * 1e6); // BID
        mockOrderBook.setBestPrice(1, uint128(2010 * 1e6), 1000 * 1e6); // ASK
        
        vm.startPrank(owner);
        oracle.updatePrice(address(token1));
        vm.stopPrank();
        
        // Advance time beyond stale threshold
        vm.warp(block.timestamp + 2 hours);
        
        bool isStale = oracle.isPriceStale(address(token1));
        assertEq(isStale, true);
    }
    
    function testTokenManagement() public {
        // Test adding new token
        MockToken token3 = new MockToken("Token3", "T3", 18);
        mockTokenRegistry.addSupportedToken(address(token3));
        
        vm.startPrank(owner);
        oracle.addToken(address(token3), 3);
        vm.stopPrank();
        
        address[] memory supportedTokens = oracle.getAllSupportedTokens();
        assertEq(supportedTokens.length, 3);
        
        // Test removing token
        vm.startPrank(owner);
        oracle.removeToken(address(token3));
        vm.stopPrank();
        
        supportedTokens = oracle.getAllSupportedTokens();
        assertEq(supportedTokens.length, 2);
    }
    
    function testUpdatePricesForAllTokens() public {
        // Set OrderBook prices for both tokens (using the same mock OrderBook)
        mockOrderBook.setBestPrice(0, uint128(2000 * 1e6), 1000 * 1e6); // BID
        mockOrderBook.setBestPrice(1, uint128(2010 * 1e6), 1000 * 1e6); // ASK
        
        vm.startPrank(owner);
        oracle.updatePricesForAllTokens();
        vm.stopPrank();
        
        // Both tokens should get the same price from the shared OrderBook
        uint256 price1 = oracle.getCurrentPrice(address(token1));
        uint256 price2 = oracle.getCurrentPrice(address(token2));
        
        assertEq(price1, 2005 * 1e6); // Mid-price of $2005
        assertEq(price2, 2005 * 1e6); // Same OrderBook, same price
    }
    
    function testUnsupportedToken() public {
        MockToken unsupportedToken = new MockToken("Unsupported", "UNS", 18);
        
        vm.expectRevert(abi.encodeWithSelector(Oracle.TokenNotSupported.selector, address(unsupportedToken)));
        oracle.getSpotPrice(address(unsupportedToken));
    }
    
    function testNoLiquidity() public {
        // Don't set any OrderBook prices
        uint256 currentPrice = oracle.getCurrentPrice(address(token1));
        assertEq(currentPrice, 0); // Should return 0 when no liquidity
    }
    
    function testOneSidedMarket() public {
        // Only set bid prices, no ask prices
        mockOrderBook.setBestPrice(0, uint128(2000 * 1e6), 1000 * 1e6); // BID only
        
        uint256 currentPrice = oracle.getCurrentPrice(address(token1));
        assertEq(currentPrice, 2000 * 1e6); // Should return bid price
        
        // Clear and set only ask prices
        mockOrderBook.setBestPrice(0, 0, 0); // Clear BID
        mockOrderBook.setBestPrice(1, uint128(2010 * 1e6), 1000 * 1e6); // ASK only
        
        currentPrice = oracle.getCurrentPrice(address(token1));
        assertEq(currentPrice, 2010 * 1e6); // Should return ask price
    }
}