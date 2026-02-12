// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC8004Identity.sol";
import "./interfaces/IERC8004Reputation.sol";
import "./interfaces/IERC8004Validation.sol";
import "./PolicyFactory.sol";
import "./ChainlinkMetricsConsumer.sol";
import "../core/interfaces/IOrderBook.sol";
import "../core/interfaces/IBalanceManager.sol";
import "../core/interfaces/ILendingManager.sol";
import "../core/interfaces/IPoolManager.sol";
import {Currency} from "../core/libraries/Currency.sol";

/**
 * @title AgentRouter
 * @notice Execution layer for AI agent trading with policy-based authorization
 * @dev Separate entry point from Router - humans use Router, agents use AgentRouter
 *      Enforces PolicyFactory rules before executing any action
 */
contract AgentRouter {
    // ============ State Variables ============

    IERC8004Identity public immutable identityRegistry;
    IERC8004Reputation public immutable reputationRegistry;
    IERC8004Validation public immutable validationRegistry;
    PolicyFactory public immutable policyFactory;
    ChainlinkMetricsConsumer public metricsConsumer;

    // Core contracts
    IPoolManager public immutable poolManager;
    IBalanceManager public immutable balanceManager;
    ILendingManager public immutable lendingManager;

    // Tracking for circuit breakers
    mapping(address => mapping(uint256 => uint256)) public dayStartValues;  // owner => day => value
    mapping(uint256 => uint256) public lastTradeTime;  // agentTokenId => timestamp
    mapping(uint256 => mapping(uint256 => uint256)) public dailyVolumes;  // agentTokenId => day => volume

    // Agent delegation - maps agentTokenId => executor address => authorized
    mapping(uint256 => mapping(address => bool)) public authorizedExecutors;

    // ============ Events ============

    event AgentSwapExecuted(
        address indexed owner,
        uint256 indexed agentTokenId,
        address indexed executor,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );

    event AgentLimitOrderPlaced(
        address indexed owner,
        uint256 indexed agentTokenId,
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
        address indexed owner,
        uint256 indexed agentTokenId,
        address indexed executor,
        bytes32 orderId,
        uint256 timestamp
    );

    event AgentBorrowExecuted(
        address indexed owner,
        uint256 indexed agentTokenId,
        address indexed executor,
        address token,
        uint256 amount,
        uint256 newHealthFactor,
        uint256 timestamp
    );

    event AgentRepayExecuted(
        address indexed owner,
        uint256 indexed agentTokenId,
        address indexed executor,
        address token,
        uint256 amount,
        uint256 newHealthFactor,
        uint256 timestamp
    );

    event AgentCollateralSupplied(
        address indexed owner,
        uint256 indexed agentTokenId,
        address indexed executor,
        address token,
        uint256 amount,
        uint256 timestamp
    );

    event AgentCollateralWithdrawn(
        address indexed owner,
        uint256 indexed agentTokenId,
        address indexed executor,
        address token,
        uint256 amount,
        uint256 timestamp
    );

    event CircuitBreakerTriggered(
        address indexed owner,
        uint256 indexed agentTokenId,
        uint256 drawdownBps,
        uint256 currentValue,
        uint256 dayStartValue,
        uint256 timestamp
    );

    event PolicyViolation(
        address indexed owner,
        uint256 indexed agentTokenId,
        string reason,
        uint256 timestamp
    );

    event ExecutorAuthorized(
        address indexed owner,
        uint256 indexed agentTokenId,
        address indexed executor,
        uint256 timestamp
    );

    event ExecutorRevoked(
        address indexed owner,
        uint256 indexed agentTokenId,
        address indexed executor,
        uint256 timestamp
    );

    // ============ Constructor ============

    constructor(
        address _identityRegistry,
        address _reputationRegistry,
        address _validationRegistry,
        address _policyFactory,
        address _poolManager,
        address _balanceManager,
        address _lendingManager
    ) {
        identityRegistry = IERC8004Identity(_identityRegistry);
        reputationRegistry = IERC8004Reputation(_reputationRegistry);
        validationRegistry = IERC8004Validation(_validationRegistry);
        policyFactory = PolicyFactory(_policyFactory);
        poolManager = IPoolManager(_poolManager);
        balanceManager = IBalanceManager(_balanceManager);
        lendingManager = ILendingManager(_lendingManager);
    }

    /**
     * @notice Set Chainlink Metrics Consumer (only called once during setup)
     * @param _metricsConsumer Address of ChainlinkMetricsConsumer
     */
    function setMetricsConsumer(address _metricsConsumer) external {
        require(address(metricsConsumer) == address(0), "Already set");
        metricsConsumer = ChainlinkMetricsConsumer(_metricsConsumer);
    }

    // ============ Trading Functions ============

    /**
     * @notice Execute a market order (swap) on behalf of an agent
     * @param agentTokenId ERC-8004 agent token ID
     * @param pool Pool to trade in
     * @param side BUY or SELL
     * @param quantity Amount to trade
     * @param minOutAmount Minimum amount to receive (slippage protection)
     * @param autoRepay Whether to auto-repay debt from proceeds
     * @param autoBorrow Whether to auto-borrow if needed
     * @return orderId Order ID
     * @return filled Amount filled
     */
    function executeMarketOrder(
        uint256 agentTokenId,
        IPoolManager.Pool calldata pool,
        IOrderBook.Side side,
        uint128 quantity,
        uint128 minOutAmount,
        bool autoRepay,
        bool autoBorrow
    ) external returns (uint48 orderId, uint128 filled) {
        // 1. Get owner and policy
        address owner = identityRegistry.ownerOf(agentTokenId);
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(owner, agentTokenId);

        // 2. Verify agent is enabled
        require(policy.enabled, "Agent disabled");
        require(block.timestamp < policy.expiryTimestamp, "Agent expired");

        // 3. Verify executor is authorized
        require(
            msg.sender == owner || _isAuthorizedExecutor(agentTokenId, owner, msg.sender),
            "Not authorized executor"
        );

        // 4. Check if requires Chainlink (complex permissions)
        require(!policy.requiresChainlinkFunctions, "Use executeMarketOrderWithMetrics");

        // 5. Enforce simple permissions
        _enforceMarketOrderPermissions(
            policy,
            owner,
            agentTokenId,
            pool,
            side,
            quantity,
            autoRepay,
            autoBorrow
        );

        // 6. Get OrderBook for this pool
        IOrderBook orderBook = pool.orderBook;

        // 7. Execute market order
        (orderId, filled) = orderBook.placeMarketOrder(
            quantity,
            side,
            owner,
            autoRepay,
            autoBorrow
        );

        // 8. Update tracking
        _updateTracking(owner, agentTokenId, quantity);

        // 9. Check circuit breaker
        _checkCircuitBreaker(owner, agentTokenId, policy);

        // 10. Record to reputation registry
        _recordTradeToReputation(agentTokenId, Currency.unwrap(pool.baseCurrency), Currency.unwrap(pool.quoteCurrency), quantity, filled);

        emit AgentSwapExecuted(
            owner,
            agentTokenId,
            msg.sender,
            Currency.unwrap(pool.baseCurrency),
            Currency.unwrap(pool.quoteCurrency),
            quantity,
            filled,
            block.timestamp
        );
    }

    /**
     * @notice Place a limit order on behalf of an agent
     * @param agentTokenId ERC-8004 agent token ID
     * @param pool Pool to trade in
     * @param price Limit price
     * @param quantity Amount to trade
     * @param side BUY or SELL
     * @param timeInForce Time in force (GTC, IOC, FOK, PO)
     * @param autoRepay Whether to auto-repay debt from proceeds
     * @param autoBorrow Whether to auto-borrow if needed
     * @return orderId Order ID
     */
    function executeLimitOrder(
        uint256 agentTokenId,
        IPoolManager.Pool calldata pool,
        uint128 price,
        uint128 quantity,
        IOrderBook.Side side,
        IOrderBook.TimeInForce timeInForce,
        bool autoRepay,
        bool autoBorrow
    ) external returns (uint48 orderId) {
        // Get owner and policy
        address owner = identityRegistry.ownerOf(agentTokenId);
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(owner, agentTokenId);

        // Verify agent is enabled
        require(policy.enabled, "Agent disabled");
        require(block.timestamp < policy.expiryTimestamp, "Agent expired");

        // Verify executor is authorized
        require(
            msg.sender == owner || _isAuthorizedExecutor(agentTokenId, owner, msg.sender),
            "Not authorized executor"
        );

        // Check permissions
        require(policy.allowLimitOrders, "Limit orders not allowed");
        require(policy.allowPlaceLimitOrder, "Placing limit orders not allowed");

        // Enforce simple permissions
        _enforceLimitOrderPermissions(
            policy,
            owner,
            agentTokenId,
            pool,
            side,
            quantity,
            autoRepay,
            autoBorrow
        );

        // Get OrderBook for this pool
        IOrderBook orderBook = pool.orderBook;

        // Place limit order
        orderId = orderBook.placeOrder(
            price,
            quantity,
            side,
            owner,
            timeInForce,
            autoRepay,
            autoBorrow
        );

        // Update tracking
        _updateTracking(owner, agentTokenId, quantity);

        emit AgentLimitOrderPlaced(
            owner,
            agentTokenId,
            msg.sender,
            bytes32(uint256(orderId)),
            Currency.unwrap(pool.baseCurrency),
            Currency.unwrap(pool.quoteCurrency),
            quantity,
            price,
            side == IOrderBook.Side.BUY,
            block.timestamp
        );
    }

    /**
     * @notice Cancel a limit order on behalf of an agent
     * @param agentTokenId ERC-8004 agent token ID
     * @param pool Pool where order was placed
     * @param orderId Order ID to cancel
     */
    function cancelOrder(
        uint256 agentTokenId,
        IPoolManager.Pool calldata pool,
        uint48 orderId
    ) external {
        address owner = identityRegistry.ownerOf(agentTokenId);
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(owner, agentTokenId);

        require(policy.enabled, "Agent disabled");
        require(policy.allowCancelOrder, "Cancelling orders not allowed");

        require(
            msg.sender == owner || _isAuthorizedExecutor(agentTokenId, owner, msg.sender),
            "Not authorized executor"
        );

        // Get OrderBook for this pool
        IOrderBook orderBook = pool.orderBook;

        // Cancel order
        orderBook.cancelOrder(orderId, owner);

        emit AgentOrderCancelled(
            owner,
            agentTokenId,
            msg.sender,
            bytes32(uint256(orderId)),
            block.timestamp
        );
    }

    // ============ Lending Functions ============

    /**
     * @notice Borrow tokens on behalf of an agent
     * @param agentTokenId ERC-8004 agent token ID
     * @param token Token to borrow
     * @param amount Amount to borrow
     */
    function executeBorrow(
        uint256 agentTokenId,
        address token,
        uint256 amount
    ) external {
        address owner = identityRegistry.ownerOf(agentTokenId);
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(owner, agentTokenId);

        require(policy.enabled, "Agent disabled");
        require(block.timestamp < policy.expiryTimestamp, "Agent expired");

        require(
            msg.sender == owner || _isAuthorizedExecutor(agentTokenId, owner, msg.sender),
            "Not authorized executor"
        );

        // Check permissions
        require(policy.allowBorrow, "Borrowing not allowed");
        require(amount <= policy.maxAutoBorrowAmount, "Borrow amount exceeds limit");

        // Check token is allowed
        require(policyFactory.isTokenAllowed(owner, agentTokenId, token), "Token not allowed");

        // Check health factor before borrow
        uint256 currentHF = lendingManager.getHealthFactor(owner);
        require(currentHF >= policy.minHealthFactor, "Health factor too low");

        // Execute borrow for user
        lendingManager.borrowForUser(owner, token, amount);

        // Check health factor after borrow
        uint256 newHF = lendingManager.getHealthFactor(owner);
        require(newHF >= policy.minHealthFactor, "Borrow would harm health factor");

        // Record to reputation
        _recordBorrowToReputation(agentTokenId, token, amount);

        emit AgentBorrowExecuted(
            owner,
            agentTokenId,
            msg.sender,
            token,
            amount,
            newHF,
            block.timestamp
        );
    }

    /**
     * @notice Repay borrowed tokens on behalf of an agent
     * @param agentTokenId ERC-8004 agent token ID
     * @param token Token to repay
     * @param amount Amount to repay
     */
    function executeRepay(
        uint256 agentTokenId,
        address token,
        uint256 amount
    ) external {
        address owner = identityRegistry.ownerOf(agentTokenId);
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(owner, agentTokenId);

        require(policy.enabled, "Agent disabled");
        require(policy.allowRepay, "Repaying not allowed");

        require(
            msg.sender == owner || _isAuthorizedExecutor(agentTokenId, owner, msg.sender),
            "Not authorized executor"
        );

        // Execute repay for user
        lendingManager.repayForUser(owner, token, amount);

        uint256 newHF = lendingManager.getHealthFactor(owner);

        // Record to reputation (repayment is good!)
        _recordRepayToReputation(agentTokenId, token, amount);

        emit AgentRepayExecuted(
            owner,
            agentTokenId,
            msg.sender,
            token,
            amount,
            newHF,
            block.timestamp
        );
    }

    /**
     * @notice Supply collateral (deposit liquidity) on behalf of an agent
     * @param agentTokenId ERC-8004 agent token ID
     * @param token Token to supply
     * @param amount Amount to supply
     */
    function executeSupplyCollateral(
        uint256 agentTokenId,
        address token,
        uint256 amount
    ) external {
        address owner = identityRegistry.ownerOf(agentTokenId);
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(owner, agentTokenId);

        require(policy.enabled, "Agent disabled");
        require(policy.allowSupplyCollateral, "Supplying collateral not allowed");

        require(
            msg.sender == owner || _isAuthorizedExecutor(agentTokenId, owner, msg.sender),
            "Not authorized executor"
        );

        // Check token is allowed
        require(policyFactory.isTokenAllowed(owner, agentTokenId, token), "Token not allowed");

        // Execute supply for user (deposit liquidity)
        lendingManager.depositLiquidity(token, amount, owner);

        emit AgentCollateralSupplied(
            owner,
            agentTokenId,
            msg.sender,
            token,
            amount,
            block.timestamp
        );
    }

    /**
     * @notice Withdraw collateral (withdraw liquidity) on behalf of an agent
     * @param agentTokenId ERC-8004 agent token ID
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function executeWithdrawCollateral(
        uint256 agentTokenId,
        address token,
        uint256 amount
    ) external {
        address owner = identityRegistry.ownerOf(agentTokenId);
        PolicyFactory.Policy memory policy = policyFactory.getPolicy(owner, agentTokenId);

        require(policy.enabled, "Agent disabled");
        require(policy.allowWithdrawCollateral, "Withdrawing collateral not allowed");

        require(
            msg.sender == owner || _isAuthorizedExecutor(agentTokenId, owner, msg.sender),
            "Not authorized executor"
        );

        // Check health factor before withdrawal
        uint256 currentHF = lendingManager.getHealthFactor(owner);
        require(currentHF >= policy.minHealthFactor, "Health factor too low");

        // Execute withdrawal (withdraw liquidity)
        lendingManager.withdrawLiquidity(token, amount, owner);

        // Check health factor after withdrawal
        uint256 newHF = lendingManager.getHealthFactor(owner);
        require(newHF >= policy.minHealthFactor, "Withdrawal would harm health factor");

        emit AgentCollateralWithdrawn(
            owner,
            agentTokenId,
            msg.sender,
            token,
            amount,
            block.timestamp
        );
    }

    // ============ Permission Enforcement ============

    /**
     * @notice Enforce permissions for market orders
     */
    function _enforceMarketOrderPermissions(
        PolicyFactory.Policy memory policy,
        address owner,
        uint256 agentTokenId,
        IPoolManager.Pool calldata pool,
        IOrderBook.Side side,
        uint128 quantity,
        bool autoRepay,
        bool autoBorrow
    ) internal view {
        // 1. Order size limits
        require(quantity <= policy.maxOrderSize, "Order too large");
        if (policy.minOrderSize > 0) {
            require(quantity >= policy.minOrderSize, "Order too small");
        }

        // 2. Token whitelist/blacklist
        require(
            policyFactory.isTokenAllowed(owner, agentTokenId, Currency.unwrap(pool.baseCurrency)),
            "Base token not allowed"
        );
        require(
            policyFactory.isTokenAllowed(owner, agentTokenId, Currency.unwrap(pool.quoteCurrency)),
            "Quote token not allowed"
        );

        // 3. Operation permissions
        require(policy.allowSwap, "Swap not allowed");
        require(policy.allowMarketOrders, "Market orders not allowed");

        // 4. Buy/Sell direction
        if (side == IOrderBook.Side.BUY) {
            require(policy.allowBuy, "Buy orders not allowed");
        } else {
            require(policy.allowSell, "Sell orders not allowed");
        }

        // 5. Auto-borrow/repay flags
        if (autoBorrow) {
            require(policy.allowAutoBorrow, "Auto-borrow not allowed");
        }
        if (autoRepay) {
            require(policy.allowAutoRepay, "Auto-repay not allowed");
        }

        // 6. Health factor check
        uint256 healthFactor = lendingManager.getHealthFactor(owner);
        require(healthFactor >= policy.minHealthFactor, "Health factor too low");

        // 7. Trade cooldown
        if (policy.minTimeBetweenTrades > 0) {
            require(
                block.timestamp >= lastTradeTime[agentTokenId] + policy.minTimeBetweenTrades,
                "Cooldown period active"
            );
        }
    }

    /**
     * @notice Enforce permissions for limit orders
     */
    function _enforceLimitOrderPermissions(
        PolicyFactory.Policy memory policy,
        address owner,
        uint256 agentTokenId,
        IPoolManager.Pool calldata pool,
        IOrderBook.Side side,
        uint128 quantity,
        bool autoRepay,
        bool autoBorrow
    ) internal view {
        // 1. Order size limits
        require(quantity <= policy.maxOrderSize, "Order too large");
        if (policy.minOrderSize > 0) {
            require(quantity >= policy.minOrderSize, "Order too small");
        }

        // 2. Token whitelist/blacklist
        require(
            policyFactory.isTokenAllowed(owner, agentTokenId, Currency.unwrap(pool.baseCurrency)),
            "Base token not allowed"
        );
        require(
            policyFactory.isTokenAllowed(owner, agentTokenId, Currency.unwrap(pool.quoteCurrency)),
            "Quote token not allowed"
        );

        // 3. Operation permissions
        require(policy.allowLimitOrders, "Limit orders not allowed");
        require(policy.allowPlaceLimitOrder, "Placing limit orders not allowed");

        // 4. Buy/Sell direction
        if (side == IOrderBook.Side.BUY) {
            require(policy.allowBuy, "Buy orders not allowed");
        } else {
            require(policy.allowSell, "Sell orders not allowed");
        }

        // 5. Auto-borrow/repay flags
        if (autoBorrow) {
            require(policy.allowAutoBorrow, "Auto-borrow not allowed");
        }
        if (autoRepay) {
            require(policy.allowAutoRepay, "Auto-repay not allowed");
        }

        // 6. Health factor check
        uint256 healthFactor = lendingManager.getHealthFactor(owner);
        require(healthFactor >= policy.minHealthFactor, "Health factor too low");

        // 7. Trade cooldown
        if (policy.minTimeBetweenTrades > 0) {
            require(
                block.timestamp >= lastTradeTime[agentTokenId] + policy.minTimeBetweenTrades,
                "Cooldown period active"
            );
        }
    }

    // ============ Circuit Breakers ============

    /**
     * @notice Check circuit breaker conditions and disable agent if triggered
     */
    function _checkCircuitBreaker(
        address owner,
        uint256 agentTokenId,
        PolicyFactory.Policy memory policy
    ) internal {
        if (policy.maxDailyDrawdown == 0) {
            return; // No drawdown limit set
        }

        uint256 today = block.timestamp / 1 days;

        // Get current portfolio value from BalanceManager
        // Note: This requires BalanceManager to have a getTotalValue function
        // If not available, we can use a different metric like total supplied collateral
        uint256 currentValue = _getPortfolioValue(owner);

        // Initialize day start value if not set
        if (dayStartValues[owner][today] == 0) {
            dayStartValues[owner][today] = currentValue;
            return;
        }

        uint256 startValue = dayStartValues[owner][today];

        // Calculate drawdown
        if (currentValue < startValue) {
            uint256 drawdownBps = ((startValue - currentValue) * 10000) / startValue;

            if (drawdownBps > policy.maxDailyDrawdown) {
                // Trigger circuit breaker
                policyFactory.emergencyDisable(
                    owner,
                    agentTokenId,
                    "CIRCUIT_BREAKER_DRAWDOWN"
                );

                // Submit validation proof to ERC-8004
                validationRegistry.requestValidation(
                    agentTokenId,
                    IERC8004Validation.ValidationTask.CIRCUIT_BREAKER,
                    abi.encode(currentValue, startValue, drawdownBps, block.timestamp)
                );

                emit CircuitBreakerTriggered(
                    owner,
                    agentTokenId,
                    drawdownBps,
                    currentValue,
                    startValue,
                    block.timestamp
                );

                revert("Circuit breaker triggered");
            }
        }
    }

    /**
     * @notice Get portfolio value for an owner
     * @dev This is a simplified version - in production would aggregate across all assets
     */
    function _getPortfolioValue(address owner) internal view returns (uint256) {
        // For now, return a placeholder
        // In production, this would query BalanceManager for total value across all assets
        // Or sum up all supplied collateral values
        return 0; // TODO: Implement proper portfolio value calculation
    }

    // ============ Tracking & Updates ============

    /**
     * @notice Update tracking data after trade
     */
    function _updateTracking(
        address owner,
        uint256 agentTokenId,
        uint256 amountIn
    ) internal {
        // Update last trade time
        lastTradeTime[agentTokenId] = block.timestamp;

        // Update daily volume
        uint256 today = block.timestamp / 1 days;
        dailyVolumes[agentTokenId][today] += amountIn;
    }

    // ============ Reputation Recording ============

    /**
     * @notice Record trade to ERC-8004 Reputation Registry
     */
    function _recordTradeToReputation(
        uint256 agentTokenId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        // Calculate PnL (simplified - just comparing amounts)
        // In production, would use oracle prices for accurate PnL
        int256 pnl = int256(amountOut) - int256(amountIn);

        bytes memory data = abi.encode(pnl, amountIn, amountOut, block.timestamp);

        reputationRegistry.submitFeedback(
            agentTokenId,
            IERC8004Reputation.FeedbackType.TRADE_EXECUTION,
            data
        );
    }

    /**
     * @notice Record borrow to reputation
     */
    function _recordBorrowToReputation(
        uint256 agentTokenId,
        address token,
        uint256 amount
    ) internal {
        bytes memory data = abi.encode(token, amount, block.timestamp);

        reputationRegistry.submitFeedback(
            agentTokenId,
            IERC8004Reputation.FeedbackType.BORROW,
            data
        );
    }

    /**
     * @notice Record repay to reputation
     */
    function _recordRepayToReputation(
        uint256 agentTokenId,
        address token,
        uint256 amount
    ) internal {
        bytes memory data = abi.encode(token, amount, block.timestamp);

        reputationRegistry.submitFeedback(
            agentTokenId,
            IERC8004Reputation.FeedbackType.REPAY,
            data
        );
    }

    // ============ Delegation Management ============

    /**
     * @notice Authorize an executor (agent wallet) to act on behalf of the owner
     * @param agentTokenId The agent token ID
     * @param executor The address to authorize (agent's dedicated wallet)
     * @dev Only the owner of the agent NFT can authorize executors
     */
    function authorizeExecutor(uint256 agentTokenId, address executor) external {
        address owner = identityRegistry.ownerOf(agentTokenId);
        require(msg.sender == owner, "Only agent owner can authorize");
        require(executor != address(0), "Invalid executor address");
        require(!authorizedExecutors[agentTokenId][executor], "Already authorized");

        authorizedExecutors[agentTokenId][executor] = true;
        emit ExecutorAuthorized(owner, agentTokenId, executor, block.timestamp);
    }

    /**
     * @notice Revoke authorization for an executor
     * @param agentTokenId The agent token ID
     * @param executor The address to revoke
     * @dev Only the owner of the agent NFT can revoke executors
     */
    function revokeExecutor(uint256 agentTokenId, address executor) external {
        address owner = identityRegistry.ownerOf(agentTokenId);
        require(msg.sender == owner, "Only agent owner can revoke");
        require(authorizedExecutors[agentTokenId][executor], "Not authorized");

        authorizedExecutors[agentTokenId][executor] = false;
        emit ExecutorRevoked(owner, agentTokenId, executor, block.timestamp);
    }

    // ============ Authorization Checks ============

    /**
     * @notice Check if an address is authorized to execute for this agent
     * @dev Checks if executor is owner, agent wallet, or explicitly authorized
     */
    function _isAuthorizedExecutor(
        uint256 agentTokenId,
        address owner,
        address executor
    ) internal view returns (bool) {
        // Owner can always execute
        if (executor == owner) return true;

        // Check if executor is the agent's registered wallet (from ERC-8004)
        address agentWallet = _getAgentWallet(agentTokenId);
        if (agentWallet != address(0) && executor == agentWallet) return true;

        // Check if executor is explicitly authorized (fallback/additional authorization)
        return authorizedExecutors[agentTokenId][executor];
    }

    /**
     * @notice Get the agent wallet address from IdentityRegistry
     * @dev Internal helper to safely get agent wallet
     */
    function _getAgentWallet(uint256 agentTokenId) internal view returns (address) {
        try identityRegistry.getAgentWallet(agentTokenId) returns (address wallet) {
            return wallet;
        } catch {
            return address(0);
        }
    }

    // ============ View Functions ============

    /**
     * @notice Get agent's current daily volume
     */
    function getDailyVolume(uint256 agentTokenId) external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        return dailyVolumes[agentTokenId][today];
    }

    /**
     * @notice Get agent's last trade timestamp
     */
    function getLastTradeTime(uint256 agentTokenId) external view returns (uint256) {
        return lastTradeTime[agentTokenId];
    }

    /**
     * @notice Get day start value for drawdown calculation
     */
    function getDayStartValue(address owner) external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        return dayStartValues[owner][today];
    }

    /**
     * @notice Check if an executor is authorized for an agent
     * @param agentTokenId The agent token ID
     * @param executor The address to check
     * @return bool True if authorized
     */
    function isExecutorAuthorized(uint256 agentTokenId, address executor) external view returns (bool) {
        address owner = identityRegistry.ownerOf(agentTokenId);
        return _isAuthorizedExecutor(agentTokenId, owner, executor);
    }

    /**
     * @notice Get the agent wallet address for a token
     * @param agentTokenId The agent token ID
     * @return The wallet address controlled by the agent (from ERC-8004 registry)
     */
    function getAgentWallet(uint256 agentTokenId) external view returns (address) {
        return _getAgentWallet(agentTokenId);
    }
}
