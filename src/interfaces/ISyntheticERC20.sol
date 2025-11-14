// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

interface ISyntheticERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

