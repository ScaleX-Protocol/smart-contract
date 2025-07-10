// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";

interface IBalanceManagerErrors {
    error InsufficientBalance(address user, uint256 id, uint256 want, uint256 have);
    error TransferError(address user, Currency currency, uint256 amount);
    error ZeroAmount();
    error UnauthorizedOperator(address operator);
    error UnauthorizedCaller(address caller);
}
