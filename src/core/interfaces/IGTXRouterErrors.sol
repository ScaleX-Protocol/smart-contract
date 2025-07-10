// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IOrderBookErrors} from "./IOrderBookErrors.sol";
import {IBalanceManagerErrors} from "./IBalanceManagerErrors.sol";
import {IPoolManagerErrors} from "./IPoolManagerErrors.sol";

interface IGTXRouterErrors is IOrderBookErrors, IBalanceManagerErrors, IPoolManagerErrors {
}
