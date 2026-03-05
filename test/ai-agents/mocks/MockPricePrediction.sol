// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPricePrediction} from "../../../src/core/interfaces/IPricePrediction.sol";

contract MockPricePrediction {
    struct PredictCall {
        address user;
        uint64 marketId;
        bool predictUp;
        uint256 amount;
    }

    struct ClaimCall {
        address user;
        uint64 marketId;
    }

    PredictCall public lastPredictCall;
    ClaimCall public lastClaimCall;
    uint256 public predictCallCount;
    uint256 public claimCallCount;

    // Configurable claimable amount for testing
    mapping(uint64 => mapping(address => uint256)) public claimableAmounts;

    function predictFor(address user, uint64 marketId, bool predictUp, uint256 amount) external {
        lastPredictCall = PredictCall(user, marketId, predictUp, amount);
        predictCallCount++;
    }

    function claimFor(address user, uint64 marketId) external {
        lastClaimCall = ClaimCall(user, marketId);
        claimCallCount++;
    }

    function predict(uint64 marketId, bool predictUp, uint256 amount) external {
        lastPredictCall = PredictCall(msg.sender, marketId, predictUp, amount);
        predictCallCount++;
    }

    function claim(uint64 marketId) external {
        lastClaimCall = ClaimCall(msg.sender, marketId);
        claimCallCount++;
    }

    function getClaimableAmount(uint64 marketId, address user) external view returns (uint256) {
        return claimableAmounts[marketId][user];
    }

    function setClaimableAmount(uint64 marketId, address user, uint256 amount) external {
        claimableAmounts[marketId][user] = amount;
    }
}
