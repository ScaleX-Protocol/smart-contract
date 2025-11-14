// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Oracle} from "../../src/core/Oracle.sol";
import {LendingManager} from "../../src/yield/LendingManager.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {BeaconDeployer} from "../core/helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract OracleLendingIntegrationTest is Test {
    Oracle public oracle;
    LendingManager public lendingManager;
    MockTokenRegistry public mockTokenRegistry;
    MockOrderBook public mockOrderBook;
    MockToken public token;
    
    address public owner = address(0x1);
    address public user = address(0x2);
    
    function setUp() public {
        mockOrderBook = new MockOrderBook();
        mockTokenRegistry = new MockTokenRegistry();
        token = new MockToken("Test Token", "TEST", 6);
        
        mockTokenRegistry.addSupportedToken(address(token));
        
        // Deploy and initialize Oracle with proxy
        vm.startPrank(owner);
        // Deploy Oracle implementation
        address oracleImpl = address(new Oracle());
        
        // Deploy proxy with initialization data
        ERC1967Proxy oracleProxy = new ERC1967Proxy(
            oracleImpl,
            abi.encodeWithSelector(
                Oracle.initialize.selector,
                owner,
                address(mockTokenRegistry)
            )
        );
        oracle = Oracle(address(oracleProxy));
        oracle.addToken(address(token), 1);
        oracle.setTokenOrderBook(address(token), address(mockOrderBook));
        
        // Deploy and initialize LendingManager using BeaconProxy pattern
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy lendingProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new LendingManager()),
            owner,
            abi.encodeCall(LendingManager.initialize, (owner, address(oracle)))
        );
        lendingManager = LendingManager(address(lendingProxy));
        
        // Configure LendingManager with Oracle
        lendingManager.setOracle(address(oracle));
        
        // Configure token in LendingManager
        lendingManager.configureAsset(
            address(token),
            8000,  // 80% LTV
            8500,  // 85% liquidation threshold
            500,   // 5% liquidation bonus
            1000   // 10% reserve factor
        );
        
        // Set interest rate parameters
        lendingManager.setInterestRateParams(
            address(token),
            200,   // 2% base rate
            8000,  // 80% optimal utilization
            1000,  // Rate slope 1
            2000   // Rate slope 2
        );
        
        vm.stopPrank();
    }
    
    function testOracleIntegration() public view {
        // Verify Oracle is properly set
        assertEq(address(lendingManager.oracle()), address(oracle));
        
        // Test pricing functions
        uint256 collateralPrice = lendingManager.getCollateralPrice(address(token));
        uint256 borrowingPrice = lendingManager.getBorrowingPrice(address(token));
        uint256 confidence = lendingManager.getPriceConfidence(address(token));
        bool isStale = lendingManager.isPriceStale(address(token));
        
        // Initially no prices available (real-time Oracle requires trade data)
        assertEq(collateralPrice, 0);
        assertEq(borrowingPrice, 0);
        assertEq(confidence, 0); // No confidence without trade data
        assertEq(isStale, true); // No recent updates
    }
    
    function testOraclePricing() public {
        // Set up real OrderBook prices
        mockOrderBook.setBestPrice(0, uint128(2000 * 1e6), 1000 * 1e6); // BID
        mockOrderBook.setBestPrice(1, uint128(2010 * 1e6), 1000 * 1e6); // ASK
        
        vm.startPrank(owner);
        oracle.updatePrice(address(token));
        vm.stopPrank();
        
        // Verify LendingManager can now get prices
        uint256 collateralPrice = lendingManager.getCollateralPrice(address(token));
        uint256 borrowingPrice = lendingManager.getBorrowingPrice(address(token));
        uint256 confidence = lendingManager.getPriceConfidence(address(token));
        
        assertGt(collateralPrice, 0);
        assertGt(borrowingPrice, 0);
        assertGt(confidence, 0);
        assertLe(confidence, 100);
        
        console.log("Collateral Price:", collateralPrice);
        console.log("Borrowing Price:", borrowingPrice);
        console.log("Confidence:", confidence);
    }
    
    function testOracleFallbackBehavior() public {
        // Deploy new LendingManager without setting Oracle
        vm.startPrank(owner);
        LendingManager isolatedLendingManager = new LendingManager();
        isolatedLendingManager.initialize(owner, address(0)); // No oracle set
        
        // Even without oracle, functions should not revert
        uint256 collateralPrice = isolatedLendingManager.getCollateralPrice(address(token));
        uint256 borrowingPrice = isolatedLendingManager.getBorrowingPrice(address(token));
        
        assertEq(collateralPrice, 0);
        assertEq(borrowingPrice, 0);
        
        vm.stopPrank();
    }
    
    function testPriceConfidenceInRiskCalculations() public {
        // Set up real OrderBook prices
        mockOrderBook.setBestPrice(0, uint128(2000 * 1e6), 1000 * 1e6); // BID
        mockOrderBook.setBestPrice(1, uint128(2010 * 1e6), 1000 * 1e6); // ASK
        
        vm.startPrank(owner);
        oracle.updatePrice(address(token));
        vm.stopPrank();
        
        uint256 confidence = lendingManager.getPriceConfidence(address(token));
        
        // In a real implementation, you might use confidence to adjust risk parameters
        if (confidence >= 50) {
            console.log("High confidence - normal borrowing allowed");
        } else {
            console.log("Low confidence - restricted borrowing");
        }
        
        assertGt(confidence, 0);
    }
}

