// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../ai-agents/PolicyFactory.sol";

/// @dev Minimal interface to avoid importing the full AgentRouter contract
interface IAgentRouterInstaller {
    function authorize(uint256 strategyAgentId, PolicyFactory.Policy calldata policy) external;
}

/**
 * @title PolicyInstaller
 * @notice Helper contract to install a simple permissive policy for an agent
 */
contract PolicyInstaller {
    address public immutable agentRouter;

    constructor(address _agentRouter) {
        agentRouter = _agentRouter;
    }

    /**
     * @notice Install a permissive trading policy for an agent
     * @param agentId The strategy agent token ID
     */
    function installPermissivePolicy(uint256 agentId) external {
        _buildAndAuthorize(agentId);
    }

    /// @dev Extracted to avoid Yul stack-too-deep from 42-field struct literal construction.
    ///      Further split: `empty` must NOT be in scope during authorize() because the ABI
    ///      encoding of the 42-field Policy struct uses ~14 internal Yul variables; combined
    ///      with `empty`, `p`, and `agentId` that exceeds the 16-slot accessible EVM window.
    function _buildAndAuthorize(uint256 agentId) internal {
        address[] memory empty = new address[](0);
        PolicyFactory.Policy memory p;
        p.maxOrderSize              = 1000000e6;
        p.minOrderSize              = 1e6;
        p.whitelistedTokens         = empty;
        p.blacklistedTokens         = empty;
        p.allowMarketOrders         = true;
        p.allowLimitOrders          = true;
        p.allowSwap                 = true;
        p.allowPlaceLimitOrder      = true;
        p.allowCancelOrder          = true;
        p.allowBuy                  = true;
        p.allowSell                 = true;
        p.maxSlippageBps            = 10000;
        p.tradingEndHour            = 23;
        _callAuthorize(agentId, p);
    }

    /// @dev Isolated so only `agentId` and `p` are live during the authorize() external call.
    ///      `empty` from _buildAndAuthorize is out of scope here, saving the critical stack slot.
    function _callAuthorize(uint256 agentId, PolicyFactory.Policy memory p) private {
        IAgentRouterInstaller(agentRouter).authorize(agentId, p);
    }
}
