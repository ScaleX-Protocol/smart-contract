// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title PolicyFactoryStorage
 * @notice Diamond storage (ERC-7201) for PolicyFactory.
 *         Policy and PolicyTemplate structs live here so the Storage struct is self-contained.
 *
 * Slot: keccak256(abi.encode(uint256(keccak256("scalex.agents.storage.policyfactory")) - 1)) & ~bytes32(uint256(0xff))
 */
abstract contract PolicyFactoryStorage {
    // keccak256(abi.encode(uint256(keccak256("scalex.agents.storage.policyfactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x81a733e84018166cbaf30c6d42e982d02d6582a904c1cba038542ca70233b000;

    // ============ Structs (live here so Storage struct can reference them) ============

    struct Policy {
        // ============ Metadata ============
        bool enabled;
        uint256 installedAt;
        uint256 expiryTimestamp;
        // Note: strategyAgentId is NOT stored here — it is the mapping key

        // ============ SIMPLE PERMISSIONS (No external compute) ============

        // Order Size
        uint256 maxOrderSize;
        uint256 minOrderSize;

        // Allowed Markets
        address[] whitelistedTokens;
        address[] blacklistedTokens;

        // Order Types
        bool allowMarketOrders;
        bool allowLimitOrders;

        // Operations
        bool allowSwap;
        bool allowBorrow;
        bool allowRepay;
        bool allowSupplyCollateral;
        bool allowWithdrawCollateral;
        bool allowPlaceLimitOrder;
        bool allowCancelOrder;

        // Buy/Sell Direction
        bool allowBuy;
        bool allowSell;

        // Auto-Borrow
        bool allowAutoBorrow;
        uint256 maxAutoBorrowAmount;

        // Auto-Repay
        bool allowAutoRepay;
        uint256 minDebtToRepay;

        // Safety
        uint256 minHealthFactor;       // e.g., 1.5e18 = 150%
        uint256 maxSlippageBps;        // e.g., 100 = 1%
        uint256 minTimeBetweenTrades;  // seconds
        address emergencyRecipient;

        // ============ COMPLEX PERMISSIONS (Chainlink/AVS Required) ============

        // Volume Limits
        uint256 dailyVolumeLimit;
        uint256 weeklyVolumeLimit;

        // Drawdown Limits
        uint256 maxDailyDrawdown;      // Basis points
        uint256 maxWeeklyDrawdown;     // Basis points

        // Market Depth
        uint256 maxTradeVsTVLBps;

        // Performance Requirements
        uint256 minWinRateBps;
        int256 minSharpeRatio;         // scaled by 1e18

        // Position Management
        uint256 maxPositionConcentrationBps;
        uint256 maxCorrelationBps;

        // Trade Frequency
        uint256 maxTradesPerDay;
        uint256 maxTradesPerHour;

        // Trading Hours
        uint256 tradingStartHour;      // UTC hour (0-23)
        uint256 tradingEndHour;        // UTC hour (0-23)

        // Reputation
        uint256 minReputationScore;
        bool useReputationMultiplier;

        // ============ Optimization Flag ============
        bool requiresChainlinkFunctions;
    }

    struct PolicyTemplate {
        string name;
        string description;
        Policy basePolicy;
        bool active;
    }

    // ============ Storage Struct ============

    struct Storage {
        address identityRegistry;
        // user => strategyAgentId => Policy
        mapping(address => mapping(uint256 => Policy)) policies;
        // user => list of authorised strategy agent IDs
        mapping(address => uint256[]) installedAgents;
        // Policy templates
        mapping(string => PolicyTemplate) templates;
        // Authorized routers (AgentRouter) - can call installPolicyFor / uninstallPolicyFor
        mapping(address => bool) authorizedRouters;
        // Note: 'owner' is omitted — handled by OwnableUpgradeable
    }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}
