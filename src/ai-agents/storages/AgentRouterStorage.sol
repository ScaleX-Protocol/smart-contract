// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title AgentRouterStorage
 * @notice Diamond storage (ERC-7201) for AgentRouter.
 *
 * Slot: keccak256(abi.encode(uint256(keccak256("scalex.agents.storage.agentrouter")) - 1)) & ~bytes32(uint256(0xff))
 */
abstract contract AgentRouterStorage {
    // keccak256(abi.encode(uint256(keccak256("scalex.agents.storage.agentrouter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0xb0282804f0dd0a74b566bd60e55ca9b401321474a0969a133b0c153c6e5e2b00;

    struct Storage {
        address identityRegistry;
        address reputationRegistry;
        address validationRegistry;
        address policyFactory;
        address metricsConsumer;
        address poolManager;
        address balanceManager;
        address lendingManager;

        // Circuit-breaker tracking (keyed by strategyAgentId — reputation is per strategy)
        mapping(address => mapping(uint256 => uint256)) dayStartValues;  // user => day => value
        mapping(uint256 => uint256) lastTradeTime;                        // strategyAgentId => timestamp
        mapping(uint256 => mapping(uint256 => uint256)) dailyVolumes;    // strategyAgentId => day => volume

        // user => strategyAgentId => authorized
        mapping(address => mapping(uint256 => bool)) authorizedStrategyAgents;
    }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}
