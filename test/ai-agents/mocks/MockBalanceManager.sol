// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../../src/core/interfaces/IBalanceManager.sol";
import {Currency} from "../../../src/core/libraries/Currency.sol";

/**
 * @title MockBalanceManager
 * @notice Mock implementation of IBalanceManager for testing
 */
contract MockBalanceManager is IBalanceManager {
    // Mock balances
    mapping(address => mapping(Currency => uint256)) private _balances;

    // Tracking for borrowForUser
    bool private _borrowCalled;
    address private _lastBorrowToken;
    uint256 private _lastBorrowAmount;

    // Tracking for repayForUser
    bool private _repayCalled;
    address private _lastRepayToken;
    uint256 private _lastRepayAmount;

    // Tracking for depositLocal
    bool private _depositLocalCalled;
    address private _lastDepositLocalToken;
    uint256 private _lastDepositLocalAmount;

    // Tracking for withdraw(Currency, uint256, address)
    bool private _withdrawCalled;
    address private _lastWithdrawToken;
    uint256 private _lastWithdrawAmount;

    // ---- Tracking getters ----
    function borrowCalled() external view returns (bool) { return _borrowCalled; }
    function lastBorrowToken() external view returns (address) { return _lastBorrowToken; }
    function lastBorrowAmount() external view returns (uint256) { return _lastBorrowAmount; }
    function repayCalled() external view returns (bool) { return _repayCalled; }
    function lastRepayToken() external view returns (address) { return _lastRepayToken; }
    function lastRepayAmount() external view returns (uint256) { return _lastRepayAmount; }
    function depositLocalCalled() external view returns (bool) { return _depositLocalCalled; }
    function lastDepositLocalToken() external view returns (address) { return _lastDepositLocalToken; }
    function lastDepositLocalAmount() external view returns (uint256) { return _lastDepositLocalAmount; }
    function withdrawCalled() external view returns (bool) { return _withdrawCalled; }
    function lastWithdrawToken() external view returns (address) { return _lastWithdrawToken; }
    function lastWithdrawAmount() external view returns (uint256) { return _lastWithdrawAmount; }

    /**
     * @notice Set balance for testing
     */
    function setBalance(address user, Currency currency, uint256 amount) external {
        _balances[user][currency] = amount;
    }

    /**
     * @notice Get user balance
     */
    function getBalance(address user, Currency currency) external view override returns (uint256) {
        return _balances[user][currency];
    }

    // ---- Implemented functions (used by AgentRouter) ----

    function borrowForUser(address, address token, uint256 amount) external override {
        _borrowCalled = true;
        _lastBorrowToken = token;
        _lastBorrowAmount = amount;
    }

    function repayForUser(address, address token, uint256 amount) external override {
        _repayCalled = true;
        _lastRepayToken = token;
        _lastRepayAmount = amount;
    }

    function depositLocal(address token, uint256 amount, address) external override {
        _depositLocalCalled = true;
        _lastDepositLocalToken = token;
        _lastDepositLocalAmount = amount;
    }

    function withdraw(Currency currency, uint256 amount, address) external override returns (uint256) {
        _withdrawCalled = true;
        _lastWithdrawToken = Currency.unwrap(currency);
        _lastWithdrawAmount = amount;
        return amount;
    }

    // Stub implementations for interface compliance
    function deposit(Currency, uint256, address, address) external payable override returns (uint256) {
        revert("Not implemented");
    }

    function withdraw(Currency, uint256) external pure override {
        revert("Not implemented");
    }

    function initializeCrossChain(address, uint32) external pure override {
        revert("Not implemented");
    }

    function setChainBalanceManager(uint32, address) external pure override {
        revert("Not implemented");
    }

    function requestWithdraw(Currency, uint256, uint32, address) external pure override {
        revert("Not implemented");
    }

    function getMailboxConfig() external pure override returns (address, uint32) {
        revert("Not implemented");
    }

    function getChainBalanceManager(uint32) external pure override returns (address) {
        revert("Not implemented");
    }

    function getUserNonce(address) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function lock(address, Currency, uint256) external pure override {
        revert("Not implemented");
    }

    function lock(address, Currency, uint256, address) external pure override {
        revert("Not implemented");
    }

    function unlock(address, Currency, uint256) external pure override {
        revert("Not implemented");
    }

    function getLockedBalance(address, address, Currency) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function getAvailableBalance(address, Currency) external pure override returns (uint256) {
        revert("Not implemented");
    }

    function getSupportedAssets() external pure override returns (address[] memory) {
        revert("Not implemented");
    }

    function getSyntheticToken(address) external pure override returns (address) {
        revert("Not implemented");
    }

    function feeMaker() external pure override returns (uint256) {
        revert("Not implemented");
    }

    function feeTaker() external pure override returns (uint256) {
        revert("Not implemented");
    }

    function feeReceiver() external pure override returns (address) {
        revert("Not implemented");
    }

    function getFeeUnit() external pure override returns (uint256) {
        revert("Not implemented");
    }

    function transferOut(address, address, Currency, uint256) external pure override {
        revert("Not implemented");
    }

    function transferLockedFrom(address, address, Currency, uint256) external pure override {
        revert("Not implemented");
    }

    function transferFrom(address, address, Currency, uint256) external pure override {
        revert("Not implemented");
    }

    function addAuthorizedOperator(address) external pure override {
        revert("Not implemented");
    }

    function lendingManager() external pure override returns (address) {
        revert("Not implemented");
    }

    function getAllBalances(address) external pure returns (Currency[] memory, uint256[] memory) {
        revert("Not implemented");
    }

    function getTotalLocked(Currency) external pure returns (uint256) {
        revert("Not implemented");
    }

    function getTotalDeposited(Currency) external pure returns (uint256) {
        revert("Not implemented");
    }

    function transfer(Currency, address, address, uint256) external pure {
        revert("Not implemented");
    }

    function setPoolManager(address) external pure override {
        revert("Not implemented");
    }

    function setAuthorizedOperator(address, bool) external pure override {
        revert("Not implemented");
    }

    function setFees(uint256, uint256) external pure override {
        revert("Not implemented");
    }

    function setLendingManager(address) external pure override {
        revert("Not implemented");
    }

    function setTokenFactory(address) external pure override {
        revert("Not implemented");
    }

    function setTokenRegistry(address) external pure override {
        revert("Not implemented");
    }

    function repayFromSyntheticBalance(address, address, address, uint256) external pure override {
        revert("Not implemented");
    }

    function addSupportedAsset(address, address) external pure override {
        revert("Not implemented");
    }

    function accrueYield() external pure override {
        revert("Not implemented");
    }

    function calculateUserYield(address, address) external pure override returns (uint256) {
        revert("Not implemented");
    }

}
