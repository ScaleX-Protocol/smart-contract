// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";
import {PoolKey} from "../libraries/Pool.sol";

import {IScaleXRouterErrors} from "./IScaleXRouterErrors.sol";
import {IOrderBook} from "./IOrderBook.sol";
import {IPoolManager} from "./IPoolManager.sol";

interface IScaleXRouter is IScaleXRouterErrors {
    // Events for lending operations
    event DepositStarted(address indexed user, address indexed token, uint256 amount);
    event DepositCompleted(address indexed user, address indexed token, uint256 amount);
    event BorrowStarted(address indexed user, address indexed token, uint256 amount);
    event BorrowCompleted(address indexed user, address indexed token, uint256 amount);
    event RepayStarted(address indexed user, address indexed token, uint256 amount);
    event RepayCompleted(address indexed user, address indexed token, uint256 amount);

    function placeLimitOrder(
        IPoolManager.Pool calldata pool,
        uint128 _price,
        uint128 _quantity,
        IOrderBook.Side _side,
        IOrderBook.TimeInForce _timeInForce,
        uint128 depositAmount
    ) external returns (uint48 orderId);

    function placeMarketOrder(
        IPoolManager.Pool calldata pool,
        uint128 _quantity,
        IOrderBook.Side _side,
        uint128 depositAmount,
        uint128 minOutAmount
    ) external returns (uint48 orderId, uint128 filled);

    function cancelOrder(IPoolManager.Pool memory pool, uint48 orderId) external;

    function withdraw(Currency currency, uint256 amount) external;
    
    function deposit(address token, uint256 amount) external;

    function batchCancelOrders(IPoolManager.Pool calldata pool, uint48[] calldata orderIds) external;

    function getBestPrice(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        IOrderBook.Side side
    ) external view returns (IOrderBook.PriceVolume memory);

    function getOrderQueue(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        IOrderBook.Side side,
        uint128 price
    ) external view returns (uint48 orderCount, uint256 totalVolume);

    function getOrder(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        uint48 orderId
    ) external view returns (IOrderBook.Order memory);

    function getNextBestPrices(
        IPoolManager.Pool memory pool,
        IOrderBook.Side side,
        uint128 price,
        uint8 count
    ) external view returns (IOrderBook.PriceVolume[] memory);

    function calculateMinOutAmountForMarket(
        IPoolManager.Pool memory pool,
        uint256 inputAmount,
        IOrderBook.Side side,
        uint256 slippageToleranceBps
    ) external view returns (uint128 minOutputAmount);

    // Lending functions
    function borrow(address token, uint256 amount) external;
    function repay(address token, uint256 amount) external;
    function liquidate(address borrower, address debtToken, address collateralToken, uint256 debtToCover) external;

    // Lending view functions
    function getUserSupply(address user, address token) external view returns (uint256);
    function getUserDebt(address user, address token) external view returns (uint256);
    function getHealthFactor(address user) external view returns (uint256);
    function getGeneratedInterest(address token) external view returns (uint256);
    function getAvailableLiquidity(address token) external view returns (uint256);
    function lendingManager() external view returns (address);

    /*    function swap(
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        uint8 maxHops,
        address user
    ) external returns (uint256 receivedAmount);*/
}
