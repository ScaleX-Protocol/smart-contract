// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Oracle} from "../../src/core/Oracle.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Real OrderBook mock that supports real-time trading
contract MockRealTimeOrderBook {
    struct MockPriceVolume {
        uint128 price;
        uint256 volume;
    }
    
    mapping(uint8 => MockPriceVolume) public bestPrices; // 0=BUY, 1=SELL
    
    // Oracle integration
    Oracle public oracle;
    address public token;
    uint256 public constant MIN_TRADE_VOLUME = 1000 * 1e6;
    
    // Trade tracking
    uint256 public totalTrades;
    uint256 public lastTradePrice;
    uint256 public lastTradeVolume;
    
    event TradeExecuted(uint128 price, uint256 volume, uint256 timestamp);
    
    function setOracle(Oracle _oracle, address _token) external {
        oracle = _oracle;
        token = _token;
    }
    
    function setBestPrice(uint8 side, uint128 price, uint256 volume) external {
        bestPrices[side] = MockPriceVolume(price, volume);
    }
    
    // Implement IOrderBook interface
    function getBestPrice(uint8 side) external view returns (IOrderBook.PriceVolume memory) {
        MockPriceVolume memory mockPrice = bestPrices[side];
        return IOrderBook.PriceVolume(mockPrice.price, mockPrice.volume);
    }
    
    function executeMockTrade(uint128 price, uint256 volume) external {
        // Simulate trade execution
        lastTradePrice = price;
        lastTradeVolume = volume;
        totalTrades++;
        
        // Update Oracle in real-time
        try oracle.updatePriceFromTrade(token, price, volume) {
            emit TradeExecuted(price, volume, block.timestamp);
        } catch Error(string memory reason) {
            console.log("Oracle update failed:", reason);
        } catch {
            console.log("Oracle update failed: unknown error");
        }
    }
    
    function getQuoteCurrency() external view returns (address) {
        return token;
    }

    function getOrderQueue(uint8 side, uint128 price) external pure returns (uint48 orderCount, uint256 totalVolume) {
        return (1, 1000 * 1e6);
    }

    // Minimal implementations for other required functions
    function initialize(address, address, address, address, address) external pure {}
    function placeOrder(address, uint128, uint128, uint128, uint8, uint8, uint48, address) external pure returns (uint48) { return 1; }
    function cancelOrder(uint48, address) external pure {}
    function placeMarketOrder(uint128, uint8, address) external pure returns (uint48, uint128) { return (1, 1); }
    function getNextBestPrices(uint8, uint128, uint8) external pure returns (IOrderBook.PriceVolume[] memory) { return new IOrderBook.PriceVolume[](0); }
    function getTradingRules() external pure returns (IOrderBook.TradingRules memory) { 
        return IOrderBook.TradingRules(1, 1, uint128(MIN_TRADE_VOLUME), 100); 
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
    
    function getChainTokens(uint32 /* sourceChainId */) external pure returns (address[] memory) {
        return new address[](0);
    }
    
    function getSyntheticToken(uint32 /* sourceChainId */, address /* sourceToken */, uint32 /* targetChainId */) external pure returns (address) {
        return address(0);
    }
}

contract RealTimeOracleTest is Test {
    Oracle public oracle;
    MockRealTimeOrderBook public mockOrderBook;
    MockTokenRegistry public mockTokenRegistry;
    MockToken public token;
    
    address public owner = address(0x1);
    address public trader = address(0x2);
    
    function setUp() public {
        mockOrderBook = new MockRealTimeOrderBook();
        mockTokenRegistry = new MockTokenRegistry();
        token = new MockToken("Test Token", "TEST", 6);
        
        mockTokenRegistry.addSupportedToken(address(token));
        
        vm.startPrank(owner);
        // Deploy Oracle using ERC1967Proxy pattern
        ERC1967Proxy oracleProxy = new ERC1967Proxy(
            address(new Oracle()),
            abi.encodeWithSelector(
                Oracle.initialize.selector,
                owner,
                address(mockTokenRegistry)
            )
        );
        oracle = Oracle(address(oracleProxy));
        oracle.addToken(address(token), 1);
        oracle.setTokenOrderBook(address(token), address(mockOrderBook));
        
        // Connect OrderBook to Oracle
        mockOrderBook.setOracle(oracle, address(token));
        vm.stopPrank();
    }
    
    function testRealTimePriceUpdate() public {
        // Set up market prices
        mockOrderBook.setBestPrice(0, uint128(2000 * 1e6), 1000 * 1e6);
        mockOrderBook.setBestPrice(1, uint128(2010 * 1e6), 1000 * 1e6);
        
        // Initially, Oracle should have no price (no trades yet)
        uint256 spotPriceBefore = oracle.getSpotPrice(address(token));
        assertEq(spotPriceBefore, 0);
        
        // Execute a trade
        uint128 tradePrice = 2005 * 1e6;
        uint256 tradeVolume = 1500 * 1e6;
        
        vm.prank(trader);
        mockOrderBook.executeMockTrade(tradePrice, tradeVolume);
        
        // Oracle should now have the trade price
        uint256 spotPriceAfter = oracle.getSpotPrice(address(token));
        assertEq(spotPriceAfter, uint256(tradePrice));
        
        console.log("Trade executed at:", tradePrice);
        console.log("Oracle spot price:", spotPriceAfter);
    }
    
    function testRealTimeTWAPCalculation() public {
        // Set up initial market
        mockOrderBook.setBestPrice(0, uint128(2000 * 1e6), 1000 * 1e6);
        mockOrderBook.setBestPrice(1, uint128(2010 * 1e6), 1000 * 1e6);
        
        // Execute first trade
        vm.prank(trader);
        mockOrderBook.executeMockTrade(2005 * 1e6, 1500 * 1e6);
        
        // Advance time
        vm.warp(block.timestamp + 10 minutes);
        
        // Execute second trade
        vm.prank(trader);
        mockOrderBook.executeMockTrade(2008 * 1e6, 1200 * 1e6);
        
        // TWAP should reflect trades
        uint256 twap = oracle.getTWAP(address(token), 10 minutes);
        assertGt(twap, 0);
        
        console.log("TWAP (10min):", twap);
        console.log("Total trades:", mockOrderBook.totalTrades());
    }
    
    function testMinimumTradeVolumeFilter() public {
        // Set minimum trade volume threshold on the oracle
        vm.prank(owner);
        oracle.setMinTradeVolume(1000 * 1e6);

        // Try to execute trade below minimum volume
        uint256 smallVolume = 500 * 1e6; // Below MIN_TRADE_VOLUME (1000 * 1e6)

        vm.prank(trader);
        mockOrderBook.executeMockTrade(2005 * 1e6, smallVolume);

        // Oracle should not be updated (price should still be 0)
        uint256 spotPrice = oracle.getSpotPrice(address(token));
        assertEq(spotPrice, 0);
        
        console.log("Small trade volume:", smallVolume);
        console.log("Oracle price after small trade:", spotPrice);
    }
    
    function testOracleSpecializedPricingAfterRealTrades() public {
        // Set up market and execute trades
        mockOrderBook.setBestPrice(0, uint128(1998 * 1e6), 2000 * 1e6);
        mockOrderBook.setBestPrice(1, uint128(2012 * 1e6), 2000 * 1e6);
        
        // Execute trade
        vm.prank(trader);
        mockOrderBook.executeMockTrade(2000 * 1e6, 1500 * 1e6);
        
        // Test specialized pricing
        uint256 collateralPrice = oracle.getPriceForCollateral(address(token));
        uint256 confidence = oracle.getPriceConfidence(address(token));
        
        assertGt(collateralPrice, 0);
        assertGt(confidence, 0);
        
        console.log("Collateral Price (from real trade):", collateralPrice);
        console.log("Price Confidence:", confidence);
    }
}

contract MaliciousUpdater {
    function attemptOracleUpdate(
        address oracleAddr,
        address token,
        uint128 price,
        uint256 volume
    ) external {
        Oracle(oracleAddr).updatePriceFromTrade(token, price, volume);
    }
}