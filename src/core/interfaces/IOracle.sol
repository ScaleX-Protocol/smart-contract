// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IOracle {
    // Price querying functions
    function getSpotPrice(address token) external view returns (uint256);
    function getTWAP(address token, uint256 window) external view returns (uint256);
    function getPriceForCollateral(address token) external view returns (uint256);
    function getPriceForBorrowing(address token) external view returns (uint256);

    // Status functions
    function isPriceStale(address token) external view returns (bool);
    function hasSufficientHistory(address token, uint256 window) external view returns (bool);
    
    // Oracle health check
    function getOracleHealth(address token) external view returns (
        bool healthy,
        uint256 confidence,
        bool stale, 
        bool hasHistory,
        string memory issue
    );
    
    // Token management
    function addToken(address token, uint256 priceId) external;
    function removeToken(address token) external;
    function setTokenOrderBook(address token, address orderBook) external;
    function setAuthorizedOrderBook(address token, address orderBook, bool authorized) external;
    function initializePrice(address token, uint256 price) external;
    function getAllSupportedTokens() external view returns (address[] memory supportedTokens);

    // OrderBook integration
    function updateOrderBook(address orderBook) external;
    
    // Constants
    function MAX_HISTORY_SIZE() external view returns (uint256);
    function STALE_PRICE_DELAY() external view returns (uint256);

    // Configurable settings
    function minTradeVolume() external view returns (uint256);
    function setMinTradeVolume(uint256 _minTradeVolume) external;
    
    // Trade-based price updates
    function updatePriceFromTrade(address token, uint128 price, uint256 volume) external;
    
    // Manual price updates
    function updatePrice(address token) external;
    
    // Token registry management
    function updateTokenRegistry(address tokenRegistry) external;
}