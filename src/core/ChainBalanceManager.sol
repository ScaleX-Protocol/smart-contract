// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IChainBalanceManager} from "./interfaces/IChainBalanceManager.sol";
import {IChainBalanceManagerErrors} from "./interfaces/IChainBalanceManagerErrors.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";

import {IMailbox} from "./interfaces/IMailbox.sol";
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";
import {Currency} from "./libraries/Currency.sol";
import {HyperlaneMessages} from "./libraries/HyperlaneMessages.sol";
import {ChainBalanceManagerStorage} from "./storages/ChainBalanceManagerStorage.sol";

// Events
event TokenDeposited(address indexed to, address indexed token, uint256 amount);
event TokenWithdrawn(address indexed to, address indexed token, uint256 amount);

// Errors
error TokenNotWhitelisted(address token);
error OnlyMailbox();
error ZeroAmount();
error ZeroAddress();
error InsufficientBalance(address user, uint256 tokenId, uint256 requested, uint256 available);
error InsufficientLockedBalance();
error InvalidAmount();
error EthSentForErc20Deposit();
error DifferentChainDomains(uint32 local, uint32 destination);
error TokenMappingNotFound(address token);
error InvalidOrigin(uint32 origin);
error InvalidSender(bytes32 sender);
error MessageAlreadyProcessed(bytes32 messageId);
error InvalidMessageType(uint256 messageType);
error InvalidSyntheticToken(address syntheticToken);
error InsufficientUnlockedBalance(address user, uint256 tokenId, uint256 requested, uint256 available);
error TokenAlreadyWhitelisted(address token);
error TokenNotFound(address token);

// Events
event DestinationChainConfigUpdated(bool isMailbox, address indexed value);
event CrossChainConfigUpdated(uint32 indexed destinationDomain, address indexed destinationBalanceManager);
event NonceIncremented(address indexed user, uint256 nonce);
event Deposit(address indexed from, address indexed to, address indexed token, uint256 amount);
event BridgeToSynthetic(address indexed to, address indexed sourceToken, address indexed syntheticToken, uint256 amount);
event WithdrawMessageReceived(address indexed recipient, address indexed sourceToken, uint256 amount);
event Claim(address indexed user, address indexed token, uint256 amount);
event Withdraw(address indexed user, address indexed token, uint256 amount);
event Unlock(address indexed user, address indexed token, uint256 amount);
event TokenWhitelisted(address indexed token);
event TokenRemoved(address indexed token);
event TokenMappingSet(address indexed sourceToken, address indexed syntheticToken);
event LocalDomainUpdated(uint32 oldDomain, uint32 newDomain);

/**
 * @title ChainBalanceManager
 * @dev Upgradeable vault contract for source chains with Espresso Hyperlane integration
 * Follows proven patterns from the working Espresso testnet implementation
 */
