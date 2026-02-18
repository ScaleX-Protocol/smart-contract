// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../ai-agents/PolicyFactory.sol";

/// @dev Minimal interface to avoid importing the full AgentRouter contract
interface IAgentRouterEncoder {
    function authorize(uint256 strategyAgentId, PolicyFactory.Policy calldata policy) external;
}

/**
 * @title PolicyEncoder
 * @notice Helper to encode policy authorization calldata
 */
contract PolicyEncoder {
    /**
     * @notice Get the encoded calldata for authorizing an agent with a permissive policy
     * @param agentId The strategy agent token ID
     * @return The encoded calldata for AgentRouter.authorize()
     */
    function getInstallPolicyCalldata(uint256 agentId) external pure returns (bytes memory) {
        return _buildCalldata(agentId);
    }

    /// @dev Extracted to avoid Yul stack-too-deep from 42-field struct literal construction.
    ///      Further split: `empty` must NOT be in scope during abi.encodeCall because the
    ///      ABI encoding of the 42-field Policy struct (2 dynamic arrays) uses ~14 internal
    ///      Yul variables; combined with `empty`, `p`, `agentId`, and `RET` (bytes return),
    ///      that is 18 stack items — 1 beyond the 17-slot accessible EVM window.
    function _buildCalldata(uint256 agentId) internal pure returns (bytes memory) {
        address[] memory empty = new address[](0);
        PolicyFactory.Policy memory p;
        p.expiryTimestamp           = type(uint256).max;
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
        p.minHealthFactor           = 1e18;
        p.maxSlippageBps            = 10000;
        p.tradingEndHour            = 23;
        return _encodeAuthorizeCall(agentId, p);
    }

    /// @dev Isolated so only `agentId` and `p` are live during abi.encodeCall.
    ///      `empty` from _buildCalldata is out of scope here, saving the critical stack slot.
    function _encodeAuthorizeCall(uint256 agentId, PolicyFactory.Policy memory p) private pure returns (bytes memory) {
        return abi.encodeCall(IAgentRouterEncoder.authorize, (agentId, p));
    }
}
