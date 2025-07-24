// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import "./interfaces/IOrderBook.sol";

import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IOrderBookErrors} from "./interfaces/IOrderBookErrors.sol";
import "./interfaces/IPoolManager.sol";

import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";

import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {Currency} from "./libraries/Currency.sol";

import {PoolIdLibrary} from "./libraries/Pool.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IGTXRouter} from "./interfaces/IGTXRouter.sol";
import {GTXRouterStorage} from "./storages/GTXRouterStorage.sol";
import {Test, console} from "forge-std/Test.sol";

contract GTXRouter is IGTXRouter, GTXRouterStorage, Initializable, OwnableUpgradeable {
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
        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        Currency depositCurrency = (_side == IOrderBook.Side.BUY) ? pool.quoteCurrency : pool.baseCurrency;

        if (depositAmount > 0) {
            balanceManager.deposit(depositCurrency, depositAmount, msg.sender, msg.sender);
        }

        orderId = pool.orderBook.placeOrder(_price, _quantity, _side, msg.sender, _timeInForce);
    }

    function placeMarketOrder(
        IPoolManager.Pool calldata pool,
        uint128 _quantity,
        IOrderBook.Side _side,
        uint128 depositAmount,
        uint128 minOutAmount
    ) external returns (uint48 orderId, uint128 filled) {
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

        SlippageContext memory ctx = _makeSlippageContext(
            balanceManager,
            msg.sender,
            pool.baseCurrency,
            pool.quoteCurrency,
            _side,
            minOutAmount
        );

        (orderId, filled) = pool.orderBook.placeMarketOrder(_quantity, _side, msg.sender);

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

    function _checkSlippageDelta(SlippageContext memory ctx) private view {
        if (ctx.side == IOrderBook.Side.BUY) {
            uint256 baseReceived = ctx.balanceManager.getBalance(ctx.user, ctx.baseCurrency) - ctx.baseBalanceBefore;
            if (baseReceived < ctx.minOutAmount) {
                revert SlippageTooHigh(uint128(baseReceived), ctx.minOutAmount);
            }
        } else {
            uint256 quoteReceived = ctx.balanceManager.getBalance(ctx.user, ctx.quoteCurrency) - ctx.quoteBalanceBefore;
            if (quoteReceived < ctx.minOutAmount) {
                revert SlippageTooHigh(uint128(quoteReceived), ctx.minOutAmount);
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

    /// @notice Swaps tokens with automatic routing through intermediary pools
    function swap(
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        uint8 maxHops,
        address user
    ) external returns (uint256 receivedAmount) {
        if (Currency.unwrap(srcCurrency) == Currency.unwrap(dstCurrency)) {
            revert IdenticalCurrencies(Currency.unwrap(srcCurrency));
        }
        if (maxHops > 3) {
            revert TooManyHops(maxHops, 3);
        }
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        
        uint256 dstBalanceBefore = balanceManager.getBalance(user, dstCurrency);
        bool directSwapExecuted = false;
        
        if (poolManager.poolExists(srcCurrency, dstCurrency) && _hasLiquidity(poolManager, srcCurrency, dstCurrency)) {
            executeDirectSwap(srcCurrency, dstCurrency, srcCurrency, dstCurrency, srcAmount, minDstAmount, user);
            directSwapExecuted = true;
        } else if (poolManager.poolExists(dstCurrency, srcCurrency) && _hasLiquidity(poolManager, dstCurrency, srcCurrency)) {
            executeDirectSwap(dstCurrency, srcCurrency, srcCurrency, dstCurrency, srcAmount, minDstAmount, user);
            directSwapExecuted = true;
        }
        
        if (!directSwapExecuted) {
            Currency[] memory intermediaries = poolManager.getCommonIntermediaries();
            bool swapExecuted = false;
            for (uint256 i = 0; i < intermediaries.length && !swapExecuted; i++) {
                Currency intermediary = intermediaries[i];
                if (Currency.unwrap(intermediary) == Currency.unwrap(srcCurrency) ||
                    Currency.unwrap(intermediary) == Currency.unwrap(dstCurrency)) continue;
                
                if ((poolManager.poolExists(srcCurrency, intermediary) && poolManager.poolExists(intermediary, dstCurrency)) ||
                    (poolManager.poolExists(srcCurrency, intermediary) && poolManager.poolExists(dstCurrency, intermediary)) ||
                    (poolManager.poolExists(intermediary, srcCurrency) && poolManager.poolExists(dstCurrency, intermediary))) {
                    executeMultiHopSwap(srcCurrency, intermediary, dstCurrency, srcAmount, minDstAmount, user);
                    swapExecuted = true;
                }
            }
            if (!swapExecuted) {
                revert NoValidSwapPath(Currency.unwrap(srcCurrency), Currency.unwrap(dstCurrency));
            }
        }
        
        uint256 dstBalanceAfter = balanceManager.getBalance(user, dstCurrency);
        receivedAmount = dstBalanceAfter > dstBalanceBefore ? dstBalanceAfter - dstBalanceBefore : 0;
        
        if (receivedAmount > 0) {
            balanceManager.transferOut(user, user, dstCurrency, receivedAmount);
        } else {
            revert NoValidSwapPath(Currency.unwrap(srcCurrency), Currency.unwrap(dstCurrency));
        }
        
        return receivedAmount;
    }

    /// @notice Check if a pool has liquidity
    function _hasLiquidity(IPoolManager poolManager, Currency baseCurrency, Currency quoteCurrency) internal view returns (bool) {
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
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user
    ) internal {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        
        PoolKey memory key = poolManager.createPoolKey(baseCurrency, quoteCurrency);
        IOrderBook.Side side = Currency.unwrap(srcCurrency) == Currency.unwrap(baseCurrency) 
            ? IOrderBook.Side.SELL 
            : IOrderBook.Side.BUY;
        
        balanceManager.deposit(srcCurrency, srcAmount, msg.sender, user);
        _placeMarketOrderForSwap(key, srcAmount, side, user, uint128(minDstAmount));
    }

    /// @notice Execute multi-hop swap through intermediary
    function executeMultiHopSwap(
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
        
        if (poolManager.poolExists(srcCurrency, intermediary)) {
            executeSwapStep(srcCurrency, intermediary, srcCurrency, intermediary, srcAmount, 0, user, IOrderBook.Side.SELL);
        } else {
            executeSwapStep(srcCurrency, intermediary, intermediary, srcCurrency, srcAmount, 0, user, IOrderBook.Side.BUY);
        }
        
        uint256 intermediateBalanceAfter = balanceManager.getBalance(user, intermediary);
        uint256 intermediateAmount = intermediateBalanceAfter > intermediateBalanceBefore ? intermediateBalanceAfter - intermediateBalanceBefore : 0;
        
        if (intermediateAmount == 0) revert SwapHopFailed(1, intermediateAmount);
        
        if (poolManager.poolExists(dstCurrency, intermediary)) {
            executeSwapStep(intermediary, dstCurrency, dstCurrency, intermediary, intermediateAmount, minDstAmount, user, IOrderBook.Side.BUY);
        } else {
            executeSwapStep(intermediary, dstCurrency, intermediary, dstCurrency, intermediateAmount, minDstAmount, user, IOrderBook.Side.SELL);
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
        executeSwapStep(
            srcCurrency, intermediary, dstCurrency, srcCurrency, srcAmount, 0, user, IOrderBook.Side.SELL
        );
        uint256 intermediateBalanceAfter = balanceManager.getBalance(user, intermediary);
        uint256 intermediateAmount = intermediateBalanceAfter > intermediateBalanceBefore ? intermediateBalanceAfter - intermediateBalanceBefore : 0;
        
        if (intermediateAmount == 0) revert SwapHopFailed(1, intermediateAmount);
        
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
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        Currency depositCurrency = (side == IOrderBook.Side.BUY) ? pool.quoteCurrency : pool.baseCurrency;

        if (side == IOrderBook.Side.SELL) {
            uint256 userBalance = balanceManager.getBalance(user, depositCurrency);
            if (userBalance < quantity) {
                revert InsufficientSwapBalance(userBalance, quantity);
            }
            
            if (userBalance > 0 && userBalance > quantity) {
                balanceManager.lock(user, depositCurrency, userBalance - quantity);
            }
        }

        SlippageContext memory ctx = _makeSlippageContext(
            balanceManager,
            user,
            pool.baseCurrency,
            pool.quoteCurrency,
            side,
            minOutAmount
        );

        (orderId, filled) = pool.orderBook.placeMarketOrder(uint128(quantity), side, user);

        if (side == IOrderBook.Side.SELL) {
            uint256 userBalance = balanceManager.getBalance(user, depositCurrency);
            if (userBalance > 0 && userBalance > quantity) {
                balanceManager.unlock(user, depositCurrency, userBalance - quantity);
            }
        }

        _checkSlippageDelta(ctx);
        return (orderId, filled);
    }
}
