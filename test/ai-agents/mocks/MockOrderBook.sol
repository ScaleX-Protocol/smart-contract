// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../../src/core/interfaces/IOrderBook.sol";
import {Currency} from "../../../src/core/libraries/Currency.sol";
import {PoolKey} from "../../../src/core/libraries/Pool.sol";

/**
 * @title MockOrderBook
 * @notice Mock implementation of IOrderBook for testing
 */
contract MockOrderBook is IOrderBook {
    uint48 private _nextOrderId = 1;
    uint128 private _nextFilled = 0;
    bool private _cancelOrderCalled = false;
    address private _lastOrderOwner;

    /**
     * @notice Set the next order response (for testing)
     */
    function setNextOrderResponse(uint48 orderId, uint128 filled) external {
        _nextOrderId = orderId;
        _nextFilled = filled;
    }

    /**
     * @notice Set the next order ID (for testing)
     */
    function setNextOrderId(uint48 orderId) external {
        _nextOrderId = orderId;
    }

    /**
     * @notice Check if cancelOrder was called
     */
    function cancelOrderCalled() external view returns (bool) {
        return _cancelOrderCalled;
    }

    /**
     * @notice Get the last order owner (for testing owner asset usage)
     */
    function lastOrderOwner() external view returns (address) {
        return _lastOrderOwner;
    }

    /**
     * @notice Mock placeMarketOrder
     */
    function placeMarketOrder(
        uint128, // quantity
        Side, // side
        address user,
        bool, // autoRepay
        bool // autoBorrow
    ) external override returns (uint48 orderId, uint128 filled) {
        _lastOrderOwner = user; // Track owner for verification
        orderId = _nextOrderId;
        filled = _nextFilled;
        _nextOrderId++;
    }

    /**
     * @notice Mock placeOrder
     */
    function placeOrder(
        uint128, // price
        uint128, // quantity
        Side, // side
        address user,
        TimeInForce, // timeInForce
        bool, // autoRepay
        bool // autoBorrow
    ) external override returns (uint48 orderId) {
        _lastOrderOwner = user; // Track owner for verification
        orderId = _nextOrderId;
        _nextOrderId++;
    }

    /**
     * @notice Mock cancelOrder
     */
    function cancelOrder(uint48, address) external override {
        _cancelOrderCalled = true;
    }

    // Stub implementations for interface compliance
    function initialize(address, address, TradingRules calldata, PoolKey calldata) external pure override {
        revert("Not implemented");
    }

    function setRouter(address) external pure override {
        revert("Not implemented");
    }

    function oracle() external pure override returns (address) {
        revert("Not implemented");
    }

    function setOracle(address) external pure override {
        revert("Not implemented");
    }

    function getOrder(uint48) external pure override returns (Order memory) {
        revert("Not implemented");
    }

    function getOrderQueue(Side, uint128) external pure override returns (uint48, uint256) {
        revert("Not implemented");
    }

    function getBestPrice(Side) external pure override returns (PriceVolume memory) {
        revert("Not implemented");
    }

    function getNextBestPrices(Side, uint128, uint8) external pure override returns (PriceVolume[] memory) {
        revert("Not implemented");
    }

    function setTradingRules(TradingRules memory) external pure override {
        revert("Not implemented");
    }

    function getTradingRules() external pure override returns (TradingRules memory) {
        revert("Not implemented");
    }

    function updateTradingRules(TradingRules memory) external pure override {
        revert("Not implemented");
    }

    function getQuoteCurrency() external pure override returns (address) {
        return address(0x2);
    }

    function getBaseCurrency() external pure override returns (address) {
        return address(0x1);
    }
}
