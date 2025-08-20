// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IChainBalanceManagerErrors {
    error InsufficientBalance(address user, uint256 id, uint256 want, uint256 have);
    error InsufficientUnlockedBalance(address user, uint256 id, uint256 want, uint256 have);
    error ZeroAmount();
    error ZeroAddress();
    error UnauthorizedWithdraw(address caller);
    error TokenNotWhitelisted(address token);
    error TokenAlreadyWhitelisted(address token);
    error TokenNotFound(address token);
}