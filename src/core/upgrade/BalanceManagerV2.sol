// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BalanceManager} from "@scalexcore/BalanceManager.sol";

/**
 * @title BalanceManagerV2
 * @dev Simple V2 for testing upgrade functionality
 */
contract BalanceManagerV2 is BalanceManager {
    
    // V2 storage
    uint256 private _withdrawalFee;
    bool private _emergencyMode;
    
    // V2 events
    event WithdrawalFeeSet(uint256 fee);
    event EmergencyModeSet(bool enabled);
    
    /**
     * @dev V2 only: Set withdrawal fee
     */
    function setWithdrawalFee(uint256 fee) external onlyOwner {
        require(fee <= 1000, "Fee too high"); // Max 10%
        _withdrawalFee = fee;
        emit WithdrawalFeeSet(fee);
    }
    
    /**
     * @dev V2 only: Get withdrawal fee
     */
    function getWithdrawalFee() external view returns (uint256) {
        return _withdrawalFee;
    }
    
    /**
     * @dev V2 only: Set emergency mode
     */
    function setEmergencyMode(bool enabled) external onlyOwner {
        _emergencyMode = enabled;
        emit EmergencyModeSet(enabled);
    }
    
    /**
     * @dev V2 only: Check emergency mode
     */
    function isEmergencyMode() external view returns (bool) {
        return _emergencyMode;
    }
    
    /**
     * @dev V2 only: Get version
     */
    function getVersion() external pure returns (string memory) {
        return "v2.0.0";
    }
}