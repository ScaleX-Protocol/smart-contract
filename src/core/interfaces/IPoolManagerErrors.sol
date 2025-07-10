// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

interface IPoolManagerErrors {
    error InvalidRouter();
    error PoolAlreadyExists(bytes32 id);
    error InvalidTradingRule(string reason);
}
