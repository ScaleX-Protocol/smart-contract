// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LendingManager} from "./LendingManager.sol";

/**
 * @title LendingManagerV2
 * @dev Simple V2 for testing upgrade functionality
 */
contract LendingManagerV2 is LendingManager {
    
    // Simple V2 storage
    bool private _emergencyMode;
    
    /**
     * @dev Set emergency mode - new V2 function
     */
    function setEmergencyMode(bool enabled) external onlyOwner {
        _emergencyMode = enabled;
    }
    
    /**
     * @dev Check emergency mode - new V2 function  
     */
    function isEmergencyMode() external view returns (bool) {
        return _emergencyMode;
    }
    
    /**
     * @dev Get version
     */
    function getVersion() external pure returns (string memory) {
        return "v2.0.0";
    }
}