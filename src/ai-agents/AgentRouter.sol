// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IERC8004Identity.sol";
import "./interfaces/IERC8004Reputation.sol";
import "./interfaces/IERC8004Validation.sol";
import "./PolicyFactory.sol";
import {PolicyFactoryStorage} from "./storages/PolicyFactoryStorage.sol";
import "./ChainlinkMetricsConsumer.sol";
import {AgentRouterStorage} from "./storages/AgentRouterStorage.sol";
import "../core/interfaces/IOrderBook.sol";
import "../core/interfaces/IBalanceManager.sol";
import "../core/interfaces/ILendingManager.sol";
import "../core/interfaces/IPoolManager.sol";
import {Currency} from "../core/libraries/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AgentRouter
 * @notice Execution layer for AI agent trading with policy-based authorization.
 *
 * Flow:
 *   1. Strategy agent calls IdentityRegistry.register() → gets strategyAgentId NFT.
 *   2. User calls AgentRouter.authorize(strategyAgentId, policy) → grants permission +
 *      installs policy (what the agent can do with user's funds) in one transaction.
 *   3. Strategy agent calls execute*() functions, passing userAddress + strategyAgentId.
 *      AgentRouter verifies: msg.sender == ownerOf(strategyAgentId)
 *                            authorizedStrategyAgents[user][strategyAgentId] == true
 *                            policy limits are respected
 *
 * @dev Upgradeable via Beacon Proxy + Diamond Storage (ERC-7201).
 */
contract AgentRouter is AgentRouterStorage, OwnableUpgradeable, ReentrancyGuardUpgradeable {

    // ============ Events ============

    event AgentSwapExecuted(
        address indexed user,
        uint256 indexed strategyAgentId,
        address indexed executor,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );

    event AgentLimitOrderPlaced(
        address indexed user,
        uint256 indexed strategyAgentId,
        address indexed executor,
        bytes32 orderId,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 limitPrice,
        bool isBuy,
        uint256 timestamp
    );

    event AgentOrderCancelled(
        address indexed user,
        uint256 indexed strategyAgentId,
        address indexed executor,
        bytes32 orderId,
        uint256 timestamp
    );

    event AgentBorrowExecuted(
        address indexed user,
        uint256 indexed strategyAgentId,
        address indexed executor,
        address token,
        uint256 amount,
        uint256 newHealthFactor,
        uint256 timestamp
    );

    event AgentRepayExecuted(
        address indexed user,
        uint256 indexed strategyAgentId,
        address indexed executor,
        address token,
        uint256 amount,
        uint256 newHealthFactor,
        uint256 timestamp
    );

    event AgentCollateralSupplied(
        address indexed user,
        uint256 indexed strategyAgentId,
        address indexed executor,
        address token,
        uint256 amount,
        uint256 timestamp
    );

    event AgentCollateralWithdrawn(
        address indexed user,
        uint256 indexed strategyAgentId,
        address indexed executor,
        address token,
        uint256 amount,
        uint256 timestamp
    );

    event CircuitBreakerTriggered(
        address indexed user,
        uint256 indexed strategyAgentId,
        uint256 drawdownBps,
        uint256 currentValue,
        uint256 dayStartValue,
        uint256 timestamp
    );

    event PolicyViolation(
        address indexed user,
        uint256 indexed strategyAgentId,
        string reason,
        uint256 timestamp
    );

    event StrategyAgentAuthorized(
        address indexed user,
        uint256 indexed strategyAgentId,
        uint256 timestamp
    );

    event StrategyAgentRevoked(
        address indexed user,
        uint256 indexed strategyAgentId,
        uint256 timestamp
    );

    // ============ Constructor / Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _identityRegistry,
        address _reputationRegistry,
        address _validationRegistry,
        address _policyFactory,
        address _poolManager,
        address _balanceManager,
        address _lendingManager
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        Storage storage $ = getStorage();
        $.identityRegistry = _identityRegistry;
        $.reputationRegistry = _reputationRegistry;
        $.validationRegistry = _validationRegistry;
        $.policyFactory = _policyFactory;
        $.poolManager = _poolManager;
        $.balanceManager = _balanceManager;
        $.lendingManager = _lendingManager;
    }

    // ============ Public getters (replaces public immutable getters) ============

    function identityRegistry() external view returns (address) {
        return getStorage().identityRegistry;
    }

    function reputationRegistry() external view returns (address) {
        return getStorage().reputationRegistry;
    }

    function validationRegistry() external view returns (address) {
        return getStorage().validationRegistry;
    }

    function policyFactory() external view returns (address) {
        return getStorage().policyFactory;
    }

    function metricsConsumer() external view returns (address) {
        return getStorage().metricsConsumer;
    }

    function poolManager() external view returns (address) {
        return getStorage().poolManager;
    }

    function balanceManager() external view returns (address) {
        return getStorage().balanceManager;
    }

    function lendingManager() external view returns (address) {
        return getStorage().lendingManager;
    }

    function dayStartValues(address user, uint256 day) external view returns (uint256) {
        return getStorage().dayStartValues[user][day];
    }

    function lastTradeTime(uint256 strategyAgentId) external view returns (uint256) {
        return getStorage().lastTradeTime[strategyAgentId];
    }

    function dailyVolumes(uint256 strategyAgentId, uint256 day) external view returns (uint256) {
        return getStorage().dailyVolumes[strategyAgentId][day];
    }

    function authorizedStrategyAgents(address user, uint256 strategyAgentId) external view returns (bool) {
        return getStorage().authorizedStrategyAgents[user][strategyAgentId];
    }

    // ============ Admin ============

    function setMetricsConsumer(address _metricsConsumer) external onlyOwner {
        getStorage().metricsConsumer = _metricsConsumer;
    }

    // ============ Authorization ============

    /**
     * @notice Grant a strategy agent permission to trade on behalf of msg.sender,
     *         and define the policy limits in a single transaction.
     * @param strategyAgentId NFT ID of the strategy agent to authorize.
     * @param policy          Trading limits the strategy agent must respect.
     */
    function authorize(
        uint256 strategyAgentId,
        PolicyFactoryStorage.Policy calldata policy
    ) external {
        Storage storage $ = getStorage();
        PolicyFactory($.policyFactory).installPolicyFor(msg.sender, strategyAgentId, policy);
        $.authorizedStrategyAgents[msg.sender][strategyAgentId] = true;
        emit StrategyAgentAuthorized(msg.sender, strategyAgentId, block.timestamp);
    }

    /**
     * @notice Revoke a strategy agent's authorization and remove its policy.
     */
    function revoke(uint256 strategyAgentId) external {
        Storage storage $ = getStorage();
        $.authorizedStrategyAgents[msg.sender][strategyAgentId] = false;
        PolicyFactory($.policyFactory).uninstallPolicyFor(msg.sender, strategyAgentId);
        emit StrategyAgentRevoked(msg.sender, strategyAgentId, block.timestamp);
    }

    /**
     * @notice Check if a strategy agent is authorized by a user.
     */
    function isAuthorized(address user, uint256 strategyAgentId) external view returns (bool) {
        return getStorage().authorizedStrategyAgents[user][strategyAgentId];
    }

    // ============ Internal Auth Helper ============

    function _verifyAndGetPolicy(
        address user,
        uint256 strategyAgentId
    ) internal view returns (PolicyFactoryStorage.Policy memory policy) {
        Storage storage $ = getStorage();
        require(
            msg.sender == IERC8004Identity($.identityRegistry).ownerOf(strategyAgentId),
            "Not strategy agent owner"
        );
        require(
            $.authorizedStrategyAgents[user][strategyAgentId],
            "Strategy agent not authorized"
        );

        policy = PolicyFactory($.policyFactory).getPolicy(user, strategyAgentId);
        require(policy.enabled, "Agent disabled");
        require(block.timestamp < policy.expiryTimestamp, "Agent expired");
    }

    // ============ Trading Functions ============

    /**
     * @notice Execute a market order on behalf of `user`.
     * @param user            Address of the user whose funds are used.
     * @param strategyAgentId NFT ID of the strategy agent executing this order.
     */
    function executeMarketOrder(
        address user,
        uint256 strategyAgentId,
        IPoolManager.Pool calldata pool,
        IOrderBook.Side side,
        uint128 quantity,
        uint128 minOutAmount,
        bool autoRepay,
        bool autoBorrow
    ) external returns (uint48 orderId, uint128 filled) {
        PolicyFactoryStorage.Policy memory policy = _verifyAndGetPolicy(user, strategyAgentId);

        require(!policy.requiresChainlinkFunctions, "Use executeMarketOrderWithMetrics");

        _enforceMarketOrderPermissions(policy, user, strategyAgentId, pool, side, quantity, autoRepay, autoBorrow);

        IOrderBook orderBook = pool.orderBook;
        (orderId, filled) = orderBook.placeMarketOrder(
            quantity, side, user, autoRepay, autoBorrow, strategyAgentId, msg.sender
        );

        _updateTracking(strategyAgentId, quantity);
        _checkCircuitBreaker(user, strategyAgentId, policy);
        _recordTradeToReputation(strategyAgentId, Currency.unwrap(pool.baseCurrency), Currency.unwrap(pool.quoteCurrency), quantity, filled);

        emit AgentSwapExecuted(
            user, strategyAgentId, msg.sender,
            Currency.unwrap(pool.baseCurrency), Currency.unwrap(pool.quoteCurrency),
            quantity, filled, block.timestamp
        );
    }

    /**
     * @notice Place a limit order on behalf of `user`.
     * @param user            Address of the user whose funds are used.
     * @param strategyAgentId NFT ID of the strategy agent executing this order.
     */
    function executeLimitOrder(
        address user,
        uint256 strategyAgentId,
        IPoolManager.Pool calldata pool,
        uint128 price,
        uint128 quantity,
        IOrderBook.Side side,
        IOrderBook.TimeInForce timeInForce,
        bool autoRepay,
        bool autoBorrow
    ) external returns (uint48 orderId) {
        PolicyFactoryStorage.Policy memory policy = _verifyAndGetPolicy(user, strategyAgentId);

        require(policy.allowLimitOrders, "Limit orders not allowed");
        require(policy.allowPlaceLimitOrder, "Placing limit orders not allowed");
        require(!policy.requiresChainlinkFunctions, "Use executeLimitOrderWithMetrics");

        _enforceLimitOrderPermissions(policy, user, strategyAgentId, pool, side, quantity, autoRepay, autoBorrow);

        IOrderBook orderBook = pool.orderBook;
        orderId = orderBook.placeOrder(
            price, quantity, side, user, timeInForce, autoRepay, autoBorrow, strategyAgentId, msg.sender
        );

        _updateTracking(strategyAgentId, quantity);

        emit AgentLimitOrderPlaced(
            user, strategyAgentId, msg.sender,
            bytes32(uint256(orderId)),
            Currency.unwrap(pool.baseCurrency), Currency.unwrap(pool.quoteCurrency),
            quantity, price,
            side == IOrderBook.Side.BUY,
            block.timestamp
        );
    }

    /**
     * @notice Cancel a limit order on behalf of `user`.
     */
    function cancelOrder(
        address user,
        uint256 strategyAgentId,
        IPoolManager.Pool calldata pool,
        uint48 orderId
    ) external {
        PolicyFactoryStorage.Policy memory policy = _verifyAndGetPolicy(user, strategyAgentId);
        require(policy.allowCancelOrder, "Cancelling orders not allowed");

        pool.orderBook.cancelOrder(orderId, user, strategyAgentId, msg.sender);

        emit AgentOrderCancelled(
            user, strategyAgentId, msg.sender,
            bytes32(uint256(orderId)),
            block.timestamp
        );
    }

    // ============ Lending Functions ============

    /**
     * @notice Borrow tokens on behalf of `user`.
     */
    function executeBorrow(
        address user,
        uint256 strategyAgentId,
        address token,
        uint256 amount
    ) external {
        Storage storage $ = getStorage();
        PolicyFactoryStorage.Policy memory policy = _verifyAndGetPolicy(user, strategyAgentId);

        require(policy.allowBorrow, "Borrowing not allowed");
        require(amount <= policy.maxAutoBorrowAmount, "Borrow amount exceeds limit");
        require(PolicyFactory($.policyFactory).isTokenAllowed(user, strategyAgentId, token), "Token not allowed");

        uint256 currentHF = ILendingManager($.lendingManager).getHealthFactor(user);
        require(currentHF >= policy.minHealthFactor, "Health factor too low");

        IBalanceManager($.balanceManager).borrowForUser(user, token, amount);

        uint256 newHF = ILendingManager($.lendingManager).getHealthFactor(user);
        require(newHF >= policy.minHealthFactor, "Borrow would harm health factor");

        _recordBorrowToReputation(strategyAgentId, token, amount);

        emit AgentBorrowExecuted(user, strategyAgentId, msg.sender, token, amount, newHF, block.timestamp);
    }

    /**
     * @notice Repay borrowed tokens on behalf of `user`.
     */
    function executeRepay(
        address user,
        uint256 strategyAgentId,
        address token,
        uint256 amount
    ) external {
        Storage storage $ = getStorage();
        PolicyFactoryStorage.Policy memory policy = _verifyAndGetPolicy(user, strategyAgentId);
        require(policy.allowRepay, "Repaying not allowed");

        IBalanceManager($.balanceManager).repayForUser(user, token, amount);

        uint256 newHF = ILendingManager($.lendingManager).getHealthFactor(user);
        _recordRepayToReputation(strategyAgentId, token, amount);

        emit AgentRepayExecuted(user, strategyAgentId, msg.sender, token, amount, newHF, block.timestamp);
    }

    /**
     * @notice Supply collateral on behalf of `user`.
     */
    function executeSupplyCollateral(
        address user,
        uint256 strategyAgentId,
        address token,
        uint256 amount
    ) external {
        Storage storage $ = getStorage();
        PolicyFactoryStorage.Policy memory policy = _verifyAndGetPolicy(user, strategyAgentId);
        require(policy.allowSupplyCollateral, "Supplying collateral not allowed");
        require(PolicyFactory($.policyFactory).isTokenAllowed(user, strategyAgentId, token), "Token not allowed");

        IERC20(token).transferFrom(user, address(this), amount);
        IERC20(token).approve($.balanceManager, amount);
        IBalanceManager($.balanceManager).depositLocal(token, amount, user);

        emit AgentCollateralSupplied(user, strategyAgentId, msg.sender, token, amount, block.timestamp);
    }

    /**
     * @notice Withdraw collateral on behalf of `user`.
     */
    function executeWithdrawCollateral(
        address user,
        uint256 strategyAgentId,
        address token,
        uint256 amount
    ) external {
        Storage storage $ = getStorage();
        PolicyFactoryStorage.Policy memory policy = _verifyAndGetPolicy(user, strategyAgentId);
        require(policy.allowWithdrawCollateral, "Withdrawing collateral not allowed");

        uint256 currentHF = ILendingManager($.lendingManager).getHealthFactor(user);
        require(currentHF >= policy.minHealthFactor, "Health factor too low");

        IBalanceManager($.balanceManager).withdraw(Currency.wrap(token), amount, user);

        uint256 newHF = ILendingManager($.lendingManager).getHealthFactor(user);
        require(newHF >= policy.minHealthFactor, "Withdrawal would harm health factor");

        emit AgentCollateralWithdrawn(user, strategyAgentId, msg.sender, token, amount, block.timestamp);
    }

    // ============ Permission Enforcement ============

    function _enforceMarketOrderPermissions(
        PolicyFactoryStorage.Policy memory policy,
        address user,
        uint256 strategyAgentId,
        IPoolManager.Pool calldata pool,
        IOrderBook.Side side,
        uint128 quantity,
        bool autoRepay,
        bool autoBorrow
    ) internal view {
        Storage storage $ = getStorage();
        require(quantity <= policy.maxOrderSize, "Order too large");
        if (policy.minOrderSize > 0) require(quantity >= policy.minOrderSize, "Order too small");

        require(PolicyFactory($.policyFactory).isTokenAllowed(user, strategyAgentId, Currency.unwrap(pool.baseCurrency)), "Base token not allowed");
        require(PolicyFactory($.policyFactory).isTokenAllowed(user, strategyAgentId, Currency.unwrap(pool.quoteCurrency)), "Quote token not allowed");

        require(policy.allowSwap, "Swap not allowed");
        require(policy.allowMarketOrders, "Market orders not allowed");

        if (side == IOrderBook.Side.BUY) require(policy.allowBuy, "Buy orders not allowed");
        else require(policy.allowSell, "Sell orders not allowed");

        if (autoBorrow) require(policy.allowAutoBorrow, "Auto-borrow not allowed");
        if (autoRepay)  require(policy.allowAutoRepay,  "Auto-repay not allowed");

        require(ILendingManager($.lendingManager).getHealthFactor(user) >= policy.minHealthFactor, "Health factor too low");

        if (policy.minTimeBetweenTrades > 0) {
            require(
                block.timestamp >= $.lastTradeTime[strategyAgentId] + policy.minTimeBetweenTrades,
                "Cooldown period active"
            );
        }
    }

    function _enforceLimitOrderPermissions(
        PolicyFactoryStorage.Policy memory policy,
        address user,
        uint256 strategyAgentId,
        IPoolManager.Pool calldata pool,
        IOrderBook.Side side,
        uint128 quantity,
        bool autoRepay,
        bool autoBorrow
    ) internal view {
        Storage storage $ = getStorage();
        require(quantity <= policy.maxOrderSize, "Order too large");
        if (policy.minOrderSize > 0) require(quantity >= policy.minOrderSize, "Order too small");

        require(PolicyFactory($.policyFactory).isTokenAllowed(user, strategyAgentId, Currency.unwrap(pool.baseCurrency)), "Base token not allowed");
        require(PolicyFactory($.policyFactory).isTokenAllowed(user, strategyAgentId, Currency.unwrap(pool.quoteCurrency)), "Quote token not allowed");

        require(policy.allowLimitOrders, "Limit orders not allowed");
        require(policy.allowPlaceLimitOrder, "Placing limit orders not allowed");

        if (side == IOrderBook.Side.BUY) require(policy.allowBuy, "Buy orders not allowed");
        else require(policy.allowSell, "Sell orders not allowed");

        if (autoBorrow) require(policy.allowAutoBorrow, "Auto-borrow not allowed");
        if (autoRepay)  require(policy.allowAutoRepay,  "Auto-repay not allowed");

        require(ILendingManager($.lendingManager).getHealthFactor(user) >= policy.minHealthFactor, "Health factor too low");

        if (policy.minTimeBetweenTrades > 0) {
            require(
                block.timestamp >= $.lastTradeTime[strategyAgentId] + policy.minTimeBetweenTrades,
                "Cooldown period active"
            );
        }
    }

    // ============ Circuit Breakers ============

    function _checkCircuitBreaker(
        address user,
        uint256 strategyAgentId,
        PolicyFactoryStorage.Policy memory policy
    ) internal {
        if (policy.maxDailyDrawdown == 0) return;

        Storage storage $ = getStorage();
        uint256 today = block.timestamp / 1 days;
        uint256 currentValue = _getPortfolioValue(user);

        if ($.dayStartValues[user][today] == 0) {
            $.dayStartValues[user][today] = currentValue;
            return;
        }

        uint256 startValue = $.dayStartValues[user][today];
        if (currentValue < startValue) {
            uint256 drawdownBps = ((startValue - currentValue) * 10000) / startValue;
            if (drawdownBps > policy.maxDailyDrawdown) {
                PolicyFactory($.policyFactory).emergencyDisable(user, strategyAgentId, "CIRCUIT_BREAKER_DRAWDOWN");

                IERC8004Validation($.validationRegistry).requestValidation(
                    strategyAgentId,
                    IERC8004Validation.ValidationTask.CIRCUIT_BREAKER,
                    abi.encode(currentValue, startValue, drawdownBps, block.timestamp)
                );

                emit CircuitBreakerTriggered(user, strategyAgentId, drawdownBps, currentValue, startValue, block.timestamp);
                revert("Circuit breaker triggered");
            }
        }
    }

    function _getPortfolioValue(address user) internal view returns (uint256) {
        return 0; // TODO: implement proper portfolio value via BalanceManager
    }

    // ============ Tracking ============

    function _updateTracking(uint256 strategyAgentId, uint256 amountIn) internal {
        Storage storage $ = getStorage();
        $.lastTradeTime[strategyAgentId] = block.timestamp;
        uint256 today = block.timestamp / 1 days;
        $.dailyVolumes[strategyAgentId][today] += amountIn;
    }

    // ============ Reputation Recording ============

    function _recordTradeToReputation(
        uint256 strategyAgentId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        int256 pnl = int256(amountOut) - int256(amountIn);
        IERC8004Reputation(getStorage().reputationRegistry).submitFeedback(
            strategyAgentId,
            IERC8004Reputation.FeedbackType.TRADE_EXECUTION,
            abi.encode(pnl, amountIn, amountOut, block.timestamp)
        );
    }

    function _recordBorrowToReputation(uint256 strategyAgentId, address token, uint256 amount) internal {
        IERC8004Reputation(getStorage().reputationRegistry).submitFeedback(
            strategyAgentId,
            IERC8004Reputation.FeedbackType.BORROW,
            abi.encode(token, amount, block.timestamp)
        );
    }

    function _recordRepayToReputation(uint256 strategyAgentId, address token, uint256 amount) internal {
        IERC8004Reputation(getStorage().reputationRegistry).submitFeedback(
            strategyAgentId,
            IERC8004Reputation.FeedbackType.REPAY,
            abi.encode(token, amount, block.timestamp)
        );
    }

    // ============ View Functions ============

    function getDailyVolume(uint256 strategyAgentId) external view returns (uint256) {
        return getStorage().dailyVolumes[strategyAgentId][block.timestamp / 1 days];
    }

    function getLastTradeTime(uint256 strategyAgentId) external view returns (uint256) {
        return getStorage().lastTradeTime[strategyAgentId];
    }

    function getDayStartValue(address user) external view returns (uint256) {
        return getStorage().dayStartValues[user][block.timestamp / 1 days];
    }
}
