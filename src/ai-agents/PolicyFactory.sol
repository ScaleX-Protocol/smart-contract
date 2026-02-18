// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC8004Identity.sol";

/**
 * @title PolicyFactory
 * @notice Central policy management for AI agent trading permissions.
 *
 * Policies are stored as: policies[user][strategyAgentId]
 *   - "user"            = the wallet that owns the funds (grants permission)
 *   - "strategyAgentId" = the NFT ID of the strategy agent being permitted
 *
 * Users never need to register an NFT. Only strategy agents need one.
 * Use AgentRouter.authorize(strategyAgentId, policy) to install a policy and
 * grant authorization in a single transaction.
 */
contract PolicyFactory {
    // ============ State Variables ============

    IERC8004Identity public immutable identityRegistry;

    // user => strategyAgentId => Policy
    mapping(address => mapping(uint256 => Policy)) public policies;

    // user => list of authorised strategy agent IDs
    mapping(address => uint256[]) public installedAgents;

    // Policy templates
    mapping(string => PolicyTemplate) public templates;

    // Authorized routers (AgentRouter) - can call installPolicyFor / uninstallPolicyFor
    mapping(address => bool) public authorizedRouters;

    address public owner;

    // ============ Structs ============

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

    struct PolicyCustomization {
        uint256 maxOrderSize;
        uint256 dailyVolumeLimit;
        uint256 expiryTimestamp;
        address[] whitelistedTokens;
    }

    // ============ Events ============

    event PolicyInstalled(
        address indexed user,
        uint256 indexed strategyAgentId,
        string templateUsed,
        uint256 timestamp
    );

    event PolicyUninstalled(
        address indexed user,
        uint256 indexed strategyAgentId,
        uint256 timestamp
    );

    event PolicyUpdated(
        address indexed user,
        uint256 indexed strategyAgentId,
        string field,
        uint256 timestamp
    );

    event PolicyEnabled(
        address indexed user,
        uint256 indexed strategyAgentId,
        uint256 timestamp
    );

    event PolicyDisabled(
        address indexed user,
        uint256 indexed strategyAgentId,
        string reason,
        uint256 timestamp
    );

    event TemplateCreated(
        string indexed name,
        string description,
        uint256 timestamp
    );

    // ============ Constructor ============

    constructor(address _identityRegistry) {
        identityRegistry = IERC8004Identity(_identityRegistry);
        owner = msg.sender;
        authorizedRouters[msg.sender] = true;
        _initializeTemplates();
    }

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyAuthorizedRouter() {
        require(authorizedRouters[msg.sender], "Not authorized router");
        _;
    }

    // ============ Install / Uninstall (called directly by user) ============

    /**
     * @notice Install a policy granting strategyAgentId permission to trade for msg.sender.
     * @dev The strategy agent NFT must exist. The caller does NOT need to own it.
     *      Prefer AgentRouter.authorize(strategyAgentId, policy) which does this + auth in one tx.
     */
    function installPolicy(
        uint256 strategyAgentId,
        Policy calldata policy
    ) external {
        // Verify strategy agent NFT exists (reverts on invalid token)
        identityRegistry.ownerOf(strategyAgentId);

        require(
            !policies[msg.sender][strategyAgentId].enabled &&
                policies[msg.sender][strategyAgentId].installedAt == 0,
            "Policy already installed"
        );

        _validatePolicy(policy);

        policies[msg.sender][strategyAgentId] = policy;
        policies[msg.sender][strategyAgentId].installedAt = block.timestamp;
        policies[msg.sender][strategyAgentId].enabled = true;
        policies[msg.sender][strategyAgentId].requiresChainlinkFunctions = _requiresChainlink(policy);

        installedAgents[msg.sender].push(strategyAgentId);

        emit PolicyInstalled(msg.sender, strategyAgentId, "custom", block.timestamp);
    }

    /**
     * @notice Install a policy from a template.
     */
    function installPolicyFromTemplate(
        uint256 strategyAgentId,
        string calldata templateName,
        PolicyCustomization calldata customizations
    ) external {
        identityRegistry.ownerOf(strategyAgentId);

        require(
            !policies[msg.sender][strategyAgentId].enabled,
            "Policy already installed"
        );

        PolicyTemplate memory tmpl = templates[templateName];
        require(tmpl.active, "Template not found or inactive");

        Policy memory policy = tmpl.basePolicy;

        if (customizations.maxOrderSize > 0)        policy.maxOrderSize = customizations.maxOrderSize;
        if (customizations.dailyVolumeLimit > 0)    policy.dailyVolumeLimit = customizations.dailyVolumeLimit;
        if (customizations.expiryTimestamp > 0)     policy.expiryTimestamp = customizations.expiryTimestamp;
        if (customizations.whitelistedTokens.length > 0) policy.whitelistedTokens = customizations.whitelistedTokens;

        _validatePolicy(policy);
        policies[msg.sender][strategyAgentId] = policy;
        policies[msg.sender][strategyAgentId].installedAt = block.timestamp;
        policies[msg.sender][strategyAgentId].enabled = true;
        policies[msg.sender][strategyAgentId].requiresChainlinkFunctions = _requiresChainlink(policy);

        installedAgents[msg.sender].push(strategyAgentId);

        emit PolicyInstalled(msg.sender, strategyAgentId, templateName, block.timestamp);
    }

    /**
     * @notice Remove the policy for a strategy agent (does not revoke AgentRouter auth).
     *         Use AgentRouter.revoke() to remove both authorization and policy at once.
     */
    function uninstallPolicy(uint256 strategyAgentId) external {
        require(
            policies[msg.sender][strategyAgentId].enabled ||
                policies[msg.sender][strategyAgentId].installedAt > 0,
            "Policy not installed"
        );

        delete policies[msg.sender][strategyAgentId];
        _removeFromInstalledList(msg.sender, strategyAgentId);

        emit PolicyUninstalled(msg.sender, strategyAgentId, block.timestamp);
    }

    // ============ Router-delegated Install / Uninstall ============
    // Called by AgentRouter on behalf of a user (msg.sender = AgentRouter).

    /**
     * @notice Install policy for `user` — called by AgentRouter.authorize().
     */
    function installPolicyFor(
        address user,
        uint256 strategyAgentId,
        Policy calldata policy
    ) external onlyAuthorizedRouter {
        identityRegistry.ownerOf(strategyAgentId);

        require(
            !policies[user][strategyAgentId].enabled &&
                policies[user][strategyAgentId].installedAt == 0,
            "Policy already installed"
        );

        _validatePolicy(policy);

        policies[user][strategyAgentId] = policy;
        policies[user][strategyAgentId].installedAt = block.timestamp;
        policies[user][strategyAgentId].enabled = true;
        policies[user][strategyAgentId].requiresChainlinkFunctions = _requiresChainlink(policy);

        installedAgents[user].push(strategyAgentId);

        emit PolicyInstalled(user, strategyAgentId, "custom", block.timestamp);
    }

    /**
     * @notice Uninstall policy for `user` — called by AgentRouter.revoke().
     */
    function uninstallPolicyFor(
        address user,
        uint256 strategyAgentId
    ) external onlyAuthorizedRouter {
        if (policies[user][strategyAgentId].installedAt == 0) return; // already gone

        delete policies[user][strategyAgentId];
        _removeFromInstalledList(user, strategyAgentId);

        emit PolicyUninstalled(user, strategyAgentId, block.timestamp);
    }

    // ============ Policy Management ============

    function updateTradingLimits(
        uint256 strategyAgentId,
        uint256 maxOrderSize,
        uint256 minOrderSize,
        uint256 dailyVolumeLimit
    ) external {
        Policy storage policy = _getPolicy(msg.sender, strategyAgentId);
        policy.maxOrderSize = maxOrderSize;
        policy.minOrderSize = minOrderSize;
        policy.dailyVolumeLimit = dailyVolumeLimit;
        policy.requiresChainlinkFunctions = _requiresChainlink(policy);
        emit PolicyUpdated(msg.sender, strategyAgentId, "tradingLimits", block.timestamp);
    }

    function updateBorrowingLimits(
        uint256 strategyAgentId,
        uint256 maxAutoBorrowAmount,
        bool allowBorrowing
    ) external {
        Policy storage policy = _getPolicy(msg.sender, strategyAgentId);
        policy.maxAutoBorrowAmount = maxAutoBorrowAmount;
        policy.allowBorrow = allowBorrowing;
        emit PolicyUpdated(msg.sender, strategyAgentId, "borrowingLimits", block.timestamp);
    }

    function updateSafetyControls(
        uint256 strategyAgentId,
        uint256 minHealthFactor,
        uint256 maxDailyDrawdown
    ) external {
        Policy storage policy = _getPolicy(msg.sender, strategyAgentId);
        require(minHealthFactor >= 1e18, "Health factor must be >= 100%");
        require(maxDailyDrawdown <= 10000, "Drawdown must be <= 100%");
        policy.minHealthFactor = minHealthFactor;
        policy.maxDailyDrawdown = maxDailyDrawdown;
        policy.requiresChainlinkFunctions = _requiresChainlink(policy);
        emit PolicyUpdated(msg.sender, strategyAgentId, "safetyControls", block.timestamp);
    }

    function updateTokenLists(
        uint256 strategyAgentId,
        address[] calldata whitelistedTokens,
        address[] calldata blacklistedTokens
    ) external {
        Policy storage policy = _getPolicy(msg.sender, strategyAgentId);
        policy.whitelistedTokens = whitelistedTokens;
        policy.blacklistedTokens = blacklistedTokens;
        emit PolicyUpdated(msg.sender, strategyAgentId, "tokenLists", block.timestamp);
    }

    function setAgentEnabled(uint256 strategyAgentId, bool enabled) external {
        Policy storage policy = _getPolicy(msg.sender, strategyAgentId);
        policy.enabled = enabled;
        if (enabled) {
            emit PolicyEnabled(msg.sender, strategyAgentId, block.timestamp);
        } else {
            emit PolicyDisabled(msg.sender, strategyAgentId, "manual", block.timestamp);
        }
    }

    /**
     * @notice Emergency disable — called by AgentRouter when circuit breaker triggers.
     */
    function emergencyDisable(
        address user,
        uint256 strategyAgentId,
        string calldata reason
    ) external onlyAuthorizedRouter {
        Policy storage policy = policies[user][strategyAgentId];
        require(policy.enabled, "Already disabled");
        policy.enabled = false;
        emit PolicyDisabled(user, strategyAgentId, reason, block.timestamp);
    }

    // ============ Policy Queries ============

    function getPolicy(
        address user,
        uint256 strategyAgentId
    ) external view returns (Policy memory) {
        return policies[user][strategyAgentId];
    }

    function isAgentEnabled(
        address user,
        uint256 strategyAgentId
    ) external view returns (bool) {
        Policy memory policy = policies[user][strategyAgentId];
        return policy.enabled && block.timestamp < policy.expiryTimestamp;
    }

    function getInstalledAgents(address user) external view returns (uint256[] memory) {
        return installedAgents[user];
    }

    function isTokenAllowed(
        address user,
        uint256 strategyAgentId,
        address token
    ) external view returns (bool) {
        Policy memory policy = policies[user][strategyAgentId];

        for (uint256 i = 0; i < policy.blacklistedTokens.length; i++) {
            if (policy.blacklistedTokens[i] == token) return false;
        }

        if (policy.whitelistedTokens.length == 0) return true;

        for (uint256 i = 0; i < policy.whitelistedTokens.length; i++) {
            if (policy.whitelistedTokens[i] == token) return true;
        }

        return false;
    }

    // ============ Internal ============

    function _getPolicy(address user, uint256 strategyAgentId) internal view returns (Policy storage) {
        Policy storage policy = policies[user][strategyAgentId];
        require(policy.installedAt > 0, "Policy not installed");
        return policy;
    }

    function _validatePolicy(Policy memory policy) internal pure {
        require(policy.maxOrderSize > 0, "Invalid maxOrderSize");
        if (policy.minOrderSize > 0) {
            require(policy.minOrderSize <= policy.maxOrderSize, "Min > max order size");
        }
        require(policy.minHealthFactor >= 1e18, "Health factor < 100%");
        require(policy.maxDailyDrawdown <= 10000, "Drawdown > 100%");
        require(policy.maxSlippageBps <= 10000, "Slippage > 100%");
    }

    function _requiresChainlink(Policy memory policy) internal pure returns (bool) {
        return (
            policy.dailyVolumeLimit > 0 ||
            policy.weeklyVolumeLimit > 0 ||
            policy.maxDailyDrawdown > 0 ||
            policy.maxWeeklyDrawdown > 0 ||
            policy.maxTradeVsTVLBps > 0 ||
            policy.minWinRateBps > 0 ||
            policy.minSharpeRatio > 0 ||
            policy.maxPositionConcentrationBps > 0 ||
            policy.maxTradesPerDay > 0 ||
            policy.maxTradesPerHour > 0 ||
            policy.tradingStartHour > 0
        );
    }

    function _removeFromInstalledList(address user, uint256 strategyAgentId) internal {
        uint256[] storage agents = installedAgents[user];
        for (uint256 i = 0; i < agents.length; i++) {
            if (agents[i] == strategyAgentId) {
                agents[i] = agents[agents.length - 1];
                agents.pop();
                break;
            }
        }
    }

    // ============ Templates ============

    function _initializeTemplates() internal {
        templates["conservative"] = PolicyTemplate({
            name: "Conservative",
            description: "Low risk, strict limits",
            active: true,
            basePolicy: Policy({
                enabled: true,
                installedAt: 0,
                expiryTimestamp: type(uint256).max,
                maxOrderSize: 1000e6,
                minOrderSize: 100e6,
                whitelistedTokens: new address[](0),
                blacklistedTokens: new address[](0),
                allowMarketOrders: true,
                allowLimitOrders: true,
                allowSwap: true,
                allowBorrow: false,
                allowRepay: true,
                allowSupplyCollateral: true,
                allowWithdrawCollateral: true,
                allowPlaceLimitOrder: true,
                allowCancelOrder: true,
                allowBuy: true,
                allowSell: true,
                allowAutoBorrow: false,
                maxAutoBorrowAmount: 0,
                allowAutoRepay: false,
                minDebtToRepay: 0,
                minHealthFactor: 2e18,
                maxSlippageBps: 50,
                minTimeBetweenTrades: 300,
                emergencyRecipient: address(0),
                dailyVolumeLimit: 5000e6,
                weeklyVolumeLimit: 0,
                maxDailyDrawdown: 500,
                maxWeeklyDrawdown: 0,
                maxTradeVsTVLBps: 0,
                minWinRateBps: 0,
                minSharpeRatio: 0,
                maxPositionConcentrationBps: 0,
                maxCorrelationBps: 0,
                maxTradesPerDay: 20,
                maxTradesPerHour: 0,
                tradingStartHour: 0,
                tradingEndHour: 0,
                minReputationScore: 75,
                useReputationMultiplier: false,
                requiresChainlinkFunctions: true
            })
        });

        templates["moderate"] = PolicyTemplate({
            name: "Moderate",
            description: "Balanced risk and limits",
            active: true,
            basePolicy: Policy({
                enabled: true,
                installedAt: 0,
                expiryTimestamp: type(uint256).max,
                maxOrderSize: 5000e6,
                minOrderSize: 100e6,
                whitelistedTokens: new address[](0),
                blacklistedTokens: new address[](0),
                allowMarketOrders: true,
                allowLimitOrders: true,
                allowSwap: true,
                allowBorrow: true,
                allowRepay: true,
                allowSupplyCollateral: true,
                allowWithdrawCollateral: true,
                allowPlaceLimitOrder: true,
                allowCancelOrder: true,
                allowBuy: true,
                allowSell: true,
                allowAutoBorrow: true,
                maxAutoBorrowAmount: 2000e6,
                allowAutoRepay: true,
                minDebtToRepay: 100e6,
                minHealthFactor: 15e17,
                maxSlippageBps: 100,
                minTimeBetweenTrades: 60,
                emergencyRecipient: address(0),
                dailyVolumeLimit: 20000e6,
                weeklyVolumeLimit: 0,
                maxDailyDrawdown: 1000,
                maxWeeklyDrawdown: 0,
                maxTradeVsTVLBps: 0,
                minWinRateBps: 0,
                minSharpeRatio: 0,
                maxPositionConcentrationBps: 0,
                maxCorrelationBps: 0,
                maxTradesPerDay: 100,
                maxTradesPerHour: 0,
                tradingStartHour: 0,
                tradingEndHour: 0,
                minReputationScore: 50,
                useReputationMultiplier: true,
                requiresChainlinkFunctions: true
            })
        });

        templates["aggressive"] = PolicyTemplate({
            name: "Aggressive",
            description: "High risk, loose limits",
            active: true,
            basePolicy: Policy({
                enabled: true,
                installedAt: 0,
                expiryTimestamp: type(uint256).max,
                maxOrderSize: 50000e6,
                minOrderSize: 100e6,
                whitelistedTokens: new address[](0),
                blacklistedTokens: new address[](0),
                allowMarketOrders: true,
                allowLimitOrders: true,
                allowSwap: true,
                allowBorrow: true,
                allowRepay: true,
                allowSupplyCollateral: true,
                allowWithdrawCollateral: true,
                allowPlaceLimitOrder: true,
                allowCancelOrder: true,
                allowBuy: true,
                allowSell: true,
                allowAutoBorrow: true,
                maxAutoBorrowAmount: 20000e6,
                allowAutoRepay: true,
                minDebtToRepay: 100e6,
                minHealthFactor: 12e17,
                maxSlippageBps: 300,
                minTimeBetweenTrades: 0,
                emergencyRecipient: address(0),
                dailyVolumeLimit: 200000e6,
                weeklyVolumeLimit: 0,
                maxDailyDrawdown: 2000,
                maxWeeklyDrawdown: 0,
                maxTradeVsTVLBps: 0,
                minWinRateBps: 0,
                minSharpeRatio: 0,
                maxPositionConcentrationBps: 0,
                maxCorrelationBps: 0,
                maxTradesPerDay: 1000,
                maxTradesPerHour: 0,
                tradingStartHour: 0,
                tradingEndHour: 0,
                minReputationScore: 25,
                useReputationMultiplier: true,
                requiresChainlinkFunctions: true
            })
        });
    }

    // ============ Access Control ============

    function setAuthorizedRouter(address router, bool authorized) external onlyOwner {
        authorizedRouters[router] = authorized;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }
}
