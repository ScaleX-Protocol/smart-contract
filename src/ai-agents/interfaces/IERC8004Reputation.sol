// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC8004Reputation
 * @notice ERC-8004 Reputation Registry interface for AI agent performance tracking
 * @dev Based on ERC-8004 standard (https://eips.ethereum.org/EIPS/eip-8004)
 *      Reputation Registry stores structured feedback about agent performance
 */
interface IERC8004Reputation {
    /**
     * @notice Feedback types for agent actions
     */
    enum FeedbackType {
        TRADE_EXECUTION,      // Feedback on trade execution
        BORROW,               // Feedback on borrowing
        REPAY,                // Feedback on repayment
        LIQUIDATION_AVOIDED,  // Positive feedback for maintaining health
        POLICY_VIOLATION,     // Negative feedback for policy violation
        CIRCUIT_BREAKER       // Feedback when circuit breaker triggers
    }

    /**
     * @notice Structured feedback data
     */
    struct Feedback {
        uint256 agentTokenId;
        FeedbackType feedbackType;
        int256 value;           // PnL, amount, or score
        bytes data;             // Additional context (ABI encoded)
        address submitter;      // Who submitted this feedback
        uint256 timestamp;
    }

    /**
     * @notice Submit feedback for an agent
     * @param agentTokenId The agent receiving feedback
     * @param feedbackType Type of feedback
     * @param data ABI-encoded feedback data
     */
    function submitFeedback(
        uint256 agentTokenId,
        FeedbackType feedbackType,
        bytes calldata data
    ) external;

    /**
     * @notice Get reputation score for an agent
     * @param agentTokenId The agent token ID
     * @return score Reputation score (0-100 scale)
     */
    function getScore(uint256 agentTokenId) external view returns (uint256 score);

    /**
     * @notice Get detailed reputation metrics
     * @param agentTokenId The agent token ID
     * @return totalTrades Total number of trades executed
     * @return profitableTrades Number of profitable trades
     * @return totalPnL Total profit/loss across all trades
     * @return lastUpdated Timestamp of last reputation update
     */
    function getMetrics(uint256 agentTokenId)
        external
        view
        returns (
            uint256 totalTrades,
            uint256 profitableTrades,
            int256 totalPnL,
            uint256 lastUpdated
        );

    /**
     * @notice Get feedback history for an agent
     * @param agentTokenId The agent token ID
     * @param offset Starting index
     * @param limit Number of records to return
     * @return feedbacks Array of feedback records
     */
    function getFeedbackHistory(
        uint256 agentTokenId,
        uint256 offset,
        uint256 limit
    ) external view returns (Feedback[] memory feedbacks);

    /**
     * @notice Emitted when feedback is submitted
     */
    event FeedbackSubmitted(
        uint256 indexed agentTokenId,
        FeedbackType indexed feedbackType,
        address indexed submitter,
        int256 value,
        uint256 timestamp
    );

    /**
     * @notice Emitted when reputation score is updated
     */
    event ReputationUpdated(
        uint256 indexed agentTokenId,
        uint256 oldScore,
        uint256 newScore,
        uint256 timestamp
    );
}
