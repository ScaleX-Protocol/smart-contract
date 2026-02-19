// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "./interfaces/IERC8004Identity.sol";
import {PolicyFactoryStorage} from "./storages/PolicyFactoryStorage.sol";

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
 *
 * @dev Upgradeable via Beacon Proxy + Diamond Storage (ERC-7201).
 */
contract PolicyFactory is PolicyFactoryStorage, OwnableUpgradeable {

    // ============ Structs (calldata-only, not stored) ============

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

    // ============ Constructor / Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _identityRegistry) public initializer {
        __Ownable_init(_owner);
        Storage storage $ = getStorage();
        $.identityRegistry = _identityRegistry;
        $.authorizedRouters[_owner] = true;
        _initializeTemplates();
    }

    // ============ Modifiers ============

    modifier onlyAuthorizedRouter() {
        require(getStorage().authorizedRouters[msg.sender], "Not authorized router");
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
        Storage storage $ = getStorage();
        // Verify strategy agent NFT exists (reverts on invalid token)
        IERC8004Identity($.identityRegistry).ownerOf(strategyAgentId);

        require(
            !$.policies[msg.sender][strategyAgentId].enabled &&
                $.policies[msg.sender][strategyAgentId].installedAt == 0,
            "Policy already installed"
        );

        _validatePolicy(policy);
        _storeCalldataPolicy(msg.sender, strategyAgentId, policy, "custom");
    }

    /**
     * @notice Install a policy from a template.
     */
    function installPolicyFromTemplate(
        uint256 strategyAgentId,
        string calldata templateName,
        PolicyCustomization calldata customizations
    ) external {
        Storage storage $ = getStorage();
        IERC8004Identity($.identityRegistry).ownerOf(strategyAgentId);

        require(
            !$.policies[msg.sender][strategyAgentId].enabled,
            "Policy already installed"
        );

        // Use storage reference to avoid copying PolicyTemplate memory (strings + Policy arrays = 4+ Yul loops)
        PolicyTemplate storage tmpl = $.templates[templateName];
        require(tmpl.active, "Template not found or inactive");

        _installFromTemplate(msg.sender, strategyAgentId, tmpl, customizations, templateName);
    }

    /**
     * @notice Remove the policy for a strategy agent (does not revoke AgentRouter auth).
     *         Use AgentRouter.revoke() to remove both authorization and policy at once.
     */
    function uninstallPolicy(uint256 strategyAgentId) external {
        Storage storage $ = getStorage();
        require(
            $.policies[msg.sender][strategyAgentId].enabled ||
                $.policies[msg.sender][strategyAgentId].installedAt > 0,
            "Policy not installed"
        );

        delete $.policies[msg.sender][strategyAgentId];
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
        Storage storage $ = getStorage();
        IERC8004Identity($.identityRegistry).ownerOf(strategyAgentId);

        require(
            !$.policies[user][strategyAgentId].enabled &&
                $.policies[user][strategyAgentId].installedAt == 0,
            "Policy already installed"
        );

        _validatePolicy(policy);
        _storeCalldataPolicy(user, strategyAgentId, policy, "custom");
    }

    /**
     * @notice Uninstall policy for `user` — called by AgentRouter.revoke().
     */
    function uninstallPolicyFor(
        address user,
        uint256 strategyAgentId
    ) external onlyAuthorizedRouter {
        Storage storage $ = getStorage();
        if ($.policies[user][strategyAgentId].installedAt == 0) return; // already gone

        delete $.policies[user][strategyAgentId];
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
        policy.requiresChainlinkFunctions = (
            policy.dailyVolumeLimit > 0 || policy.weeklyVolumeLimit > 0 ||
            policy.maxDailyDrawdown > 0 || policy.maxWeeklyDrawdown > 0 ||
            policy.maxTradeVsTVLBps > 0 || policy.minWinRateBps > 0 ||
            policy.minSharpeRatio > 0 || policy.maxPositionConcentrationBps > 0 ||
            policy.maxTradesPerDay > 0 || policy.maxTradesPerHour > 0 ||
            policy.tradingStartHour > 0
        );
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
        policy.requiresChainlinkFunctions = (
            policy.dailyVolumeLimit > 0 || policy.weeklyVolumeLimit > 0 ||
            policy.maxDailyDrawdown > 0 || policy.maxWeeklyDrawdown > 0 ||
            policy.maxTradeVsTVLBps > 0 || policy.minWinRateBps > 0 ||
            policy.minSharpeRatio > 0 || policy.maxPositionConcentrationBps > 0 ||
            policy.maxTradesPerDay > 0 || policy.maxTradesPerHour > 0 ||
            policy.tradingStartHour > 0
        );
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
        Policy storage policy = getStorage().policies[user][strategyAgentId];
        require(policy.enabled, "Already disabled");
        policy.enabled = false;
        emit PolicyDisabled(user, strategyAgentId, reason, block.timestamp);
    }

    // ============ Policy Queries ============

    function getPolicy(
        address user,
        uint256 strategyAgentId
    ) external view returns (Policy memory) {
        return getStorage().policies[user][strategyAgentId];
    }

    function isAgentEnabled(
        address user,
        uint256 strategyAgentId
    ) external view returns (bool) {
        Policy storage policy = getStorage().policies[user][strategyAgentId];
        return policy.enabled && block.timestamp < policy.expiryTimestamp;
    }

    function getInstalledAgents(address user) external view returns (uint256[] memory) {
        return getStorage().installedAgents[user];
    }

    function isTokenAllowed(
        address user,
        uint256 strategyAgentId,
        address token
    ) external view returns (bool) {
        // Use storage ref to avoid copying large struct to memory (prevents Yul stack-too-deep)
        Policy storage policy = getStorage().policies[user][strategyAgentId];

        for (uint256 i = 0; i < policy.blacklistedTokens.length; i++) {
            if (policy.blacklistedTokens[i] == token) return false;
        }

        if (policy.whitelistedTokens.length == 0) return true;

        for (uint256 j = 0; j < policy.whitelistedTokens.length; j++) {
            if (policy.whitelistedTokens[j] == token) return true;
        }

        return false;
    }

    // ============ Public getters (replaces public state variable getters) ============

    function policies(address user, uint256 strategyAgentId) external view returns (Policy memory) {
        return getStorage().policies[user][strategyAgentId];
    }

    function installedAgents(address user, uint256 index) external view returns (uint256) {
        return getStorage().installedAgents[user][index];
    }

    function templates(string calldata name) external view returns (PolicyTemplate memory) {
        return getStorage().templates[name];
    }

    function authorizedRouters(address router) external view returns (bool) {
        return getStorage().authorizedRouters[router];
    }

    function identityRegistry() external view returns (address) {
        return getStorage().identityRegistry;
    }

    // ============ Internal ============

    function _getPolicy(address user, uint256 strategyAgentId) internal view returns (Policy storage) {
        Policy storage policy = getStorage().policies[user][strategyAgentId];
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

    function _removeFromInstalledList(address user, uint256 strategyAgentId) internal {
        uint256[] storage agents = getStorage().installedAgents[user];
        for (uint256 i = 0; i < agents.length; i++) {
            if (agents[i] == strategyAgentId) {
                agents[i] = agents[agents.length - 1];
                agents.pop();
                break;
            }
        }
    }

    /// @dev Extracted to separate function to avoid Yul stack-too-deep during calldata Policy storage write.
    ///      Copying a struct with two dynamic arrays (whitelistedTokens, blacklistedTokens) from
    ///      calldata to storage generates two Yul loops; the calling function's live variables push
    ///      the second loop counter below the 16-slot accessible window.
    function _storeCalldataPolicy(
        address user,
        uint256 agentId,
        Policy calldata policy,
        string memory templateName
    ) internal {
        Storage storage $ = getStorage();
        $.policies[user][agentId] = policy;
        Policy storage s = $.policies[user][agentId];
        s.installedAt = block.timestamp;
        s.enabled = true;
        s.requiresChainlinkFunctions = (
            s.dailyVolumeLimit > 0 || s.weeklyVolumeLimit > 0 ||
            s.maxDailyDrawdown > 0 || s.maxWeeklyDrawdown > 0 ||
            s.maxTradeVsTVLBps > 0 || s.minWinRateBps > 0 ||
            s.minSharpeRatio > 0 || s.maxPositionConcentrationBps > 0 ||
            s.maxTradesPerDay > 0 || s.maxTradesPerHour > 0 ||
            s.tradingStartHour > 0
        );
        $.installedAgents[user].push(agentId);
        emit PolicyInstalled(user, agentId, templateName, block.timestamp);
    }

    /// @dev Handles the memory copy and customization of a template policy in an isolated stack frame.
    ///      Called by installPolicyFromTemplate after the storage ref to the template is obtained.
    ///      Isolates Policy memory copy (2 Yul loops) from the template storage-ref setup.
    function _installFromTemplate(
        address user,
        uint256 agentId,
        PolicyTemplate storage tmpl,
        PolicyCustomization calldata customizations,
        string calldata templateName
    ) private {
        Policy memory policy = tmpl.basePolicy;
        if (customizations.maxOrderSize > 0)     policy.maxOrderSize = customizations.maxOrderSize;
        if (customizations.dailyVolumeLimit > 0) policy.dailyVolumeLimit = customizations.dailyVolumeLimit;
        if (customizations.expiryTimestamp > 0)  policy.expiryTimestamp = customizations.expiryTimestamp;
        if (customizations.whitelistedTokens.length > 0) policy.whitelistedTokens = customizations.whitelistedTokens;
        _validatePolicy(policy);
        _storeMemoryPolicy(user, agentId, policy, templateName);
    }

    /// @dev Same as _storeCalldataPolicy but for a memory Policy (used by installPolicyFromTemplate).
    function _storeMemoryPolicy(
        address user,
        uint256 agentId,
        Policy memory policy,
        string calldata templateName
    ) internal {
        policy.installedAt = block.timestamp;
        policy.enabled = true;
        Storage storage $ = getStorage();
        $.policies[user][agentId] = policy;
        // Read requiresChainlink from storage after write (avoids holding memory Policy
        // live simultaneously with the storage slot computation vars)
        Policy storage s = $.policies[user][agentId];
        s.requiresChainlinkFunctions = (
            s.dailyVolumeLimit > 0 || s.weeklyVolumeLimit > 0 ||
            s.maxDailyDrawdown > 0 || s.maxWeeklyDrawdown > 0 ||
            s.maxTradeVsTVLBps > 0 || s.minWinRateBps > 0 ||
            s.minSharpeRatio > 0 || s.maxPositionConcentrationBps > 0 ||
            s.maxTradesPerDay > 0 || s.maxTradesPerHour > 0 ||
            s.tradingStartHour > 0
        );
        $.installedAgents[user].push(agentId);
        emit PolicyInstalled(user, agentId, templateName, block.timestamp);
    }

    // ============ Templates ============

    // Each template initializer is a separate function to avoid Yul stack-too-deep
    // from large struct literal construction.
    function _initializeTemplates() internal {
        _initConservativeTemplate();
        _initModerateTemplate();
        _initAggressiveTemplate();
    }

    function _initConservativeTemplate() private {
        PolicyTemplate storage t = getStorage().templates["conservative"];
        t.name = "Conservative";
        t.description = "Low risk, strict limits";
        t.active = true;
        Policy storage p = t.basePolicy;
        p.enabled = true;
        p.expiryTimestamp = type(uint256).max;
        p.maxOrderSize = 1000e6;
        p.minOrderSize = 100e6;
        p.allowMarketOrders = true;
        p.allowLimitOrders = true;
        p.allowSwap = true;
        p.allowRepay = true;
        p.allowSupplyCollateral = true;
        p.allowWithdrawCollateral = true;
        p.allowPlaceLimitOrder = true;
        p.allowCancelOrder = true;
        p.allowBuy = true;
        p.allowSell = true;
        p.minHealthFactor = 2e18;
        p.maxSlippageBps = 50;
        p.minTimeBetweenTrades = 300;
        p.dailyVolumeLimit = 5000e6;
        p.maxDailyDrawdown = 500;
        p.maxTradesPerDay = 20;
        p.minReputationScore = 75;
        p.requiresChainlinkFunctions = true;
    }

    function _initModerateTemplate() private {
        PolicyTemplate storage t = getStorage().templates["moderate"];
        t.name = "Moderate";
        t.description = "Balanced risk and limits";
        t.active = true;
        Policy storage p = t.basePolicy;
        p.enabled = true;
        p.expiryTimestamp = type(uint256).max;
        p.maxOrderSize = 5000e6;
        p.minOrderSize = 100e6;
        p.allowMarketOrders = true;
        p.allowLimitOrders = true;
        p.allowSwap = true;
        p.allowBorrow = true;
        p.allowRepay = true;
        p.allowSupplyCollateral = true;
        p.allowWithdrawCollateral = true;
        p.allowPlaceLimitOrder = true;
        p.allowCancelOrder = true;
        p.allowBuy = true;
        p.allowSell = true;
        p.allowAutoBorrow = true;
        p.maxAutoBorrowAmount = 2000e6;
        p.allowAutoRepay = true;
        p.minDebtToRepay = 100e6;
        p.minHealthFactor = 15e17;
        p.maxSlippageBps = 100;
        p.minTimeBetweenTrades = 60;
        p.dailyVolumeLimit = 20000e6;
        p.maxDailyDrawdown = 1000;
        p.maxTradesPerDay = 100;
        p.minReputationScore = 50;
        p.useReputationMultiplier = true;
        p.requiresChainlinkFunctions = true;
    }

    function _initAggressiveTemplate() private {
        PolicyTemplate storage t = getStorage().templates["aggressive"];
        t.name = "Aggressive";
        t.description = "High risk, loose limits";
        t.active = true;
        Policy storage p = t.basePolicy;
        p.enabled = true;
        p.expiryTimestamp = type(uint256).max;
        p.maxOrderSize = 50000e6;
        p.minOrderSize = 100e6;
        p.allowMarketOrders = true;
        p.allowLimitOrders = true;
        p.allowSwap = true;
        p.allowBorrow = true;
        p.allowRepay = true;
        p.allowSupplyCollateral = true;
        p.allowWithdrawCollateral = true;
        p.allowPlaceLimitOrder = true;
        p.allowCancelOrder = true;
        p.allowBuy = true;
        p.allowSell = true;
        p.allowAutoBorrow = true;
        p.maxAutoBorrowAmount = 20000e6;
        p.allowAutoRepay = true;
        p.minDebtToRepay = 100e6;
        p.minHealthFactor = 12e17;
        p.maxSlippageBps = 300;
        p.dailyVolumeLimit = 200000e6;
        p.maxDailyDrawdown = 2000;
        p.maxTradesPerDay = 1000;
        p.minReputationScore = 25;
        p.useReputationMultiplier = true;
        p.requiresChainlinkFunctions = true;
    }

    // ============ Access Control ============

    function setAuthorizedRouter(address router, bool authorized) external onlyOwner {
        getStorage().authorizedRouters[router] = authorized;
    }
}
