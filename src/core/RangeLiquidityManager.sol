// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IRangeLiquidityManager} from "./interfaces/IRangeLiquidityManager.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {IScaleXRouter} from "./interfaces/IScaleXRouter.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IOracle} from "./interfaces/IOracle.sol";

import {RangeLiquidityManagerStorage} from "./storages/RangeLiquidityManagerStorage.sol";
import {RangeLiquidityDistribution} from "./libraries/RangeLiquidityDistribution.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import {PoolKey, PoolIdLibrary} from "./libraries/Pool.sol";

contract RangeLiquidityManager is
    IRangeLiquidityManager,
    RangeLiquidityManagerStorage,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _poolManager,
        address _balanceManager,
        address _router
    ) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        $.poolManager = _poolManager;
        $.balanceManager = _balanceManager;
        $.router = _router;
        $.nextPositionId = 1;
        $.protocolFeeBps = 10; // Default 0.1% protocol fee
    }

    /// @notice Create a new range liquidity position
    function createPosition(PositionParams calldata params)
        external
        nonReentrant
        returns (uint256 positionId)
    {
        Storage storage $ = getStorage();

        // Validate parameters
        _validatePositionParams(params);

        // Check: user can only have 1 position per pool
        bytes32 poolId = keccak256(abi.encode(params.poolKey));
        if ($.userPoolPosition[msg.sender][poolId] != 0) {
            revert PositionAlreadyExists(msg.sender, params.poolKey);
        }

        // Get pool and orderbook
        IPoolManager.Pool memory pool = IPoolManager($.poolManager).getPool(params.poolKey);
        IOrderBook orderBook = pool.orderBook;

        // Get current price from oracle
        uint128 currentPrice = _getCurrentPrice(params.poolKey, address(orderBook));

        // Validate price range
        if (currentPrice < params.lowerPrice || currentPrice > params.upperPrice) {
            revert InvalidPriceRange(params.lowerPrice, params.upperPrice);
        }

        // Transfer tokens from user to this contract
        IBalanceManager($.balanceManager).deposit(
            params.depositCurrency,
            params.depositAmount,
            msg.sender,
            address(this)
        );

        // Calculate tick prices with tick spacing
        uint128[] memory tickPrices = RangeLiquidityDistribution.calculateTickPrices(
            params.lowerPrice,
            params.upperPrice,
            params.tickCount,
            params.tickSpacing
        );

        // Determine if deposit is in base or quote currency
        bool isBaseCurrency = Currency.unwrap(params.depositCurrency) ==
                              Currency.unwrap(params.poolKey.baseCurrency);

        // Calculate distribution
        RangeLiquidityDistribution.DistributionResult memory distribution =
            RangeLiquidityDistribution.calculateDistribution(
                params.strategy,
                params.depositAmount,
                tickPrices,
                currentPrice,
                params.depositCurrency,
                isBaseCurrency
            );

        // Place all orders
        (uint48[] memory buyOrderIds, uint48[] memory sellOrderIds) = _placeRangeOrders(
            pool,
            tickPrices,
            distribution.buyAmounts,
            distribution.sellAmounts
        );

        // Create position
        positionId = $.nextPositionId++;

        RangePosition storage position = $.positions[positionId];
        position.positionId = positionId;
        position.owner = msg.sender;
        position.poolKey = params.poolKey;
        position.strategy = params.strategy;
        position.lowerPrice = params.lowerPrice;
        position.upperPrice = params.upperPrice;
        position.centerPriceAtCreation = currentPrice;
        position.tickCount = params.tickCount;
        position.tickSpacing = params.tickSpacing;
        position.initialDepositAmount = params.depositAmount;
        position.initialDepositCurrency = params.depositCurrency;
        position.buyOrderIds = buyOrderIds;
        position.sellOrderIds = sellOrderIds;
        position.feesCollectedBase = 0;
        position.feesCollectedQuote = 0;
        position.autoRebalanceEnabled = params.autoRebalance;
        position.rebalanceThresholdBps = params.rebalanceThresholdBps;
        position.authorizedBot = address(0);
        position.isActive = true;
        position.createdAt = uint48(block.timestamp);
        position.lastRebalancedAt = uint48(block.timestamp);
        position.rebalanceCount = 0;

        // Track user position
        $.userPositions[msg.sender].push(positionId);
        $.userPoolPosition[msg.sender][poolId] = positionId;

        emit PositionCreated(
            positionId,
            msg.sender,
            params.poolKey,
            params.lowerPrice,
            params.upperPrice,
            params.depositAmount,
            params.strategy,
            params.tickSpacing,
            params.poolKey.feeTier
        );
    }

    /// @notice Close position and withdraw all funds
    function closePosition(uint256 positionId) external nonReentrant {
        Storage storage $ = getStorage();
        RangePosition storage position = $.positions[positionId];

        // Validate ownership and state
        if (position.owner != msg.sender) {
            revert NotPositionOwner(positionId, msg.sender);
        }
        if (!position.isActive) {
            revert PositionNotActive(positionId);
        }

        // Get pool
        IPoolManager.Pool memory pool = IPoolManager($.poolManager).getPool(position.poolKey);

        // Cancel all orders
        _cancelAllOrders(pool.orderBook, position.buyOrderIds);
        _cancelAllOrders(pool.orderBook, position.sellOrderIds);

        // Calculate final balances
        uint256 baseBalance = $.positionBalances[positionId][Currency.unwrap(position.poolKey.baseCurrency)];
        uint256 quoteBalance = $.positionBalances[positionId][Currency.unwrap(position.poolKey.quoteCurrency)];

        // Get balances from BalanceManager
        baseBalance += IBalanceManager($.balanceManager).getBalance(
            address(this),
            position.poolKey.baseCurrency
        );
        quoteBalance += IBalanceManager($.balanceManager).getBalance(
            address(this),
            position.poolKey.quoteCurrency
        );

        // Withdraw to user
        if (baseBalance > 0) {
            IBalanceManager($.balanceManager).withdraw(
                position.poolKey.baseCurrency,
                baseBalance,
                msg.sender
            );
        }
        if (quoteBalance > 0) {
            IBalanceManager($.balanceManager).withdraw(
                position.poolKey.quoteCurrency,
                quoteBalance,
                msg.sender
            );
        }

        // Mark inactive
        position.isActive = false;

        // Clear user pool position mapping
        bytes32 poolId = keccak256(abi.encode(position.poolKey));
        delete $.userPoolPosition[msg.sender][poolId];

        emit PositionClosed(
            positionId,
            msg.sender,
            baseBalance,
            quoteBalance,
            position.feesCollectedBase,
            position.feesCollectedQuote
        );
    }

    /// @notice Rebalance position around current price
    function rebalancePosition(uint256 positionId) external nonReentrant {
        Storage storage $ = getStorage();
        RangePosition storage position = $.positions[positionId];

        // Authorization check
        bool isOwner = msg.sender == position.owner;
        bool isAuthorizedBot = position.autoRebalanceEnabled &&
            position.authorizedBot != address(0) &&
            msg.sender == position.authorizedBot;

        if (!isOwner && !isAuthorizedBot) {
            revert NotAuthorizedToRebalance(positionId, msg.sender);
        }

        if (!position.isActive) {
            revert PositionNotActive(positionId);
        }

        // Get current price
        IPoolManager.Pool memory pool = IPoolManager($.poolManager).getPool(position.poolKey);
        uint128 currentPrice = _getCurrentPrice(position.poolKey, address(pool.orderBook));

        // Check drift threshold (if called by bot)
        if (isAuthorizedBot && !isOwner) {
            uint256 drift = RangeLiquidityDistribution.calculatePriceDrift(
                position.centerPriceAtCreation,
                currentPrice
            );
            if (drift < position.rebalanceThresholdBps) {
                revert RebalanceThresholdNotMet(positionId, drift, position.rebalanceThresholdBps);
            }
        }

        uint128 oldCenterPrice = position.centerPriceAtCreation;

        // Cancel all existing orders
        _cancelAllOrders(pool.orderBook, position.buyOrderIds);
        _cancelAllOrders(pool.orderBook, position.sellOrderIds);

        // Calculate current inventory
        (uint256 baseBalance, uint256 quoteBalance) = _getPositionBalances(positionId, position.poolKey);

        // Convert total value to quote currency
        uint8 baseDecimals = position.poolKey.baseCurrency.decimals();
        uint256 totalValueInQuote = RangeLiquidityDistribution.convertToQuoteValue(
            baseBalance,
            quoteBalance,
            currentPrice,
            baseDecimals
        );

        // Calculate new range centered at current price
        (uint128 newLowerPrice, uint128 newUpperPrice) = RangeLiquidityDistribution.calculateNewRange(
            position.lowerPrice,
            position.upperPrice,
            currentPrice
        );

        // Recalculate tick prices with tick spacing
        uint128[] memory newTickPrices = RangeLiquidityDistribution.calculateTickPrices(
            newLowerPrice,
            newUpperPrice,
            position.tickCount,
            position.tickSpacing
        );

        // Redistribute liquidity (always rebalance in quote currency)
        RangeLiquidityDistribution.DistributionResult memory distribution =
            RangeLiquidityDistribution.calculateDistribution(
                position.strategy,
                totalValueInQuote,
                newTickPrices,
                currentPrice,
                position.poolKey.quoteCurrency,
                false // Always treat as quote currency for rebalance
            );

        // Place new orders
        (uint48[] memory newBuyIds, uint48[] memory newSellIds) = _placeRangeOrders(
            pool,
            newTickPrices,
            distribution.buyAmounts,
            distribution.sellAmounts
        );

        // Update position
        position.buyOrderIds = newBuyIds;
        position.sellOrderIds = newSellIds;
        position.centerPriceAtCreation = currentPrice;
        position.lowerPrice = newLowerPrice;
        position.upperPrice = newUpperPrice;
        position.lastRebalancedAt = uint48(block.timestamp);
        position.rebalanceCount++;

        emit PositionRebalanced(
            positionId,
            oldCenterPrice,
            currentPrice,
            newLowerPrice,
            newUpperPrice,
            position.rebalanceCount
        );
    }

    /// @notice Set authorized bot for auto-rebalancing
    function setAuthorizedBot(uint256 positionId, address bot) external {
        Storage storage $ = getStorage();
        RangePosition storage position = $.positions[positionId];

        if (position.owner != msg.sender) {
            revert NotPositionOwner(positionId, msg.sender);
        }

        position.authorizedBot = bot;

        emit BotAuthorized(positionId, bot);
    }

    /// @notice Revoke bot authorization
    function revokeBot(uint256 positionId) external {
        Storage storage $ = getStorage();
        RangePosition storage position = $.positions[positionId];

        if (position.owner != msg.sender) {
            revert NotPositionOwner(positionId, msg.sender);
        }

        address oldBot = position.authorizedBot;
        position.authorizedBot = address(0);

        emit BotRevoked(positionId, oldBot);
    }

    /// @notice Get position details
    function getPosition(uint256 positionId) external view returns (RangePosition memory) {
        return getStorage().positions[positionId];
    }

    /// @notice Get position value breakdown
    function getPositionValue(uint256 positionId) external view returns (PositionValue memory value) {
        Storage storage $ = getStorage();
        RangePosition storage position = $.positions[positionId];

        if (!position.isActive) {
            return value;
        }

        IPoolManager.Pool memory pool = IPoolManager($.poolManager).getPool(position.poolKey);
        uint128 currentPrice = _getCurrentPrice(position.poolKey, address(pool.orderBook));

        // Calculate balances
        (uint256 baseAmount, uint256 quoteAmount) = _getPositionBalances(positionId, position.poolKey);

        // Calculate total value in quote
        uint8 baseDecimals = position.poolKey.baseCurrency.decimals();
        uint256 totalValueInQuote = RangeLiquidityDistribution.convertToQuoteValue(
            baseAmount,
            quoteAmount,
            currentPrice,
            baseDecimals
        );

        value.totalValueInQuote = totalValueInQuote;
        value.baseAmount = baseAmount;
        value.quoteAmount = quoteAmount;
        value.lockedInOrders = _calculateLockedInOrders(position, pool.orderBook);
        value.freeBalance = totalValueInQuote - value.lockedInOrders;
        value.feesEarnedBase = position.feesCollectedBase;
        value.feesEarnedQuote = position.feesCollectedQuote;
    }

    /// @notice Get all positions for a user
    function getUserPositions(address user) external view returns (uint256[] memory) {
        return getStorage().userPositions[user];
    }

    /// @notice Check if position can be rebalanced
    function canRebalance(uint256 positionId)
        external
        view
        returns (bool canReb, uint256 currentDriftBps)
    {
        Storage storage $ = getStorage();
        RangePosition storage position = $.positions[positionId];

        if (!position.isActive) {
            return (false, 0);
        }

        IPoolManager.Pool memory pool = IPoolManager($.poolManager).getPool(position.poolKey);
        uint128 currentPrice = _getCurrentPrice(position.poolKey, address(pool.orderBook));

        currentDriftBps = RangeLiquidityDistribution.calculatePriceDrift(
            position.centerPriceAtCreation,
            currentPrice
        );

        canReb = position.autoRebalanceEnabled && currentDriftBps >= position.rebalanceThresholdBps;
    }

    /// @notice Get total number of positions created
    function totalPositions() external view returns (uint256) {
        return getStorage().nextPositionId - 1;
    }

    /// @notice Collect accumulated fees for a position
    function collectFees(uint256 positionId) external nonReentrant {
        Storage storage $ = getStorage();
        RangePosition storage position = $.positions[positionId];

        // Validate ownership
        if (position.owner != msg.sender) {
            revert NotPositionOwner(positionId, msg.sender);
        }
        if (!position.isActive) {
            revert PositionNotActive(positionId);
        }

        // Get accumulated fees
        uint256 baseFees = $.accumulatedFees[positionId][Currency.unwrap(position.poolKey.baseCurrency)];
        uint256 quoteFees = $.accumulatedFees[positionId][Currency.unwrap(position.poolKey.quoteCurrency)];

        // Update position fee tracking
        position.feesCollectedBase += baseFees;
        position.feesCollectedQuote += quoteFees;

        // Transfer fees to owner
        if (baseFees > 0) {
            IBalanceManager($.balanceManager).withdraw(
                position.poolKey.baseCurrency,
                baseFees,
                msg.sender
            );
            $.accumulatedFees[positionId][Currency.unwrap(position.poolKey.baseCurrency)] = 0;
        }

        if (quoteFees > 0) {
            IBalanceManager($.balanceManager).withdraw(
                position.poolKey.quoteCurrency,
                quoteFees,
                msg.sender
            );
            $.accumulatedFees[positionId][Currency.unwrap(position.poolKey.quoteCurrency)] = 0;
        }

        emit FeesCollected(positionId, baseFees, quoteFees);
    }

    /// @notice Get fee tier for a pool
    function getFeeTierForPool(PoolKey calldata poolKey) external pure returns (uint24) {
        return poolKey.feeTier;
    }

    /// @notice Set protocol fee percentage (only owner)
    /// @param newProtocolFeeBps New protocol fee in basis points (e.g., 10 = 0.1%)
    function setProtocolFee(uint16 newProtocolFeeBps) external onlyOwner {
        if (newProtocolFeeBps > 1000) {
            revert("Protocol fee too high");
        }
        getStorage().protocolFeeBps = newProtocolFeeBps;
    }

    /// @notice Get protocol fee percentage
    function getProtocolFee() external view returns (uint16) {
        return getStorage().protocolFeeBps;
    }

    /// @notice Calculate LP yield from fee tier
    /// @dev LP yield = fee tier - protocol fee
    /// @param positionId Position ID
    /// @return lpYieldBps LP yield in basis points
    function getLPYield(uint256 positionId) external view returns (uint24 lpYieldBps) {
        Storage storage $ = getStorage();
        RangePosition storage position = $.positions[positionId];

        uint24 feeTier = position.poolKey.feeTier;
        uint16 protocolFee = $.protocolFeeBps;

        // LP yield is the spread between fee tier and protocol fee
        // For example: 0.5% fee tier - 0.1% protocol fee = 0.4% for LP
        lpYieldBps = feeTier - protocolFee;
    }

    // ========== Internal Functions ==========

    function _validatePositionParams(PositionParams calldata params) internal pure {
        if (params.lowerPrice >= params.upperPrice) {
            revert InvalidPriceRange(params.lowerPrice, params.upperPrice);
        }
        if (params.tickCount == 0 || params.tickCount > 100) {
            revert InvalidTickCount(params.tickCount);
        }
        // Validate fee tier first (0.2% = 20bps or 0.5% = 50bps)
        if (params.poolKey.feeTier != 20 && params.poolKey.feeTier != 50) {
            revert InvalidFeeTier(params.poolKey.feeTier);
        }
        // Validate tick spacing must match fee tier:
        //   feeTier 20 (0.2%) → tickSpacing 50
        //   feeTier 50 (0.5%) → tickSpacing 200
        if (params.poolKey.feeTier == 20 && params.tickSpacing != 50) {
            revert InvalidTickSpacing(params.tickSpacing);
        }
        if (params.poolKey.feeTier == 50 && params.tickSpacing != 200) {
            revert InvalidTickSpacing(params.tickSpacing);
        }
        if (params.depositAmount == 0) {
            revert InvalidDepositAmount(params.depositAmount);
        }
        if (params.rebalanceThresholdBps > 10000) {
            revert InvalidRebalanceThreshold(params.rebalanceThresholdBps);
        }
        if (
            params.strategy != Strategy.UNIFORM &&
            params.strategy != Strategy.BID_HEAVY &&
            params.strategy != Strategy.ASK_HEAVY
        ) {
            revert InvalidStrategy(params.strategy);
        }
    }

    function _placeRangeOrders(
        IPoolManager.Pool memory pool,
        uint128[] memory tickPrices,
        uint128[] memory buyAmounts,
        uint128[] memory sellAmounts
    ) internal returns (uint48[] memory buyIds, uint48[] memory sellIds) {
        Storage storage $ = getStorage();
        IScaleXRouter router = IScaleXRouter($.router);

        buyIds = new uint48[](tickPrices.length);
        sellIds = new uint48[](tickPrices.length);

        for (uint256 i = 0; i < tickPrices.length; i++) {
            if (buyAmounts[i] > 0) {
                // Place buy order (Post-Only)
                uint128 quantity = uint128((uint256(buyAmounts[i]) * 1e8) / tickPrices[i]);
                buyIds[i] = router.placeLimitOrder(
                    pool,
                    tickPrices[i],
                    quantity,
                    IOrderBook.Side.BUY,
                    IOrderBook.TimeInForce.PO,
                    0 // No additional deposit
                );
            }

            if (sellAmounts[i] > 0) {
                // Place sell order (Post-Only)
                sellIds[i] = router.placeLimitOrder(
                    pool,
                    tickPrices[i],
                    sellAmounts[i],
                    IOrderBook.Side.SELL,
                    IOrderBook.TimeInForce.PO,
                    0 // No additional deposit
                );
            }
        }
    }

    function _cancelAllOrders(IOrderBook orderBook, uint48[] memory orderIds) internal {
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (orderIds[i] != 0) {
                try orderBook.cancelOrder(orderIds[i], address(this)) {
                    // Order cancelled successfully
                } catch {
                    // Order already filled or cancelled, skip
                }
            }
        }
    }

    function _getCurrentPrice(PoolKey memory poolKey, address orderBookAddress)
        internal
        view
        returns (uint128)
    {
        IOrderBook orderBook = IOrderBook(orderBookAddress);
        address oracleAddr = orderBook.oracle();

        if (oracleAddr != address(0)) {
            IOracle oracle = IOracle(oracleAddr);
            return uint128(oracle.getSpotPrice(Currency.unwrap(poolKey.baseCurrency)));
        }

        // Fallback: get mid price from orderbook
        IOrderBook.PriceVolume memory bestBid = orderBook.getBestPrice(IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestAsk = orderBook.getBestPrice(IOrderBook.Side.SELL);

        if (bestBid.price > 0 && bestAsk.price > 0) {
            return uint128((uint256(bestBid.price) + uint256(bestAsk.price)) / 2);
        }

        return bestBid.price > 0 ? bestBid.price : bestAsk.price;
    }

    function _getPositionBalances(uint256 positionId, PoolKey memory poolKey)
        internal
        view
        returns (uint256 baseBalance, uint256 quoteBalance)
    {
        Storage storage $ = getStorage();

        // Get free balances from position tracking
        baseBalance = $.positionBalances[positionId][Currency.unwrap(poolKey.baseCurrency)];
        quoteBalance = $.positionBalances[positionId][Currency.unwrap(poolKey.quoteCurrency)];

        // Add balances held in BalanceManager
        baseBalance += IBalanceManager($.balanceManager).getBalance(
            address(this),
            poolKey.baseCurrency
        );
        quoteBalance += IBalanceManager($.balanceManager).getBalance(
            address(this),
            poolKey.quoteCurrency
        );
    }

    function _calculateLockedInOrders(RangePosition storage position, IOrderBook orderBook)
        internal
        view
        returns (uint256 locked)
    {
        // Sum up locked amounts in all active orders
        for (uint256 i = 0; i < position.buyOrderIds.length; i++) {
            if (position.buyOrderIds[i] != 0) {
                IOrderBook.Order memory order = orderBook.getOrder(position.buyOrderIds[i]);
                if (order.status == IOrderBook.Status.OPEN || order.status == IOrderBook.Status.PARTIALLY_FILLED) {
                    uint128 unfilled = order.quantity - order.filled;
                    locked += (uint256(unfilled) * order.price) / 1e8;
                }
            }
        }

        for (uint256 i = 0; i < position.sellOrderIds.length; i++) {
            if (position.sellOrderIds[i] != 0) {
                IOrderBook.Order memory order = orderBook.getOrder(position.sellOrderIds[i]);
                if (order.status == IOrderBook.Status.OPEN || order.status == IOrderBook.Status.PARTIALLY_FILLED) {
                    locked += order.quantity - order.filled;
                }
            }
        }
    }
}
