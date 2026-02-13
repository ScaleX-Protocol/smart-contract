// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PoolId, PoolKey} from "../libraries/Pool.sol";
import {IOrderBookErrors} from "./IOrderBookErrors.sol";

interface IOrderBook is IOrderBookErrors {
    enum Side {
        BUY,
        SELL
    }

    enum Status {
        OPEN,
        PARTIALLY_FILLED,
        FILLED,
        CANCELLED,
        REJECTED,
        EXPIRED
    }

    enum OrderType {
        LIMIT,
        MARKET
    }

    enum TimeInForce {
        GTC,
        IOC,
        FOK,
        PO
    }

    struct Order {
        // Slot 1
        address user;
        uint48 id;
        uint48 next;
        // Slot 2
        uint128 quantity;
        uint128 filled;
        // Slot 3
        uint128 price;
        uint48 prev;
        uint48 expiry;
        Status status;
        OrderType orderType;
        Side side;
        bool autoRepay;
        bool autoBorrow;
        // Slot 4 - Agent tracking
        uint256 agentTokenId;  // ERC-8004 agent token ID (0 if not agent order)
        address executor;       // Executor wallet that placed the order
    }

    struct MatchContext {
        Order order;
        Side side;
        address user;
        bool isMarketOrder;
        uint128 bestPrice;
        uint128 remaining;
        uint128 previousRemaining;
        uint128 filled;
    }

    struct MatchState {
        uint128 remaining;
        uint128 orderPrice;
        uint128 latestBestPrice;
        uint128 previousRemaining;
        uint128 filled;
    }

    struct OrderQueue {
        uint256 totalVolume;
        uint48 orderCount;
        uint48 head;
        uint48 tail;
    }

    struct TradingRules {
        uint128 minTradeAmount;
        uint128 minAmountMovement;
        uint128 minPriceMovement;
        uint128 minOrderSize;
    }

    struct PriceVolume {
        uint128 price;
        uint256 volume;
    }

    struct MatchOrder {
        IOrderBook.Order order;
        IOrderBook.Side side;
        address trader;
        address balanceManager;
        IOrderBook orderBook;
    }

    event OrderPlaced(
        uint48 indexed orderId,
        address indexed user,
        Side indexed side,
        uint128 price,
        uint128 quantity,
        uint48 expiry,
        bool isMarketOrder,
        Status status,
        bool autoRepay,
        bool autoBorrow,
        TimeInForce timeInForce,
        uint256 agentTokenId,
        address executor
    );

    event OrderMatched(
        address indexed user,
        uint48 indexed buyOrderId,
        uint48 indexed sellOrderId,
        IOrderBook.Side side,
        uint48 timestamp,
        uint128 executionPrice,
        uint128 executedQuantity,
        uint256 agentTokenId,
        address executor
    );

    event UpdateOrder(uint48 indexed orderId, uint48 timestamp, uint128 filled, IOrderBook.Status status);

    event OrderCancelled(uint48 indexed orderId, address indexed user, uint48 timestamp, Status status, uint256 agentTokenId, address executor);

    event TradingRulesUpdated(PoolId indexed poolId, IOrderBook.TradingRules newRules);

    event AutoRepaymentExecuted(
        address indexed user,
        address indexed debtToken,
        uint256 repayAmount,
        uint256 savings,
        uint256 timestamp,
        uint48 orderId,
        uint256 agentTokenId,
        address executor
    );

    event AutoRepaymentFailed(
        address indexed user,
        address indexed debtToken,
        uint256 attemptedAmount,
        uint256 timestamp,
        uint48 orderId,
        uint256 agentTokenId,
        address executor
    );

    event AutoBorrowExecuted(
        address indexed user,
        address indexed borrowedToken,
        uint256 borrowAmount,
        uint256 timestamp,
        uint48 orderId,
        uint256 agentTokenId,
        address executor
    );

    event AutoBorrowFailed(
        address indexed user,
        address indexed attemptedToken,
        uint256 attemptedAmount,
        uint256 timestamp,
        uint48 orderId,
        uint256 agentTokenId,
        address executor
    );

    function initialize(
        address poolManager,
        address balanceManager,
        TradingRules calldata tradingRules,
        PoolKey calldata poolKey
    ) external;

    function setRouter(
        address router
    ) external;

    function oracle() external view returns (address);

    function setOracle(
        address oracle
    ) external;

    function placeOrder(
        uint128 price,
        uint128 quantity,
        Side side,
        address user,
        TimeInForce timeInForce,
        bool autoRepay,
        bool autoBorrow,
        uint256 agentTokenId,
        address executor
    ) external returns (uint48 orderId);

    function getOrder(
        uint48 orderId
    ) external view returns (Order memory order);

    function placeMarketOrder(uint128 quantity, Side side, address user, bool autoRepay, bool autoBorrow, uint256 agentTokenId, address executor) external returns (uint48, uint128);

    function cancelOrder(uint48 orderId, address user, uint256 agentTokenId, address executor) external;

    function getOrderQueue(Side side, uint128 price) external view returns (uint48 orderCount, uint256 totalVolume);

    function getBestPrice(
        Side side
    ) external view returns (PriceVolume memory);

    function getNextBestPrices(Side side, uint128 price, uint8 count) external view returns (PriceVolume[] memory);

    function setTradingRules(
        TradingRules calldata tradingRules
    ) external;

    function getTradingRules() external view returns (TradingRules memory);

    function updateTradingRules(
        TradingRules memory _newRules
    ) external;

    function getQuoteCurrency() external view returns (address);

    function getBaseCurrency() external view returns (address);
}
