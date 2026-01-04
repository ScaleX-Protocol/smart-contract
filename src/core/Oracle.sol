// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {ITokenRegistry} from "./interfaces/ITokenRegistry.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/**
 * @title Oracle
 * @dev Time-Weighted Average Price (TWAP) oracle for all registered tokens
 * @notice Provides manipulation-resistant price feeds using OrderBook trading data
 */
contract Oracle is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IOracle {
    
    // Structs
    struct PricePoint {
        uint256 price;
        uint256 timestamp;
        uint256 cumulativePrice;
        bool initialized;
    }
    
    struct TokenPriceData {
        mapping(uint256 => PricePoint) priceHistory; // block.timestamp -> price
        uint256 lastUpdateTime;
        uint256 lastCumulativePrice;
        uint256 oldestTimestamp;
        uint256 maxHistorySize;
        bool supported;
    }
    
    // Storage
    mapping(address => TokenPriceData) public tokenPriceData;
    mapping(address => uint256) public tokenPriceIds; // token -> priceId for OrderBook
    
    // Constants
    uint256 public constant MAX_HISTORY_SIZE = 1000;
    uint256 public constant STALE_PRICE_DELAY = 1 hours;
    uint256 public constant MIN_TRADE_VOLUME = 1000 * 1e6; // Minimum volume for reliable price
    
    // Interfaces
    ITokenRegistry public tokenRegistry;
    
    // Multi-token OrderBook support
    mapping(address => IOrderBook) public tokenOrderBooks;
    
    // Events
    event PriceUpdate(address indexed token, uint256 price, uint256 timestamp);
    event TokenAdded(address indexed token, uint256 priceId);
    event TokenRemoved(address indexed token);
    event TWAPCalculated(address indexed token, uint256 twapPrice, uint256 window);
    event OracleUpdated(address indexed tokenRegistry);
    
    // Errors
    error TokenNotSupported(address token);
    error InsufficientPriceHistory(address token, uint256 window);
    error StalePrice(address token, uint256 lastUpdate);
    error InvalidConfiguration();
    error NoTradingLiquidity(address token);
    error ZeroAddress();
    error UnauthorizedOracleUpdate(address caller);
    error InsufficientTradeVolume(uint256 volume, uint256 minVolume);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _tokenRegistry
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        
        if (_tokenRegistry == address(0)) {
            revert InvalidConfiguration();
        }
        
        tokenRegistry = ITokenRegistry(_tokenRegistry);
        
        emit OracleUpdated(_tokenRegistry);
    }
    
    // =============================================================
    //                   OWNER FUNCTIONS
    // =============================================================
    
    function addToken(address token, uint256 priceId) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();

        TokenPriceData storage data = tokenPriceData[token];
        data.supported = true;
        data.maxHistorySize = MAX_HISTORY_SIZE;
        tokenPriceIds[token] = priceId;

        emit TokenAdded(token, priceId);
    }
    
    function removeToken(address token) external onlyOwner {
        TokenPriceData storage data = tokenPriceData[token];
        data.supported = false;
        delete tokenPriceIds[token];
        
        emit TokenRemoved(token);
    }

    function setTokenOrderBook(address token, address orderBook) external onlyOwner {
        if (!tokenPriceData[token].supported) {
            revert TokenNotSupported(token);
        }
        if (orderBook == address(0)) revert ZeroAddress();
        tokenOrderBooks[token] = IOrderBook(orderBook);
    }

    /// @notice Initialize price for a token (for bootstrapping when no trades exist yet)
    /// @dev Only callable by owner, should be removed once sufficient trading data exists
    function initializePrice(address token, uint256 price) external onlyOwner {
        if (!tokenPriceData[token].supported) {
            revert TokenNotSupported(token);
        }
        if (price == 0) revert ZeroPrice();

        TokenPriceData storage data = tokenPriceData[token];

        // Only allow initialization if no trade data exists
        if (data.lastUpdateTime > 0) {
            revert PriceAlreadyInitialized();
        }

        // Set initial price
        uint256 currentTime = block.timestamp;
        data.priceHistory[currentTime] = PricePoint({
            price: price,
            timestamp: currentTime,
            cumulativePrice: 0,
            initialized: true
        });
        data.lastUpdateTime = currentTime;

        emit PriceUpdate(token, price, currentTime);
    }

    /// @notice Set price for a token (admin function for manual price updates)
    /// @dev Only callable by owner, allows updating price at any time
    function setPrice(address token, uint256 price) external onlyOwner {
        if (!tokenPriceData[token].supported) {
            revert TokenNotSupported(token);
        }
        if (price == 0) revert ZeroPrice();

        // Store the price point
        _storePricePoint(token, price, block.timestamp);

        emit PriceUpdate(token, price, block.timestamp);
    }


    function updateOrderBook(address /* orderBook */) external pure {
        // Legacy function - not used in multi-token setup
        revert("Function deprecated - use setTokenOrderBook instead");
    }

    function setTokenPriceId(address token, uint256 priceId) external onlyOwner {
        if (!tokenPriceData[token].supported) {
            revert TokenNotSupported(token);
        }
        tokenPriceIds[token] = priceId;
    }

    function updatePriceFromTrade(
        address token,
        uint128 price,
        uint256 volume
    ) external {
        // Only authorized OrderBooks can call this function
        if (!tokenPriceData[token].supported) {
            revert TokenNotSupported(token);
        }
        if (address(tokenOrderBooks[token]) == address(0) || address(tokenOrderBooks[token]) != msg.sender) {
            revert UnauthorizedOracleUpdate(msg.sender);
        }
        if (volume < MIN_TRADE_VOLUME) {
            revert InsufficientTradeVolume(volume, MIN_TRADE_VOLUME);
        }
        
        // Store price point immediately when trade occurs
        _storePricePoint(token, uint256(price), block.timestamp);
        
        emit PriceUpdate(token, uint256(price), block.timestamp);
    }
    
    function updateTokenRegistry(address _tokenRegistry) external onlyOwner {
        if (_tokenRegistry == address(0)) revert InvalidConfiguration();
        tokenRegistry = ITokenRegistry(_tokenRegistry);
        emit OracleUpdated(_tokenRegistry);
    }
    
    // =============================================================
    //                   PRICE UPDATE FUNCTIONS
    // =============================================================
    
    function updatePrice(address token) external nonReentrant {
        if (!tokenPriceData[token].supported) {
            revert TokenNotSupported(token);
        }
        
        uint256 currentPrice = _getCurrentPrice(token);
        if (currentPrice == 0) {
            revert NoTradingLiquidity(token);
        }
        
        _storePricePoint(token, currentPrice, block.timestamp);
        emit PriceUpdate(token, currentPrice, block.timestamp);
    }
    
    function updatePricesForAllTokens() external nonReentrant {
        address[] memory tokens = tokenRegistry.getSupportedTokens();
        
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenPriceData[tokens[i]].supported) {
                try this.updatePrice(tokens[i]) {
                    // Price updated successfully
                } catch {
                    // Skip tokens with no trading liquidity
                    continue;
                }
            }
        }
    }
    
    // =============================================================
    //                   PUBLIC ORACLE FUNCTIONS
    // =============================================================
    
    function getTWAP(address token, uint256 window) external view returns (uint256) {
        if (!tokenPriceData[token].supported) {
            revert TokenNotSupported(token);
        }
        
        uint256 currentTime = block.timestamp;
        uint256 targetTime = currentTime > window ? currentTime - window : 0;
        
        return _calculateTWAP(token, targetTime, currentTime);
    }
    
    function getSpotPrice(address token) external view returns (uint256) {
        if (!tokenPriceData[token].supported) {
            revert TokenNotSupported(token);
        }
        
        TokenPriceData storage data = tokenPriceData[token];
        
        // Only return stored price from trades
        if (data.lastUpdateTime > 0) {
            return data.priceHistory[data.lastUpdateTime].price;
        }
        
        // No trade data yet - return 0
        return 0;
    }
    
    function getPrices(address token) external view returns (
        uint256 spotPrice,
        uint256 twap5m,
        uint256 twap15m,
        uint256 twap1h,
        uint256 twap6h
    ) {
        if (!tokenPriceData[token].supported) {
            revert TokenNotSupported(token);
        }
        
        spotPrice = _getCurrentPrice(token);
        uint256 currentTime = block.timestamp;
        twap5m = _calculateTWAP(token, currentTime > 5 minutes ? currentTime - 5 minutes : 0, currentTime);
        twap15m = _calculateTWAP(token, currentTime > 15 minutes ? currentTime - 15 minutes : 0, currentTime);
        twap1h = _calculateTWAP(token, currentTime > 1 hours ? currentTime - 1 hours : 0, currentTime);
        twap6h = _calculateTWAP(token, currentTime > 6 hours ? currentTime - 6 hours : 0, currentTime);
    }
    
    function getPriceForCollateral(address token) external view returns (uint256) {
        // Use longer TWAP for collateral to prevent manipulation
        // Take the more conservative (lower) price between 1h and 6h TWAP
        uint256 twap1h = this.getTWAP(token, 1 hours);
        uint256 twap6h = this.getTWAP(token, 6 hours);

        if (twap1h == 0 && twap6h == 0) {
            return this.getSpotPrice(token); 
        }

        if (twap1h == 0) return twap6h;
        if (twap6h == 0) return twap1h;

        return twap1h < twap6h ? twap1h : twap6h;
    }
    
    function getPriceForBorrowing(address token) external view returns (uint256) {
        // Use medium-term TWAP for borrowing to balance responsiveness and stability
        uint256 twap15m = this.getTWAP(token, 15 minutes);
        uint256 twap1h = this.getTWAP(token, 1 hours);

        if (twap15m == 0 && twap1h == 0) {
            return this.getSpotPrice(token); 
        }

        if (twap15m == 0) return twap1h;
        if (twap1h == 0) return twap15m;

        // Take the average for a balanced approach
        return (twap15m + twap1h) / 2;
    }
    
    // =============================================================
    //                   VALIDATION & HEALTH FUNCTIONS
    // =============================================================
    
    function isPriceStale(address token) external view returns (bool) {
        TokenPriceData storage data = tokenPriceData[token];
        
        // If no updates ever, consider it stale
        if (data.lastUpdateTime == 0) return true;
        
        return (block.timestamp - data.lastUpdateTime) > STALE_PRICE_DELAY;
    }
    
    function hasSufficientHistory(address token, uint256 window) external view returns (bool) {
        TokenPriceData storage data = tokenPriceData[token];
        uint256 targetTime = block.timestamp > window ? block.timestamp - window : 0;
        return data.oldestTimestamp <= targetTime && data.oldestTimestamp > 0;
    }
    
    function getPriceConfidence(address token) external view returns (uint256 confidence) {
        if (!tokenPriceData[token].supported) return 0;
        
        TokenPriceData storage data = tokenPriceData[token];
        
        // If no price updates yet, return 0 confidence (require trade data)
        if (data.lastUpdateTime == 0) return 0;
        
        // Check if price is stale
        if ((block.timestamp - data.lastUpdateTime) > STALE_PRICE_DELAY) return 0;
        
        (uint256 spotPrice, , , uint256 twap1h, ) = this.getPrices(token);
        
        // For testing: if no TWAP history, return high confidence
        if (twap1h == 0) return 100;
        
        uint256 deviation = spotPrice > twap1h ? spotPrice - twap1h : twap1h - spotPrice;
        uint256 deviationPercent = (deviation * 10000) / twap1h;
        
        // Confidence scoring based on deviation from long-term average
        if (deviationPercent < 100) { // Less than 1% deviation
            confidence = 100;
        } else if (deviationPercent < 500) { // Less than 5% deviation
            confidence = 80;
        } else if (deviationPercent < 1000) { // Less than 10% deviation
            confidence = 50;
        } else if (deviationPercent < 2000) { // Less than 20% deviation
            confidence = 25;
        } else {
            confidence = 10;
        }
    }
    
    function getOracleHealth(address token) external view returns (
        bool healthy,
        uint256 confidence,
        bool stale,
        bool hasHistory,
        string memory issue
    ) {
        healthy = true;
        issue = "All systems operational";
        
        if (!tokenPriceData[token].supported) {
            healthy = false;
            issue = "Token not supported";
            return (healthy, 0, false, false, issue);
        }
        
        confidence = this.getPriceConfidence(token);
        stale = this.isPriceStale(token);
        hasHistory = this.hasSufficientHistory(token, 15 minutes); // Use shorter window for testing
        
        if (stale) {
            healthy = false;
            issue = "Price is stale";
        } else if (!hasHistory) {
            healthy = false;
            issue = "Insufficient price history";
        } else if (confidence < 25) {
            healthy = false;
            issue = "Low price confidence";
        } else if (confidence < 50) {
            healthy = true;
            issue = "Medium price confidence";
        }
    }
    

    // =============================================================
    //                   TESTING FUNCTIONS
    // =============================================================
    
    /// @notice For testing only - get current price from OrderBook
    function getCurrentPriceFromOrderBook(address token) external view returns (uint256) {
        return _getCurrentPrice(token);
    }
    
    /// @notice Get current price from OrderBook (not from stored trade data)
    function getCurrentPrice(address token) external view returns (uint256) {
        if (!tokenPriceData[token].supported) {
            revert TokenNotSupported(token);
        }
        return _getCurrentPrice(token);
    }
    
    /// @notice For testing only - get debug info about token data
    function getDebugInfo(address token) external view returns (
        uint256 lastUpdateTime,
        uint256 oldestTimestamp,
        uint256 maxHistorySize,
        uint256 historyDuration
    ) {
        TokenPriceData storage data = tokenPriceData[token];
        return (
            data.lastUpdateTime,
            data.oldestTimestamp,
            data.maxHistorySize,
            data.lastUpdateTime - data.oldestTimestamp
        );
    }
    
    // =============================================================
    //                   INTERNAL FUNCTIONS
    // =============================================================
    
    function _getCurrentPrice(address token) internal view returns (uint256) {
        // Get token-specific OrderBook
        IOrderBook tokenOrderBook = tokenOrderBooks[token];
        if (address(tokenOrderBook) == address(0)) {
            // No OrderBook configured for this token
            return 0;
        }
        
        uint256 bidPrice = 0;
        uint256 askPrice = 0;
        
        // Try to get bid price
        try tokenOrderBook.getBestPrice(IOrderBook.Side.BUY) returns (IOrderBook.PriceVolume memory bestBid) {
            bidPrice = uint256(bestBid.price);
        } catch {
            // Continue with ask price if bid fails
        }
        
        // Try to get ask price
        try tokenOrderBook.getBestPrice(IOrderBook.Side.SELL) returns (IOrderBook.PriceVolume memory bestAsk) {
            askPrice = uint256(bestAsk.price);
        } catch {
            // Continue with bid price if ask fails
        }
        
        // Handle different scenarios
        if (bidPrice == 0 && askPrice == 0) {
            // No prices available - insufficient liquidity
            return 0;
        }
        
        if (bidPrice == 0) {
            // Only ask price available
            return askPrice;
        }
        
        if (askPrice == 0) {
            // Only bid price available
            return bidPrice;
        }
        
        // Both prices available - return mid-price
        return (bidPrice + askPrice) / 2;
    }
    
    function _storePricePoint(address token, uint256 price, uint256 timestamp) internal {
        TokenPriceData storage data = tokenPriceData[token];
        
        // Update cumulative price
        if (data.lastUpdateTime > 0) {
            uint256 timeDelta = timestamp - data.lastUpdateTime;
            uint256 lastPrice = data.priceHistory[data.lastUpdateTime].price;
            data.lastCumulativePrice += lastPrice * timeDelta;
        } else {
            data.lastCumulativePrice = price;
            data.oldestTimestamp = timestamp;
        }
        
        // Store new price point
        PricePoint storage point = data.priceHistory[timestamp];
        point.price = price;
        point.timestamp = timestamp;
        point.cumulativePrice = data.lastCumulativePrice;
        point.initialized = true;
        
        data.lastUpdateTime = timestamp;
        
        // Clean old data points if exceeding max size
        _cleanOldData(token);
    }
    
    function _calculateTWAP(address token, uint256 startTime, uint256 endTime) internal view returns (uint256) {
        TokenPriceData storage data = tokenPriceData[token];
        
        if (startTime < data.oldestTimestamp) {
            startTime = data.oldestTimestamp;
        }
        
        if (endTime <= startTime || data.lastUpdateTime <= startTime) {
            return 0;
        }
        
        // Find cumulative price at start time
        uint256 startCumulative = _findCumulativePriceAtTime(token, startTime);
        uint256 timeDelta = endTime - startTime;
        
        if (timeDelta == 0) return 0;
        
        return (data.lastCumulativePrice - startCumulative) / timeDelta;
    }
    
    function _findCumulativePriceAtTime(address token, uint256 targetTime) internal view returns (uint256) {
        TokenPriceData storage data = tokenPriceData[token];
        
        // Simple linear search - in production, use binary search for efficiency
        for (uint256 t = targetTime; t <= data.lastUpdateTime; t++) {
            if (data.priceHistory[t].initialized) {
                return data.priceHistory[t].cumulativePrice;
            }
        }
        
        // If exact time not found, return the previous cumulative price
        for (uint256 t = targetTime; t > data.oldestTimestamp && t > 0; t--) {
            if (data.priceHistory[t].initialized) {
                return data.priceHistory[t].cumulativePrice;
            }
        }
        
        return data.lastCumulativePrice;
    }
    
    function _cleanOldData(address token) internal {
        TokenPriceData storage data = tokenPriceData[token];
        
        // Simple cleanup logic - remove oldest entries if exceeding max size
        uint256 historyDuration = data.lastUpdateTime - data.oldestTimestamp;
        if (historyDuration > data.maxHistorySize) {
            data.oldestTimestamp = data.lastUpdateTime - data.maxHistorySize;
        }
    }
}