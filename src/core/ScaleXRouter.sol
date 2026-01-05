// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IOrderBookErrors} from "./interfaces/IOrderBookErrors.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {Currency} from "./libraries/Currency.sol";
import {PoolKey, PoolIdLibrary} from "./libraries/Pool.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IScaleXRouter} from "./interfaces/IScaleXRouter.sol";
import {ScaleXRouterStorage} from "./storages/ScaleXRouterStorage.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";

contract ScaleXRouter is IScaleXRouter, ScaleXRouterStorage, Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _poolManager, address _balanceManager) public initializer {
        __Ownable_init(msg.sender);
        Storage storage $ = getStorage();
        $.poolManager = _poolManager;
        $.balanceManager = _balanceManager;
    }

    function initializeWithLending(address _poolManager, address _balanceManager, address _lendingManager) public initializer {
        __Ownable_init(msg.sender);
        Storage storage $ = getStorage();
        $.poolManager = _poolManager;
        $.balanceManager = _balanceManager;
        $.lendingManager = _lendingManager;
    }

    function setLendingManager(address _lendingManager) external onlyOwner {
        getStorage().lendingManager = _lendingManager;
    }

    struct SlippageContext {
        IBalanceManager balanceManager;
        address user;
        Currency baseCurrency;
        Currency quoteCurrency;
        uint256 baseBalanceBefore;
        uint256 quoteBalanceBefore;
        IOrderBook.Side side;
        uint128 minOutAmount;
    }

    function placeLimitOrder(
        IPoolManager.Pool calldata pool,
        uint128 _price,
        uint128 _quantity,
        IOrderBook.Side _side,
        IOrderBook.TimeInForce _timeInForce,
        uint128 depositAmount
    ) external returns (uint48 orderId) {
        // Default to false for autoRepay and autoBorrow to maintain backward compatibility
        return _placeLimitOrderInternal(pool, _price, _quantity, _side, _timeInForce, depositAmount, false, false);
    }

    function placeLimitOrderWithFlags(
        IPoolManager.Pool calldata pool,
        uint128 _price,
        uint128 _quantity,
        IOrderBook.Side _side,
        IOrderBook.TimeInForce _timeInForce,
        uint128 depositAmount,
        bool autoRepay,
        bool autoBorrow
    ) external returns (uint48 orderId) {
        return _placeLimitOrderInternal(pool, _price, _quantity, _side, _timeInForce, depositAmount, autoRepay, autoBorrow);
    }

    function _placeLimitOrderInternal(
        IPoolManager.Pool calldata pool,
        uint128 _price,
        uint128 _quantity,
        IOrderBook.Side _side,
        IOrderBook.TimeInForce _timeInForce,
        uint128 depositAmount,
        bool autoRepay,
        bool autoBorrow
    ) internal returns (uint48 orderId) {
        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        Currency depositCurrency = (_side == IOrderBook.Side.BUY) ? pool.quoteCurrency : pool.baseCurrency;

        if (depositAmount > 0) {
            balanceManager.deposit(depositCurrency, depositAmount, msg.sender, msg.sender);
        }
        
        orderId = pool.orderBook.placeOrder(_price, _quantity, _side, msg.sender, _timeInForce, autoRepay, autoBorrow);
    }

    function placeMarketOrder(
        IPoolManager.Pool calldata pool,
        uint128 _quantity,
        IOrderBook.Side _side,
        uint128 depositAmount,
        uint128 minOutAmount
    ) external returns (uint48 orderId, uint128 filled) {
        // Default to false for autoRepay and autoBorrow to maintain backward compatibility
        return _placeMarketOrderInternal(pool, _quantity, _side, depositAmount, minOutAmount, false, false);
    }

    function placeMarketOrder(
        IPoolManager.Pool calldata pool,
        uint128 _quantity,
        IOrderBook.Side _side,
        uint128 depositAmount,
        uint128 minOutAmount,
        bool autoRepay,
        bool autoBorrow
    ) external returns (uint48 orderId, uint128 filled) {
        return _placeMarketOrderInternal(pool, _quantity, _side, depositAmount, minOutAmount, autoRepay, autoBorrow);
    }

    function _placeMarketOrderInternal(
        IPoolManager.Pool calldata pool,
        uint128 _quantity,
        IOrderBook.Side _side,
        uint128 depositAmount,
        uint128 minOutAmount,
        bool autoRepay,
        bool autoBorrow
    ) internal returns (uint48 orderId, uint128 filled) {
        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        Currency depositCurrency = (_side == IOrderBook.Side.BUY) ? pool.quoteCurrency : pool.baseCurrency;

        if (depositAmount > 0) {
            balanceManager.deposit(depositCurrency, depositAmount, msg.sender, msg.sender);
        }

        if (_side == IOrderBook.Side.SELL) {
            uint256 userBalance = balanceManager.getBalance(msg.sender, depositCurrency);
            if (userBalance < _quantity) {
                revert InsufficientSwapBalance(userBalance, _quantity);
            }

            if (userBalance > 0 && userBalance > _quantity) {
                balanceManager.lock(msg.sender, depositCurrency, userBalance - _quantity);
            }
        }

        SlippageContext memory ctx =
            _makeSlippageContext(balanceManager, msg.sender, pool.baseCurrency, pool.quoteCurrency, _side, minOutAmount);

        (orderId, filled) = pool.orderBook.placeMarketOrder(_quantity, _side, msg.sender, autoRepay, autoBorrow);

        if (_side == IOrderBook.Side.SELL) {
            uint256 userBalance = balanceManager.getBalance(msg.sender, depositCurrency);
            if (userBalance > 0 && userBalance > _quantity) {
                balanceManager.unlock(msg.sender, depositCurrency, userBalance - _quantity);
            }
        }

        _checkSlippageDelta(ctx);
    }

    function _makeSlippageContext(
        IBalanceManager balanceManager,
        address user,
        Currency baseCurrency,
        Currency quoteCurrency,
        IOrderBook.Side side,
        uint128 minOutAmount
    ) internal view returns (SlippageContext memory ctx) {
        ctx.balanceManager = balanceManager;
        ctx.user = user;
        ctx.baseCurrency = baseCurrency;
        ctx.quoteCurrency = quoteCurrency;
        ctx.baseBalanceBefore = balanceManager.getBalance(user, baseCurrency);
        ctx.quoteBalanceBefore = balanceManager.getBalance(user, quoteCurrency);
        ctx.side = side;
        ctx.minOutAmount = minOutAmount;
    }

    function _checkSlippageDelta(
        SlippageContext memory ctx
    ) private view {
        if (ctx.minOutAmount == 0) {
            return; // No slippage protection needed
        }
        
        uint256 baseBalanceAfter = ctx.balanceManager.getBalance(ctx.user, ctx.baseCurrency);
        uint256 quoteBalanceAfter = ctx.balanceManager.getBalance(ctx.user, ctx.quoteCurrency);
        
        uint256 baseDelta;
        uint256 quoteDelta;
        
        if (ctx.side == IOrderBook.Side.BUY) {
            // For BUY orders: user spends quote currency, receives base currency
            baseDelta = baseBalanceAfter > ctx.baseBalanceBefore ? 
                baseBalanceAfter - ctx.baseBalanceBefore : 0;
            quoteDelta = ctx.quoteBalanceBefore > quoteBalanceAfter ? 
                ctx.quoteBalanceBefore - quoteBalanceAfter : 0;
        } else {
            // For SELL orders: user spends base currency, receives quote currency  
            baseDelta = ctx.baseBalanceBefore > baseBalanceAfter ? 
                ctx.baseBalanceBefore - baseBalanceAfter : 0;
            quoteDelta = quoteBalanceAfter > ctx.quoteBalanceBefore ? 
                quoteBalanceAfter - ctx.quoteBalanceBefore : 0;
        }
        
        // Check if user received at least the minimum expected amount
        if (ctx.side == IOrderBook.Side.BUY) {
            if (baseDelta < ctx.minOutAmount) {
                revert SlippageTooHigh(baseDelta, ctx.minOutAmount);
            }
        } else {
            if (quoteDelta < ctx.minOutAmount) {
                revert SlippageTooHigh(quoteDelta, ctx.minOutAmount);
            }
        }
    }

    function cancelOrder(IPoolManager.Pool memory pool, uint48 orderId) external {
        pool.orderBook.cancelOrder(orderId, msg.sender);
    }

    function withdraw(Currency, uint256) external {}

    function batchCancelOrders(IPoolManager.Pool calldata, uint48[] calldata) external pure override {}

    function getBestPrice(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        IOrderBook.Side side
    ) external view returns (IOrderBook.PriceVolume memory) {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        PoolKey memory key = poolManager.createPoolKey(_baseCurrency, _quoteCurrency);
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return pool.orderBook.getBestPrice(side);
    }

    function getOrderQueue(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        IOrderBook.Side side,
        uint128 price
    ) external view returns (uint48 orderCount, uint256 totalVolume) {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        PoolKey memory key = poolManager.createPoolKey(_baseCurrency, _quoteCurrency);
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return IOrderBook(pool.orderBook).getOrderQueue(side, price);
    }

    function getOrder(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        uint48 orderId
    ) external view returns (IOrderBook.Order memory) {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        PoolKey memory key = poolManager.createPoolKey(_baseCurrency, _quoteCurrency);
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return IOrderBook(pool.orderBook).getOrder(orderId);
    }

    function calculateMinOutAmountForMarket(
        IPoolManager.Pool memory pool,
        uint256 inputAmount,
        IOrderBook.Side side,
        uint256 slippageToleranceBps
    ) public view returns (uint128 minOutputAmount) {
        if (slippageToleranceBps > 10_000) {
            revert InvalidSlippageTolerance(slippageToleranceBps);
        }

        if (inputAmount == 0) {
            return 0;
        }

        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);

        IOrderBook.Side oppositeSide = side == IOrderBook.Side.BUY ? IOrderBook.Side.SELL : IOrderBook.Side.BUY;
        IOrderBook.PriceVolume[] memory oppositePrices = pool.orderBook.getNextBestPrices(oppositeSide, 0, 100);

        
        uint256 totalOutputReceived = _calculateOutputFromPrices(pool, oppositePrices, inputAmount, side);

        if (totalOutputReceived == 0) {
            return 0;
        }

        return _calculateMinOutputWithFeesAndSlippage(balanceManager, totalOutputReceived, slippageToleranceBps);
    }

    function _calculateOutputFromPrices(
        IPoolManager.Pool memory pool,
        IOrderBook.PriceVolume[] memory oppositePrices,
        uint256 inputAmount,
        IOrderBook.Side side
    ) internal view returns (uint256 totalOutputReceived) {
        uint256 remainingInput = inputAmount;

        for (uint256 i = 0; i < oppositePrices.length && remainingInput > 0; i++) {
            IOrderBook.PriceVolume memory priceLevel = oppositePrices[i];

            if (priceLevel.price == 0 || priceLevel.volume == 0) {
                break;
            }

            uint256 outputToReceive = _calculateOutputForPriceLevel(pool, priceLevel, remainingInput, side);

            totalOutputReceived += outputToReceive;
            remainingInput = _updateRemainingInput(pool, priceLevel, remainingInput, side);
        }
    }

    function _calculateOutputForPriceLevel(
        IPoolManager.Pool memory pool,
        IOrderBook.PriceVolume memory priceLevel,
        uint256 remainingInput,
        IOrderBook.Side side
    ) internal view returns (uint256 outputToReceive) {
        if (side == IOrderBook.Side.BUY) {
            uint256 quoteNeededForLevel =
                PoolIdLibrary.baseToQuote(priceLevel.volume, priceLevel.price, pool.baseCurrency.decimals());

            if (quoteNeededForLevel <= remainingInput) {
                outputToReceive = priceLevel.volume;
            } else {
                outputToReceive =
                    PoolIdLibrary.quoteToBase(remainingInput, priceLevel.price, pool.baseCurrency.decimals());
            }
        } else {
            uint256 baseToSell = priceLevel.volume <= remainingInput ? priceLevel.volume : remainingInput;

            outputToReceive = PoolIdLibrary.baseToQuote(baseToSell, priceLevel.price, pool.baseCurrency.decimals());
        }
    }

    function _updateRemainingInput(
        IPoolManager.Pool memory pool,
        IOrderBook.PriceVolume memory priceLevel,
        uint256 remainingInput,
        IOrderBook.Side side
    ) internal view returns (uint256) {
        if (side == IOrderBook.Side.BUY) {
            uint256 quoteNeededForLevel =
                PoolIdLibrary.baseToQuote(priceLevel.volume, priceLevel.price, pool.baseCurrency.decimals());

            return quoteNeededForLevel <= remainingInput ? remainingInput - quoteNeededForLevel : 0;
        } else {
            return priceLevel.volume <= remainingInput ? remainingInput - priceLevel.volume : 0;
        }
    }

    function _calculateMinOutputWithFeesAndSlippage(
        IBalanceManager balanceManager,
        uint256 totalOutputReceived,
        uint256 slippageToleranceBps
    ) internal view returns (uint128) {
        uint256 feeTaker = balanceManager.feeTaker();
        uint256 feeUnit = balanceManager.getFeeUnit();
        uint256 feeAmount = (totalOutputReceived * feeTaker) / feeUnit;

        uint256 outputAfterFees = totalOutputReceived > feeAmount ? totalOutputReceived - feeAmount : 0;

        uint256 slippageAmount = (outputAfterFees * slippageToleranceBps) / 10_000;
        return uint128(outputAfterFees - slippageAmount);
    }

    function getNextBestPrices(
        IPoolManager.Pool memory pool,
        IOrderBook.Side side,
        uint128 price,
        uint8 count
    ) external view returns (IOrderBook.PriceVolume[] memory) {
        return pool.orderBook.getNextBestPrices(side, price, count);
    }

    /// Calculate minimum output amount for swap operations
    function calculateMinOutForSwap(
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 inputAmount,
        uint256 slippageToleranceBps
    ) external view returns (uint128 minOutputAmount) {
        if (Currency.unwrap(srcCurrency) == Currency.unwrap(dstCurrency)) {
            revert IdenticalCurrencies(Currency.unwrap(srcCurrency));
        }
        if (slippageToleranceBps > 10_000) {
            revert InvalidSlippageTolerance(slippageToleranceBps);
        }
        if (inputAmount == 0) {
            return 0;
        }

        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);

        // Try direct swap first
        if (poolManager.poolExists(srcCurrency, dstCurrency)) {
            return _calculateDirectSwapMinOut(srcCurrency, dstCurrency, srcCurrency, inputAmount, slippageToleranceBps);
        } else if (poolManager.poolExists(dstCurrency, srcCurrency)) {
            return _calculateDirectSwapMinOut(dstCurrency, srcCurrency, srcCurrency, inputAmount, slippageToleranceBps);
        }

        // Try multi-hop via common intermediaries
        Currency[] memory intermediaries = poolManager.getCommonIntermediaries();

        for (uint256 i = 0; i < intermediaries.length; i++) {
            Currency intermediary = intermediaries[i];
            if (
                Currency.unwrap(intermediary) == Currency.unwrap(srcCurrency)
                    || Currency.unwrap(intermediary) == Currency.unwrap(dstCurrency)
            ) {
                continue;
            }

            if (_canSwapViaIntermediary(poolManager, srcCurrency, intermediary, dstCurrency)) {
                return _calculateMultiHopMinOut(
                    poolManager, srcCurrency, intermediary, dstCurrency, inputAmount, slippageToleranceBps
                );
            }
        }

        return 0; // No valid swap path found
    }

    /// @dev Calculate minimum output for direct swap
    function _calculateDirectSwapMinOut(
        Currency baseCurrency,
        Currency quoteCurrency,
        Currency srcCurrency,
        uint256 inputAmount,
        uint256 slippageToleranceBps
    ) internal view returns (uint128) {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);

        PoolKey memory key = poolManager.createPoolKey(baseCurrency, quoteCurrency);
        IPoolManager.Pool memory pool = poolManager.getPool(key);

        // Determine side: if we're selling the base currency, it's a SELL order
        // If we're buying the base currency with quote currency, it's a BUY order
        IOrderBook.Side side =
            Currency.unwrap(srcCurrency) == Currency.unwrap(baseCurrency) ? IOrderBook.Side.SELL : IOrderBook.Side.BUY;

        return calculateMinOutAmountForMarket(pool, inputAmount, side, slippageToleranceBps);
    }

    /// @dev Calculate minimum output for multi-hop swap
    function _calculateMultiHopMinOut(
        IPoolManager poolManager,
        Currency srcCurrency,
        Currency intermediateCurrency,
        Currency dstCurrency,
        uint256 inputAmount,
        uint256 slippageToleranceBps
    ) internal view returns (uint128) {
        // Split slippage tolerance across both hops
        uint256 slippagePerHop = slippageToleranceBps / 2;

        // First hop: calculate intermediate amount
        uint128 intermediateAmount;
        if (poolManager.poolExists(srcCurrency, intermediateCurrency)) {
            intermediateAmount =
                _calculateDirectSwapMinOut(srcCurrency, intermediateCurrency, srcCurrency, inputAmount, slippagePerHop);
        } else if (poolManager.poolExists(intermediateCurrency, srcCurrency)) {
            intermediateAmount =
                _calculateDirectSwapMinOut(intermediateCurrency, srcCurrency, srcCurrency, inputAmount, slippagePerHop);
        } else {
            return 0; // First hop not possible
        }

        // Second hop: calculate final amount
        if (poolManager.poolExists(intermediateCurrency, dstCurrency)) {
            return _calculateDirectSwapMinOut(
                intermediateCurrency, dstCurrency, intermediateCurrency, intermediateAmount, slippagePerHop
            );
        } else if (poolManager.poolExists(dstCurrency, intermediateCurrency)) {
            return _calculateDirectSwapMinOut(
                dstCurrency, intermediateCurrency, intermediateCurrency, intermediateAmount, slippagePerHop
            );
        } else {
            return 0; // Second hop not possible
        }
    }

    /// @dev Check if swap is possible via intermediary
    function _canSwapViaIntermediary(
        IPoolManager poolManager,
        Currency srcCurrency,
        Currency intermediary,
        Currency dstCurrency
    ) internal view returns (bool) {
        bool firstHopExists =
            poolManager.poolExists(srcCurrency, intermediary) || poolManager.poolExists(intermediary, srcCurrency);
        bool secondHopExists =
            poolManager.poolExists(intermediary, dstCurrency) || poolManager.poolExists(dstCurrency, intermediary);

        return firstHopExists && secondHopExists;
    }

    /// @notice Swaps tokens with automatic routing through intermediary pools
    /// @dev Default behavior: deposits from wallet and transfers output to wallet
    function swap(
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        uint8 maxHops,
        address user
    ) external returns (uint256 receivedAmount) {
        // Default behavior: deposit the full srcAmount from user's wallet, transfer out to wallet
        return swap(srcCurrency, dstCurrency, srcAmount, minDstAmount, maxHops, user, srcAmount, false);
    }

    /// @notice Swaps tokens with automatic routing and optional deposit
    /// @dev Output is transferred to user's wallet
    /// @param srcCurrency Source token currency
    /// @param dstCurrency Destination token currency
    /// @param srcAmount Amount of source tokens to swap
    /// @param minDstAmount Minimum amount of destination tokens to receive
    /// @param maxHops Maximum number of hops for multi-hop swaps
    /// @param user User address to execute swap for
    /// @param depositAmount Amount to deposit from wallet (0 = use existing balance)
    function swap(
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        uint8 maxHops,
        address user,
        uint256 depositAmount
    ) public returns (uint256 receivedAmount) {
        return swap(srcCurrency, dstCurrency, srcAmount, minDstAmount, maxHops, user, depositAmount, false);
    }

    /// @notice Swaps tokens with automatic routing, optional deposit, and optional output destination
    /// @param srcCurrency Source token currency
    /// @param dstCurrency Destination token currency
    /// @param srcAmount Amount of source tokens to swap
    /// @param minDstAmount Minimum amount of destination tokens to receive
    /// @param maxHops Maximum number of hops for multi-hop swaps
    /// @param user User address to execute swap for
    /// @param depositAmount Amount to deposit from wallet (0 = use existing balance)
    /// @param keepInBalance If true, keeps output in BalanceManager; if false, transfers to wallet
    function swap(
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        uint8 maxHops,
        address user,
        uint256 depositAmount,
        bool keepInBalance
    ) public returns (uint256 receivedAmount) {
        if (Currency.unwrap(srcCurrency) == Currency.unwrap(dstCurrency)) {
            revert IdenticalCurrencies(Currency.unwrap(srcCurrency));
        }
        if (maxHops > 3) {
            revert TooManyHops(maxHops, 3);
        }

        return _executeSwap(srcCurrency, dstCurrency, srcAmount, minDstAmount, user, depositAmount, keepInBalance);
    }

    /// @dev Internal function to execute swap logic with reduced stack depth
    function _executeSwap(
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user,
        uint256 depositAmount,
        bool keepInBalance
    ) internal returns (uint256 receivedAmount) {
        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);

        uint256 dstBalanceBefore = balanceManager.getBalance(user, dstCurrency);

        // Try direct swap first
        if (_tryDirectSwap(srcCurrency, dstCurrency, srcAmount, minDstAmount, user, depositAmount)) {
            return _calculateReceivedAmount(balanceManager, user, dstCurrency, dstBalanceBefore, keepInBalance);
        }

        // Try multi-hop swap
        if (_tryMultiHopSwap(srcCurrency, dstCurrency, srcAmount, minDstAmount, user, depositAmount)) {
            return _calculateReceivedAmount(balanceManager, user, dstCurrency, dstBalanceBefore, keepInBalance);
        }

        revert NoValidSwapPath(Currency.unwrap(srcCurrency), Currency.unwrap(dstCurrency));
    }

    /// @dev Try direct swap between two currencies
    function _tryDirectSwap(
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user,
        uint256 depositAmount
    ) internal returns (bool success) {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);

        if (poolManager.poolExists(srcCurrency, dstCurrency) && _hasLiquidity(poolManager, srcCurrency, dstCurrency)) {
            executeDirectSwap(srcCurrency, dstCurrency, srcCurrency, dstCurrency, srcAmount, minDstAmount, user, depositAmount);
            return true;
        } else if (
            poolManager.poolExists(dstCurrency, srcCurrency) && _hasLiquidity(poolManager, dstCurrency, srcCurrency)
        ) {
            executeDirectSwap(dstCurrency, srcCurrency, srcCurrency, dstCurrency, srcAmount, minDstAmount, user, depositAmount);
            return true;
        }

        return false;
    }

    /// @dev Try multi-hop swap through intermediary currencies
    function _tryMultiHopSwap(
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user,
        uint256 depositAmount
    ) internal returns (bool success) {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);

        Currency[] memory intermediaries = poolManager.getCommonIntermediaries();

        for (uint256 i = 0; i < intermediaries.length; i++) {
            Currency intermediary = intermediaries[i];
            if (
                Currency.unwrap(intermediary) == Currency.unwrap(srcCurrency)
                    || Currency.unwrap(intermediary) == Currency.unwrap(dstCurrency)
            ) {
                continue;
            }

            if (_canExecuteMultiHop(poolManager, srcCurrency, intermediary, dstCurrency)) {
                executeMultiHopSwap(srcCurrency, intermediary, dstCurrency, srcAmount, minDstAmount, user, depositAmount);
                return true;
            }
        }

        return false;
    }

    /// @dev Check if multi-hop swap is possible through intermediary
    function _canExecuteMultiHop(
        IPoolManager poolManager,
        Currency srcCurrency,
        Currency intermediary,
        Currency dstCurrency
    ) internal view returns (bool) {
        return (poolManager.poolExists(srcCurrency, intermediary) && poolManager.poolExists(intermediary, dstCurrency))
            || (poolManager.poolExists(srcCurrency, intermediary) && poolManager.poolExists(dstCurrency, intermediary))
            || (poolManager.poolExists(intermediary, srcCurrency) && poolManager.poolExists(dstCurrency, intermediary));
    }

    /// @dev Calculate received amount and optionally transfer to user's wallet
    /// @param keepInBalance If true, keeps output in BalanceManager; if false, transfers to wallet
    function _calculateReceivedAmount(
        IBalanceManager balanceManager,
        address user,
        Currency dstCurrency,
        uint256 dstBalanceBefore,
        bool keepInBalance
    ) internal returns (uint256 receivedAmount) {
        uint256 dstBalanceAfter = balanceManager.getBalance(user, dstCurrency);
        receivedAmount = dstBalanceAfter > dstBalanceBefore ? dstBalanceAfter - dstBalanceBefore : 0;

        if (receivedAmount > 0) {
            // Only transfer out if keepInBalance is false
            if (!keepInBalance) {
                balanceManager.transferOut(user, user, dstCurrency, receivedAmount);
            }
        } else {
            revert NoValidSwapPath(Currency.unwrap(dstCurrency), Currency.unwrap(dstCurrency));
        }

        return receivedAmount;
    }

    /// @notice Check if a pool has liquidity
    function _hasLiquidity(
        IPoolManager poolManager,
        Currency baseCurrency,
        Currency quoteCurrency
    ) internal view returns (bool) {
        PoolKey memory key = poolManager.createPoolKey(baseCurrency, quoteCurrency);
        IPoolManager.Pool memory pool = poolManager.getPool(key);

        IOrderBook.PriceVolume memory buyPrice = pool.orderBook.getBestPrice(IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory sellPrice = pool.orderBook.getBestPrice(IOrderBook.Side.SELL);

        return (buyPrice.price > 0 && buyPrice.volume > 0) || (sellPrice.price > 0 && sellPrice.volume > 0);
    }

    /// @notice Execute direct swap between two currencies
    function executeDirectSwap(
        Currency baseCurrency,
        Currency quoteCurrency,
        Currency srcCurrency,
        Currency /* dstCurrency */,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user,
        uint256 depositAmount
    ) internal {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);

        PoolKey memory key = poolManager.createPoolKey(baseCurrency, quoteCurrency);
        IOrderBook.Side side =
            Currency.unwrap(srcCurrency) == Currency.unwrap(baseCurrency) ? IOrderBook.Side.SELL : IOrderBook.Side.BUY;

        if (depositAmount > 0) {
            balanceManager.deposit(srcCurrency, depositAmount, msg.sender, user);
        }
        _placeMarketOrderForSwap(key, srcAmount, side, user, uint128(minDstAmount));
    }

    /// @notice Execute multi-hop swap through intermediary
    function executeMultiHopSwap(
        Currency srcCurrency,
        Currency intermediary,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user,
        uint256 depositAmount
    ) internal {
        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        IPoolManager poolManager = IPoolManager($.poolManager);

        if (depositAmount > 0) {
            balanceManager.deposit(srcCurrency, depositAmount, msg.sender, user);
        }

        uint256 intermediateBalanceBefore = balanceManager.getBalance(user, intermediary);

        if (poolManager.poolExists(srcCurrency, intermediary)) {
            executeSwapStep(
                srcCurrency, intermediary, srcCurrency, intermediary, srcAmount, 0, user, IOrderBook.Side.SELL
            );
        } else {
            executeSwapStep(
                srcCurrency, intermediary, intermediary, srcCurrency, srcAmount, 0, user, IOrderBook.Side.BUY
            );
        }

        uint256 intermediateBalanceAfter = balanceManager.getBalance(user, intermediary);
        uint256 intermediateAmount = intermediateBalanceAfter > intermediateBalanceBefore
            ? intermediateBalanceAfter - intermediateBalanceBefore
            : 0;

        if (intermediateAmount == 0) {
            revert SwapHopFailed(1, intermediateAmount);
        }

        if (poolManager.poolExists(dstCurrency, intermediary)) {
            executeSwapStep(
                intermediary,
                dstCurrency,
                dstCurrency,
                intermediary,
                intermediateAmount,
                minDstAmount,
                user,
                IOrderBook.Side.BUY
            );
        } else {
            executeSwapStep(
                intermediary,
                dstCurrency,
                intermediary,
                dstCurrency,
                intermediateAmount,
                minDstAmount,
                user,
                IOrderBook.Side.SELL
            );
        }
    }

    /// @notice Execute single swap step
    function executeSwapStep(
        Currency, /* srcCurrency */
        Currency, /* dstCurrency */
        Currency baseCurrency,
        Currency quoteCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user,
        IOrderBook.Side side
    ) internal {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        PoolKey memory key = poolManager.createPoolKey(baseCurrency, quoteCurrency);
        _placeMarketOrderForSwap(key, srcAmount, side, user, uint128(minDstAmount));
    }

    /// @notice Execute reverse multi-hop swap
    function executeReverseMultiHopSwap(
        Currency srcCurrency,
        Currency intermediary,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user
    ) internal {
        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        IPoolManager poolManager = IPoolManager($.poolManager);

        balanceManager.deposit(srcCurrency, srcAmount, msg.sender, user);

        uint256 intermediateBalanceBefore = balanceManager.getBalance(user, intermediary);
        executeSwapStep(srcCurrency, intermediary, dstCurrency, srcCurrency, srcAmount, 0, user, IOrderBook.Side.SELL);
        uint256 intermediateBalanceAfter = balanceManager.getBalance(user, intermediary);
        uint256 intermediateAmount = intermediateBalanceAfter > intermediateBalanceBefore
            ? intermediateBalanceAfter - intermediateBalanceBefore
            : 0;

        if (intermediateAmount == 0) {
            revert SwapHopFailed(1, intermediateAmount);
        }

        PoolKey memory reverseKey = poolManager.createPoolKey(dstCurrency, intermediary);
        _placeMarketOrderForSwap(reverseKey, intermediateAmount, IOrderBook.Side.BUY, user, uint128(minDstAmount));
    }

    /// @notice Place market order for swap operations
    function _placeMarketOrderForSwap(
        PoolKey memory key,
        uint256 quantity,
        IOrderBook.Side side,
        address user,
        uint128 minOutAmount
    ) internal returns (uint48 orderId, uint128 filled) {
        return _executePlaceMarketOrder(key, quantity, side, user, minOutAmount);
    }

    /// @dev Internal helper to execute market order placement with reduced stack depth
    function _executePlaceMarketOrder(
        PoolKey memory key,
        uint256 quantity,
        IOrderBook.Side side,
        address user,
        uint128 minOutAmount
    ) internal returns (uint48 orderId, uint128 filled) {
        Storage storage $ = getStorage();
        IPoolManager.Pool memory pool = IPoolManager($.poolManager).getPool(key);
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);

        Currency depositCurrency = (side == IOrderBook.Side.BUY) ? pool.quoteCurrency : pool.baseCurrency;

        // Handle pre-order balance locking for SELL orders
        if (side == IOrderBook.Side.SELL) {
            _handleSellOrderPreLock(balanceManager, user, depositCurrency, quantity);
        }

        // Create slippage context and execute order
        SlippageContext memory ctx =
            _makeSlippageContext(balanceManager, user, pool.baseCurrency, pool.quoteCurrency, side, minOutAmount);

        (orderId, filled) = pool.orderBook.placeMarketOrder(uint128(quantity), side, user, false, false);

        // Handle post-order balance unlocking for SELL orders
        if (side == IOrderBook.Side.SELL) {
            _handleSellOrderPostUnlock(balanceManager, user, depositCurrency, quantity);
        }

        _checkSlippageDelta(ctx);
        return (orderId, filled);
    }

    /// @dev Handle balance locking before SELL order
    function _handleSellOrderPreLock(
        IBalanceManager balanceManager,
        address user,
        Currency depositCurrency,
        uint256 quantity
    ) internal {
        uint256 userBalance = balanceManager.getBalance(user, depositCurrency);
        if (userBalance < quantity) {
            revert InsufficientSwapBalance(userBalance, quantity);
        }

        if (userBalance > quantity) {
            balanceManager.lock(user, depositCurrency, userBalance - quantity);
        }
    }

    /// @dev Handle balance unlocking after SELL order
    function _handleSellOrderPostUnlock(
        IBalanceManager balanceManager,
        address user,
        Currency depositCurrency,
        uint256 quantity
    ) internal {
        uint256 userBalance = balanceManager.getBalance(user, depositCurrency);
        if (userBalance > quantity) {
            balanceManager.unlock(user, depositCurrency, userBalance - quantity);
        }
    }

    // =============================================================
    //                   LENDING MANAGER FUNCTIONS
    // =============================================================

    function borrow(address token, uint256 amount) external {
        Storage storage $ = getStorage();

        if ($.balanceManager == address(0)) revert BalanceManagerNotSet();

        // Call BalanceManager which will delegate to LendingManager
        // Let errors bubble up directly for better error visibility
        IBalanceManager($.balanceManager).borrowForUser(msg.sender, token, amount);
    }

    function repay(address token, uint256 amount) external {
        Storage storage $ = getStorage();
        
        if ($.balanceManager == address(0)) revert BalanceManagerNotSet();
        
        // Pull tokens from user to this contract first
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        // Transfer tokens to BalanceManager
        IERC20(token).transfer($.balanceManager, amount);
        
        // Call BalanceManager which will delegate to LendingManager
        try IBalanceManager($.balanceManager).repayForUser(msg.sender, token, amount) {
            // Success - repayment completed
        } catch {
            revert RepayFailed();
        }
    }

    function deposit(address token, uint256 amount) external {
        Storage storage $ = getStorage();
        
        if ($.balanceManager == address(0)) revert BalanceManagerNotSet();
        
        // Pull tokens from user to this contract first
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        // Approve BalanceManager to spend tokens from this contract
        IERC20(token).approve($.balanceManager, amount);
        
        // Call BalanceManager's depositLocal which will transfer tokens from this contract
        try IBalanceManager($.balanceManager).depositLocal(token, amount, msg.sender) {
            // Success - deposit completed
        } catch {
            revert DepositFailed();
        }
    }

    function liquidate(
        address borrower,
        address debtToken,
        address collateralToken,
        uint256 debtToCover
    ) external {
        Storage storage $ = getStorage();
        if ($.lendingManager == address(0)) revert LendingManagerNotSet();

        // Transfer debt tokens from liquidator to router first
        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), debtToCover);

        // Approve LendingManager to spend the tokens
        IERC20(debtToken).forceApprove($.lendingManager, debtToCover);

        try ILendingManager($.lendingManager).liquidate(borrower, debtToken, collateralToken, debtToCover) {
            // Transfer any collateral received to the liquidator
            // (LendingManager transfers collateral to the router as msg.sender)
            uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(this));
            if (collateralBalance > 0) {
                IERC20(collateralToken).safeTransfer(msg.sender, collateralBalance);
            }

            // Reset approval to 0 for security
            IERC20(debtToken).forceApprove($.lendingManager, 0);
        } catch {
            // Return tokens to liquidator on failure
            IERC20(debtToken).safeTransfer(msg.sender, debtToCover);
            revert LiquidationFailed();
        }
    }

    // =============================================================
    //                   LENDING VIEW FUNCTIONS
    // =============================================================

    function getUserSupply(address user, address token) external view returns (uint256) {
        Storage storage $ = getStorage();
        if ($.lendingManager == address(0)) return 0;
        
        try ILendingManager($.lendingManager).getUserSupply(user, token) returns (uint256 result) {
            return result;
        } catch {
            return 0;
        }
    }

    function getUserDebt(address user, address token) external view returns (uint256) {
        Storage storage $ = getStorage();
        if ($.lendingManager == address(0)) return 0;
        
        try ILendingManager($.lendingManager).getUserDebt(user, token) returns (uint256 result) {
            return result;
        } catch {
            return 0;
        }
    }

    function getHealthFactor(address user) external view returns (uint256) {
        Storage storage $ = getStorage();
        if ($.lendingManager == address(0)) return 0;
        
        try ILendingManager($.lendingManager).getHealthFactor(user) returns (uint256 result) {
            return result;
        } catch {
            return 0;
        }
    }

    function getGeneratedInterest(address token) external view returns (uint256) {
        Storage storage $ = getStorage();
        if ($.lendingManager == address(0)) return 0;
        
        try ILendingManager($.lendingManager).getGeneratedInterest(token) returns (uint256 result) {
            return result;
        } catch {
            return 0;
        }
    }

    function getAvailableLiquidity(address token) external view returns (uint256) {
        Storage storage $ = getStorage();
        if ($.lendingManager == address(0)) return 0;
        
        try ILendingManager($.lendingManager).getAvailableLiquidity(token) returns (uint256 result) {
            return result;
        } catch {
            return 0;
        }
    }

    function lendingManager() external view returns (address) {
        return getStorage().lendingManager;
    }
}
