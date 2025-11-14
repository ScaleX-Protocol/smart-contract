// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface PriceFeed {
    function price(string memory symbol) external view returns (uint256);
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}