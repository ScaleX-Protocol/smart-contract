// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IOrderBookErrors} from "./interfaces/IOrderBookErrors.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {IAutoBorrowHelper} from "./interfaces/IAutoBorrowHelper.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "./libraries/Pool.sol";
import {PoolIdLibrary} from "./libraries/Pool.sol";

import {OrderBookStorage} from "./storages/OrderBookStorage.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {RedBlackTreeLib} from "@solady/utils/RedBlackTreeLib.sol";


contract OrderBook is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, IOrderBook, OrderBookStorage {
    using RedBlackTreeLib for RedBlackTreeLib.Tree;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyRouter() {
        Storage storage $ = getStorage();
        if (msg.sender != $.router && msg.sender != owner() && msg.sender != address(this)) {
            revert UnauthorizedRouter(msg.sender);
        }
        _;
    }

    function initialize(
        address _poolManager,
        address _balanceManager,
        TradingRules memory _tradingRules,
        PoolKey memory _poolKey
    ) public initializer {
        __Ownable_init(_poolManager);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        $.balanceManager = _balanceManager;
        $.tradingRules = _tradingRules;
        $.poolKey = _poolKey;
        $.nextOrderId = 1;
        $.expiryDays = 90 days;
    }

    function getTradingRules() external view returns (TradingRules memory) {
        Storage storage $ = getStorage();
        return $.tradingRules;
    }

    function getQuoteCurrency() external view returns (address) {
        Storage storage $ = getStorage();
        return Currency.unwrap($.poolKey.quoteCurrency);
    }

    function getBaseCurrency() external view returns (address) {
        Storage storage $ = getStorage();
        return Currency.unwrap($.poolKey.baseCurrency);
    }

    function setRouter(
        address _router
    ) external onlyOwner {
        Storage storage $ = getStorage();
        $.router = _router;
    }

    function setTradingRules(
        TradingRules calldata _tradingRules
    ) external onlyOwner {
        Storage storage $ = getStorage();
        $.tradingRules = _tradingRules;
    }

    function oracle() external view returns (address) {
        Storage storage $ = getStorage();
        return address($.oracle);
    }

    function setOracle(address _oracle) external {
        Storage storage $ = getStorage();
        $.oracle = IOracle(_oracle);
    }

    function setAutoBorrowHelper(address _helper) external onlyOwner {
        Storage storage $ = getStorage();
        $.autoBorrowHelper = _helper;
    }

    function validateOrder(
        uint128 price,
        uint128 quantity,
        Side side,
        OrderType orderType,
        TimeInForce timeInForce
    ) private view {
        Storage storage $ = getStorage();

        if(side == Side.BUY && orderType == OrderType.MARKET) {
            return;
        }

        (uint256 orderAmount, uint256 quoteAmount) = calculateOrderAmounts(price, quantity, side, orderType);

        validateMinimumSizes(orderAmount, quoteAmount);

        // Check price increments
        uint256 minPriceMove = $.tradingRules.minPriceMovement;
        if (price % minPriceMove != 0) {
            revert InvalidPriceIncrement();
        }

        if (orderType == OrderType.LIMIT) {
            validateLimitOrder(price, side, timeInForce);
        }
    }

    function validateBasicOrderParameters(uint128 price, uint128 quantity, OrderType orderType) private pure {
        if (quantity == 0) {
            revert InvalidQuantity();
        }

        if (orderType == OrderType.LIMIT && price == 0) {
            revert InvalidPrice(price);
        }
    }

    function calculateOrderAmounts(
        uint128 price,
        uint128 quantity,
        Side side,
        OrderType orderType
    ) private view returns (uint256 orderAmount, uint256 quoteAmount) {
        orderAmount = quantity;

        if (orderType == OrderType.LIMIT) {
            quoteAmount = _calculateLimitOrderQuoteAmount(orderAmount, price);
        } else {
            quoteAmount = _calculateMarketOrderQuoteAmount(orderAmount, side);
        }

        return (orderAmount, quoteAmount);
    }

    function _calculateLimitOrderQuoteAmount(uint256 orderAmount, uint128 price) private view returns (uint256) {
        Storage storage $ = getStorage();
        return PoolIdLibrary.baseToQuote(orderAmount, price, $.poolKey.baseCurrency.decimals());
    }

    function _calculateMarketOrderQuoteAmount(uint256 orderAmount, Side side) private view returns (uint256) {
        Storage storage $ = getStorage();
        bytes32 bestOppositePricePtr =
            side == Side.SELL ? $.priceTrees[Side.BUY].last() : $.priceTrees[Side.SELL].first();
        uint128 bestOppositePrice = uint128(RedBlackTreeLib.value(bestOppositePricePtr));

        if (bestOppositePrice == 0) {
            revert OrderHasNoLiquidity();
        }

        return PoolIdLibrary.baseToQuote(orderAmount, bestOppositePrice, $.poolKey.baseCurrency.decimals());
    }

    function validateMinimumSizes(uint256 orderAmount, uint256 quoteAmount) private view {
        Storage storage $ = getStorage();
        // Validate minimum order size (quote currency)
        uint256 minSize = $.tradingRules.minOrderSize;

        if (quoteAmount < minSize) {
            revert OrderTooSmall(quoteAmount, minSize);
        }

        // Validate minimum trade amount (base currency)
        uint256 minAmount = $.tradingRules.minTradeAmount;
        if (orderAmount < minAmount) {
            revert OrderTooSmall(orderAmount, minAmount);
        }
    }

    function validateLimitOrder(uint128 price, Side side, TimeInForce timeInForce) private view returns (uint128) {
        Storage storage $ = getStorage();
        if (timeInForce == TimeInForce.PO) {
            bytes32 bestOppositePricePtr =
                side == Side.BUY ? $.priceTrees[Side.SELL].first() : $.priceTrees[Side.BUY].last();
            uint128 bestOppositePrice = uint128(RedBlackTreeLib.value(bestOppositePricePtr));

            if (bestOppositePrice != 0) {
                bool wouldTake = side == Side.BUY ? price >= bestOppositePrice : price <= bestOppositePrice;

                if (wouldTake) {
                    revert PostOnlyWouldTake();
                }
            }
        }

        return price;
    }

    function placeOrder(
        uint128 price,
        uint128 quantity,
        Side side,
        address user,
        TimeInForce timeInForce,
        bool autoRepay,
        bool autoBorrow
    ) external onlyRouter returns (uint48 orderId) {
        Storage storage $ = getStorage();
        validateOrder(price, quantity, side, OrderType.LIMIT, timeInForce);

        // Validate auto-repay if enabled
        if (autoRepay) {
            _validateAutoRepay(user, side);
        }

        orderId = $.nextOrderId;

        Order memory newOrder = Order({
            id: orderId,
            user: user,
            next: 0,
            prev: 0,
            price: price,
            quantity: quantity,
            filled: 0,
            expiry: uint48(block.timestamp + $.expiryDays),
            status: Status.OPEN,
            orderType: OrderType.LIMIT,
            side: side,
            autoRepay: autoRepay,
            autoBorrow: autoBorrow
        });

        // Validate balance before locking (supports autoBorrow)
        uint256 amountToLock;
        Currency currencyToLock;
        if (side == Side.BUY) {
            amountToLock = PoolIdLibrary.baseToQuote(quantity, price, $.poolKey.baseCurrency.decimals());
            currencyToLock = $.poolKey.quoteCurrency;
        } else {
            amountToLock = quantity;
            currencyToLock = $.poolKey.baseCurrency;
        }
        // Validate and execute auto-borrow if needed (before locking)
        if ($.autoBorrowHelper != address(0)) {
            IAutoBorrowHelper($.autoBorrowHelper).validateAndBorrowIfNeeded(
                $.balanceManager, user, currencyToLock, amountToLock, autoBorrow
            );
        }

        // Inline lock amount to save bytecode
        {
            uint256 amountToLock;
            Currency currencyToLock;
            if (side == Side.BUY) {
                amountToLock = PoolIdLibrary.baseToQuote(quantity, price, $.poolKey.baseCurrency.decimals());
                currencyToLock = $.poolKey.quoteCurrency;
            } else {
                amountToLock = quantity;
                currencyToLock = $.poolKey.baseCurrency;
            }
            IBalanceManager($.balanceManager).lock(user, currencyToLock, amountToLock);
        }

        _addOrderToQueue(newOrder);

        emit OrderPlaced(orderId, user, side, price, quantity, newOrder.expiry, false, Status.OPEN, autoRepay, autoBorrow, timeInForce);

        _handleTimeInForce(newOrder, side, user, timeInForce);

        _validateNoNegativeSpread();

        unchecked {
            $.nextOrderId++;
        }

        return orderId;
    }

    function _validateAutoRepay(address user, Side side) private view {
        // Auto-repay works for both BUY and SELL orders:
        // - BUY orders: receive base tokens (synthetic), can repay base underlying debt
        // - SELL orders: receive quote tokens (synthetic), can repay quote underlying debt
        IBalanceManager bm = IBalanceManager(getStorage().balanceManager);
        address lendingManager = bm.lendingManager();

        // Determine synthetic token based on order side (token user will receive)
        address syntheticToken = side == Side.BUY
            ? Currency.unwrap(getStorage().poolKey.baseCurrency)
            : Currency.unwrap(getStorage().poolKey.quoteCurrency);

        // Get the underlying token from the synthetic token
        // Debt is tracked in underlying tokens, not synthetic tokens
        address debtToken = _getUnderlyingToken(syntheticToken);

        if (lendingManager != address(0)) {
            try ILendingManager(lendingManager).getUserDebt(user, debtToken) returns (uint256 userDebt) {
                if (userDebt == 0) {
                    revert NoDebtToRepay();
                }
            } catch {
                // If LendingManager call fails, allow order placement anyway
            }
        }
    }

    /// @dev Get underlying token from synthetic token using BalanceManager's mapping
    function _getUnderlyingToken(address syntheticToken) private view returns (address) {
        Storage storage $ = getStorage();
        IBalanceManager bm = IBalanceManager($.balanceManager);

        // Use BalanceManager's mapping to find underlying token
        address[] memory supportedAssets = bm.getSupportedAssets();
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            if (bm.getSyntheticToken(supportedAssets[i]) == syntheticToken) {
                return supportedAssets[i];
            }
        }

        return syntheticToken; // Fallback to the token itself
    }


    /// @dev Validates that no negative spread exists (best bid < best ask)
    /// @notice This catches cases where self-trade prevention skips matches, creating crossed markets
    function _validateNoNegativeSpread() private view {
        Storage storage $ = getStorage();

        // Get best bid (highest buy price)
        bytes32 bestBidPtr = $.priceTrees[Side.BUY].last();
        uint128 bestBid = uint128(RedBlackTreeLib.value(bestBidPtr));

        // Get best ask (lowest sell price)
        bytes32 bestAskPtr = $.priceTrees[Side.SELL].first();
        uint128 bestAsk = uint128(RedBlackTreeLib.value(bestAskPtr));

        // If either side is empty, no spread issue
        if (bestBid == 0 || bestAsk == 0) {
            return;
        }

        // Negative spread: best bid >= best ask (should have matched but didn't)
        if (bestBid >= bestAsk) {
            revert NegativeSpreadCreated(bestBid, bestAsk);
        }
    }




    function _handleTimeInForce(
        Order memory order,
        Side side,
        address user,
        TimeInForce timeInForce
    ) private returns (uint128 filled) {
        Storage storage $ = getStorage();
        filled = 0;

        if (timeInForce != TimeInForce.PO) {
            filled = _matchOrder(order, side, user, false);
        }

        $.orders[order.id].filled = filled;
        $.orderQueues[side][order.price].totalVolume -= filled;

        if (filled == order.quantity) {
            _removeOrderFromQueue($.orderQueues[side][order.price], $.orders[order.id]);
            emit UpdateOrder(order.id, uint48(block.timestamp), filled, Status.FILLED);
        }

        if (timeInForce == TimeInForce.FOK && filled < uint128(order.quantity)) {
            revert FillOrKillNotFulfilled(filled, uint128(order.quantity));
        } else if (timeInForce == TimeInForce.IOC && filled < uint128(order.quantity)) {
            Order storage orderToCancel = $.orders[order.id];
            if (orderToCancel.quantity > orderToCancel.filled) {
                _cancelOrder(order.id, user);
            }
        }

        return filled;
    }

    function placeMarketOrder(
        uint128 quantity,
        Side side,
        address user,
        bool autoRepay,
        bool autoBorrow
    ) external onlyRouter nonReentrant returns (uint48 orderId, uint128 receivedAmount) {
        Storage storage $ = getStorage();
        Side oppositeSide = side == Side.BUY ? Side.SELL : Side.BUY;
        bytes32 bestPricePtr = oppositeSide == Side.BUY 
            ? $.priceTrees[oppositeSide].last() 
            : $.priceTrees[oppositeSide].first();
        
        if (RedBlackTreeLib.value(bestPricePtr) == 0) {
            revert OrderHasNoLiquidity();
        }
        
        if (side == Side.BUY) {
            return _placeMarketOrderWithQuoteAmount(quantity, side, user, autoRepay, autoBorrow);
        }

        validateBasicOrderParameters(0, quantity, OrderType.MARKET);

        // Market orders: validate balance (borrow happens during matching)
        if ($.autoBorrowHelper != address(0)) {
            IAutoBorrowHelper($.autoBorrowHelper).validateBalanceOnly(
                $.balanceManager, user, $.poolKey.baseCurrency, quantity, autoBorrow
            );
        }

        orderId = $.nextOrderId;

        Order memory marketOrder = Order({
            id: orderId,
            user: user,
            next: 0,
            prev: 0,
            price: 0,
            quantity: quantity,
            filled: 0,
            expiry: uint48(block.timestamp + $.expiryDays),
            status: Status.OPEN,
            orderType: OrderType.MARKET,
            side: side,
            autoRepay: autoRepay,
            autoBorrow: autoBorrow
        });

        emit OrderPlaced(orderId, user, side, 0, quantity, marketOrder.expiry, true, Status.OPEN, autoRepay, autoBorrow, TimeInForce.IOC);

        uint128 filled = _matchOrder(marketOrder, side, user, true);

        // Update market order status based on execution result
        Status finalStatus = filled == 0 ? Status.EXPIRED :
                           filled == quantity ? Status.FILLED : Status.PARTIALLY_FILLED;

        emit UpdateOrder(orderId, uint48(block.timestamp), filled, finalStatus);

        IBalanceManager bm = IBalanceManager($.balanceManager);
        uint256 feeTaker = bm.feeTaker();
        uint256 feeUnit = bm.getFeeUnit();
        // address feeReceiver = bm.feeReceiver();

        uint128 feeAmount = uint128(uint256(filled) * feeTaker / feeUnit);
        receivedAmount = filled > feeAmount ? filled - feeAmount : 0;

        unchecked {
            $.nextOrderId++;
        }

        return (orderId, receivedAmount);
    }

    function _placeMarketOrderWithQuoteAmount(
        uint128 quoteAmount,
        Side side,
        address user,
        bool autoRepay,
        bool autoBorrow
    ) private returns (uint48 orderId, uint128 receivedAmount) {
        Storage storage $ = getStorage();

        if (side != Side.BUY) {
            revert InvalidSideForQuoteAmount();
        }

        if (quoteAmount < $.tradingRules.minOrderSize) {
            revert OrderTooSmall(quoteAmount, $.tradingRules.minOrderSize);
        }

        // Market orders: validate balance (borrow happens during matching)
        if ($.autoBorrowHelper != address(0)) {
            IAutoBorrowHelper($.autoBorrowHelper).validateBalanceOnly(
                $.balanceManager, user, $.poolKey.quoteCurrency, quoteAmount, autoBorrow
            );
        }

        orderId = $.nextOrderId;

        Order memory marketOrder = Order({
            id: orderId,
            user: user,
            next: 0,
            prev: 0,
            price: 0,
            quantity: quoteAmount,
            filled: 0,
            expiry: uint48(block.timestamp + $.expiryDays),
            status: Status.OPEN,
            orderType: OrderType.MARKET,
            side: side,
            autoRepay: autoRepay,
            autoBorrow: autoBorrow
        });

        emit OrderPlaced(orderId, user, side, 0, quoteAmount, marketOrder.expiry, true, Status.OPEN, autoRepay, autoBorrow, TimeInForce.IOC);

        uint128 baseAmountFilled = _matchOrderWithQuoteAmount(marketOrder, side, user, quoteAmount);

        // Update market order status based on execution result
        Status finalStatus = baseAmountFilled == 0 ? Status.EXPIRED : Status.FILLED;

        emit UpdateOrder(orderId, uint48(block.timestamp), baseAmountFilled, finalStatus);

        IBalanceManager bm = IBalanceManager($.balanceManager);
        uint256 feeTaker = bm.feeTaker();
        uint256 feeUnit = bm.getFeeUnit();

        uint128 feeAmount = uint128(uint256(baseAmountFilled) * feeTaker / feeUnit);
        receivedAmount = baseAmountFilled > feeAmount ? baseAmountFilled - feeAmount : 0;

        unchecked {
            $.nextOrderId++;
        }

        return (orderId, receivedAmount);
    }

    struct QuoteMatchContext {
        uint128 bestPrice;
        uint128 remainingQuoteAmount;
        uint128 totalBaseAmountFilled;
        address user;
        uint8 baseDecimals;
        Currency quoteCurrency;
        bool encounteredNonSelfOrder;
        uint128 lastSkippedPrice;
    }

    function _matchOrderWithQuoteAmount(
        Order memory order,
        Side /* side */,
        address user,
        uint128 quoteAmount
    ) private returns (uint128) {
        Storage storage $ = getStorage();
        Side oppositeSide = Side.SELL;

        QuoteMatchContext memory ctx = QuoteMatchContext({
            bestPrice: 0,
            remainingQuoteAmount: quoteAmount,
            totalBaseAmountFilled: 0,
            user: user,
            baseDecimals: $.poolKey.baseCurrency.decimals(),
            quoteCurrency: $.poolKey.quoteCurrency,
            encounteredNonSelfOrder: false,
            lastSkippedPrice: 0
        });

        uint256 loopCount = 0;
        while (ctx.remainingQuoteAmount > 0) {
            loopCount++;
            uint128 prevRemaining = ctx.remainingQuoteAmount;
            ctx.encounteredNonSelfOrder = false; 
            
            ctx.bestPrice = _getNextAvailablePrice(oppositeSide, ctx.lastSkippedPrice);
            
            if (ctx.bestPrice == 0) {
                break;
            }

            OrderQueue storage queue = $.orderQueues[oppositeSide][ctx.bestPrice];
            
            ctx = _matchAtPriceLevelWithQuoteAmount(order, queue, ctx);
            
            _updatePriceLevel(ctx.bestPrice, queue, $.priceTrees[oppositeSide]);

            if (ctx.remainingQuoteAmount == prevRemaining && ctx.encounteredNonSelfOrder) {
                break;
            } else if (ctx.remainingQuoteAmount == prevRemaining && !ctx.encounteredNonSelfOrder) {
                ctx.lastSkippedPrice = ctx.bestPrice;
            }
            
            if (loopCount > 10) {
                break;
            }
        }

        return ctx.totalBaseAmountFilled;
    }

    function _matchAtPriceLevelWithQuoteAmount(
        Order memory order,
        OrderQueue storage queue,
        QuoteMatchContext memory ctx
    ) private returns (QuoteMatchContext memory) {
        Storage storage $ = getStorage();
        uint48 currentOrderId = queue.head;
        while (currentOrderId != 0 && ctx.remainingQuoteAmount > 0) {
            Order storage matchingOrder = $.orders[currentOrderId];
            if (matchingOrder.expiry < block.timestamp) {
                _handleExpiredOrder(queue, matchingOrder);
                currentOrderId = matchingOrder.next;
                continue;
            }

            if (matchingOrder.user == ctx.user) {
                currentOrderId = matchingOrder.next;
                continue;
            }
            
            ctx.encounteredNonSelfOrder = true;

            uint128 maxBase = uint128(
                PoolIdLibrary.quoteToBase(ctx.remainingQuoteAmount, ctx.bestPrice, ctx.baseDecimals)
            );
            uint128 available = matchingOrder.quantity - matchingOrder.filled;
            uint128 baseAmount = available < maxBase ? available : maxBase;

            if (baseAmount == 0) {
                break;
            }

            uint128 quoteAmount = uint128(
                PoolIdLibrary.baseToQuote(baseAmount, ctx.bestPrice, ctx.baseDecimals)
            );

            IBalanceManager bm = IBalanceManager($.balanceManager);
            if (bm.getBalance(ctx.user, ctx.quoteCurrency) < quoteAmount) {
                baseAmount = uint128(
                    PoolIdLibrary.quoteToBase(bm.getBalance(ctx.user, ctx.quoteCurrency), ctx.bestPrice, ctx.baseDecimals)
                );
                if (baseAmount == 0) break;
                quoteAmount = uint128(
                    PoolIdLibrary.baseToQuote(baseAmount, ctx.bestPrice, ctx.baseDecimals)
                );
            }

            ctx.remainingQuoteAmount -= quoteAmount;
            ctx.totalBaseAmountFilled += baseAmount;
            matchingOrder.filled += baseAmount;
            queue.totalVolume -= baseAmount;

            transferBalances(ctx.user, matchingOrder.user, ctx.bestPrice, baseAmount, Side.BUY, true, order.id, order.autoRepay);

            if (matchingOrder.filled == matchingOrder.quantity) {
                _removeOrderFromQueue(queue, matchingOrder);
                matchingOrder.status = Status.FILLED;
                emit UpdateOrder(matchingOrder.id, uint48(block.timestamp), matchingOrder.filled, Status.FILLED);
            } else {
                matchingOrder.status = Status.PARTIALLY_FILLED;
                emit UpdateOrder(matchingOrder.id, uint48(block.timestamp), matchingOrder.filled, Status.PARTIALLY_FILLED);
            }

            
            // Update Oracle with real-time price from this trade
            _updateOracleFromTrade(ctx.bestPrice, baseAmount);

            emit OrderMatched(
                ctx.user,
                order.id,
                matchingOrder.id,
                Side.BUY,
                uint48(block.timestamp),
                ctx.bestPrice,
                baseAmount
            );

            currentOrderId = matchingOrder.next;
        }

        return ctx;
    }

    function cancelOrder(uint48 orderId, address user) external onlyRouter {
        _cancelOrder(orderId, user);
    }

    function _cancelOrder(uint48 orderId, address user) private {
        Storage storage $ = getStorage();
        Order storage order = $.orders[orderId];
        IOrderBook.OrderQueue storage queue = $.orderQueues[order.side][order.price];

        if (order.user != user) {
            revert UnauthorizedCancellation();
        }

        IOrderBook.Status orderStatus = order.status;

        if (orderStatus != Status.OPEN && orderStatus != Status.PARTIALLY_FILLED) {
            revert OrderIsNotOpenOrder(uint8(orderStatus));
        }

        order.status = Status.CANCELLED;

        uint128 remainingQuantity = order.quantity - order.filled;

        _removeOrderFromQueue(queue, order);

        emit OrderCancelled(orderId, user, uint48(block.timestamp), Status.CANCELLED);

        uint256 amountToUnlock;
        if (order.side == Side.BUY) {
            amountToUnlock =
                PoolIdLibrary.baseToQuote(remainingQuantity, order.price, $.poolKey.baseCurrency.decimals());
        } else {
            amountToUnlock = remainingQuantity;
        }

        IBalanceManager($.balanceManager).unlock(
            user, order.side == Side.BUY ? $.poolKey.quoteCurrency : $.poolKey.baseCurrency, amountToUnlock
        );

        if (isQueueEmpty(order.side, order.price)) {
            RedBlackTreeLib.remove($.priceTrees[order.side], order.price);
        }
    }

    function getBestPrice(
        Side side
    ) external view override returns (PriceVolume memory) {
        Storage storage $ = getStorage();
        bytes32 pricePtr = side == Side.BUY ? $.priceTrees[side].last() : $.priceTrees[side].first();
        uint128 price = uint128(RedBlackTreeLib.value(pricePtr));

        return PriceVolume({price: price, volume: $.orderQueues[side][price].totalVolume});
    }

    function getOrderQueue(Side side, uint128 price) external view returns (uint48 orderCount, uint256 totalVolume) {
        Storage storage $ = getStorage();
        IOrderBook.OrderQueue storage queue = $.orderQueues[side][price];
        orderCount = queue.orderCount;
        totalVolume = queue.totalVolume;
    }

    function getOrder(
        uint48 orderId
    ) external view returns (Order memory) {
        Storage storage $ = getStorage();
        return $.orders[orderId];
    }

    function _handleExpiredOrder(IOrderBook.OrderQueue storage queue, IOrderBook.Order storage order) private {
        _removeOrderFromQueue(queue, order);
        emit UpdateOrder(order.id, uint48(block.timestamp), 0, Status.EXPIRED);
    }

    function _processMatchingOrder(
        MatchContext memory ctx,
        Order storage matchingOrder,
        OrderQueue storage queue
    ) private returns (uint128, uint128) {
        uint128 matchingRemaining = matchingOrder.quantity - matchingOrder.filled;
        uint128 executedQuantity = ctx.remaining < matchingRemaining ? ctx.remaining : matchingRemaining;

        if (ctx.isMarketOrder) {
            executedQuantity = _handleMarketOrderBalanceCheck(ctx, executedQuantity);
            if (executedQuantity == 0) {
                return (0, ctx.filled);
            }
        }

        ctx.remaining -= executedQuantity;
        ctx.filled += executedQuantity;

        matchingOrder.filled += executedQuantity;
        queue.totalVolume -= executedQuantity;

        transferBalances(ctx.user, matchingOrder.user, ctx.bestPrice, executedQuantity, ctx.side, ctx.isMarketOrder, ctx.order.id, ctx.order.autoRepay);

        if (matchingOrder.filled == matchingOrder.quantity) {
            _removeOrderFromQueue(queue, matchingOrder);
            matchingOrder.status = Status.FILLED;
            emit UpdateOrder(matchingOrder.id, uint48(block.timestamp), matchingOrder.filled, Status.FILLED);
        } else {
            matchingOrder.status = Status.PARTIALLY_FILLED;
            emit UpdateOrder(matchingOrder.id, uint48(block.timestamp), matchingOrder.filled, Status.PARTIALLY_FILLED);
        }

        // Check for auto-borrow on successful order fills
        // Auto-borrow works for both orders in the match
        if (matchingOrder.autoBorrow) {
            _handleAutoBorrow(matchingOrder.user, executedQuantity, ctx.bestPrice, matchingOrder.side, matchingOrder.id);
        }

        // Also check auto-borrow for the primary order (ctx.order)
        if (ctx.order.autoBorrow) {
            // Calculate the amount for the primary order based on side
            uint256 primaryOrderAmount = executedQuantity;
            _handleAutoBorrow(ctx.user, primaryOrderAmount, ctx.bestPrice, ctx.order.side, ctx.order.id);
        }

        // Update Oracle with real-time price from this trade
        _updateOracleFromTrade(ctx.bestPrice, executedQuantity);

        emit OrderMatched(
            ctx.user,
            ctx.side == Side.BUY ? ctx.order.id : matchingOrder.id,
            ctx.side == Side.SELL ? ctx.order.id : matchingOrder.id,
            ctx.side,
            uint48(block.timestamp),
            ctx.bestPrice,
            executedQuantity
        );

        return (ctx.remaining, ctx.filled);
    }

    function _handleMarketOrderBalanceCheck(
        MatchContext memory ctx,
        uint128 executedQuantity
    ) private returns (uint128) {
        Storage storage $ = getStorage();
        IBalanceManager bm = IBalanceManager($.balanceManager);
        
        uint256 requiredAmount;
        Currency currency;
        
        if (ctx.side == IOrderBook.Side.BUY) {
            requiredAmount = PoolIdLibrary.baseToQuote(executedQuantity, ctx.bestPrice, $.poolKey.baseCurrency.decimals());
            currency = $.poolKey.quoteCurrency;
        } else {
            requiredAmount = executedQuantity;
            currency = $.poolKey.baseCurrency;
        }
        
        uint256 userBalance = bm.getBalance(ctx.user, currency);

        if (userBalance < requiredAmount) {
            uint128 affordableQuantity;
            if (ctx.side == IOrderBook.Side.BUY) {
                affordableQuantity = uint128(
                    PoolIdLibrary.quoteToBase(userBalance, ctx.bestPrice, $.poolKey.baseCurrency.decimals())
                );
            } else {
                affordableQuantity = uint128(userBalance);
            }

            ctx.previousRemaining = affordableQuantity;

            if (affordableQuantity == 0 || ctx.previousRemaining == affordableQuantity) {
                return 0;
            }

            return affordableQuantity < executedQuantity ? affordableQuantity : executedQuantity;
        }
        
        return executedQuantity;
    }

    function _updatePriceLevel(
        uint128 bestPrice,
        OrderQueue storage queue,
        RedBlackTreeLib.Tree storage priceTree
    ) private {
        if (queue.orderCount == 0 && priceTree.exists(bestPrice)) {
            priceTree.remove(bestPrice);
        }
    }

    function _matchOrder(Order memory order, Side side, address user, bool isMarketOrder) private returns (uint128) {
        Storage storage $ = getStorage();
        Side oppositeSide = side == Side.BUY ? Side.SELL : Side.BUY;
        MatchState memory s = MatchState({
            remaining: order.quantity - order.filled,
            orderPrice: order.price,
            latestBestPrice: 0,
            previousRemaining: 0,
            filled: 0
        });

        uint256 loopCount = 0;
        while (s.remaining > 0) {
            loopCount++;
            uint128 prevRemaining = s.remaining;
            
            uint128 bestPrice = _getBestMatchingPrice(s.orderPrice, oppositeSide, isMarketOrder);
            if (bestPrice == 0) {
                break;
            }

            if (bestPrice == s.latestBestPrice && s.previousRemaining == s.remaining) {
                bytes32 ptr = $.priceTrees[oppositeSide].find(bestPrice);
                bestPrice = side == Side.BUY
                    ? uint128(RedBlackTreeLib.value(RedBlackTreeLib.next(ptr)))
                    : uint128(RedBlackTreeLib.value(RedBlackTreeLib.prev(ptr)));
                if (bestPrice == 0) {
                    break;
                }
            }

            s.latestBestPrice = bestPrice;
            s.previousRemaining = s.remaining;
            OrderQueue storage queue = $.orderQueues[oppositeSide][bestPrice];

            (s.remaining, s.filled) =
                _matchAtPriceLevel(order, queue, bestPrice, s.remaining, s.filled, side, user, isMarketOrder);
            _updatePriceLevel(bestPrice, queue, $.priceTrees[oppositeSide]);
            
            if (s.remaining == prevRemaining) {
                break;
            }
            
            if (loopCount > 10) {
                break;
            }
        }

        return s.filled;
    }

    function _matchAtPriceLevel(
        Order memory order,
        OrderQueue storage queue,
        uint128 bestPrice,
        uint128 remaining,
        uint128 filled,
        Side side,
        address user,
        bool isMarketOrder
    ) private returns (uint128, uint128) {
        MatchContext memory ctx = MatchContext({
            order: order,
            side: side,
            user: user,
            isMarketOrder: isMarketOrder,
            bestPrice: bestPrice,
            remaining: remaining,
            previousRemaining: remaining,
            filled: filled
        });

        (ctx.remaining, ctx.filled) = _processOrderQueue(queue, ctx);
        return (ctx.remaining, ctx.filled);
    }

    function _processOrderQueue(OrderQueue storage queue, MatchContext memory ctx) private returns (uint128, uint128) {
        Storage storage $ = getStorage();
        uint48 currentOrderId = queue.head;

        while (currentOrderId != 0 && ctx.remaining > 0) {
            Order storage matchingOrder = $.orders[currentOrderId];
            uint48 nextOrderId = matchingOrder.next;

            if (matchingOrder.expiry < block.timestamp) {
                _handleExpiredOrder(queue, matchingOrder);
            } else if (matchingOrder.user != ctx.user) {
                ctx.previousRemaining = ctx.remaining;
                (ctx.remaining, ctx.filled) = _processMatchingOrder(ctx, matchingOrder, queue);
            }
            currentOrderId = nextOrderId;
        }
        return (ctx.remaining, ctx.filled);
    }

    function getNextBestPrices(
        Side side,
        uint128 price,
        uint8 count
    ) external view override returns (PriceVolume[] memory) {
        Storage storage $ = getStorage();
        PriceVolume[] memory levels = new PriceVolume[](count);
        uint128 currentPrice = price;

        for (uint8 i = 0; i < count; i++) {
            currentPrice = _getNextBestPrice(side, currentPrice);
            if (currentPrice == 0) {
                break;
            }

            levels[i] = PriceVolume({price: currentPrice, volume: $.orderQueues[side][currentPrice].totalVolume});
        }

        return levels;
    }

    function _getNextBestPrice(Side side, uint128 price) private view returns (uint128) {
        Storage storage $ = getStorage();
        RedBlackTreeLib.Tree storage priceTree = $.priceTrees[side];

        bytes32 pricePtr;
        if (price == 0) {
            // Get the first or last price based on the side
            pricePtr = side == Side.BUY ? priceTree.last() : priceTree.first();
        } else {
            // Find the pointer for the current price
            bytes32 currentPricePtr = priceTree.find(uint256(price));
            // Traverse to the next or previous price based on the side
            pricePtr = side == Side.BUY ? RedBlackTreeLib.prev(currentPricePtr) : RedBlackTreeLib.next(currentPricePtr);
        }

        // Return the price value if the pointer is valid
        return pricePtr != bytes32(0) ? uint128(RedBlackTreeLib.value(pricePtr)) : 0;
    }

    function _getNextAvailablePrice(
        IOrderBook.Side oppositeSide,
        uint128 skipPrice
    ) private view returns (uint128) {
        Storage storage $ = getStorage();
        RedBlackTreeLib.Tree storage oppositePriceTree = $.priceTrees[oppositeSide];
        
        if (skipPrice == 0) {
            bytes32 oppositePricePtr =
                oppositeSide == IOrderBook.Side.BUY ? oppositePriceTree.last() : oppositePriceTree.first();
            return uint128(RedBlackTreeLib.value(oppositePricePtr));
        } else {
            bytes32 ptr = oppositePriceTree.find(skipPrice);
            bytes32 nextPtr = oppositeSide == IOrderBook.Side.BUY 
                ? RedBlackTreeLib.prev(ptr)  
                : RedBlackTreeLib.next(ptr);
            return uint128(RedBlackTreeLib.value(nextPtr));
        }
    }

    function _getBestMatchingPrice(
        uint128 orderPrice,
        IOrderBook.Side oppositeSide,
        bool isMarketOrder
    ) private view returns (uint128) {
        Storage storage $ = getStorage();
        RedBlackTreeLib.Tree storage oppositePriceTree = $.priceTrees[oppositeSide];

        bytes32 oppositePricePtr =
            oppositeSide == IOrderBook.Side.BUY ? oppositePriceTree.last() : oppositePriceTree.first();
        uint128 oppositePrice = uint128(RedBlackTreeLib.value(oppositePricePtr));

        if (isMarketOrder) {
            return oppositePrice;
        }

        if (oppositePrice > 0) {
            if (
                (oppositeSide == IOrderBook.Side.BUY && orderPrice <= oppositePrice)
                    || (oppositeSide == IOrderBook.Side.SELL && orderPrice >= oppositePrice)
            ) {
                return oppositePrice;
            }
        }

        return oppositePriceTree.exists(orderPrice) ? orderPrice : 0;
    }

    function transferBalances(
        address trader,
        address matchingUser,
        uint128 matchPrice,
        uint128 executedQuantity,
        IOrderBook.Side side,
        bool isMarketOrder,
        uint48 traderOrderId,
        bool traderAutoRepay
    ) private {
        Storage storage $ = getStorage();
        IBalanceManager bm = IBalanceManager($.balanceManager);
        uint256 baseAmount = executedQuantity;
        uint256 quoteAmount = PoolIdLibrary.baseToQuote(baseAmount, matchPrice, $.poolKey.baseCurrency.decimals());

        if (side == IOrderBook.Side.SELL) {
            _handleSellTransfer(bm, trader, matchingUser, baseAmount, quoteAmount, isMarketOrder);

            // Check for auto-repay on successful SELL orders only if enabled
            // SELL orders receive quote tokens, can repay quote token debt
            if (traderAutoRepay) {
                _handleAutoRepay(trader, quoteAmount, matchPrice, side, traderOrderId);
            }
        } else {
            _handleBuyTransfer(bm, trader, matchingUser, baseAmount, quoteAmount, isMarketOrder);

            // Check for auto-repay on successful BUY orders only if enabled
            // BUY orders receive base tokens, can repay base token debt
            if (traderAutoRepay) {
                _handleAutoRepay(trader, baseAmount, matchPrice, side, traderOrderId);
            }
        }
    }

    function _handleSellTransfer(
        IBalanceManager bm,
        address trader,
        address matchingUser,
        uint256 baseAmount,
        uint256 quoteAmount,
        bool isMarketOrder
    ) private {
        Storage storage $ = getStorage();
        
        if (!isMarketOrder) {
            bm.unlock(trader, $.poolKey.baseCurrency, baseAmount);
        }

        // Transfer base currency from trader to matching user
        bm.transferFrom(trader, matchingUser, $.poolKey.baseCurrency, baseAmount);

        // Transfer quote currency from matching user to trader
        bm.transferLockedFrom(
            matchingUser, trader, $.poolKey.quoteCurrency, quoteAmount
        );
    }

    function _handleBuyTransfer(
        IBalanceManager bm,
        address trader,
        address matchingUser,
        uint256 baseAmount,
        uint256 quoteAmount,
        bool isMarketOrder
    ) private {
        Storage storage $ = getStorage();
        
        if (!isMarketOrder) {
            bm.unlock(trader, $.poolKey.quoteCurrency, quoteAmount);
        }
        
        // Transfer quote currency from trader to matching user
        bm.transferFrom(trader, matchingUser, $.poolKey.quoteCurrency, quoteAmount);

        // Transfer base currency from matching user to trader
        bm.transferLockedFrom(
            matchingUser, trader, $.poolKey.baseCurrency, baseAmount
        );
    }

    function _addOrderToQueue(
        IOrderBook.Order memory _order
    ) private {
        Storage storage $ = getStorage();
        IOrderBook.OrderQueue storage queue = $.orderQueues[_order.side][_order.price];
        Order storage order = $.orders[_order.id];

        order.id = _order.id;
        order.user = _order.user;
        order.next = _order.next;
        order.prev = _order.prev;
        order.price = _order.price;
        order.quantity = _order.quantity;
        order.filled = _order.filled;
        order.expiry = _order.expiry;
        order.status = _order.status;
        order.orderType = _order.orderType;
        order.side = _order.side;
        order.autoRepay = _order.autoRepay;
        order.autoBorrow = _order.autoBorrow;

        if (queue.head == 0) {
            queue.head = _order.id;
            queue.tail = _order.id;
        } else {
            $.orders[queue.tail].next = _order.id;
            order.prev = queue.tail;
            queue.tail = _order.id;
        }

        unchecked {
            queue.totalVolume += uint256(_order.quantity);
            queue.orderCount++;
        }

        RedBlackTreeLib.Tree storage priceTree = $.priceTrees[_order.side];

        if (!RedBlackTreeLib.exists(priceTree, uint256(_order.price))) {
            RedBlackTreeLib.insert(priceTree, (_order.price));
        }
    }

    function _removeOrderFromQueue(
        IOrderBook.OrderQueue storage queue,
        IOrderBook.Order storage order
    ) private returns (uint256) {
        Storage storage $ = getStorage();

        if (queue.orderCount == 0) {
            revert QueueEmpty();
        }

        uint256 remainingQuantity = order.quantity - order.filled;

        // Update queue pointers
        if (order.prev != 0) {
            $.orders[order.prev].next = order.next;
        } else {
            queue.head = order.next;
        }

        if (order.next != 0) {
            $.orders[order.next].prev = order.prev;
        } else {
            queue.tail = order.prev;
        }

        queue.orderCount--;
        queue.totalVolume -= remainingQuantity;

        return remainingQuantity;
    }

    function isQueueEmpty(IOrderBook.Side side, uint128 price) private view returns (bool) {
        Storage storage $ = getStorage();
        return $.orderQueues[side][price].orderCount == 0;
    }

    function _updateOracleFromTrade(uint128 tradePrice, uint256 tradeVolume) private {
        Storage storage $ = getStorage();

        // Only update Oracle if it's set and trade volume is significant
        if (address($.oracle) != address(0) && tradeVolume >= $.tradingRules.minTradeAmount) {
            $.oracle.updatePriceFromTrade(
                Currency.unwrap($.poolKey.baseCurrency), // Base currency of the pool
                tradePrice,
                tradeVolume
            );
            // If Oracle update fails, the entire trade will revert
            // This ensures Oracle issues are immediately visible
        }
    }

    function updateTradingRules(
        TradingRules memory _newRules
    ) external {
        Storage storage $ = getStorage();

        if (msg.sender != owner()) {
            revert NotAuthorized();
        }

        $.tradingRules = _newRules;

        emit TradingRulesUpdated($.poolKey.toId(), _newRules);
    }

    // =============================================================
    //                   AUTO-REPAY HELPERS
    // =============================================================

    function _handleAutoRepay(
        address user,
        uint256 receivedAmount,
        uint128 fillPrice,
        Side orderSide,
        uint48 orderId
    ) private {
        Storage storage $ = getStorage();
        IBalanceManager bm = IBalanceManager($.balanceManager);
        address lendingManager = bm.lendingManager();

        if (lendingManager == address(0)) {
            return; // No lending manager available
        }

        // Get synthetic token based on order side (token user receives)
        address syntheticToken = orderSide == Side.BUY
            ? Currency.unwrap($.poolKey.baseCurrency)
            : Currency.unwrap($.poolKey.quoteCurrency);

        // Get the underlying token - debt is tracked in underlying, not synthetic
        address underlyingToken = _getUnderlyingToken(syntheticToken);

        _repayToken(user, syntheticToken, underlyingToken, receivedAmount, lendingManager, bm, fillPrice, orderId);
    }

    function _repayToken(
        address user,
        address syntheticToken,
        address underlyingToken,
        uint256 receivedAmount,
        address lendingManager,
        IBalanceManager balanceManager,
        uint128 fillPrice,
        uint48 orderId
    ) private {
        // Check debt in underlying token (lending is in underlying)
        try ILendingManager(lendingManager).getUserDebt(user, underlyingToken) returns (uint256 userDebt) {
            if (userDebt == 0) {
                return; // No debt to repay for this token
            }

            // Only repay up to the amount received from the trade, capped by user's debt
            uint256 repayAmount = receivedAmount > userDebt ? userDebt : receivedAmount;

            if (repayAmount > 0) {
                _executeAutoRepayment(user, syntheticToken, underlyingToken, repayAmount, fillPrice, orderId);
            }
        } catch {
            // If checking debt fails, skip auto-repay for this token
        }
    }

    // Auto-borrow functionality for both BUY and SELL orders
    function _handleAutoBorrow(
        address user,
        uint256 amount,
        uint128 fillPrice,
        Side orderSide,
        uint48 orderId
    ) private {
        Storage storage $ = getStorage();
        IBalanceManager bm = IBalanceManager($.balanceManager);
        address lendingManager = bm.lendingManager();

        if (lendingManager == address(0)) {
            return; // No lending manager available
        }

        // Determine which token needs to be borrowed based on order side
        address tokenToBorrow;
        if (orderSide == Side.SELL) {
            // SELL orders need to borrow base tokens (e.g., USDC) to sell
            tokenToBorrow = Currency.unwrap($.poolKey.baseCurrency);
        } else {
            // BUY orders need to borrow quote tokens (e.g., WETH) to buy
            tokenToBorrow = Currency.unwrap($.poolKey.quoteCurrency);
        }

        // Borrow through BalanceManager to borrow on behalf of the user
        try bm.borrowForUser(user, tokenToBorrow, amount) {
            emit AutoBorrowExecuted(user, tokenToBorrow, amount, block.timestamp, orderId);
        } catch {
            // If borrowing fails, emit event and continue
            emit AutoBorrowFailed(user, tokenToBorrow, amount, block.timestamp, orderId);
        }
    }

    // Simplified auto-repay - uses BalanceManager to deduct synthetic and repay underlying

    function _executeAutoRepayment(
        address user,
        address syntheticToken,
        address underlyingToken,
        uint256 repayAmount,
        uint128 fillPrice,
        uint48 orderId
    ) private {
        Storage storage $ = getStorage();
        IBalanceManager bm = IBalanceManager($.balanceManager);

        // Execute repayment through BalanceManager
        // This deducts synthetic balance and repays underlying debt
        try bm.repayFromSyntheticBalance(user, syntheticToken, underlyingToken, repayAmount) {
            emit AutoRepaymentExecuted(user, underlyingToken, repayAmount, 0, block.timestamp, orderId);
        } catch {
            // If repayment fails, emit event and continue (don't revert the trade)
            emit AutoRepaymentFailed(user, underlyingToken, repayAmount, block.timestamp, orderId);
        }
    }

    // Auto-repay helper removed - simplified approach

    // Auto-repay errors
    error NoDebtToRepay();
    
    // Auto-borrow errors  
    error NoCollateralToBorrow();
    error AutoBorrowOnlyForSellOrders();
    
    error NotAuthorized();
}
