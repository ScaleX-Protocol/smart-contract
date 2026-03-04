// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC8004Reputation
 * @notice ERC-8004 Reputation Registry interface matching the canonical ReputationRegistryUpgradeable.
 * @dev See https://eips.ethereum.org/EIPS/eip-8004
 */
interface IERC8004Reputation {
    /**
     * @notice Submit feedback for an agent on the canonical Reputation Registry.
     * @param agentId       Token ID of the agent in the Identity Registry
     * @param value         Feedback value (e.g. PnL in wei)
     * @param valueDecimals Decimal precision of the value
     * @param tag1          Primary category tag (e.g. "trade")
     * @param tag2          Secondary category tag (e.g. "swap", "borrow", "repay")
     * @param endpoint      Optional service endpoint
     * @param feedbackURI   Optional off-chain URI with detailed feedback data
     * @param feedbackHash  Optional hash of the feedback data for integrity
     */
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;
}
