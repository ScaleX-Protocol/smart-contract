// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IChainBalanceManager} from "./interfaces/IChainBalanceManager.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";

import {IMailbox} from "./interfaces/IMailbox.sol";
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";
import {Currency} from "./libraries/Currency.sol";
import {HyperlaneMessages} from "./libraries/HyperlaneMessages.sol";
import {ChainBalanceManagerStorage} from "./storages/ChainBalanceManagerStorage.sol";

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

    // Additional events not in interface
    event BridgeToSynthetic(
        address indexed user, address indexed sourceToken, address indexed syntheticToken, uint256 amount
    );
    event WithdrawMessageReceived(address indexed user, address indexed token, uint256 amount);
    event TokenMappingSet(address indexed sourceToken, address indexed syntheticToken);
    event NonceIncremented(address indexed user, uint256 newNonce);
    event CrossChainConfigUpdated(uint32 indexed destinationDomain, address indexed destinationBalanceManager);
    event LocalDeposit(address indexed user, address indexed token, uint256 amount);
    event DestinationChainConfigUpdated(bool isDestinationChain, address messageHandler);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Unified initialization for both cross-chain and same-chain modes
     * @param _owner Contract owner
     * @param _messageHandler Either Hyperlane mailbox (cross-chain) or BalanceManager (same-chain)
     * @param _isDestinationChain true = same-chain mode, false = cross-chain mode
     * @param _destinationDomain Target chain domain (can be same as local for destination mode)
     * @param _destinationBalanceManager BalanceManager address on destination chain
     */
    function initialize(
        address _owner,
        address _messageHandler,
        bool _isDestinationChain,
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
        $.isDestinationChain = _isDestinationChain;
        $.messageHandler = _messageHandler;

        if (_isDestinationChain) {
            // DESTINATION CHAIN MODE: Same-chain operation
            // messageHandler should be BalanceManager
            $.mailbox = address(0); // No mailbox needed
            
            // Validate destination domain matches local domain for same-chain
            if ($.destinationDomain != $.localDomain) {
                revert("Destination chain mode requires destinationDomain == localDomain");
            }
            
            emit DestinationChainConfigUpdated(true, _messageHandler);
        } else {
            // SOURCE CHAIN MODE: Cross-chain operation  
            // messageHandler should be Hyperlane mailbox
            $.mailbox = _messageHandler; // Keep legacy field for compatibility
            
            // Validate we're not targeting the same chain for cross-chain mode
            if ($.localDomain == _destinationDomain) {
                revert("Cross-chain mode requires different localDomain and destinationDomain");
            }
            
            emit DestinationChainConfigUpdated(false, _messageHandler);
        }
        
        emit CrossChainConfigUpdated(_destinationDomain, _destinationBalanceManager);
    }

    /**
     * @dev Convenience function for cross-chain mode initialization
     */
    function initializeCrossChain(
        address _owner,
        address _mailbox,
        uint32 _destinationDomain,
        address _destinationBalanceManager
    ) public initializer {
        initialize(
            _owner,
            _mailbox,           // messageHandler = mailbox
            false,             // isDestinationChain = false (cross-chain)
            _destinationDomain,
            _destinationBalanceManager
        );
    }

    /**
     * @dev Convenience function for same-chain mode initialization  
     */
    function initializeSameChain(
        address _owner,
        address _balanceManager
    ) public initializer {
        uint32 localDomain = uint32(block.chainid);
        
        initialize(
            _owner,
            _balanceManager,    // messageHandler = balanceManager
            true,              // isDestinationChain = true (same-chain)
            localDomain,       // destinationDomain = localDomain
            _balanceManager    // destinationBalanceManager = balanceManager
        );
    }

    // Legacy interface compatibility - use overloading
    function initialize(
        address _owner
    ) external override {
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

        $.totalDeposited[token] += amount;

        // Get and increment user nonce (security pattern)
        uint256 currentNonce = $.userNonces[recipient]++;
        emit NonceIncremented(recipient, $.userNonces[recipient]);

        // Get synthetic token mapping
        address syntheticToken = $.sourceToSynthetic[token];
        if (syntheticToken == address(0)) {
            revert TokenMappingNotFound(token);
        }

        if ($.isDestinationChain) {
            // SAME CHAIN: Call BalanceManager directly
            _handleLocalDeposit(token, syntheticToken, amount, recipient, currentNonce);
        } else {
            // CROSS CHAIN: Send Hyperlane message
            _handleCrossChainDeposit(token, syntheticToken, amount, recipient, currentNonce);
        }

        emit Deposit(msg.sender, recipient, token, amount);
        emit BridgeToSynthetic(recipient, token, syntheticToken, amount);
    }

    /**
     * @dev Handle local deposit on destination chain - call BalanceManager directly
     */
    function _handleLocalDeposit(
        address token,
        address syntheticToken,
        uint256 amount,
        address recipient,
        uint256 nonce
    ) internal {
        Storage storage $ = getStorage();

        // Create message exactly like cross-chain version
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: syntheticToken,
            user: recipient,
            amount: amount,
            sourceChainId: $.localDomain,
            nonce: nonce
        });

        bytes memory messageBody = abi.encode(message);
        bytes32 senderAddress = bytes32(uint256(uint160(address(this))));

        // Call BalanceManager.handle() directly (same as Hyperlane would do)
        IMessageRecipient($.destinationBalanceManager).handle{value: 0}(
            $.localDomain,        // origin = local domain
            senderAddress,        // sender = this contract
            messageBody          // message body
        );

        emit LocalDeposit(recipient, token, amount);
    }

    /**
     * @dev Handle cross-chain deposit - send Hyperlane message
     */
    function _handleCrossChainDeposit(
        address token,
        address syntheticToken,
        uint256 amount,
        address recipient,
        uint256 nonce
    ) internal {
        Storage storage $ = getStorage();

        // Create Espresso-style message for recipient
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: syntheticToken,
            user: recipient, // Mint to recipient
            amount: amount,
            sourceChainId: $.localDomain,
            nonce: nonce
        });

        // Send cross-chain message via Hyperlane
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
        $.totalUnlocked[sourceToken] += message.amount;

        emit WithdrawMessageReceived(message.recipient, sourceToken, message.amount);
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
        $.totalWithdrawn[token] += amount;

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
        addWhitelistedToken(token);
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

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    function getBalance(address user, address token) external view returns (uint256) {
        return getStorage().balanceOf[user][token];
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
     * @dev Get unified configuration - works for both cross-chain and same-chain modes
     */
    function getUnifiedConfig() external view returns (
        bool isDestinationChain,
        address messageHandler,
        uint32 localDomain,
        uint32 destinationDomain,
        address destinationBalanceManager
    ) {
        Storage storage $ = getStorage();
        return (
            $.isDestinationChain,
            $.messageHandler,
            $.localDomain,
            $.destinationDomain,
            $.destinationBalanceManager
        );
    }

    /**
     * @dev Admin function to configure for destination chain mode (post-deployment)
     */
    function configureDestinationChainMode(
        address _balanceManager
    ) external onlyOwner {
        Storage storage $ = getStorage();
        $.isDestinationChain = true;
        $.messageHandler = _balanceManager;
        $.destinationBalanceManager = _balanceManager;
        $.mailbox = address(0); // No mailbox needed for same-chain

        emit DestinationChainConfigUpdated(true, _balanceManager);
    }

    /**
     * @dev Admin function to configure for cross-chain mode (post-deployment)
     */
    function configureCrossChainMode(
        address _mailbox,
        uint32 _destinationDomain,
        address _destinationBalanceManager
    ) external onlyOwner {
        Storage storage $ = getStorage();
        $.isDestinationChain = false;
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
