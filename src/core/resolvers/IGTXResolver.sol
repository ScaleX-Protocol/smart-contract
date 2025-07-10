// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IOrderBook} from "../interfaces/IOrderBook.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Currency} from "../libraries/Currency.sol";

interface IGTXResolver {
    function getBestPrice(
        IPoolManager.Pool calldata pool,
        IOrderBook.Side side
    ) external view returns (IOrderBook.PriceVolume memory);

    function getOrderQueue(
        IPoolManager.Pool calldata pool,
        IOrderBook.Side side,
        uint128 price
    ) external view returns (uint48 orderCount, uint256 totalVolume);

    function getOrder(
        IPoolManager.Pool calldata pool,
        uint48 orderId
    ) external view returns (IOrderBook.Order memory);

    function calculateMinOutAmountForMarket(
        IPoolManager.Pool calldata pool,
        uint256 inputAmount,
        IOrderBook.Side side,
        uint256 slippageToleranceBps
    ) external view returns (uint128 minOutputAmount);

    function getFees() external view returns (uint128 feeTakerBps, uint128 feeMakerBps);

    function getOrderBookDepth(
        IPoolManager.Pool calldata pool,
        IOrderBook.Side side,
        uint8 depth
    ) external view returns (IOrderBook.PriceVolume[] memory);

    function estimatePriceImpact(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        IOrderBook.Side side,
        uint128 quantity
    ) external view returns (uint128 expectedAveragePrice, uint128 slippageBps);

    //implement getPools

    //implement get pool key
}
