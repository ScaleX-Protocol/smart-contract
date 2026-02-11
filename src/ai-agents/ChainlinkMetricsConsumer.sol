// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "./PolicyFactory.sol";
import "./AgentRouter.sol";

/**
 * @title ChainlinkMetricsConsumer
 * @notice Chainlink Functions consumer for computing complex agent metrics off-chain
 * @dev Handles requests for daily volume, drawdown, performance metrics, etc.
 */
contract ChainlinkMetricsConsumer is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    // ============ State Variables ============

    PolicyFactory public immutable policyFactory;
    AgentRouter public immutable agentRouter;

    // Chainlink Functions configuration
    bytes32 public donId;
    uint64 public subscriptionId;
    uint32 public gasLimit;

    // JavaScript source code for off-chain computation
    string public metricsSource;

    // Request tracking
    struct MetricsRequest {
        address owner;
        uint256 agentTokenId;
        uint256 timestamp;
        MetricsType metricsType;
        bool fulfilled;
    }

    enum MetricsType {
        DAILY_VOLUME,
        DAILY_DRAWDOWN,
        WEEKLY_VOLUME,
        WEEKLY_DRAWDOWN,
        PERFORMANCE_METRICS,
        FULL_CHECK
    }

    mapping(bytes32 => MetricsRequest) public requests;

    // Cached metrics results (requestId => encoded result)
    mapping(bytes32 => bytes) public metricsResults;

    // Owner for configuration
    address public owner;

    // ============ Events ============

    event MetricsRequested(
        bytes32 indexed requestId,
        address indexed owner,
        uint256 indexed agentTokenId,
        MetricsType metricsType,
        uint256 timestamp
    );

    event MetricsFulfilled(
        bytes32 indexed requestId,
        address indexed owner,
        uint256 indexed agentTokenId,
        bytes result,
        uint256 timestamp
    );

    event MetricsSourceUpdated(string newSource, uint256 timestamp);
    event ConfigurationUpdated(bytes32 donId, uint64 subscriptionId, uint32 gasLimit);

    // ============ Errors ============

    error UnauthorizedCaller();
    error InvalidRequest();
    error RequestAlreadyFulfilled();
    error MetricsCheckFailed(string reason);

    // ============ Constructor ============

    constructor(
        address _router,
        address _policyFactory,
        address _agentRouter,
        bytes32 _donId,
        uint64 _subscriptionId,
        uint32 _gasLimit
    ) FunctionsClient(_router) {
        policyFactory = PolicyFactory(_policyFactory);
        agentRouter = AgentRouter(_agentRouter);
        donId = _donId;
        subscriptionId = _subscriptionId;
        gasLimit = _gasLimit;
        owner = msg.sender;
    }

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedCaller();
        _;
    }

    modifier onlyAgentRouter() {
        if (msg.sender != address(agentRouter)) revert UnauthorizedCaller();
        _;
    }

    // ============ Configuration Functions ============

    /**
     * @notice Update the JavaScript source code for metrics computation
     * @param newSource New JavaScript source code
     */
    function updateMetricsSource(string calldata newSource) external onlyOwner {
        metricsSource = newSource;
        emit MetricsSourceUpdated(newSource, block.timestamp);
    }

    /**
     * @notice Update Chainlink Functions configuration
     * @param _donId New DON ID
     * @param _subscriptionId New subscription ID
     * @param _gasLimit New gas limit
     */
    function updateConfiguration(
        bytes32 _donId,
        uint64 _subscriptionId,
        uint32 _gasLimit
    ) external onlyOwner {
        donId = _donId;
        subscriptionId = _subscriptionId;
        gasLimit = _gasLimit;
        emit ConfigurationUpdated(_donId, _subscriptionId, _gasLimit);
    }

    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    // ============ Request Functions ============

    /**
     * @notice Request metrics computation for an agent
     * @param agentOwner Owner of the agent
     * @param agentTokenId Agent token ID
     * @param metricsType Type of metrics to compute
     * @return requestId Chainlink request ID
     */
    function requestMetrics(
        address agentOwner,
        uint256 agentTokenId,
        MetricsType metricsType
    ) external onlyAgentRouter returns (bytes32 requestId) {
        // Build Chainlink Functions request
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(metricsSource);

        // Add arguments: [owner, agentTokenId, metricsType, timestamp]
        string[] memory args = new string[](4);
        args[0] = _addressToString(agentOwner);
        args[1] = _uint256ToString(agentTokenId);
        args[2] = _uint256ToString(uint256(metricsType));
        args[3] = _uint256ToString(block.timestamp);
        req.setArgs(args);

        // Send request to Chainlink DON
        requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donId
        );

        // Store request metadata
        requests[requestId] = MetricsRequest({
            owner: agentOwner,
            agentTokenId: agentTokenId,
            timestamp: block.timestamp,
            metricsType: metricsType,
            fulfilled: false
        });

        emit MetricsRequested(
            requestId,
            agentOwner,
            agentTokenId,
            metricsType,
            block.timestamp
        );
    }

    /**
     * @notice Fulfill metrics request (called by Chainlink DON)
     * @param requestId Request ID
     * @param response Encoded metrics response
     * @param err Error message if any
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        MetricsRequest storage request = requests[requestId];

        if (request.timestamp == 0) revert InvalidRequest();
        if (request.fulfilled) revert RequestAlreadyFulfilled();

        // Mark as fulfilled
        request.fulfilled = true;

        // Store result
        metricsResults[requestId] = response;

        // Check for errors
        if (err.length > 0) {
            emit MetricsFulfilled(
                requestId,
                request.owner,
                request.agentTokenId,
                err,
                block.timestamp
            );
            return;
        }

        emit MetricsFulfilled(
            requestId,
            request.owner,
            request.agentTokenId,
            response,
            block.timestamp
        );
    }

    // ============ View Functions ============

    /**
     * @notice Get metrics result for a request
     * @param requestId Request ID
     * @return result Encoded metrics result
     * @return fulfilled Whether request was fulfilled
     */
    function getMetricsResult(bytes32 requestId)
        external
        view
        returns (bytes memory result, bool fulfilled)
    {
        MetricsRequest memory request = requests[requestId];
        return (metricsResults[requestId], request.fulfilled);
    }

    /**
     * @notice Check if metrics pass policy requirements
     * @param requestId Request ID
     * @param agentOwner Owner of agent
     * @param agentTokenId Agent token ID
     * @return passed Whether metrics pass policy checks
     * @return reason Reason if failed
     */
    function checkMetrics(
        bytes32 requestId,
        address agentOwner,
        uint256 agentTokenId
    ) external view returns (bool passed, string memory reason) {
        MetricsRequest memory request = requests[requestId];

        if (!request.fulfilled) {
            return (false, "Request not fulfilled");
        }

        // Verify request matches
        if (request.owner != agentOwner || request.agentTokenId != agentTokenId) {
            return (false, "Request mismatch");
        }

        // Decode result
        bytes memory result = metricsResults[requestId];
        if (result.length == 0) {
            return (false, "Empty result");
        }

        // Parse metrics based on type
        if (request.metricsType == MetricsType.DAILY_VOLUME) {
            return _checkDailyVolume(agentOwner, agentTokenId, result);
        } else if (request.metricsType == MetricsType.DAILY_DRAWDOWN) {
            return _checkDailyDrawdown(agentOwner, agentTokenId, result);
        } else if (request.metricsType == MetricsType.PERFORMANCE_METRICS) {
            return _checkPerformanceMetrics(agentOwner, agentTokenId, result);
        } else if (request.metricsType == MetricsType.FULL_CHECK) {
            return _checkFullMetrics(agentOwner, agentTokenId, result);
        }

        return (true, "");
    }

    // ============ Internal Check Functions ============

    /**
     * @notice Check daily volume against policy limit
     */
    function _checkDailyVolume(
        address agentOwner,
        uint256 agentTokenId,
        bytes memory result
    ) internal view returns (bool, string memory) {
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(agentOwner, agentTokenId);

        // Decode volume from result (uint256)
        uint256 dailyVolume = abi.decode(result, (uint256));

        if (policy.dailyVolumeLimit > 0 && dailyVolume >= policy.dailyVolumeLimit) {
            return (false, "Daily volume limit exceeded");
        }

        return (true, "");
    }

    /**
     * @notice Check daily drawdown against policy limit
     */
    function _checkDailyDrawdown(
        address agentOwner,
        uint256 agentTokenId,
        bytes memory result
    ) internal view returns (bool, string memory) {
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(agentOwner, agentTokenId);

        // Decode drawdown from result (uint256 in basis points)
        uint256 drawdownBps = abi.decode(result, (uint256));

        if (policy.maxDailyDrawdown > 0 && drawdownBps > policy.maxDailyDrawdown) {
            return (false, "Daily drawdown limit exceeded");
        }

        return (true, "");
    }

    /**
     * @notice Check performance metrics (win rate, Sharpe ratio, etc.)
     */
    function _checkPerformanceMetrics(
        address agentOwner,
        uint256 agentTokenId,
        bytes memory result
    ) internal view returns (bool, string memory) {
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(agentOwner, agentTokenId);

        // Decode metrics: (winRateBps, sharpeRatio, reputationScore)
        (uint256 winRateBps, uint256 sharpeRatio, uint256 reputationScore) =
            abi.decode(result, (uint256, uint256, uint256));

        // Check win rate
        if (policy.minWinRateBps > 0 && winRateBps < policy.minWinRateBps) {
            return (false, "Win rate below minimum");
        }

        // Check Sharpe ratio
        if (policy.minSharpeRatio > 0 && int256(sharpeRatio) < policy.minSharpeRatio) {
            return (false, "Sharpe ratio below minimum");
        }

        // Check reputation score
        if (policy.minReputationScore > 0 && reputationScore < policy.minReputationScore) {
            return (false, "Reputation score below minimum");
        }

        return (true, "");
    }

    /**
     * @notice Check all metrics (full validation)
     */
    function _checkFullMetrics(
        address agentOwner,
        uint256 agentTokenId,
        bytes memory result
    ) internal view returns (bool, string memory) {
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(agentOwner, agentTokenId);

        // Decode full metrics
        (
            uint256 dailyVolume,
            uint256 weeklyVolume,
            uint256 dailyDrawdownBps,
            uint256 weeklyDrawdownBps,
            uint256 winRateBps,
            uint256 sharpeRatio,
            uint256 reputationScore
        ) = abi.decode(result, (uint256, uint256, uint256, uint256, uint256, uint256, uint256));

        // Check daily volume
        if (policy.dailyVolumeLimit > 0 && dailyVolume >= policy.dailyVolumeLimit) {
            return (false, "Daily volume limit exceeded");
        }

        // Check weekly volume
        if (policy.weeklyVolumeLimit > 0 && weeklyVolume >= policy.weeklyVolumeLimit) {
            return (false, "Weekly volume limit exceeded");
        }

        // Check daily drawdown
        if (policy.maxDailyDrawdown > 0 && dailyDrawdownBps > policy.maxDailyDrawdown) {
            return (false, "Daily drawdown limit exceeded");
        }

        // Check weekly drawdown
        if (policy.maxWeeklyDrawdown > 0 && weeklyDrawdownBps > policy.maxWeeklyDrawdown) {
            return (false, "Weekly drawdown limit exceeded");
        }

        // Check win rate
        if (policy.minWinRateBps > 0 && winRateBps < policy.minWinRateBps) {
            return (false, "Win rate below minimum");
        }

        // Check Sharpe ratio
        if (policy.minSharpeRatio > 0 && int256(sharpeRatio) < policy.minSharpeRatio) {
            return (false, "Sharpe ratio below minimum");
        }

        // Check reputation score
        if (policy.minReputationScore > 0 && reputationScore < policy.minReputationScore) {
            return (false, "Reputation score below minimum");
        }

        return (true, "");
    }

    // ============ Helper Functions ============

    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes memory data = abi.encodePacked(_addr);
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        for (uint i = 0; i < 20; i++) {
            str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }

    function _uint256ToString(uint256 _value) internal pure returns (string memory) {
        if (_value == 0) {
            return "0";
        }
        uint256 temp = _value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(_value % 10)));
            _value /= 10;
        }
        return string(buffer);
    }
}
