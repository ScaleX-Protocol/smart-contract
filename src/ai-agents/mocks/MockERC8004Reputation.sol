// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IERC8004Reputation.sol";

/**
 * @title MockERC8004Reputation
 * @notice Mock implementation of canonical ERC-8004 Reputation Registry for testing.
 * @dev Tracks giveFeedback() calls for assertion in tests.
 */
contract MockERC8004Reputation is IERC8004Reputation {
    struct FeedbackRecord {
        uint256 agentId;
        int128 value;
        uint8 valueDecimals;
        string tag1;
        string tag2;
        string endpoint;
        string feedbackURI;
        bytes32 feedbackHash;
        address sender;
        uint256 timestamp;
    }

    FeedbackRecord[] public feedbackRecords;
    mapping(uint256 => uint256) public feedbackCount;

    // If true, giveFeedback() will revert (simulates self-feedback guard)
    bool public shouldRevert;
    string public revertReason;

    function setRevert(bool _shouldRevert, string calldata _reason) external {
        shouldRevert = _shouldRevert;
        revertReason = _reason;
    }

    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external override {
        if (shouldRevert) {
            revert(revertReason);
        }

        feedbackRecords.push(FeedbackRecord({
            agentId: agentId,
            value: value,
            valueDecimals: valueDecimals,
            tag1: tag1,
            tag2: tag2,
            endpoint: endpoint,
            feedbackURI: feedbackURI,
            feedbackHash: feedbackHash,
            sender: msg.sender,
            timestamp: block.timestamp
        }));
        feedbackCount[agentId]++;
    }

    function getFeedbackRecordCount() external view returns (uint256) {
        return feedbackRecords.length;
    }
}
