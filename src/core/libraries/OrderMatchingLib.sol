// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IOrderBook} from "../interfaces/IOrderBook.sol";
import {IBalanceManager} from "../interfaces/IBalanceManager.sol";
import {OrderBookStorage} from "../storages/OrderBookStorage.sol";
import {RedBlackTreeLib} from "@solady/utils/RedBlackTreeLib.sol";
import {PoolIdLibrary} from "../libraries/Pool.sol";
import {Currency} from "../libraries/Currency.sol";

/**
 * @title OrderMatchingLib
 * @notice Library for order matching logic
 * @dev Extracted from OrderBook to reduce contract size
 */
library OrderMatchingLib {
    using RedBlackTreeLib for RedBlackTreeLib.Tree;

    struct MatchState {
        uint128 remaining;
        uint128 orderPrice;
        uint128 latestBestPrice;
        uint128 previousRemaining;
        uint128 filled;
    }

    struct MatchContext {
        IOrderBook.Order order;
        IOrderBook.Side side;
        address user;
        bool isMarketOrder;
        uint128 bestPrice;
        uint128 remaining;
        uint128 previousRemaining;
        uint128 filled;
    }

    function matchOrder(
        OrderBookStorage.Storage storage $,
        IOrderBook.Order memory order,
        IOrderBook.Side side,
        address user,
        bool isMarketOrder
    ) external returns (uint128) {
        IOrderBook.Side oppositeSide = side == IOrderBook.Side.BUY ? IOrderBook.Side.SELL : IOrderBook.Side.BUY;
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

            uint128 bestPrice = getBestMatchingPrice($, s.orderPrice, oppositeSide, isMarketOrder);
            if (bestPrice == 0) {
                break;
            }

            if (bestPrice == s.latestBestPrice && s.previousRemaining == s.remaining) {
                bytes32 ptr = $.priceTrees[oppositeSide].find(bestPrice);
                bestPrice = side == IOrderBook.Side.BUY
                    ? uint128(RedBlackTreeLib.value(RedBlackTreeLib.next(ptr)))
                    : uint128(RedBlackTreeLib.value(RedBlackTreeLib.prev(ptr)));
                if (bestPrice == 0) {
                    break;
                }
            }

            s.latestBestPrice = bestPrice;
            s.previousRemaining = s.remaining;
            IOrderBook.OrderQueue storage queue = $.orderQueues[oppositeSide][bestPrice];

            (s.remaining, s.filled) =
                matchAtPriceLevel($, order, queue, bestPrice, s.remaining, s.filled, side, user, isMarketOrder);
            updatePriceLevel($, bestPrice, queue, $.priceTrees[oppositeSide]);

            if (s.remaining == prevRemaining) {
                break;
            }

            if (loopCount > 10) {
                break;
            }
        }

        return s.filled;
    }

    function matchAtPriceLevel(
        OrderBookStorage.Storage storage $,
        IOrderBook.Order memory order,
        IOrderBook.OrderQueue storage queue,
        uint128 bestPrice,
        uint128 remaining,
        uint128 filled,
        IOrderBook.Side side,
        address user,
        bool isMarketOrder
    ) public returns (uint128, uint128) {
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

        (ctx.remaining, ctx.filled) = processOrderQueue($, queue, ctx);
        return (ctx.remaining, ctx.filled);
    }

    function processOrderQueue(
        OrderBookStorage.Storage storage $,
        IOrderBook.OrderQueue storage queue,
        MatchContext memory ctx
    ) public returns (uint128, uint128) {
        uint48 currentOrderId = queue.head;

        while (currentOrderId != 0 && ctx.remaining > 0) {
            IOrderBook.Order storage matchingOrder = $.orders[currentOrderId];
            uint48 nextOrderId = matchingOrder.next;

            if (matchingOrder.expiry < block.timestamp) {
                handleExpiredOrder($, queue, matchingOrder);
            } else if (matchingOrder.user != ctx.user) {
                ctx.previousRemaining = ctx.remaining;
                (ctx.remaining, ctx.filled) = processMatchingOrder($, ctx, matchingOrder, queue);
            }
            currentOrderId = nextOrderId;
        }
        return (ctx.remaining, ctx.filled);
    }

    function processMatchingOrder(
        OrderBookStorage.Storage storage $,
        MatchContext memory ctx,
        IOrderBook.Order storage matchingOrder,
        IOrderBook.OrderQueue storage queue
    ) public returns (uint128, uint128) {
        uint128 matchingRemaining = matchingOrder.quantity - matchingOrder.filled;
        uint128 executedQuantity = ctx.remaining < matchingRemaining ? ctx.remaining : matchingRemaining;

        if (ctx.isMarketOrder) {
            executedQuantity = handleMarketOrderBalanceCheck($, ctx, executedQuantity);
            if (executedQuantity == 0) {
                return (0, ctx.filled);
            }
        }

        ctx.remaining -= executedQuantity;
        ctx.filled += executedQuantity;

        matchingOrder.filled += executedQuantity;
        queue.totalVolume -= executedQuantity;

        // Transfer balances between users
        transferBalances($, ctx.user, matchingOrder.user, ctx.bestPrice, executedQuantity, ctx.side, ctx.isMarketOrder, ctx.order.id, ctx.order.autoRepay);

        if (matchingOrder.filled == matchingOrder.quantity) {
            removeOrderFromQueue($, queue, matchingOrder);
            matchingOrder.status = IOrderBook.Status.FILLED;
        } else {
            matchingOrder.status = IOrderBook.Status.PARTIALLY_FILLED;
        }

        return (ctx.remaining, ctx.filled);
    }

    function handleExpiredOrder(
        OrderBookStorage.Storage storage $,
        IOrderBook.OrderQueue storage queue,
        IOrderBook.Order storage order
    ) public {
        removeOrderFromQueue($, queue, order);
    }

    function updatePriceLevel(
        OrderBookStorage.Storage storage $,
        uint128 bestPrice,
        IOrderBook.OrderQueue storage queue,
        RedBlackTreeLib.Tree storage priceTree
    ) public {
        if (queue.orderCount == 0 && priceTree.exists(bestPrice)) {
            priceTree.remove(bestPrice);
        }
    }

    function getBestMatchingPrice(
        OrderBookStorage.Storage storage $,
        uint128 orderPrice,
        IOrderBook.Side oppositeSide,
        bool isMarketOrder
    ) public view returns (uint128) {
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

    function handleMarketOrderBalanceCheck(
        OrderBookStorage.Storage storage $,
        MatchContext memory ctx,
        uint128 executedQuantity
    ) public view returns (uint128) {
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

    function removeOrderFromQueue(
        OrderBookStorage.Storage storage $,
        IOrderBook.OrderQueue storage queue,
        IOrderBook.Order storage order
    ) public returns (uint256) {
        if (queue.orderCount == 0) {
            revert("Queue empty");
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

    function transferBalances(
        OrderBookStorage.Storage storage $,
        address trader,
        address matchingUser,
        uint128 matchPrice,
        uint128 executedQuantity,
        IOrderBook.Side side,
        bool isMarketOrder,
        uint48 traderOrderId,
        bool traderAutoRepay
    ) public {
        IBalanceManager bm = IBalanceManager($.balanceManager);
        uint256 baseAmount = executedQuantity;
        uint256 quoteAmount = PoolIdLibrary.baseToQuote(baseAmount, matchPrice, $.poolKey.baseCurrency.decimals());

        if (side == IOrderBook.Side.SELL) {
            if (!isMarketOrder) {
                bm.unlock(trader, $.poolKey.baseCurrency, baseAmount);
            }
            bm.transferFrom(trader, matchingUser, $.poolKey.baseCurrency, baseAmount);
            bm.transferLockedFrom(matchingUser, trader, $.poolKey.quoteCurrency, quoteAmount);
        } else {
            if (!isMarketOrder) {
                bm.unlock(trader, $.poolKey.quoteCurrency, quoteAmount);
            }
            bm.transferFrom(trader, matchingUser, $.poolKey.quoteCurrency, quoteAmount);
            bm.transferLockedFrom(matchingUser, trader, $.poolKey.baseCurrency, baseAmount);
        }
    }
}
