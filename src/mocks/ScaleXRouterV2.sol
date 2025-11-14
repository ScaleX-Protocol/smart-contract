// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../core/ScaleXRouter.sol";

/// @custom:oz-upgrades-from ScaleXRouter
contract ScaleXRouterV2 is ScaleXRouter {
    function getVersion() external pure returns (string memory) {
        return "ScaleXRouter V2";
    }
}
