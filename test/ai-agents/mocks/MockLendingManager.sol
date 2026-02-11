// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../../src/core/interfaces/ILendingManager.sol";

/**
 * @title MockLendingManager
 * @notice Mock implementation of ILendingManager for testing
 */
contract MockLendingManager is ILendingManager {
    // Mock health factors
    mapping(address => uint256) private _healthFactors;

    // Track function calls
    bool private _borrowCalled = false;
    address private _lastBorrowToken;
    uint256 private _lastBorrowAmount;

    bool private _repayCalled = false;
    address private _lastRepayToken;
    uint256 private _lastRepayAmount;

    bool private _depositCalled = false;
    address private _lastDepositToken;
    uint256 private _lastDepositAmount;

    bool private _withdrawCalled = false;
    address private _lastWithdrawToken;
    uint256 private _lastWithdrawAmount;

    /**
     * @notice Set health factor for a user (for testing)
     */
    function setHealthFactor(address user, uint256 healthFactor) external {
        _healthFactors[user] = healthFactor;
    }

    /**
     * @notice Get health factor for a user
     */
    function getHealthFactor(address user) external view override returns (uint256) {
        return _healthFactors[user];
    }

    /**
     * @notice Check if borrow was called
     */
    function borrowCalled() external view returns (bool) {
        return _borrowCalled;
    }

    function lastBorrowToken() external view returns (address) {
        return _lastBorrowToken;
    }

    function lastBorrowAmount() external view returns (uint256) {
        return _lastBorrowAmount;
    }

    /**
     * @notice Check if repay was called
     */
    function repayCalled() external view returns (bool) {
        return _repayCalled;
    }

    function lastRepayToken() external view returns (address) {
        return _lastRepayToken;
    }

    function lastRepayAmount() external view returns (uint256) {
        return _lastRepayAmount;
    }

    /**
     * @notice Check if deposit was called
     */
    function depositCalled() external view returns (bool) {
        return _depositCalled;
    }

    function lastDepositToken() external view returns (address) {
        return _lastDepositToken;
    }

    function lastDepositAmount() external view returns (uint256) {
        return _lastDepositAmount;
    }

    /**
     * @notice Check if withdraw was called
     */
    function withdrawCalled() external view returns (bool) {
        return _withdrawCalled;
    }

    function lastWithdrawToken() external view returns (address) {
        return _lastWithdrawToken;
    }

    function lastWithdrawAmount() external view returns (uint256) {
        return _lastWithdrawAmount;
    }

    /**
     * @notice Mock borrowForUser
     */
    function borrowForUser(
        address user,
        address token,
        uint256 amount
    ) external override {
        _borrowCalled = true;
        _lastBorrowToken = token;
        _lastBorrowAmount = amount;
    }

    /**
     * @notice Mock repayForUser
     */
    function repayForUser(
        address user,
        address token,
        uint256 amount
    ) external override {
        _repayCalled = true;
        _lastRepayToken = token;
        _lastRepayAmount = amount;
    }

    /**
     * @notice Mock depositLiquidity
     */
    function depositLiquidity(
        address token,
        uint256 amount,
        address user
    ) external override {
        _depositCalled = true;
        _lastDepositToken = token;
        _lastDepositAmount = amount;
    }

    /**
     * @notice Mock withdrawLiquidity
     */
    function withdrawLiquidity(
        address token,
        uint256 amount,
        address user
    ) external override returns (uint256, uint256) {
        _withdrawCalled = true;
        _lastWithdrawToken = token;
        _lastWithdrawAmount = amount;
        return (amount, 0);
    }

    // Stub implementations for interface compliance
    function supplyForUser(address, address, uint256) external pure override {
        revert("Not implemented");
    }

    function withdraw(address, uint256) external pure override {
        revert("Not implemented");
    }

    function withdrawGeneratedInterest(address, uint256) external pure override {
        revert("Not implemented");
    }

    function updateInterestAccrual(address) external pure override {
        revert("Not implemented");
    }

    function borrow(address, uint256) external pure override {
        revert("Not implemented");
    }

    function repay(address, uint256) external pure override {
        revert("Not implemented");
    }

    function repayFromBalance(address, address, uint256) external pure override {
        revert("Not implemented");
    }

    function liquidate(address, address, address, uint256) external pure override {
        revert("Not implemented");
    }

    function getUserLiquidity(address, address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function getUserDebt(address, address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function getUserSupply(address, address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function calculateInterestRate(address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function getGeneratedInterest(address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function configureAsset(
        address,
        uint256,
        uint256,
        uint256,
        uint256
    ) external pure override {
        revert("Not implemented");
    }

    function setInterestRateParams(
        address,
        uint256,
        uint256,
        uint256,
        uint256
    ) external pure override {
        revert("Not implemented");
    }

    function setOracle(address) external pure override {
        revert("Not implemented");
    }

    function getProjectedHealthFactor(address, address, uint256) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function getAvailableLiquidity(address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function calculateYield(address, address) external pure override returns (uint256) {
        revert("Not implemented");
    }
}
