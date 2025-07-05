// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
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


contract GTXRouter is IGTXRouter, GTXRouterStorage, Initializable, OwnableUpgradeable, IOrderBookErrors {
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

    function placeOrder(
        IPoolManager.Pool memory pool,
        uint128 _price,
        uint128 _quantity,
        IOrderBook.Side _side,
        IOrderBook.TimeInForce _timeInForce
    ) public returns (uint48 orderId) {
        orderId = _placeLimitOrder(pool, _price, _quantity, _side, _timeInForce, false, msg.sender);
    }

    function placeOrderWithDeposit(
        IPoolManager.Pool memory pool,
        uint128 _price,
        uint128 _quantity,
        IOrderBook.Side _side,
        IOrderBook.TimeInForce _timeInForce
    ) external returns (uint48 orderId) {
        orderId = _placeLimitOrder(pool, _price, _quantity, _side, _timeInForce, true, msg.sender);
    }


    function _validateCallerBalance(
        IPoolManager.Pool memory pool,
        address _caller,
        IOrderBook.Side _side,
        uint128 _quantity,
        uint128 _price,
        bool _isMarketOrder,
        bool _isWalletDeposit
    ) internal view returns (Currency, uint256) {
        Currency depositCurrency;
        uint256 requiredBalance;

        if (_side == IOrderBook.Side.BUY) {
            depositCurrency = pool.quoteCurrency;
            uint128 price;

            if (_isMarketOrder) {
                price = pool.orderBook.getBestPrice(IOrderBook.Side.SELL).price;
            } else {
                price = _price;
            }

            // Calculate required USDC based on ETH quantity and price
            requiredBalance = PoolIdLibrary.baseToQuote(_quantity, price, pool.baseCurrency.decimals());
        } else {
            // For market SELL orders, user must deposit base currency (e.g., ETH)
            depositCurrency = pool.baseCurrency;
            requiredBalance = _quantity;
        }

        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);

        // Check balance in the balance manager or wallet
        uint256 currentBalance = _isWalletDeposit
            ? IERC20(Currency.unwrap(depositCurrency)).balanceOf(_caller)
            : balanceManager.getBalance(_caller, depositCurrency);

        if (currentBalance < requiredBalance) {
            revert InsufficientBalance(requiredBalance, currentBalance);
        }

        return (depositCurrency, requiredBalance);
    }

    function _placeLimitOrder(
        IPoolManager.Pool memory pool,
        uint128 _price,
        uint128 _quantity,
        IOrderBook.Side _side,
        IOrderBook.TimeInForce _timeInForce,
        bool depositTokens,
        address _user
    ) internal returns (uint48 orderId) {
        //TODO: Immediately deposit and lock balance for limit order

        (Currency depositCurrency, uint256 requiredBalance) =
                        _validateCallerBalance(pool, _user, _side, _quantity, _price, false, depositTokens);

        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);

        if (depositTokens) {
            balanceManager.deposit(depositCurrency, requiredBalance, _user, _user);
        }

        orderId = pool.orderBook.placeOrder(_price, _quantity, _side, _user, _timeInForce);
    }

    function _placeMarketOrder(
        IPoolManager.Pool memory pool,
        uint128 quantity,
        IOrderBook.Side side,
        address user
    ) internal returns (uint48 orderId, uint128 filled) {
        (orderId, filled) = pool.orderBook.placeMarketOrder(quantity, side, user);
    }

    function placeMarketOrder(
        IPoolManager.Pool memory pool,
        uint128 _quantity,
        IOrderBook.Side _side,
        uint128 minOutAmount
    ) public returns (uint48 orderId, uint128 filled) {
        _validateCallerBalance(pool, msg.sender, _side, _quantity, 0, true, false);
        return _placeMarketOrder(pool, _quantity, _side, msg.sender);
    }

    /**
     * @notice Place a market order specifically for swap operations, ensuring quantity is in base asset
     * @param key The pool key
     * @param amount The amount in source currency (base for SELL, quote for BUY)
     * @param side The side of the order
     * @param user The user address
     * @return orderId The ID of the placed order
     */
    function _placeMarketOrderForSwap(
        PoolKey memory key,
        uint256 amount,
        IOrderBook.Side side,
        address user,
        uint128 minOutAmount
    ) internal returns (uint48 orderId, uint128 filled) {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        uint128 quantity;
        if (side == IOrderBook.Side.SELL) {
            quantity = uint128(amount);
        } else {
            IOrderBook.PriceVolume memory bestPrice = pool.orderBook.getBestPrice(IOrderBook.Side.SELL);
            if (bestPrice.price == 0) {
                revert OrderHasNoLiquidity();
            }
            uint256 baseAmount = PoolIdLibrary.quoteToBase(amount, bestPrice.price, pool.baseCurrency.decimals());
            quantity = uint128(baseAmount);
        }
        if (quantity == 0) {
            revert InvalidQuantity();
        }
        return placeMarketOrder(pool, quantity, side, minOutAmount);
    }
    function placeMarketOrderWithDeposit(
        IPoolManager.Pool memory pool,
        uint128 _quantity,
        IOrderBook.Side _side,
        uint128 minOutAmount,
        uint128 depositAmount,
        uint128 maxBalanceAllowed
    ) external returns (uint48 orderId, uint128 filled) {
        Currency depositCurrency = (_side == IOrderBook.Side.BUY) ? pool.quoteCurrency : pool.baseCurrency;

        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);

        console.log("Deposit amount:", depositAmount);

        balanceManager.deposit(depositCurrency, depositAmount, msg.sender, msg.sender);

        uint256 userBalance = balanceManager.getBalance(msg.sender, depositCurrency);

        if (userBalance > 0 && userBalance > maxBalanceAllowed) {
            balanceManager.lock(msg.sender, depositCurrency, userBalance - maxBalanceAllowed);
        }

        (orderId, filled) = _placeMarketOrder(pool, _quantity, _side, msg.sender);

        if (userBalance > 0 && userBalance > maxBalanceAllowed) {
            balanceManager.unlock(msg.sender, depositCurrency, userBalance - maxBalanceAllowed);
        }

         if (filled < minOutAmount) {
             revert SlippageTooHigh(filled, minOutAmount);
         }
    }

    function cancelOrder(IPoolManager.Pool memory pool, uint48 orderId) external {
        pool.orderBook.cancelOrder(orderId, msg.sender);
    }

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
        if (slippageToleranceBps > 10000) {
            revert InvalidSlippageTolerance(slippageToleranceBps);
        }
        
        if (inputAmount == 0) {
            return 0;
        }

        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        
        IOrderBook.Side oppositeSide = side == IOrderBook.Side.BUY ? IOrderBook.Side.SELL : IOrderBook.Side.BUY;
        IOrderBook.PriceVolume[] memory oppositePrices = pool.orderBook.getNextBestPrices(oppositeSide, 0, 100);
        
        uint256 remainingInput = inputAmount;
        uint256 totalOutputReceived = 0;
        
        for (uint256 i = 0; i < oppositePrices.length && remainingInput > 0; i++) {
            IOrderBook.PriceVolume memory priceLevel = oppositePrices[i];
            
            if (priceLevel.price == 0 || priceLevel.volume == 0) {
                break;
            }

            uint256 outputToReceive;
            
            if (side == IOrderBook.Side.BUY) {
                uint256 quoteNeededForLevel = PoolIdLibrary.baseToQuote(
                    priceLevel.volume, 
                    priceLevel.price, 
                    pool.baseCurrency.decimals()
                );
                
                if (quoteNeededForLevel <= remainingInput) {
                    outputToReceive = priceLevel.volume;
                    remainingInput -= quoteNeededForLevel;
                } else {
                    outputToReceive = PoolIdLibrary.quoteToBase(
                        remainingInput, 
                        priceLevel.price, 
                        pool.baseCurrency.decimals()
                    );
                    remainingInput = 0;
                }
            } else {
                uint256 baseToSell;
                
                if (priceLevel.volume <= remainingInput) {
                    baseToSell = priceLevel.volume;
                    remainingInput -= priceLevel.volume;
                } else {
                    baseToSell = remainingInput;
                    remainingInput = 0;
                }
                
                outputToReceive = PoolIdLibrary.baseToQuote(
                    baseToSell, 
                    priceLevel.price, 
                    pool.baseCurrency.decimals()
                );
            }
            
            totalOutputReceived += outputToReceive;
        }

        if (totalOutputReceived == 0) {
            return 0;
        }

        uint256 feeTaker = balanceManager.feeTaker();
        uint256 feeUnit = balanceManager.getFeeUnit();
        uint256 feeAmount = (totalOutputReceived * feeTaker) / feeUnit;
        
        uint256 outputAfterFees = totalOutputReceived > feeAmount ? totalOutputReceived - feeAmount : 0;
        
        uint256 slippageAmount = (outputAfterFees * slippageToleranceBps) / 10000;
        minOutputAmount = uint128(outputAfterFees - slippageAmount);
        
        return minOutputAmount;
    }

    function getNextBestPrices(
        IPoolManager.Pool memory pool,
        IOrderBook.Side side,
        uint128 price,
        uint8 count
    ) external view returns (IOrderBook.PriceVolume[] memory) {
        return pool.orderBook.getNextBestPrices(side, price, count);
    }

    /**
     * @notice Swaps one token for another with automatic routing
     * @param srcCurrency The currency the user is providing
     * @param dstCurrency The currency the user wants to receive
     * @param srcAmount The amount of source currency to swap
     * @param minDstAmount The minimum amount of destination currency to receive
     * @param maxHops Maximum number of intermediate hops allowed (1-3)
     * @param user The user address that will receive the destination currency
     * @return receivedAmount The actual amount of destination currency received
     */
    function swap(
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        uint8 maxHops,
        address user
    ) external returns (uint256 receivedAmount) {
        require(Currency.unwrap(srcCurrency) != Currency.unwrap(dstCurrency), "Same currency");
        require(maxHops <= 3, "Too many hops");
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        // Try direct swap first (most efficient)
        if (poolManager.poolExists(srcCurrency, dstCurrency)) {
            receivedAmount =
                            executeDirectSwap(srcCurrency, dstCurrency, srcCurrency, dstCurrency, srcAmount, minDstAmount, user);
        } else if (poolManager.poolExists(dstCurrency, srcCurrency)) {
            receivedAmount =
                            executeDirectSwap(dstCurrency, srcCurrency, srcCurrency, dstCurrency, srcAmount, minDstAmount, user);
        }
        // If no direct pool, try to find intermediaries
        // Try common intermediaries first (from PoolManager)
        Currency[] memory intermediaries = poolManager.getCommonIntermediaries();
        // Try one-hop paths through intermediaries
        if (receivedAmount == 0) {
            for (uint256 i = 0; i < intermediaries.length; i++) {
                Currency intermediary = intermediaries[i];
                // Skip if intermediary is source or destination currency
                if (
                    Currency.unwrap(intermediary) == Currency.unwrap(srcCurrency)
                    || Currency.unwrap(intermediary) == Currency.unwrap(dstCurrency)
                ) {
                    continue;
                }
                // Check if both pools exist
                if (
                    (
                        poolManager.poolExists(srcCurrency, intermediary)
                        && poolManager.poolExists(intermediary, dstCurrency)
                    )
                    || (
                        poolManager.poolExists(srcCurrency, intermediary)
                        && poolManager.poolExists(dstCurrency, intermediary)
                    )
                    || (
                        poolManager.poolExists(intermediary, srcCurrency)
                        && poolManager.poolExists(dstCurrency, intermediary)
                    )
                    || (
                    poolManager.poolExists(intermediary, srcCurrency)
                    && poolManager.poolExists(dstCurrency, intermediary)
                )
                ) {
                    // Execute multi-hop swap where second pool is accessed in reverse
                    receivedAmount =
                                    executeMultiHopSwap(srcCurrency, intermediary, dstCurrency, srcAmount, minDstAmount, user);
                }
            }
        }
        if (receivedAmount > 0) {
            balanceManager.transferOut(user, user, dstCurrency, receivedAmount);
            return receivedAmount;
        }
        revert("No valid swap path found");
    }

    /**
     * @notice Execute a direct swap between two currencies
     */
    function executeDirectSwap(
        Currency baseCurrency,
        Currency quoteCurrency,
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user
    ) internal returns (uint256 receivedAmount) {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        // Determine the pool key and side
        PoolKey memory key = poolManager.createPoolKey(baseCurrency, quoteCurrency);
        IOrderBook.Side side;
        // Determine side based on whether source is base or quote
        if (Currency.unwrap(srcCurrency) == Currency.unwrap(baseCurrency)) {
            side = IOrderBook.Side.SELL; // Selling base currency for quote currency
        } else {
            side = IOrderBook.Side.BUY; // Buying base currency with quote currency
        }
        // Deposit the source currency to the protocol
        balanceManager.deposit(srcCurrency, srcAmount, msg.sender, user);
        (, uint128 receivedAmount) = _placeMarketOrderForSwap(key, srcAmount, side, user, uint128(minDstAmount));
        // Ensure minimum destination amount is met
        if (receivedAmount < minDstAmount) {
            revert SlippageTooHigh(receivedAmount, minDstAmount);
        }
        return receivedAmount;
    }

    /**
     * @notice Execute a multi-hop swap through one intermediary
     */
    function executeMultiHopSwap(
        Currency srcCurrency,
        Currency intermediary,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user
    ) internal returns (uint256 receivedAmount) {
        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        IPoolManager poolManager = IPoolManager($.poolManager);
        // Deposit the source currency to the protocol
        balanceManager.deposit(srcCurrency, srcAmount, msg.sender, user);
        uint256 intermediateAmount;
        if (poolManager.poolExists(srcCurrency, intermediary)) {
            intermediateAmount = executeSwapStep(
                srcCurrency, intermediary, srcCurrency, intermediary, srcAmount, 0, user, IOrderBook.Side.SELL
            );
        } else {
            intermediateAmount = executeSwapStep(
                srcCurrency, intermediary, intermediary, srcCurrency, srcAmount, 0, user, IOrderBook.Side.BUY
            );
        }
        // If we received 0 from the first swap, something went wrong
        if (intermediateAmount == 0) {
            revert("First hop failed");
        }
        // Execute second swap (intermediary -> dstCurrency)
        // For the final swap, use the provided minDstAmount
        if (poolManager.poolExists(dstCurrency, intermediary)) {
            return executeSwapStep(
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
            return executeSwapStep(
                intermediary, dstCurrency, intermediary, dstCurrency, intermediateAmount, 0, user, IOrderBook.Side.SELL
            );
        }
    }

    /**
     * @notice Execute a single swap step within a multi-hop swap
     */
    function executeSwapStep(
        Currency srcCurrency,
        Currency dstCurrency,
        Currency baseCurrency,
        Currency quoteCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user,
        IOrderBook.Side side
    ) internal returns (uint256 receivedAmount) {
        Storage storage $ = getStorage();
        IPoolManager poolManager = IPoolManager($.poolManager);
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        PoolKey memory key = poolManager.createPoolKey(baseCurrency, quoteCurrency);
        (, uint128 receivedAmount) = _placeMarketOrderForSwap(key, srcAmount, side, user, uint128(minDstAmount));

        if (receivedAmount < minDstAmount) {
            revert SlippageTooHigh(receivedAmount, minDstAmount);
        }
        return receivedAmount;
    }

    /**
     * @notice Execute a multi-hop swap where the second pool is accessed in reverse
     * @dev Used when we have pools: srcCurrency-intermediary and dstCurrency-intermediary
     */
    function executeReverseMultiHopSwap(
        Currency srcCurrency,
        Currency intermediary,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user
    ) internal returns (uint256 receivedAmount) {
        Storage storage $ = getStorage();
        IBalanceManager balanceManager = IBalanceManager($.balanceManager);
        IPoolManager poolManager = IPoolManager($.poolManager);
        // Deposit the source currency to the protocol
        balanceManager.deposit(srcCurrency, srcAmount, msg.sender, user);
        // Execute first swap (srcCurrency -> intermediary)
        uint256 intermediateAmount = executeSwapStep(
            srcCurrency,
            intermediary,
            dstCurrency,
            srcCurrency,
            srcAmount,
            0, // No minimum for intermediate step
            user,
            IOrderBook.Side.SELL
        );
        // If we received 0 from the first swap, something went wrong
        if (intermediateAmount == 0) {
            revert("First hop failed");
        }
        // Execute second swap (intermediary -> dstCurrency)
        // Note: For the second step, we're selling the intermediary to get dstCurrency
        // We need to use the pool dstCurrency-intermediary but in reverse
        PoolKey memory reverseKey = poolManager.createPoolKey(dstCurrency, intermediary);
        // Record balance before swap
        uint256 balanceBefore = balanceManager.getBalance(user, dstCurrency);
        _placeMarketOrderForSwap(reverseKey, intermediateAmount, IOrderBook.Side.BUY, user, uint128(minDstAmount));
        // Calculate received amount
        uint256 balanceAfter = balanceManager.getBalance(user, dstCurrency);
        receivedAmount = balanceAfter - balanceBefore;
        // Check minimum received amount
        if (receivedAmount < minDstAmount) {
            revert SlippageTooHigh(receivedAmount, minDstAmount);
        }
        return receivedAmount;
    }
}
