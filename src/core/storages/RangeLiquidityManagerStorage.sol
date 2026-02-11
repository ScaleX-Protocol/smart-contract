// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IRangeLiquidityManager} from "../interfaces/IRangeLiquidityManager.sol";
import {PoolKey} from "../libraries/Pool.sol";

contract RangeLiquidityManagerStorage {
    /// @custom:storage-location erc7201:scalex.storage.RangeLiquidityManager
    struct Storage {
        // Core dependencies
        address poolManager;
        address balanceManager;
        address router;

        // Position tracking
        uint256 nextPositionId;
        mapping(uint256 => IRangeLiquidityManager.RangePosition) positions;
        mapping(address => uint256[]) userPositions;

        // Constraints: 1 user can only have 1 position per pool
        mapping(address => mapping(bytes32 => uint256)) userPoolPosition; // user => poolId => positionId

        // Position balance tracking (free balances from filled orders)
        mapping(uint256 => mapping(address => uint256)) positionBalances; // positionId => token => amount
    }

    // keccak256(abi.encode(uint256(keccak256("scalex.storage.RangeLiquidityManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x8a8b7f6f5c4d3e2a1b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f00;

    function getStorage() internal pure returns (Storage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}
