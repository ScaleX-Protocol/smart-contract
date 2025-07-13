// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IBalanceManagerErrors} from "./IBalanceManagerErrors.sol";
import {IOrderBookErrors} from "./IOrderBookErrors.sol";
import {IPoolManagerErrors} from "./IPoolManagerErrors.sol";

interface IGTXRouterErrors is IOrderBookErrors, IBalanceManagerErrors, IPoolManagerErrors {}
