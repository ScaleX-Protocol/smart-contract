// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ScaleXRouter} from "@scalexcore/ScaleXRouter.sol";

/**
 * @title ScaleXRouterV2
 * @dev Simple V2 for testing upgrade functionality
 */
contract ScaleXRouterV2 is ScaleXRouter {
    
    // V2 storage
    uint256 private _maxSlippage;
    bool private _pauseState;
    
    // V2 events
    event MaxSlippageSet(uint256 maxSlippage);
    event PauseStateChanged(bool paused);
    
    /**
     * @dev V2 only: Set maximum slippage
     */
    function setMaxSlippage(uint256 maxSlippage) external onlyOwner {
        require(maxSlippage <= 5000, "Max slippage too high"); // Max 50%
        _maxSlippage = maxSlippage;
        emit MaxSlippageSet(maxSlippage);
    }
    
    /**
     * @dev V2 only: Get maximum slippage
     */
    function getMaxSlippage() external view returns (uint256) {
        return _maxSlippage;
    }
    
    /**
     * @dev V2 only: Pause/unpause router
     */
    function setPaused(bool paused) external onlyOwner {
        _pauseState = paused;
        emit PauseStateChanged(paused);
    }
    
    /**
     * @dev V2 only: Check if router is paused
     */
    function isPaused() external view returns (bool) {
        return _pauseState;
    }
    
    /**
     * @dev V2 only: Get version
     */
    function getVersion() external pure returns (string memory) {
        return "v2.0.0";
    }
}