contract ChainBalanceManager is
    IChainBalanceManager,
    IMessageRecipient,
    ChainBalanceManagerStorage,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using HyperlaneMessages for *;
    using SafeERC20 for IERC20;

  
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize ChainBalanceManager for cross-chain operation only
     * @param _owner Contract owner
     * @param _mailbox Hyperlane mailbox for cross-chain messaging
     * @param _destinationDomain Target chain domain (Rari: 1918988905)
     * @param _destinationBalanceManager BalanceManager address on Rari
     */
    function initialize(
        address _owner,
        address _mailbox,
        uint32 _destinationDomain,
        address _destinationBalanceManager
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        
        // Use chain ID as domain (Hyperlane convention)
        $.localDomain = uint32(block.chainid);
        $.destinationDomain = _destinationDomain;
        $.destinationBalanceManager = _destinationBalanceManager;
        $.isDestinationChain = false; // Always cross-chain mode
        $.messageHandler = _mailbox;
        $.mailbox = _mailbox;
        
        // Validate we're targeting a different chain (source -> destination)
        if ($.localDomain == _destinationDomain) {
            revert DifferentChainDomains($.localDomain, _destinationDomain);
        }
        
        emit DestinationChainConfigUpdated(false, _mailbox);
        emit CrossChainConfigUpdated(_destinationDomain, _destinationBalanceManager);
    }

    /**
     * @dev Legacy compatibility function - use main initialize instead
     */
    function initializeCrossChain(
        address _owner,
        address _mailbox,
        uint32 _destinationDomain,
        address _destinationBalanceManager
    ) public initializer {
        initialize(_owner, _mailbox, _destinationDomain, _destinationBalanceManager);
    }

    // Legacy interface compatibility - use overloading
    function initialize(
        address /* _owner */
    ) external {
        revert("Use initialize with full parameters");
    }

    modifier onlyWhitelistedToken(
        address token
    ) {
        Storage storage $ = getStorage();
        if (!$.whitelistedTokens[token] && token != address(0)) {
            revert TokenNotWhitelisted(token);
        }
        _;
    }

    modifier onlyMailbox() {
        Storage storage $ = getStorage();
        // For backward compatibility, check both mailbox and messageHandler
        if (msg.sender != $.mailbox && msg.sender != $.messageHandler) {
            revert OnlyMailbox();
        }
        _;
    }

    // =============================================================
    //                     CORE VAULT FUNCTIONS
    // =============================================================

    function deposit(
        address token,
        uint256 amount,
        address recipient
    ) external payable nonReentrant onlyWhitelistedToken(token) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (recipient == address(0)) {
            revert ZeroAddress();
        }

        Storage storage $ = getStorage();
        
        // Transfer tokens to this contract
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount sent");
        } else {
            require(msg.value == 0, "No ETH should be sent for ERC20 deposit");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Get and increment user nonce (security pattern)
        uint256 currentNonce = $.userNonces[recipient]++;
        emit NonceIncremented(recipient, $.userNonces[recipient]);

        // Get synthetic token mapping
        address syntheticToken = $.sourceToSynthetic[token];
        if (syntheticToken == address(0)) {
            revert TokenMappingNotFound(token);
        }

        // Always cross-chain - send Hyperlane message to Rari
        _handleCrossChainDeposit(token, syntheticToken, amount, recipient, currentNonce);

        emit Deposit(msg.sender, recipient, token, amount);
        emit BridgeToSynthetic(recipient, token, syntheticToken, amount);
    }


    /**
     * @dev Handle cross-chain deposit - send Hyperlane message to Rari
     */
    function _handleCrossChainDeposit(
        address /* token */,
        address syntheticToken,
        uint256 amount,
        address recipient,
        uint256 nonce
    ) internal {
        Storage storage $ = getStorage();

        // Create message for BalanceManager on Rari
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: syntheticToken,
            user: recipient, // Mint to recipient
            amount: amount,
            sourceChainId: $.localDomain,
            nonce: nonce
        });

        // Send cross-chain message via Hyperlane to Rari BalanceManager
        bytes memory messageBody = abi.encode(message);
        bytes32 recipientAddress = bytes32(uint256(uint160($.destinationBalanceManager)));

        IMailbox($.mailbox).dispatch($.destinationDomain, recipientAddress, messageBody);
    }


    /**
     * @dev Handle cross-chain messages from Rari (Espresso pattern)
     */
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _messageBody
    ) external payable override onlyMailbox nonReentrant {
        Storage storage $ = getStorage();

        // Verify origin and sender (Espresso security pattern)
        if (_origin != $.destinationDomain) {
            revert InvalidOrigin(_origin);
        }

        if (_sender != bytes32(uint256(uint160($.destinationBalanceManager)))) {
            revert InvalidSender(_sender);
        }

        // Generate message ID for replay protection
        bytes32 messageId = HyperlaneMessages.generateMessageId(_origin, _sender, _messageBody);
        if ($.processedMessages[messageId]) {
            revert MessageAlreadyProcessed(messageId);
        }
        $.processedMessages[messageId] = true;

        // Process message based on type
        uint8 messageType = HyperlaneMessages.decodeMessageType(_messageBody);

        if (messageType == HyperlaneMessages.WITHDRAW_MESSAGE) {
            _handleWithdrawMessage(_messageBody);
        } else {
            revert InvalidMessageType(messageType);
        }
    }

    /**
     * @dev Handle withdrawal message from Rari (unlock tokens)
     */
    function _handleWithdrawMessage(
        bytes calldata _messageBody
    ) internal {
        Storage storage $ = getStorage();

        HyperlaneMessages.WithdrawMessage memory message = HyperlaneMessages.decodeWithdrawMessage(_messageBody);

        // Get source token from synthetic token mapping
        address sourceToken = $.syntheticToSource[message.syntheticToken];
        if (sourceToken == address(0)) {
            revert InvalidSyntheticToken(message.syntheticToken);
        }

        // Unlock tokens for user to claim
        $.unlockedBalanceOf[message.recipient][sourceToken] += message.amount;
        emit WithdrawMessageReceived(message.recipient, sourceToken, message.amount);
    }

    // =============================================================
    //                 IChainBalanceManager INTERFACE
    // =============================================================

    function deposit(
        address to,
        Currency currency,
        uint256 amount
    ) external payable onlyWhitelistedToken(Currency.unwrap(currency)) nonReentrant returns (uint256 depositedAmount) {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        
        Storage storage $ = getStorage();
        address token = Currency.unwrap(currency);
        
        // Handle ETH deposits
        if (token == address(0)) {
            if (msg.value != amount) revert InvalidAmount();
        } else {
            if (msg.value != 0) revert EthSentForErc20Deposit();
            IERC20(token).transferFrom(msg.sender, address(this), amount);
        }
        
        $.balanceOf[to][token] += amount;
        depositedAmount = amount;

        emit TokenDeposited(to, token, amount);
    }

    /// @notice Deposit tokens on behalf of a user (tokens already in contract)
    /// @dev Used by LendingManager after borrowing - converts to synthetic token balance
    /// @param user The user to credit
    /// @param underlyingToken The underlying token address
    /// @param amount The amount to credit
    function depositFor(address user, address underlyingToken, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (user == address(0)) revert ZeroAddress();

        Storage storage $ = getStorage();

        // Get synthetic token
        address syntheticToken = $.sourceToSynthetic[underlyingToken];
        if (syntheticToken == address(0)) {
            revert TokenMappingNotFound(underlyingToken);
        }

        // Credit user's synthetic token balance
        $.balanceOf[user][syntheticToken] += amount;

        emit TokenDeposited(user, syntheticToken, amount);
    }

    function withdraw(
        address to,
        Currency currency,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        
        Storage storage $ = getStorage();
        address token = Currency.unwrap(currency);
        
        if ($.balanceOf[to][token] < amount) {
            revert InsufficientBalance(to, uint256(uint160(token)), amount, $.balanceOf[to][token]);
        }
        
        $.balanceOf[to][token] -= amount;
        
        // Handle ETH withdrawals
        if (token == address(0)) {
            (bool success, ) = payable(to).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).transfer(to, amount);
        }
        
        emit TokenWithdrawn(to, token, amount);
    }
    
    function lock(
        address to,
        Currency currency,
        uint256 amount,
        uint256 /* timeout */
    ) external nonReentrant {
        // Note: Simplified implementation - would need timeout handling
        Storage storage $ = getStorage();
        address token = Currency.unwrap(currency);
        
        if ($.balanceOf[to][token] < amount) {
            revert InsufficientBalance(to, uint256(uint160(token)), amount, $.balanceOf[to][token]);
        }
        
        $.balanceOf[to][token] -= amount;
        // Note: Would need proper locked balance tracking with timeout
        $.lockedBalanceOf[to][msg.sender][token] += amount;
    }
    
    function unlock(
        address to,
        Currency currency,
        uint256 amount,
        address manager
    ) external nonReentrant {
        Storage storage $ = getStorage();
        address token = Currency.unwrap(currency);
        
        if ($.lockedBalanceOf[to][manager][token] < amount) {
            revert InsufficientLockedBalance();
        }
        
        $.lockedBalanceOf[to][manager][token] -= amount;
        $.unlockedBalanceOf[to][token] += amount;
    }
    
    function getLockedBalance(
        address user,
        address manager,
        Currency currency
    ) external view returns (uint256) {
        Storage storage $ = getStorage();
        return $.lockedBalanceOf[user][manager][Currency.unwrap(currency)];
    }

    /**
     * @dev Claim unlocked tokens (Espresso pattern)
     */
    function claim(address token, uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();

        if ($.unlockedBalanceOf[msg.sender][token] < amount) {
            revert InsufficientUnlockedBalance(
                msg.sender, uint256(uint160(token)), amount, $.unlockedBalanceOf[msg.sender][token]
            );
        }

        $.unlockedBalanceOf[msg.sender][token] -= amount;
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit Claim(msg.sender, token, amount);
    }

    /**
     * @dev Direct withdrawal from deposited balance (owner only - for emergencies)
     */
    function withdraw(address token, uint256 amount, address user) external onlyOwner nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();

        if ($.balanceOf[user][token] < amount) {
            revert InsufficientBalance(user, uint256(uint160(token)), amount, $.balanceOf[user][token]);
        }

        $.balanceOf[user][token] -= amount;

        if (token == address(0)) {
            payable(user).transfer(amount);
        } else {
            IERC20(token).safeTransfer(user, amount);
        }

        emit Withdraw(user, token, amount);
    }

    /**
     * @dev Unlock tokens for withdrawal (owner only - for cross-chain unlocks)
     */
    function unlock(address token, uint256 amount, address user) external onlyOwner {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();

        if ($.balanceOf[user][token] < amount) {
            revert InsufficientBalance(user, uint256(uint160(token)), amount, $.balanceOf[user][token]);
        }

        $.balanceOf[user][token] -= amount;
        $.unlockedBalanceOf[user][token] += amount;

        emit Unlock(user, token, amount);
    }

    // =============================================================
    //                  ADMINISTRATIVE FUNCTIONS
    // =============================================================

    /**
     * @dev Add token to whitelist
     */
    function addWhitelistedToken(
        address token
    ) external onlyOwner {
        Storage storage $ = getStorage();

        if ($.whitelistedTokens[token]) {
            revert TokenAlreadyWhitelisted(token);
        }

        $.whitelistedTokens[token] = true;
        $.tokenList.push(token);

        emit TokenWhitelisted(token);
    }

    /**
     * @dev Add token to whitelist (legacy alias)  
     */
    function addToken(address token) external onlyOwner {
        Storage storage $ = getStorage();

        if ($.whitelistedTokens[token]) {
            revert TokenAlreadyWhitelisted(token);
        }

        $.whitelistedTokens[token] = true;
        $.tokenList.push(token);

        emit TokenWhitelisted(token);
    }

    /**
     * @dev Remove token from whitelist
     */
    function removeToken(
        address token
    ) external onlyOwner {
        Storage storage $ = getStorage();

        if (!$.whitelistedTokens[token]) {
            revert TokenNotFound(token);
        }

        $.whitelistedTokens[token] = false;

        // Remove from tokenList array
        for (uint256 i = 0; i < $.tokenList.length; i++) {
            if ($.tokenList[i] == token) {
                $.tokenList[i] = $.tokenList[$.tokenList.length - 1];
                $.tokenList.pop();
                break;
            }
        }

        emit TokenRemoved(token);
    }

    /**
     * @dev Set cross-chain token mapping (Espresso pattern)
     */
    function setTokenMapping(address sourceToken, address syntheticToken) external onlyOwner {
        Storage storage $ = getStorage();

        $.sourceToSynthetic[sourceToken] = syntheticToken;
        $.syntheticToSource[syntheticToken] = sourceToken;

        emit TokenMappingSet(sourceToken, syntheticToken);
    }

    /**
     * @dev Update cross-chain configuration
     */
    function updateCrossChainConfig(uint32 _destinationDomain, address _destinationBalanceManager) external onlyOwner {
        Storage storage $ = getStorage();

        $.destinationDomain = _destinationDomain;
        $.destinationBalanceManager = _destinationBalanceManager;

        emit CrossChainConfigUpdated(_destinationDomain, _destinationBalanceManager);
    }

    /**
     * @dev Update local domain (fix for incorrect domain during deployment)
     */
    function updateLocalDomain(uint32 _localDomain) external onlyOwner {
        Storage storage $ = getStorage();
        uint32 oldDomain = $.localDomain;
        $.localDomain = _localDomain;
        emit LocalDomainUpdated(oldDomain, _localDomain);
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    function getBalance(address user, Currency currency) external view returns (uint256) {
        return getStorage().balanceOf[user][Currency.unwrap(currency)];
    }

    function getUnlockedBalance(address user, address token) external view returns (uint256) {
        return getStorage().unlockedBalanceOf[user][token];
    }

    function isTokenWhitelisted(
        address token
    ) external view returns (bool) {
        return getStorage().whitelistedTokens[token] || token == address(0);
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        return getStorage().tokenList;
    }

    function getTokenCount() external view returns (uint256) {
        return getStorage().tokenList.length;
    }

    function getUserNonce(
        address user
    ) external view returns (uint256) {
        return getStorage().userNonces[user];
    }

    function isMessageProcessed(
        bytes32 messageId
    ) external view returns (bool) {
        return getStorage().processedMessages[messageId];
    }

    function getTokenMapping(
        address sourceToken
    ) external view returns (address) {
        return getStorage().sourceToSynthetic[sourceToken];
    }

    function getReverseTokenMapping(
        address syntheticToken
    ) external view returns (address) {
        return getStorage().syntheticToSource[syntheticToken];
    }

    function getCrossChainConfig()
        external
        view
        returns (uint32 destinationDomain, address destinationBalanceManager)
    {
        Storage storage $ = getStorage();
        return ($.destinationDomain, $.destinationBalanceManager);
    }

    function getMailboxConfig() external view returns (address mailbox, uint32 localDomain) {
        Storage storage $ = getStorage();
        return ($.mailbox, $.localDomain);
    }

    function getDestinationConfig() external view returns (uint32 destinationDomain, address destinationBalanceManager) {
        Storage storage $ = getStorage();
        return ($.destinationDomain, $.destinationBalanceManager);
    }

    /**
     * @dev Get cross-chain configuration
     */
    function getCrossChainInfo() external view returns (
        address mailbox,
        uint32 localDomain,
        uint32 destinationDomain,
        address destinationBalanceManager
    ) {
        Storage storage $ = getStorage();
        return (
            $.mailbox,
            $.localDomain,
            $.destinationDomain,
            $.destinationBalanceManager
        );
    }

    /**
     * @dev Admin function to update cross-chain configuration (post-deployment)
     */
    function updateCrossChainConfig(
        address _mailbox,
        uint32 _destinationDomain,
        address _destinationBalanceManager
    ) external onlyOwner {
        Storage storage $ = getStorage();
        $.messageHandler = _mailbox;
        $.mailbox = _mailbox;
        $.destinationDomain = _destinationDomain;
        $.destinationBalanceManager = _destinationBalanceManager;

        emit DestinationChainConfigUpdated(false, _mailbox);
        emit CrossChainConfigUpdated(_destinationDomain, _destinationBalanceManager);
    }


    // =============================================================
    //                    LEGACY COMPATIBILITY
    // =============================================================

    // Maintain compatibility with existing interfaces
    function balanceOf(address user, address token) external view returns (uint256) {
        return getStorage().balanceOf[user][token];
    }

    function unlockedBalanceOf(address user, address token) external view returns (uint256) {
        return getStorage().unlockedBalanceOf[user][token];
    }

    function whitelistedTokens(
        address token
    ) external view returns (bool) {
        return getStorage().whitelistedTokens[token];
    }

    function tokenList(
        uint256 index
    ) external view returns (address) {
        return getStorage().tokenList[index];
    }
}
