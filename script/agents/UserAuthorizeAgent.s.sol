// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";

/**
 * @title UserAuthorizeAgent
 * @notice User grants a strategy agent permission to execute orders on their behalf.
 * @dev Run this AFTER the agent wallet has registered its NFT via CreateMultipleAgents.
 *
 * Flow:
 *   1. Agent wallet runs CreateMultipleAgents  →  registers NFT, gets strategyAgentId
 *   2. User wallet runs this script            →  AgentRouter.authorize(strategyAgentId, policy)
 *   3. Agent wallet calls AgentRouter.execute*(userAddress, strategyAgentId, ...)
 *      AgentRouter checks:
 *        • msg.sender == ownerOf(strategyAgentId)        (agent wallet owns NFT)
 *        • authorizedStrategyAgents[user][strategyAgentId]  (user granted permission)
 *
 * Required env vars:
 *   USER_PRIVATE_KEY    — wallet that owns funds and is granting authorization
 *   STRATEGY_AGENT_ID  — NFT token ID of the agent being authorized (from CreateMultipleAgents)
 */
contract UserAuthorizeAgent is Script {
    /// @dev Cached agentRouter — stored in slot so it is not a live stack variable
    ///      during the 42-field Policy ABI encoding, avoiding stack-too-deep errors.
    address private _agentRouterCache;

    function run() external {
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");
        string memory json = vm.readFile(deploymentPath);

        address agentRouter = _extractAddress(json, "AgentRouter");

        uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
        address userWallet = vm.addr(userPrivateKey);
        uint256 strategyAgentId = vm.envUint("STRATEGY_AGENT_ID");

        console.log("=== USER AUTHORIZE AGENT ===");
        console.log("");
        console.log("AgentRouter:       ", agentRouter);
        console.log("User Wallet:       ", userWallet);
        console.log("Strategy Agent ID: ", strategyAgentId);
        console.log("");

        vm.startBroadcast(userPrivateKey);
        _authorize(agentRouter, strategyAgentId);
        vm.stopBroadcast();

        // Verify
        bool authorized = AgentRouter(agentRouter).isAuthorized(userWallet, strategyAgentId);
        if (authorized) {
            console.log("[OK] Authorization confirmed");
            console.log("");
            console.log("Agent", strategyAgentId, "can now execute orders on behalf of user:");
            console.log(" ", userWallet);
        } else {
            console.log("[FAIL] Authorization not recorded - check agent ID and router address");
        }
    }

    /// @dev Stage 1: cache agentRouter in storage, then delegate to isolated frames
    ///      to keep Yul stack depth within the SWAP16 window during Policy encoding.
    function _authorize(address agentRouter, uint256 strategyAgentId) internal {
        _agentRouterCache = agentRouter;
        _callAuthorize(strategyAgentId, _buildDefaultPolicy());
    }

    /// @dev Builds the Policy in an isolated pure frame so its locals are gone before
    ///      _callAuthorize begins encoding the 42-field struct.
    function _buildDefaultPolicy() private pure returns (PolicyFactory.Policy memory p) {
        address[] memory empty = new address[](0);
        p.expiryTimestamp             = type(uint256).max;
        p.maxOrderSize                = 10000e6;
        p.minOrderSize                = 1e6;
        p.whitelistedTokens           = empty;
        p.blacklistedTokens           = empty;
        p.allowMarketOrders           = true;
        p.allowLimitOrders            = true;
        p.allowSwap                   = true;
        p.allowBorrow                 = true;
        p.allowRepay                  = true;
        p.allowSupplyCollateral       = true;
        p.allowWithdrawCollateral     = true;
        p.allowPlaceLimitOrder        = true;
        p.allowCancelOrder            = true;
        p.allowBuy                    = true;
        p.allowSell                   = true;
        p.allowAutoBorrow             = true;
        p.maxAutoBorrowAmount         = 5000e6;
        p.allowAutoRepay              = true;
        p.minDebtToRepay              = 100e6;
        p.minHealthFactor             = 13e17;   // 1.3 = 30% safety buffer
        p.maxSlippageBps              = 500;      // 5%
        p.minTimeBetweenTrades        = 60;       // 1 minute
        p.dailyVolumeLimit            = 50000e6;
        p.weeklyVolumeLimit           = 200000e6;
        p.maxDailyDrawdown            = 2000;     // 20%
        p.maxWeeklyDrawdown           = 3000;     // 30%
        p.maxTradeVsTVLBps            = 1000;     // 10%
        p.maxPositionConcentrationBps = 5000;     // 50%
        p.maxCorrelationBps           = 10000;
        p.maxTradesPerDay             = 1000;
        p.maxTradesPerHour            = 100;
        p.tradingEndHour              = 23;
    }

    /// @dev Assembly ABI encoder for authorize(uint256, Policy).
    ///      Policy has 42 ABI head words; whitelistedTokens (field 5) and
    ///      blacklistedTokens (field 6) are dynamic — always empty here,
    ///      so their tail lengths are hardcoded 0.
    ///      Calldata: 4 (sel) + 32 (id) + 32 (Policy offset=64) + 1344 (42-word head)
    ///                + 32 (wTokens len=0) + 32 (bTokens len=0) = 1476 bytes total.
    function _callAuthorize(uint256 agentId, PolicyFactory.Policy memory p) private {
        bytes4 sel = AgentRouter.authorize.selector;
        assembly {
            let router  := sload(_agentRouterCache.slot)
            let cdStart := mload(0x40)
            mstore(0x40, add(cdStart, 1476))

            mstore(cdStart,           sel)    // selector
            mstore(add(cdStart,  4),  agentId) // param 1: strategyAgentId
            mstore(add(cdStart, 36),  0x40)    // param 2: offset to Policy tuple

            let base := add(cdStart, 68)       // Policy head starts here

            // Copy all 42 head words from Policy memory → calldata
            for { let i := 0 } lt(i, 42) { i := add(i, 1) } {
                mstore(add(base, mul(i, 0x20)), mload(add(p, mul(i, 0x20))))
            }

            // Overwrite dynamic field offsets (relative to Policy tuple start)
            mstore(add(base, 0xa0), 0x540)  // whitelistedTokens tail offset
            mstore(add(base, 0xc0), 0x560)  // blacklistedTokens tail offset

            // Empty array lengths in the tail
            mstore(add(base, 0x540), 0)
            mstore(add(base, 0x560), 0)

            let ok := call(gas(), router, 0, cdStart, 1476, 0, 0)
            if iszero(ok) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes.concat('"', bytes(key), '": "');

        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) return address(0);

        uint256 addressStart = keyPos + keyBytes.length;
        bytes memory addressBytes = new bytes(42);
        for (uint256 i = 0; i < 42; i++) {
            addressBytes[i] = jsonBytes[addressStart + i];
        }
        return _bytesToAddress(addressBytes);
    }

    function _indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        if (needle.length == 0 || haystack.length < needle.length) return type(uint256).max;

        uint256 needleLength = needle.length;
        for (uint256 i = 0; i <= haystack.length - needleLength; i++) {
            bool found = true;
            for (uint256 j = 0; j < needleLength; j++) {
                if (haystack[i + j] != needle[j]) { found = false; break; }
            }
            if (found) return i;
        }
        return type(uint256).max;
    }

    function _bytesToAddress(bytes memory data) internal pure returns (address) {
        return address(uint160(uint256(_hexToUint(data))));
    }

    function _hexToUint(bytes memory data) internal pure returns (uint256) {
        uint256 result = 0;
        for (uint256 i = 0; i < data.length; i++) {
            uint8 b = uint8(data[i]);
            uint256 digit;
            if (b >= 48 && b <= 57)       digit = uint256(b) - 48;
            else if (b >= 97 && b <= 102) digit = uint256(b) - 87;
            else if (b >= 65 && b <= 70)  digit = uint256(b) - 55;
            else continue;
            result = result * 16 + digit;
        }
        return result;
    }
}
