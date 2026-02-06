// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";

interface IAutoBorrowHelper {
    function validateAndBorrowIfNeeded(
        address balanceManager,
        address user,
        Currency currency,
        uint256 requiredAmount,
        bool autoBorrow
    ) external returns (uint256 borrowed);

    function validateBalanceOnly(
        address balanceManager,
        address user,
        Currency currency,
        uint256 requiredAmount,
        bool autoBorrow
    ) external view;
}
