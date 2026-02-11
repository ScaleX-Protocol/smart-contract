// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IERC8004Reputation.sol";

/**
 * @title MockERC8004Reputation
 * @notice Mock implementation of ERC-8004 Reputation Registry for testing
 * @dev Simplified reputation tracking for agent performance
 */
contract MockERC8004Reputation is IERC8004Reputation {
    // Agent metrics
    struct Metrics {
        uint256 totalTrades;
        uint256 profitableTrades;
        int256 totalPnL;
        uint256 lastUpdated;
        uint256 score; // 0-100
    }

    // Agent ID => Metrics
    mapping(uint256 => Metrics) private _metrics;

    // Agent ID => Feedback history
    mapping(uint256 => Feedback[]) private _feedbackHistory;

    // Authorized submitters (contracts that can submit feedback)
    mapping(address => bool) public authorizedSubmitters;

    // Owner (for access control)
    address public owner;

    constructor() {
        owner = msg.sender;
        authorizedSubmitters[msg.sender] = true;
    }

    modifier onlyAuthorized() {
        require(authorizedSubmitters[msg.sender], "Not authorized");
        _;
    }

    /**
     * @notice Authorize a submitter
     */
    function setAuthorizedSubmitter(address submitter, bool authorized) external {
        require(msg.sender == owner, "Only owner");
        authorizedSubmitters[submitter] = authorized;
    }

    /**
     * @notice Submit feedback for an agent
     */
    function submitFeedback(
        uint256 agentTokenId,
        FeedbackType feedbackType,
        bytes calldata data
    ) external override onlyAuthorized {
        // Decode data based on feedback type
        int256 value = 0;

        if (feedbackType == FeedbackType.TRADE_EXECUTION) {
            // Expect: (pnl, amountIn, amountOut, timestamp)
            (int256 pnl,,,) = abi.decode(data, (int256, uint256, uint256, uint256));
            value = pnl;

            // Update metrics
            _metrics[agentTokenId].totalTrades++;
            _metrics[agentTokenId].totalPnL += pnl;
            if (pnl > 0) {
                _metrics[agentTokenId].profitableTrades++;
            }
        } else if (feedbackType == FeedbackType.BORROW || feedbackType == FeedbackType.REPAY) {
            // Expect: (token, amount, timestamp)
            (, uint256 amount,) = abi.decode(data, (address, uint256, uint256));
            value = int256(amount);
        }

        // Store feedback
        _feedbackHistory[agentTokenId].push(
            Feedback({
                agentTokenId: agentTokenId,
                feedbackType: feedbackType,
                value: value,
                data: data,
                submitter: msg.sender,
                timestamp: block.timestamp
            })
        );

        // Update score and timestamp
        _updateScore(agentTokenId);
        _metrics[agentTokenId].lastUpdated = block.timestamp;

        emit FeedbackSubmitted(
            agentTokenId,
            feedbackType,
            msg.sender,
            value,
            block.timestamp
        );
    }

    /**
     * @notice Get reputation score for an agent
     */
    function getScore(uint256 agentTokenId) external view override returns (uint256) {
        return _metrics[agentTokenId].score;
    }

    /**
     * @notice Get detailed reputation metrics
     */
    function getMetrics(uint256 agentTokenId)
        external
        view
        override
        returns (
            uint256 totalTrades,
            uint256 profitableTrades,
            int256 totalPnL,
            uint256 lastUpdated
        )
    {
        Metrics memory m = _metrics[agentTokenId];
        return (m.totalTrades, m.profitableTrades, m.totalPnL, m.lastUpdated);
    }

    /**
     * @notice Get feedback history for an agent
     */
    function getFeedbackHistory(
        uint256 agentTokenId,
        uint256 offset,
        uint256 limit
    ) external view override returns (Feedback[] memory feedbacks) {
        Feedback[] storage history = _feedbackHistory[agentTokenId];

        uint256 total = history.length;
        if (offset >= total) {
            return new Feedback[](0);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 resultLength = end - offset;
        feedbacks = new Feedback[](resultLength);

        for (uint256 i = 0; i < resultLength; i++) {
            feedbacks[i] = history[offset + i];
        }
    }

    /**
     * @notice Update reputation score based on performance
     * @dev Simple algorithm: base score 50, +1 for each profitable trade, -1 for each loss
     */
    function _updateScore(uint256 agentTokenId) internal {
        Metrics storage m = _metrics[agentTokenId];

        uint256 oldScore = m.score;

        if (m.totalTrades == 0) {
            m.score = 50; // New agent starts at 50
        } else {
            // Win rate component (0-50 points)
            uint256 winRate = (m.profitableTrades * 50) / m.totalTrades;

            // PnL component (0-50 points)
            uint256 pnlScore = 25; // Default neutral
            if (m.totalPnL > 0) {
                pnlScore = 50; // Profitable
            } else if (m.totalPnL < 0) {
                pnlScore = 0; // Losing
            }

            m.score = winRate + pnlScore;

            // Cap at 100
            if (m.score > 100) {
                m.score = 100;
            }
        }

        if (oldScore != m.score) {
            emit ReputationUpdated(agentTokenId, oldScore, m.score, block.timestamp);
        }
    }
}
