// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Oracle} from "../../src/core/Oracle.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Very simple OrderBook mock for testing
contract SimpleOrderBook {
    Oracle public oracle;
    address public token;
    uint256 public minTradeVolume;
    
    event TradeExecuted(uint128 price, uint256 volume);
    
    function setup(Oracle _oracle, address _token, uint256 _minVolume) external {
        oracle = _oracle;
        token = _token;
        minTradeVolume = _minVolume;
    }
    
    function executeTrade(uint128 price, uint256 volume) external {
        if (volume >= minTradeVolume) {
            oracle.updatePriceFromTrade(token, price, volume);
            emit TradeExecuted(price, volume);
        }
    }
    
    function getQuoteCurrency() external view returns (address) {
        return token;
    }

    function getBestPrice(uint8) external pure returns (IOrderBook.PriceVolume memory) {
        return IOrderBook.PriceVolume(2005 * 1e6, 1000 * 1e6);
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
    
    function getChainTokens(uint32) external pure returns (address[] memory) {
        return new address[](0);
    }
    
    function getSyntheticToken(uint32, address, uint32) external pure returns (address) {
        return address(0);
    }
}

contract SimpleRealTimeOracleTest is Test {
    Oracle public oracle;
    SimpleOrderBook public orderBook;
    MockTokenRegistry public tokenRegistry;
    MockToken public token;
    
    address public owner = address(0x1);
    address public trader = address(0x2);
    uint256 public constant MIN_TRADE_VOLUME = 1000 * 1e6;
    
    function setUp() public {
        token = new MockToken("Test Token", "TEST", 6);
        tokenRegistry = new MockTokenRegistry();
        tokenRegistry.addSupportedToken(address(token));
        
        vm.startPrank(owner);
        // Deploy Oracle using ERC1967Proxy pattern
        ERC1967Proxy oracleProxy = new ERC1967Proxy(
            address(new Oracle()),
            abi.encodeWithSelector(
                Oracle.initialize.selector,
                owner,
                address(tokenRegistry)
            )
        );
        oracle = Oracle(address(oracleProxy));
        oracle.addToken(address(token), 1);
        
        orderBook = new SimpleOrderBook();
        orderBook.setup(oracle, address(token), MIN_TRADE_VOLUME);
        oracle.setTokenOrderBook(address(token), address(orderBook));
        vm.stopPrank();
    }
    
    function testRealTimeOracleUpdate() public {
        // Oracle should have no price initially
        uint256 priceBefore = oracle.getSpotPrice(address(token));
        assertEq(priceBefore, 0);
        
        // Execute a trade
        uint128 tradePrice = 2005 * 1e6;
        uint256 tradeVolume = 1500 * 1e6;
        
        vm.prank(trader);
        orderBook.executeTrade(tradePrice, tradeVolume);
        
        // Oracle should now have the trade price
        uint256 priceAfter = oracle.getSpotPrice(address(token));
        assertEq(priceAfter, uint256(tradePrice));
        
        console.log("Real-time Oracle price update successful!");
        console.log("Trade price:", tradePrice);
        console.log("Oracle price:", priceAfter);
    }
    
    function testInsufficientVolumeFilter() public {
        // Try trade below minimum volume
        uint256 smallVolume = 500 * 1e6; // Below MIN_TRADE_VOLUME
        
        vm.prank(trader);
        orderBook.executeTrade(2005 * 1e6, smallVolume);
        
        // Oracle should not be updated
        uint256 price = oracle.getSpotPrice(address(token));
        assertEq(price, 0);
        
        console.log("Minimum volume filter working!");
        console.log("Small volume trade filtered out");
    }
}