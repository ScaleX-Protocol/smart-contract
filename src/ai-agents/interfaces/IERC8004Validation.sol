// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC8004Validation
 * @notice ERC-8004 Validation Registry interface for cryptographic/economic verification
 * @dev Based on ERC-8004 standard (https://eips.ethereum.org/EIPS/eip-8004)
 *      Validation Registry enables agents to submit proofs for verification
 */
interface IERC8004Validation {
    /**
     * @notice Validation task types
     */
    enum ValidationTask {
        CIRCUIT_BREAKER,      // Circuit breaker triggered
        POLICY_VIOLATION,     // Policy violation detected
        REPUTATION_DISPUTE,   // Dispute on reputation score
        PERFORMANCE_PROOF,    // Proof of performance metrics
        CUSTOM                // Custom validation task
    }

    /**
     * @notice Validation request structure
     */
    struct ValidationRequest {
        uint256 agentTokenId;
        ValidationTask taskType;
        bytes data;             // ABI-encoded task-specific data
        address requester;      // Who requested validation
        uint256 timestamp;
        bool validated;         // Has been validated
        address validator;      // Who validated (if validated)
    }

    /**
     * @notice Request validation for an agent action
     * @param agentTokenId The agent token ID
     * @param taskType Type of validation needed
     * @param data ABI-encoded proof data
     * @return requestId Unique ID for this validation request
     */
    function requestValidation(
        uint256 agentTokenId,
        ValidationTask taskType,
        bytes calldata data
    ) external returns (bytes32 requestId);

    /**
     * @notice Submit validation result (validators only)
     * @param requestId The validation request ID
     * @param isValid Whether the proof is valid
     * @param validatorSignature Validator's signature
     */
    function submitValidation(
        bytes32 requestId,
        bool isValid,
        bytes calldata validatorSignature
    ) external;

    /**
     * @notice Check if a validation request has been validated
     * @param requestId The validation request ID
     * @return validated True if validated
     * @return isValid Whether the validation passed
     */
    function getValidationStatus(bytes32 requestId)
        external
        view
        returns (bool validated, bool isValid);

    /**
     * @notice Get validation request details
     * @param requestId The validation request ID
     * @return request The validation request struct
     */
    function getValidationRequest(bytes32 requestId)
        external
        view
        returns (ValidationRequest memory request);

    /**
     * @notice Emitted when validation is requested
     */
    event ValidationRequested(
        bytes32 indexed requestId,
        uint256 indexed agentTokenId,
        ValidationTask indexed taskType,
        address requester,
        uint256 timestamp
    );

    /**
     * @notice Emitted when validation is submitted
     */
    event ValidationSubmitted(
        bytes32 indexed requestId,
        uint256 indexed agentTokenId,
        address indexed validator,
        bool isValid,
        uint256 timestamp
    );
}
