// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC8004Identity.sol";

/**
 * @title PolicyFactory
 * @notice Central policy management for AI agent trading permissions
 * @dev Stores and manages policies that define what actions agents can perform
 *      Single source of truth for all agent authorization rules
 */
contract PolicyFactory {
    // ============ State Variables ============

    IERC8004Identity public immutable identityRegistry;

    // owner => agentTokenId => Policy
    mapping(address => mapping(uint256 => Policy)) public policies;

    // owner => list of installed agent token IDs
    mapping(address => uint256[]) public installedAgents;

    // Policy templates
    mapping(string => PolicyTemplate) public templates;

    // Authorized routers (can call emergencyDisable)
    mapping(address => bool) public authorizedRouters;

    // Owner
    address public owner;

    // ============ Structs ============

    struct Policy {
        // ============ Metadata ============
        bool enabled;
        uint256 installedAt;
        uint256 expiryTimestamp;
        uint256 agentTokenId;

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
        uint256 maxTradeVsTVLBps;      // Max trade as % of TVL

        // Performance Requirements
        uint256 minWinRateBps;         // Minimum win rate
        int256 minSharpeRatio;         // Minimum Sharpe ratio (scaled by 1e18)

        // Position Management
        uint256 maxPositionConcentrationBps;  // Max % in one asset
        uint256 maxCorrelationBps;     // Max correlation to market

        // Trade Frequency
        uint256 maxTradesPerDay;
        uint256 maxTradesPerHour;

        // Trading Hours
        uint256 tradingStartHour;      // UTC hour (0-23)
        uint256 tradingEndHour;        // UTC hour (0-23)

        // Reputation
        uint256 minReputationScore;    // Minimum ERC-8004 reputation (0-100)
        bool useReputationMultiplier;  // Scale limits based on reputation

        // ============ Optimization Flag ============
        bool requiresChainlinkFunctions;  // True if any complex permissions enabled
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

    event AgentInstalled(
        address indexed owner,
        uint256 indexed agentTokenId,
        string templateUsed,
        uint256 timestamp
    );

    event AgentUninstalled(
        address indexed owner,
        uint256 indexed agentTokenId,
        uint256 timestamp
    );

    event PolicyUpdated(
        address indexed owner,
        uint256 indexed agentTokenId,
        string field,
        uint256 timestamp
    );

    event PolicyEnabled(
        address indexed owner,
        uint256 indexed agentTokenId,
        uint256 timestamp
    );

    event PolicyDisabled(
        address indexed owner,
        uint256 indexed agentTokenId,
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

    // ============ Install/Uninstall ============

    /**
     * @notice Install an agent with a custom policy
     * @param agentTokenId The ERC-8004 agent token ID
     * @param policy The policy configuration
     */
    function installAgent(
        uint256 agentTokenId,
        Policy calldata policy
    ) external {
        // Verify caller owns the agent
        require(
            identityRegistry.ownerOf(agentTokenId) == msg.sender,
            "Not agent owner"
        );

        // Verify agent not already installed
        require(
            !policies[msg.sender][agentTokenId].enabled &&
                policies[msg.sender][agentTokenId].installedAt == 0,
            "Agent already installed"
        );

        // Validate policy
        _validatePolicy(policy);

        // Store policy
        policies[msg.sender][agentTokenId] = policy;
        policies[msg.sender][agentTokenId].installedAt = block.timestamp;
        policies[msg.sender][agentTokenId].enabled = true;
        policies[msg.sender][agentTokenId].agentTokenId = agentTokenId;

        // Auto-detect if requires Chainlink
        policies[msg.sender][agentTokenId].requiresChainlinkFunctions = _requiresChainlink(
            policy
        );

        // Add to installed agents list
        installedAgents[msg.sender].push(agentTokenId);

        emit AgentInstalled(msg.sender, agentTokenId, "custom", block.timestamp);
    }

    /**
     * @notice Install an agent using a template
     * @param agentTokenId The ERC-8004 agent token ID
     * @param templateName Name of the template to use
     * @param customizations Optional customizations to the template
     */
    function installAgentFromTemplate(
        uint256 agentTokenId,
        string calldata templateName,
        PolicyCustomization calldata customizations
    ) external {
        require(
            identityRegistry.ownerOf(agentTokenId) == msg.sender,
            "Not agent owner"
        );

        require(
            !policies[msg.sender][agentTokenId].enabled,
            "Agent already installed"
        );

        PolicyTemplate memory template = templates[templateName];
        require(template.active, "Template not found or inactive");

        // Start with template policy
        Policy memory policy = template.basePolicy;
        policy.agentTokenId = agentTokenId;

        // Apply customizations
        if (customizations.maxOrderSize > 0) {
            policy.maxOrderSize = customizations.maxOrderSize;
        }
        if (customizations.dailyVolumeLimit > 0) {
            policy.dailyVolumeLimit = customizations.dailyVolumeLimit;
        }
        if (customizations.expiryTimestamp > 0) {
            policy.expiryTimestamp = customizations.expiryTimestamp;
        }
        if (customizations.whitelistedTokens.length > 0) {
            policy.whitelistedTokens = customizations.whitelistedTokens;
        }

        // Validate and store
        _validatePolicy(policy);
        policies[msg.sender][agentTokenId] = policy;
        policies[msg.sender][agentTokenId].installedAt = block.timestamp;
        policies[msg.sender][agentTokenId].enabled = true;
        policies[msg.sender][agentTokenId].requiresChainlinkFunctions = _requiresChainlink(
            policy
        );

        installedAgents[msg.sender].push(agentTokenId);

        emit AgentInstalled(msg.sender, agentTokenId, templateName, block.timestamp);
    }

    /**
     * @notice Uninstall an agent (removes all permissions)
     * @param agentTokenId The agent to uninstall
     */
    function uninstallAgent(uint256 agentTokenId) external {
        require(
            policies[msg.sender][agentTokenId].enabled ||
                policies[msg.sender][agentTokenId].installedAt > 0,
            "Agent not installed"
        );

        delete policies[msg.sender][agentTokenId];

        // Remove from installed agents list
        _removeFromInstalledList(msg.sender, agentTokenId);

        emit AgentUninstalled(msg.sender, agentTokenId, block.timestamp);
    }

    // ============ Policy Management ============

    /**
     * @notice Update trading limits
     */
    function updateTradingLimits(
        uint256 agentTokenId,
        uint256 maxOrderSize,
        uint256 minOrderSize,
        uint256 dailyVolumeLimit
    ) external {
        Policy storage policy = _getPolicy(msg.sender, agentTokenId);

        policy.maxOrderSize = maxOrderSize;
        policy.minOrderSize = minOrderSize;
        policy.dailyVolumeLimit = dailyVolumeLimit;

        policy.requiresChainlinkFunctions = _requiresChainlink(policy);

        emit PolicyUpdated(msg.sender, agentTokenId, "tradingLimits", block.timestamp);
    }

    /**
     * @notice Update borrowing limits
     */
    function updateBorrowingLimits(
        uint256 agentTokenId,
        uint256 maxAutoBorrowAmount,
        bool allowBorrowing
    ) external {
        Policy storage policy = _getPolicy(msg.sender, agentTokenId);

        policy.maxAutoBorrowAmount = maxAutoBorrowAmount;
        policy.allowBorrow = allowBorrowing;

        emit PolicyUpdated(msg.sender, agentTokenId, "borrowingLimits", block.timestamp);
    }

    /**
     * @notice Update safety controls
     */
    function updateSafetyControls(
        uint256 agentTokenId,
        uint256 minHealthFactor,
        uint256 maxDailyDrawdown
    ) external {
        Policy storage policy = _getPolicy(msg.sender, agentTokenId);

        require(minHealthFactor >= 1e18, "Health factor must be >= 100%");
        require(maxDailyDrawdown <= 10000, "Drawdown must be <= 100%");

        policy.minHealthFactor = minHealthFactor;
        policy.maxDailyDrawdown = maxDailyDrawdown;

        policy.requiresChainlinkFunctions = _requiresChainlink(policy);

        emit PolicyUpdated(msg.sender, agentTokenId, "safetyControls", block.timestamp);
    }

    /**
     * @notice Update token whitelist/blacklist
     */
    function updateTokenLists(
        uint256 agentTokenId,
        address[] calldata whitelistedTokens,
        address[] calldata blacklistedTokens
    ) external {
        Policy storage policy = _getPolicy(msg.sender, agentTokenId);

        policy.whitelistedTokens = whitelistedTokens;
        policy.blacklistedTokens = blacklistedTokens;

        emit PolicyUpdated(msg.sender, agentTokenId, "tokenLists", block.timestamp);
    }

    /**
     * @notice Enable or disable an agent
     */
    function setAgentEnabled(uint256 agentTokenId, bool enabled) external {
        Policy storage policy = _getPolicy(msg.sender, agentTokenId);

        policy.enabled = enabled;

        if (enabled) {
            emit PolicyEnabled(msg.sender, agentTokenId, block.timestamp);
        } else {
            emit PolicyDisabled(msg.sender, agentTokenId, "manual", block.timestamp);
        }
    }

    /**
     * @notice Emergency disable (callable by AgentRouter when circuit breaker triggers)
     */
    function emergencyDisable(
        address owner,
        uint256 agentTokenId,
        string calldata reason
    ) external onlyAuthorizedRouter {
        Policy storage policy = policies[owner][agentTokenId];
        require(policy.enabled, "Already disabled");

        policy.enabled = false;

        emit PolicyDisabled(owner, agentTokenId, reason, block.timestamp);
    }

    // ============ Policy Queries ============

    /**
     * @notice Get policy for an agent
     */
    function getPolicy(
        address _owner,
        uint256 agentTokenId
    ) external view returns (Policy memory) {
        return policies[_owner][agentTokenId];
    }

    /**
     * @notice Check if an agent is installed and enabled
     */
    function isAgentEnabled(
        address _owner,
        uint256 agentTokenId
    ) external view returns (bool) {
        Policy memory policy = policies[_owner][agentTokenId];
        return policy.enabled && block.timestamp < policy.expiryTimestamp;
    }

    /**
     * @notice Get all installed agents for an owner
     */
    function getInstalledAgents(address _owner) external view returns (uint256[] memory) {
        return installedAgents[_owner];
    }

    /**
     * @notice Check if a token is allowed for trading
     */
    function isTokenAllowed(
        address _owner,
        uint256 agentTokenId,
        address token
    ) external view returns (bool) {
        Policy memory policy = policies[_owner][agentTokenId];

        // Check blacklist first
        for (uint256 i = 0; i < policy.blacklistedTokens.length; i++) {
            if (policy.blacklistedTokens[i] == token) {
                return false;
            }
        }

        // If whitelist is empty, all tokens (except blacklisted) are allowed
        if (policy.whitelistedTokens.length == 0) {
            return true;
        }

        // Check whitelist
        for (uint256 i = 0; i < policy.whitelistedTokens.length; i++) {
            if (policy.whitelistedTokens[i] == token) {
                return true;
            }
        }

        return false;
    }

    // ============ Internal Functions ============

    function _getPolicy(
        address _owner,
        uint256 agentTokenId
    ) internal view returns (Policy storage) {
        Policy storage policy = policies[_owner][agentTokenId];
        require(policy.installedAt > 0, "Agent not installed");
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

    function _removeFromInstalledList(address _owner, uint256 agentTokenId) internal {
        uint256[] storage agents = installedAgents[_owner];
        for (uint256 i = 0; i < agents.length; i++) {
            if (agents[i] == agentTokenId) {
                agents[i] = agents[agents.length - 1];
                agents.pop();
                break;
            }
        }
    }

    // ============ Templates ============

    function _initializeTemplates() internal {
        // Conservative Template
        templates["conservative"] = PolicyTemplate({
            name: "Conservative",
            description: "Low risk, strict limits",
            active: true,
            basePolicy: Policy({
                enabled: true,
                installedAt: 0,
                expiryTimestamp: type(uint256).max,
                agentTokenId: 0,
                maxOrderSize: 1000e6,        // $1,000 max per order
                minOrderSize: 100e6,         // $100 min per order
                whitelistedTokens: new address[](0),
                blacklistedTokens: new address[](0),
                allowMarketOrders: true,
                allowLimitOrders: true,
                allowSwap: true,
                allowBorrow: false,          // No borrowing
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
                minHealthFactor: 2e18,       // 200% minimum
                maxSlippageBps: 50,          // 0.5% max slippage
                minTimeBetweenTrades: 300,   // 5 min cooldown
                emergencyRecipient: address(0),
                dailyVolumeLimit: 5000e6,    // $5,000 per day
                weeklyVolumeLimit: 0,
                maxDailyDrawdown: 500,       // 5% max daily loss
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
                requiresChainlinkFunctions: true  // Uses daily volume & drawdown
            })
        });

        // Moderate Template
        templates["moderate"] = PolicyTemplate({
            name: "Moderate",
            description: "Balanced risk and limits",
            active: true,
            basePolicy: Policy({
                enabled: true,
                installedAt: 0,
                expiryTimestamp: type(uint256).max,
                agentTokenId: 0,
                maxOrderSize: 5000e6,        // $5,000 max per order
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
                minHealthFactor: 15e17,      // 150% minimum
                maxSlippageBps: 100,         // 1% max slippage
                minTimeBetweenTrades: 60,    // 1 min cooldown
                emergencyRecipient: address(0),
                dailyVolumeLimit: 20000e6,   // $20,000 per day
                weeklyVolumeLimit: 0,
                maxDailyDrawdown: 1000,      // 10% max daily loss
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

        // Aggressive Template
        templates["aggressive"] = PolicyTemplate({
            name: "Aggressive",
            description: "High risk, loose limits",
            active: true,
            basePolicy: Policy({
                enabled: true,
                installedAt: 0,
                expiryTimestamp: type(uint256).max,
                agentTokenId: 0,
                maxOrderSize: 50000e6,       // $50,000 max per order
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
                minHealthFactor: 12e17,      // 120% minimum
                maxSlippageBps: 300,         // 3% max slippage
                minTimeBetweenTrades: 0,     // No cooldown
                emergencyRecipient: address(0),
                dailyVolumeLimit: 200000e6,  // $200,000 per day
                weeklyVolumeLimit: 0,
                maxDailyDrawdown: 2000,      // 20% max daily loss
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
