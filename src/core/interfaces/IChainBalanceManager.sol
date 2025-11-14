// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";

/**
 * @title IChainBalanceManager
 * @dev Interface for on-chain balance management
 */
interface IChainBalanceManager {
    function deposit(
        address to,
        Currency currency,
        uint256 amount
    ) external payable returns (uint256 depositedAmount);
    
    function withdraw(
        address to,
        Currency currency,
        uint256 amount
    ) external;
    
    function lock(
        address to,
        Currency currency,
        uint256 amount,
        uint256 timeout
    ) external;
    
    function unlock(
        address to,
        Currency currency,
        uint256 amount,
        address manager
    ) external;
    
    function getBalance(
        address user,
        Currency currency
    ) external view returns (uint256);
    
    function getLockedBalance(
        address user,
        address manager,
        Currency currency
    ) external view returns (uint256);
}