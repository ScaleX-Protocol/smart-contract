// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";
import {PoolId, PoolKey} from "../libraries/Pool.sol";
import {IOrderBook} from "./IOrderBook.sol";
import {IPoolManagerErrors} from "./IPoolManagerErrors.sol";

interface IPoolManager is IPoolManagerErrors {
    struct Pool {
        Currency baseCurrency;
        Currency quoteCurrency;
        IOrderBook orderBook;
        uint24 feeTier;  // Fee tier in basis points (20 = 0.2%, 50 = 0.5%)
    }

    event TradingRulesUpdated(PoolId indexed poolId, IOrderBook.TradingRules newRules);
    event PoolCreated(
        PoolId indexed poolId,
        address orderBook,
        Currency baseCurrency,
        Currency quoteCurrency,
        uint24 feeTier
    );
    event CurrencyAdded(Currency currency);
    event IntermediaryAdded(Currency currency);
    event IntermediaryRemoved(Currency currency);
    event PoolLiquidityUpdated(PoolId poolId, uint256 newLiquidity);

    function setRouter(
        address router
    ) external;

    function getPool(
        PoolKey calldata key
    ) external view returns (Pool memory);

    function getPoolId(
        PoolKey calldata key
    ) external pure returns (PoolId);

    function createPool(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        IOrderBook.TradingRules memory _tradingRules,
        uint24 _feeTier
    ) external returns (PoolId);

    function addCommonIntermediary(
        Currency currency
    ) external;

    function removeCommonIntermediary(
        Currency currency
    ) external;

    function updatePoolLiquidity(PoolKey calldata key, uint256 liquidityScore) external;

    function updatePoolTradingRules(PoolId _poolId, IOrderBook.TradingRules memory _newRules) external;

    function getAllCurrencies() external view returns (Currency[] memory);

    function getCommonIntermediaries() external view returns (Currency[] memory);

    function poolExists(Currency currency1, Currency currency2) external view returns (bool);

    function getPoolLiquidityScore(Currency currency1, Currency currency2) external view returns (uint256);

    function createPoolKey(Currency currency1, Currency currency2) external pure returns (PoolKey memory);

    function createPoolKey(Currency currency1, Currency currency2, uint24 feeTier) external pure returns (PoolKey memory);
}
