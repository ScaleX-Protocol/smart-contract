// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IERC8004Validation.sol";

/**
 * @title MockERC8004Validation
 * @notice Mock implementation of ERC-8004 Validation Registry for testing
 * @dev Simplified validation tracking for agent proofs
 */
contract MockERC8004Validation is IERC8004Validation {
    // Request ID => Validation Request
    mapping(bytes32 => ValidationRequest) private _requests;

    // Request ID => Validation result
    mapping(bytes32 => bool) private _validationResults;

    // Authorized validators
    mapping(address => bool) public authorizedValidators;

    // Owner (for access control)
    address public owner;

    // Request counter
    uint256 private _requestCounter;

    constructor() {
        owner = msg.sender;
        authorizedValidators[msg.sender] = true;
    }

    /**
     * @notice Authorize a validator
     */
    function setAuthorizedValidator(address validator, bool authorized) external {
        require(msg.sender == owner, "Only owner");
        authorizedValidators[validator] = authorized;
    }

    /**
     * @notice Request validation for an agent action
     */
    function requestValidation(
        uint256 agentTokenId,
        ValidationTask taskType,
        bytes calldata data
    ) external override returns (bytes32 requestId) {
        // Generate unique request ID
        requestId = keccak256(
            abi.encodePacked(
                agentTokenId,
                taskType,
                data,
                msg.sender,
                block.timestamp,
                _requestCounter++
            )
        );

        // Store validation request
        _requests[requestId] = ValidationRequest({
            agentTokenId: agentTokenId,
            taskType: taskType,
            data: data,
            requester: msg.sender,
            timestamp: block.timestamp,
            validated: false,
            validator: address(0)
        });

        emit ValidationRequested(
            requestId,
            agentTokenId,
            taskType,
            msg.sender,
            block.timestamp
        );
    }

    /**
     * @notice Submit validation result (validators only)
     */
    function submitValidation(
        bytes32 requestId,
        bool isValid,
        bytes calldata validatorSignature
    ) external override {
        require(authorizedValidators[msg.sender], "Not authorized validator");
        require(_requests[requestId].timestamp > 0, "Request does not exist");
        require(!_requests[requestId].validated, "Already validated");

        // Note: In production, would verify validatorSignature
        // For mock, we just trust authorized validators

        _requests[requestId].validated = true;
        _requests[requestId].validator = msg.sender;
        _validationResults[requestId] = isValid;

        emit ValidationSubmitted(
            requestId,
            _requests[requestId].agentTokenId,
            msg.sender,
            isValid,
            block.timestamp
        );
    }

    /**
     * @notice Auto-validate (convenience for testing)
     */
    function autoValidate(bytes32 requestId, bool isValid) external {
        require(msg.sender == owner || authorizedValidators[msg.sender], "Not authorized");
        require(_requests[requestId].timestamp > 0, "Request does not exist");

        _requests[requestId].validated = true;
        _requests[requestId].validator = msg.sender;
        _validationResults[requestId] = isValid;

        emit ValidationSubmitted(
            requestId,
            _requests[requestId].agentTokenId,
            msg.sender,
            isValid,
            block.timestamp
        );
    }

    /**
     * @notice Check if a validation request has been validated
     */
    function getValidationStatus(bytes32 requestId)
        external
        view
        override
        returns (bool validated, bool isValid)
    {
        validated = _requests[requestId].validated;
        isValid = _validationResults[requestId];
    }

    /**
     * @notice Get validation request details
     */
    function getValidationRequest(bytes32 requestId)
        external
        view
        override
        returns (ValidationRequest memory)
    {
        return _requests[requestId];
    }
}
