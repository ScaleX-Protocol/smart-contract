// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IChainBalanceManager} from "./interfaces/IChainBalanceManager.sol";

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _mailbox,
        uint32 _destinationDomain,
        address _destinationBalanceManager
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        $.mailbox = _mailbox;
        $.destinationDomain = _destinationDomain;
        $.destinationBalanceManager = _destinationBalanceManager;

        // Set local domain based on known Espresso domains
        if (_destinationDomain == 1_918_988_905) {
            // If destination is Rari, we're on Appchain
            $.localDomain = 4661;
        } else {
            // Default to Arbitrum Sepolia
            $.localDomain = 421_614;
        }
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
        if (msg.sender != $.mailbox) {
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

        // Get and increment user nonce (Espresso security pattern)
        uint256 currentNonce = $.userNonces[recipient]++;
        emit NonceIncremented(recipient, $.userNonces[recipient]);

        // Get synthetic token mapping
        address syntheticToken = $.sourceToSynthetic[token];
        if (syntheticToken == address(0)) {
            revert TokenMappingNotFound(token);
        }

        // Create Espresso-style message for recipient
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: syntheticToken,
            user: recipient, // Mint to recipient
            amount: amount,
            sourceChainId: $.localDomain,
            nonce: currentNonce
        });

        // Send cross-chain message
        bytes memory messageBody = abi.encode(message);
        bytes32 recipientAddress = bytes32(uint256(uint160($.destinationBalanceManager)));

        IMailbox($.mailbox).dispatch($.destinationDomain, recipientAddress, messageBody);

        emit Deposit(msg.sender, recipient, token, amount);
        emit BridgeToSynthetic(recipient, token, syntheticToken, amount);
    }

    /**
     * @dev Bridge tokens to synthetic tokens on Rari (Espresso pattern)
     */
    function bridgeToSynthetic(address token, uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();

        if ($.balanceOf[msg.sender][token] < amount) {
            revert InsufficientBalance(msg.sender, uint256(uint160(token)), amount, $.balanceOf[msg.sender][token]);
        }

        // Lock tokens by reducing user balance
        $.balanceOf[msg.sender][token] -= amount;

        // Get and increment user nonce (Espresso security pattern)
        uint256 currentNonce = $.userNonces[msg.sender]++;
        emit NonceIncremented(msg.sender, $.userNonces[msg.sender]);

        // Get synthetic token mapping
        address syntheticToken = $.sourceToSynthetic[token];
        if (syntheticToken == address(0)) {
            revert TokenMappingNotFound(token);
        }

        // Create Espresso-style message
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: syntheticToken,
            user: msg.sender,
            amount: amount,
            sourceChainId: $.localDomain,
            nonce: currentNonce
        });

        // Send cross-chain message
        bytes memory messageBody = abi.encode(message);
        bytes32 recipientAddress = bytes32(uint256(uint160($.destinationBalanceManager)));

        IMailbox($.mailbox).dispatch($.destinationDomain, recipientAddress, messageBody);

        emit BridgeToSynthetic(msg.sender, token, syntheticToken, amount);
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
    function addToken(
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
