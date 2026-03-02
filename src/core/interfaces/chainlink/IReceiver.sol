// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Vendored from Chainlink CRE (Compute Runtime Environment)
// Consumers of Chainlink CRE reports must implement this interface.
// The KeystoneForwarder contract calls onReport() after verifying BFT quorum
// of DON node signatures — callers do NOT verify signatures themselves.
interface IReceiver {
    /// @notice Called by the Chainlink KeystoneForwarder with a verified report
    /// @param metadata ABI-encoded metadata: (bytes32 workflowExecutionId, uint32 timestamp, ...)
    /// @param report ABI-encoded report payload defined by the workflow
    function onReport(bytes calldata metadata, bytes calldata report) external;
}
