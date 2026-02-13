// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";
import {PoolKey} from "../libraries/Pool.sol";
import {IOrderBook} from "./IOrderBook.sol";

interface IRangeLiquidityManager {
    /// @notice Distribution strategy for liquidity across price range
    enum Strategy {
        UNIFORM,        // 50/50 split between buys and sells
        BID_HEAVY,      // 70% buy orders, 30% sell orders (accumulation)
        ASK_HEAVY       // 30% buy orders, 70% sell orders (distribution)
    }

    /// @notice Range liquidity position
    struct RangePosition {
        uint256 positionId;
        address owner;
        PoolKey poolKey;

        // Configuration
        Strategy strategy;
        uint128 lowerPrice;
        uint128 upperPrice;
        uint128 centerPriceAtCreation;
        uint16 tickCount;
        uint16 tickSpacing;  // Tick spacing used for this position

        // Capital tracking
        uint256 initialDepositAmount;
        Currency initialDepositCurrency;

        // Order tracking
        uint48[] buyOrderIds;
        uint48[] sellOrderIds;

        // Fee tracking
        uint256 feesCollectedBase;   // Accumulated fees in base currency
        uint256 feesCollectedQuote;  // Accumulated fees in quote currency

        // Rebalance settings
        bool autoRebalanceEnabled;
        uint16 rebalanceThresholdBps;
        address authorizedBot;

        // State
        bool isActive;
        uint48 createdAt;
        uint48 lastRebalancedAt;
        uint16 rebalanceCount;
    }

    /// @notice Parameters for creating a range position
    struct PositionParams {
        PoolKey poolKey;
        Strategy strategy;
        uint128 lowerPrice;
        uint128 upperPrice;
        uint16 tickCount;
        uint16 tickSpacing;  // Tick spacing (50 or 200)
        uint256 depositAmount;
        Currency depositCurrency;
        bool autoRebalance;
        uint16 rebalanceThresholdBps;
    }

    /// @notice Position value breakdown
    struct PositionValue {
        uint256 totalValueInQuote;
        uint256 baseAmount;
        uint256 quoteAmount;
        uint256 lockedInOrders;
        uint256 freeBalance;
        uint256 feesEarnedBase;   // Total fees earned in base currency
        uint256 feesEarnedQuote;  // Total fees earned in quote currency
    }

    // Events
    event PositionCreated(
        uint256 indexed positionId,
        address indexed owner,
        PoolKey poolKey,
        uint128 lowerPrice,
        uint128 upperPrice,
        uint256 totalLiquidity,
        Strategy strategy,
        uint16 tickSpacing,
        uint24 feeTier
    );

    event PositionRebalanced(
        uint256 indexed positionId,
        uint128 oldCenterPrice,
        uint128 newCenterPrice,
        uint128 newLowerPrice,
        uint128 newUpperPrice,
        uint256 rebalanceCount
    );

    event PositionClosed(
        uint256 indexed positionId,
        address indexed owner,
        uint256 baseReturned,
        uint256 quoteReturned,
        uint256 feesEarnedBase,
        uint256 feesEarnedQuote
    );

    event FeesCollected(
        uint256 indexed positionId,
        uint256 baseAmount,
        uint256 quoteAmount
    );

    event BotAuthorized(
        uint256 indexed positionId,
        address indexed bot
    );

    event BotRevoked(
        uint256 indexed positionId,
        address indexed bot
    );

    // Errors
    error NotPositionOwner(uint256 positionId, address caller);
    error PositionNotActive(uint256 positionId);
    error PositionAlreadyExists(address owner, PoolKey poolKey);
    error InvalidPriceRange(uint128 lowerPrice, uint128 upperPrice);
    error InvalidTickCount(uint16 tickCount);
    error InvalidTickSpacing(uint16 tickSpacing);
    error InvalidDepositAmount(uint256 amount);
    error InvalidRebalanceThreshold(uint16 threshold);
    error NotAuthorizedToRebalance(uint256 positionId, address caller);
    error RebalanceThresholdNotMet(uint256 positionId, uint256 currentDrift, uint256 threshold);
    error InvalidStrategy(Strategy strategy);
    error InvalidFeeTier(uint24 feeTier);

    // Core functions
    function createPosition(PositionParams calldata params) external returns (uint256 positionId);

    function closePosition(uint256 positionId) external;

    function rebalancePosition(uint256 positionId) external;

    function collectFees(uint256 positionId) external;

    function setAuthorizedBot(uint256 positionId, address bot) external;

    function revokeBot(uint256 positionId) external;

    // View functions
    function getPosition(uint256 positionId) external view returns (RangePosition memory);

    function getPositionValue(uint256 positionId) external view returns (PositionValue memory);

    function getUserPositions(address user) external view returns (uint256[] memory);

    function canRebalance(uint256 positionId) external view returns (bool canReb, uint256 currentDriftBps);

    function totalPositions() external view returns (uint256);

    function getFeeTierForPool(PoolKey calldata poolKey) external view returns (uint24);
}