// MockOrderBook implementation for integration tests
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
    function getBestPrice(uint8 side) external view returns (IOrderBook.PriceVolume memory) {
        MockPriceVolume memory mockPrice = bestPrices[side];
        return IOrderBook.PriceVolume(mockPrice.price, mockPrice.volume);
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
        return IOrderBook.TradingRules(1, 1, 100, 100); 
    }
}


contract MockTokenRegistry is ITokenRegistry {
    address[] public supportedTokens;
    mapping(address => bool) public isSupported;
    
    function addSupportedToken(address token) external {
        if (!isSupported[token]) {
            supportedTokens.push(token);
            isSupported[token] = true;
        }
    }
    
    function getSupportedTokens() external view override returns (address[] memory) {
        return supportedTokens;
    }
    
    function isTokenSupported(address token) external view override returns (bool) {
        return isSupported[token];
    }
    
    function getChainTokens(uint32 /* sourceChainId */) external pure override returns (address[] memory) {
        return new address[](0);
    }
    
    function getSyntheticToken(uint32 /* sourceChainId */, address /* sourceToken */, uint32 /* targetChainId */) external pure override returns (address) {
        return address(0);
    }
    
    function getSyntheticTokenForUser(uint32, address, uint32, address) external pure returns (address) {
        return address(0);
    }
    
    // Missing methods from updated ITokenRegistry interface
    function initialize(address) external pure override {}
    
    function registerTokenMapping(
        uint32 /* sourceChainId */,
        address /* sourceToken */,
        uint32 /* targetChainId */,
        address /* syntheticToken */,
        string memory /* tokenName */,
        uint8 /* sourceDecimals */,
        uint8 /* targetDecimals */
    ) external pure override {}
    
    function updateTokenMapping(
        uint32 /* sourceChainId */,
        address /* sourceToken */,
        uint32 /* targetChainId */,
        address /* newSyntheticToken */
    ) external pure override {}
    
    function setTokenMappingStatus(
        uint32 /* sourceChainId */,
        address /* sourceToken */,
        uint32 /* targetChainId */,
        bool /* isActive */
    ) external pure override {}
    
    function removeTokenMapping(
        uint32 /* sourceChainId */,
        address /* sourceToken */,
        uint32 /* targetChainId */
    ) external pure override {}
    
    function getTokenMapping(
        uint32 /* sourceChainId */,
        address /* sourceToken */,
        uint32 /* targetChainId */
    ) external pure override returns (
        address syntheticToken,
        string memory tokenName,
        uint8 sourceDecimals,
        uint8 targetDecimals,
        bool isActive
    ) {
        return (address(0x0), "", 0, 0, false);
    }
    
    function getSourceToken(
        uint32 /* sourceChainId */,
        address /* syntheticToken */,
        uint32 /* targetChainId */
    ) external pure override returns (address) {
        return address(0);
    }
    
    function isTokenMappingActive(
        uint32 /* sourceChainId */,
        address /* sourceToken */,
        uint32 /* targetChainId */
    ) external pure override returns (bool) {
        return false;
    }
    
    function convertAmount(
        uint32 /* sourceChainId */,
        address /* sourceToken */,
        uint32 /* targetChainId */,
        uint256 /* amount */,
        bool /* roundUp */
    ) external pure override returns (uint256) {
        return 0;
    }
    
    function convertAmountForMapping(
        uint32 /* sourceChainId */,
        address /* sourceToken */,
        uint32 /* targetChainId */,
        uint256 /* amount */,
        bool /* roundUp */
    ) external pure override returns (uint256) {
        return 0;
    }
    
    function initializeUpgrade(address /* _newOwner */, address /* _factory */) external pure override {}
}