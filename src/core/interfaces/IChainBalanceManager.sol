// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./IChainBalanceManagerErrors.sol";

interface IChainBalanceManager is IChainBalanceManagerErrors {
    event Deposit(address indexed depositor, address indexed recipient, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Unlock(address indexed user, address indexed token, uint256 amount);
    event Claim(address indexed user, address indexed token, uint256 amount);
    event TokenWhitelisted(address indexed token);
    event TokenRemoved(address indexed token);

    function initialize(address _owner) external;
    
    function addToken(address token) external;
    
    function removeToken(address token) external;
    
    function deposit(address token, uint256 amount, address recipient) external payable;
    
    function withdraw(address token, uint256 amount, address user) external;
    
    function unlock(address token, uint256 amount, address user) external;
    
    function claim(address token, uint256 amount) external;
    
    function getBalance(address user, address token) external view returns (uint256);
    
    function getUnlockedBalance(address user, address token) external view returns (uint256);
    
    function isTokenWhitelisted(address token) external view returns (bool);
    
    function getWhitelistedTokens() external view returns (address[] memory);
    
    function getTokenCount() external view returns (uint256);
}