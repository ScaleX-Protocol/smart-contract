// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

interface IOrderBookErrors {
    error SlippageTooHigh(uint256 received, uint256 minReceived);
    error InvalidSlippageTolerance(uint256 slippageBps);
    error FillOrKillNotFulfilled(uint128 filledAmount, uint128 requestedAmount);
    error InvalidOrderType();
    error InvalidPrice(uint256 price);
    error InvalidPriceIncrement();
    error InvalidQuantity();
    error InvalidQuantityIncrement();
    error OrderHasNoLiquidity();
    error OrderTooLarge(uint256 amount, uint256 maxAmount);
    error OrderTooSmall(uint256 amount, uint256 minAmount);
    error PostOnlyWouldTake();
    error SlippageExceeded(uint256 requestedPrice, uint256 limitPrice);
    error TradingPaused();
    error UnauthorizedCancellation();
    error UnauthorizedRouter(address reouter);
    error InsufficientBalanceRequired(uint256 requiredDeposit, uint256 userBalance);
    error OrderNotFound();
    error QueueEmpty();
    error OrderIsNotOpenOrder(uint8 status);
    error InvalidSideForQuoteAmount();
    error SwapHopFailed(uint256 hopIndex, uint256 receivedAmount);
    error NoValidSwapPath(address srcCurrency, address dstCurrency);
    error IdenticalCurrencies(address currency);
    error TooManyHops(uint8 maxHops, uint8 limit);
    error InsufficientSwapBalance(uint256 available, uint256 required);
}
