// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolManager} from "@scalexcore/PoolManager.sol";

/**
 * @title PoolManagerV2
 * @dev Simple V2 for testing upgrade functionality
 */
contract PoolManagerV2 is PoolManager {
    
    // V2 storage
    uint256 private _minLiquidity;
    bool private _maintenanceMode;
    
    // V2 events
    event MinLiquiditySet(uint256 minLiquidity);
    event MaintenanceModeSet(bool enabled);
    
    /**
     * @dev V2 only: Set minimum liquidity
     */
    function setMinLiquidity(uint256 minLiquidity) external onlyOwner {
        _minLiquidity = minLiquidity;
        emit MinLiquiditySet(minLiquidity);
    }
    
    /**
     * @dev V2 only: Get minimum liquidity
     */
    function getMinLiquidity() external view returns (uint256) {
        return _minLiquidity;
    }
    
    /**
     * @dev V2 only: Set maintenance mode
     */
    function setMaintenanceMode(bool enabled) external onlyOwner {
        _maintenanceMode = enabled;
        emit MaintenanceModeSet(enabled);
    }
    
    /**
     * @dev V2 only: Check maintenance mode
     */
    function isMaintenanceMode() external view returns (bool) {
        return _maintenanceMode;
    }
    
    /**
     * @dev V2 only: Get version
     */
    function getVersion() external pure returns (string memory) {
        return "v2.0.0";
    }
}