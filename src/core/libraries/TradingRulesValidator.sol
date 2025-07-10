// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IOrderBook} from "../interfaces/IOrderBook.sol";

library TradingRulesValidator {
    function validate(IOrderBook.TradingRules memory _rules) internal pure {
        if (_rules.minTradeAmount == 0) revert("minTradeAmount cannot be zero");
        if (_rules.minAmountMovement == 0) revert("minAmountMovement cannot be zero");
        if (_rules.minPriceMovement == 0) revert("minPriceMovement cannot be zero");
        if (_rules.minOrderSize == 0) revert("minOrderSize cannot be zero");

        if (_rules.minTradeAmount > type(uint128).max / 100)
            revert("minTradeAmount too large");

        if (_rules.minPriceMovement > type(uint128).max / 100)
            revert("minPriceMovement too large");
    }
}