// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../../src/core/interfaces/IPoolManager.sol";
import "../../../src/core/interfaces/IOrderBook.sol";
import {Currency} from "../../../src/core/libraries/Currency.sol";
import {PoolKey, PoolId} from "../../../src/core/libraries/Pool.sol";

/**
 * @title MockPoolManager
 * @notice Mock implementation of IPoolManager for testing
 */
contract MockPoolManager is IPoolManager {
    // Store a single pool for testing
    Pool private _pool;
    bool private _poolSet = false;

    /**
     * @notice Set pool for testing
     */
    function setPool(Pool memory pool) external {
        _pool = pool;
        _poolSet = true;
    }

    /**
     * @notice Get pool
     */
    function getPool(PoolKey calldata) external view override returns (Pool memory) {
        require(_poolSet, "Pool not set");
        return _pool;
    }

    // Mock stub implementations for interface compliance
    function setRouter(address) external pure override {
        revert("Not implemented");
    }

    function getPoolId(PoolKey calldata) external pure override returns (PoolId) {
        revert("Not implemented");
    }

    function createPool(
        Currency,
        Currency,
        IOrderBook.TradingRules memory
    ) external pure override returns (PoolId) {
        revert("Not implemented");
    }

    function addCommonIntermediary(Currency) external pure override {
        revert("Not implemented");
    }

    function removeCommonIntermediary(Currency) external pure override {
        revert("Not implemented");
    }

    function updatePoolLiquidity(PoolKey calldata, uint256) external pure override {
        revert("Not implemented");
    }

    function updatePoolTradingRules(PoolId, IOrderBook.TradingRules memory) external pure override {
        revert("Not implemented");
    }

    function updatePoolRouter(PoolId, address) external pure override {
        revert("Not implemented");
    }

    function getAllCurrencies() external pure override returns (Currency[] memory) {
        revert("Not implemented");
    }

    function getCommonIntermediaries() external pure override returns (Currency[] memory) {
        revert("Not implemented");
    }

    function poolExists(Currency, Currency) external pure override returns (bool) {
        revert("Not implemented");
    }

    function getPoolLiquidityScore(Currency, Currency) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function createPoolKey(Currency, Currency) external pure override returns (PoolKey memory) {
        revert("Not implemented");
    }
}
