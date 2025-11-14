// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";

/**
 * @title IBalanceManager
 * @dev Interface for balance management functionality
 */
interface IBalanceManager {
    // =============================================================
    //                   DEPOSIT FUNCTIONS
    // =============================================================

    function deposit(
        Currency currency,
        uint256 amount,
        address sender,
        address user
    ) external payable returns (uint256);

    function depositLocal(
        address token,
        uint256 amount,
        address recipient
    ) external;

    function withdraw(
        Currency currency,
        uint256 amount
    ) external;
    
    function withdraw(
        Currency currency,
        uint256 amount,
        address user
    ) external returns (uint256 totalAmount);
    
    function initializeCrossChain(address _mailbox, uint32 _localDomain) external;
    
    function setChainBalanceManager(uint32 domain, address chainBalanceManager) external;
    function requestWithdraw(Currency syntheticCurrency, uint256 amount, uint32 targetChainId, address recipient) external;
    function getMailboxConfig() external view returns (address mailbox, uint32 domain);
    function getChainBalanceManager(uint32 domain) external view returns (address);
    function getUserNonce(address user) external view returns (uint256);

    // =============================================================
    //                   TRADING FUNCTIONS
    // =============================================================

    function lock(
        address user,
        Currency currency,
        uint256 amount
    ) external;

    function lock(
        address user,
        Currency currency,
        uint256 amount,
        address orderBook
    ) external;

    function unlock(
        address user,
        Currency currency,
        uint256 amount
    ) external;

    // =============================================================
    //                   VIEW FUNCTIONS
    // =============================================================

    function getBalance(
        address user, 
        Currency currency
    ) external view returns (uint256);

    function getLockedBalance(
        address user, 
        address operator,
        Currency currency
    ) external view returns (uint256);
    function getAvailableBalance(address user, Currency currency) external view returns (uint256);

    function getSupportedAssets() external view returns (address[] memory);
    function getSyntheticToken(address realToken) external view returns (address);
    function feeMaker() external view returns (uint256);
    function feeTaker() external view returns (uint256);
    function feeReceiver() external view returns (address);
    function getFeeUnit() external pure returns (uint256);
    function transferOut(address from, address to, Currency currency, uint256 amount) external;
    function transferLockedFrom(address from, address to, Currency currency, uint256 amount) external;
    function transferFrom(address from, address to, Currency currency, uint256 amount) external;
    function addAuthorizedOperator(address operator) external;
    function lendingManager() external view returns (address);

    // =============================================================
    //                   OWNER FUNCTIONS
    // =============================================================

    function setPoolManager(address poolManager) external;
    function setAuthorizedOperator(address operator, bool authorized) external;
    function setFees(uint256 feeMaker, uint256 feeTaker) external;
    function setLendingManager(address lendingManager) external;
    function setTokenFactory(address tokenFactory) external;
    function setTokenRegistry(address tokenRegistry) external;
    function addSupportedAsset(address realToken, address syntheticToken) external;
    function accrueYield() external;
    function calculateUserYield(address user, address syntheticToken) external view returns (uint256);
                // unlockWithYield function removed - unlock() now always claims yield

    // =============================================================
    //                   LENDING FUNCTIONS
    // =============================================================

    function borrowForUser(address user, address token, uint256 amount) external;
    function repayForUser(address user, address token, uint256 amount) external;

    // Events
    event DepositedWithYield(
        address indexed user,
        address indexed realToken,
        address indexed syntheticToken,
        uint256 amount,
        uint256 timestamp
    );
    event WithdrawnWithYield(
        address indexed user,
        address indexed realToken,
        address indexed syntheticToken,
        uint256 amount,
        uint256 yieldAmount,
        uint256 timestamp
    );
    event PoolManagerSet(address indexed poolManager);
    event OperatorSet(address indexed operator, bool authorized);
    event AssetConfigured(
        address indexed token,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor
    );
    event FeeUpdated(uint256 indexed feeMaker, uint256 indexed feeTaker);
    event LendingManagerSet(address indexed lendingManager);
    event YieldDistributorSet(address indexed yieldDistributor);
    event Deposit(address indexed user, uint256 indexed id, uint256 amount);
    event Withdrawal(address indexed user, uint256 indexed id, uint256 amount);
    event Lock(address indexed user, uint256 indexed id, uint256 amount);
    event Unlock(address indexed user, uint256 indexed id, uint256 amount);
      // Cross-chain events
    event CrossChainDepositReceived(
        address indexed user, Currency indexed currency, uint256 amount, uint32 sourceChain
    );
    event CrossChainWithdrawSent(address indexed user, Currency indexed currency, uint256 amount, uint32 targetChain);
    event ChainBalanceManagerSet(uint32 indexed chainId, address indexed chainBalanceManager);
    event CrossChainInitialized(address indexed mailbox, uint32 indexed localDomain);
    event CrossChainConfigUpdated(address indexed oldMailbox, address indexed newMailbox, uint32 oldDomain, uint32 newDomain);
    event TokenFactorySet(address indexed tokenFactory);

    // Standard balance manager events
    event TransferLockedFrom(address indexed operator, address indexed from, address indexed to, uint256 currencyId, uint256 amount, uint256 fee);
    event TransferFrom(address indexed operator, address indexed from, address indexed to, uint256 currencyId, uint256 amount, uint256 fee);

    // Local deposit event
    event LocalDeposit(
        address indexed recipient,
        address indexed sourceToken,
        address indexed syntheticToken,
        uint256 sourceAmount,
        uint256 syntheticAmount
    );

    // Synthetic token events
    event AssetAdded(address indexed realToken, address indexed syntheticToken);
    event AssetRemoved(address indexed realToken);
    event YieldAccrued(uint256 timestamp);
    event YieldDistributed(address indexed underlyingToken, address indexed syntheticToken, uint256 amount, uint256 yieldPerToken);
    
    // Withdrawal and yield events (always include yield)
    event WithdrawalWithYield(address indexed user, uint256 indexed currencyId, uint256 principal, uint256 yield, uint256 remainingBalance);
    event YieldAutoClaimed(address indexed user, uint256 indexed currencyId, uint256 timestamp);
}