// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {IBalanceManager} from "./interfaces/IBalanceManager.sol";

import {IMailbox} from "./interfaces/IMailbox.sol";
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";
import {Currency} from "./libraries/Currency.sol";

import {HyperlaneMessages} from "./libraries/HyperlaneMessages.sol";
import {BalanceManagerStorage} from "./storages/BalanceManagerStorage.sol";

import {console} from "forge-std/Test.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BalanceManager is
    IBalanceManager,
    IMessageRecipient,
    BalanceManagerStorage,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _feeReceiver,
        uint256 _feeMaker,
        uint256 _feeTaker
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        $.feeReceiver = _feeReceiver;
        $.feeMaker = _feeMaker;
        $.feeTaker = _feeTaker;
        $.feeUnit = 1000;
    }

    function setPoolManager(
        address _poolManager
    ) external onlyOwner {
        getStorage().poolManager = _poolManager;
        emit PoolManagerSet(_poolManager);
    }

    // Allow owner to set authorized operators (e.g., Router)
    function setAuthorizedOperator(address operator, bool approved) external {
        Storage storage $ = getStorage();

        if (msg.sender != owner() && msg.sender != $.poolManager) {
            revert UnauthorizedCaller(msg.sender);
        }

        $.authorizedOperators[operator] = approved;
        emit OperatorSet(operator, approved);
    }

    function setFees(uint256 _feeMaker, uint256 _feeTaker) external onlyOwner {
        Storage storage $ = getStorage();
        $.feeMaker = _feeMaker;
        $.feeTaker = _feeTaker;
    }

    // Allow anyone to check balanceOf
    function getBalance(address user, Currency currency) external view returns (uint256) {
        return getStorage().balanceOf[user][currency.toId()];
    }

    function getLockedBalance(address user, address operator, Currency currency) external view returns (uint256) {
        return getStorage().lockedBalanceOf[user][operator][currency.toId()];
    }

    function deposit(Currency currency, uint256 amount, address sender, address user) public payable nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();
        if (msg.sender != sender && !$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if (currency.isAddressZero()) {
            require(msg.value == amount, "Incorrect ETH amount sent");
        } else {
            require(msg.value == 0, "No ETH should be sent for ERC20 deposit");

            IERC20 token = IERC20(Currency.unwrap(currency));
            uint256 allowance = token.allowance(sender, address(this));
            uint256 balance = token.balanceOf(sender);

            console.log("Token allowance from sender to BalanceManager:", allowance);
            console.log("Token balance of sender:", balance);
            console.log("Amount to transfer:", amount);

            if (allowance < amount) {
                console.log("INSUFFICIENT ALLOWANCE! Required:", amount, "Available:", allowance);
            }
            if (balance < amount) {
                console.log("INSUFFICIENT BALANCE! Required:", amount, "Available:", balance);
            }

            currency.transferFrom(sender, address(this), amount);
        }

        uint256 currencyId = currency.toId();

        uint256 balanceBefore = $.balanceOf[user][currencyId];

        unchecked {
            $.balanceOf[user][currencyId] += amount;
        }

        uint256 balanceAfter = $.balanceOf[user][currencyId];

        emit Deposit(user, currencyId, amount);
    }

    function depositAndLock(
        Currency currency,
        uint256 amount,
        address user,
        address orderBook
    ) external nonReentrant returns (uint256) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();

        // Verify if the caller is the user or an authorized operator
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        // Transfer tokens directly from sender to this contract
        currency.transferFrom(user, address(this), amount);

        // Credit directly to locked balance, bypassing the regular balance
        uint256 currencyId = currency.toId();

        unchecked {
            $.lockedBalanceOf[user][orderBook][currencyId] += amount;
        }

        emit Deposit(user, currencyId, amount);

        return amount;
    }

    function withdraw(Currency currency, uint256 amount) external {
        withdraw(currency, amount, msg.sender);
    }

    // Withdraw tokens
    function withdraw(Currency currency, uint256 amount, address user) public nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();
        // Verify if the caller is the user or an authorized operator
        if (msg.sender != user && !$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if ($.balanceOf[user][currency.toId()] < amount) {
            revert InsufficientBalance(user, currency.toId(), amount, $.balanceOf[user][currency.toId()]);
        }
        $.balanceOf[user][currency.toId()] -= amount;
        currency.transfer(user, amount);
        emit Withdrawal(user, currency.toId(), amount);
    }

    function lock(address user, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        _lock(user, currency, amount, msg.sender);
    }

    function lock(address user, Currency currency, uint256 amount, address orderBook) external {
        Storage storage $ = getStorage();

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        _lock(user, currency, amount, orderBook);
    }

    function _lock(address user, Currency currency, uint256 amount, address locker) private {
        Storage storage $ = getStorage();

        if ($.balanceOf[user][currency.toId()] < amount) {
            revert InsufficientBalance(user, currency.toId(), amount, $.balanceOf[user][currency.toId()]);
        }

        $.balanceOf[user][currency.toId()] -= amount;
        $.lockedBalanceOf[user][locker][currency.toId()] += amount;

        emit Lock(user, currency.toId(), amount);
    }

    function unlock(address user, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if ($.lockedBalanceOf[user][msg.sender][currency.toId()] < amount) {
            revert InsufficientBalance(
                user, currency.toId(), amount, $.lockedBalanceOf[user][msg.sender][currency.toId()]
            );
        }

        $.lockedBalanceOf[user][msg.sender][currency.toId()] -= amount;
        $.balanceOf[user][currency.toId()] += amount;

        emit Unlock(user, currency.toId(), amount);
    }

    function transferOut(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.balanceOf[sender][currency.toId()] < amount) {
            revert InsufficientBalance(sender, currency.toId(), amount, $.balanceOf[sender][currency.toId()]);
        }

        currency.transfer(receiver, amount);

        $.balanceOf[sender][currency.toId()] -= amount;
    }

    function transferLockedFrom(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.lockedBalanceOf[sender][msg.sender][currency.toId()] < amount) {
            revert InsufficientBalance(
                sender, currency.toId(), amount, $.lockedBalanceOf[sender][msg.sender][currency.toId()]
            );
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = amount * $.feeTaker / _feeUnit();
        require(feeAmount <= amount, "Fee exceeds the transfer amount");

        // Deduct fee and update balances
        $.lockedBalanceOf[sender][msg.sender][currency.toId()] -= amount;
        uint256 amountAfterFee = amount - feeAmount;
        $.balanceOf[receiver][currency.toId()] += amountAfterFee;

        // Transfer the fee to the feeReceiver
        $.balanceOf[$.feeReceiver][currency.toId()] += feeAmount;

        emit TransferLockedFrom(msg.sender, sender, receiver, currency.toId(), amount, feeAmount);
    }

    function transferFrom(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.balanceOf[sender][currency.toId()] < amount) {
            revert InsufficientBalance(sender, currency.toId(), amount, $.balanceOf[sender][currency.toId()]);
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = amount * $.feeMaker / _feeUnit();
        require(feeAmount <= amount, "Fee exceeds the transfer amount");

        // Deduct fee and update balances
        $.balanceOf[sender][currency.toId()] -= amount;
        uint256 amountAfterFee = amount - feeAmount;
        $.balanceOf[receiver][currency.toId()] += amountAfterFee;

        // Transfer the fee to the feeReceiver
        $.balanceOf[$.feeReceiver][currency.toId()] += feeAmount;

        emit TransferFrom(msg.sender, sender, receiver, currency.toId(), amount, feeAmount);
    }

    // Add public getters for fees and feeReceiver
    function feeMaker() external view returns (uint256) {
        return getStorage().feeMaker;
    }

    function feeTaker() external view returns (uint256) {
        return getStorage().feeTaker;
    }

    function feeReceiver() external view returns (address) {
        return getStorage().feeReceiver;
    }

    function getFeeUnit() external view returns (uint256) {
        return _feeUnit();
    }

    function _feeUnit() private view returns (uint256) {
        return getStorage().feeUnit;
    }

    // =============================================================
    //                   CROSS-CHAIN FUNCTIONS
    // =============================================================

    // Initialize cross-chain functionality
    function initializeCrossChain(address _mailbox, uint32 _localDomain) external onlyOwner {
        Storage storage $ = getStorage();
        require($.mailbox == address(0), "Already initialized");

        $.mailbox = _mailbox;
        $.localDomain = _localDomain;
    }

    // Set ChainBalanceManager for a source chain
    function setChainBalanceManager(uint32 chainId, address chainBalanceManager) external onlyOwner {
        Storage storage $ = getStorage();
        $.chainBalanceManagers[chainId] = chainBalanceManager;
        emit ChainBalanceManagerSet(chainId, chainBalanceManager);
    }

    // Cross-chain message handler (receives deposit messages from ChainBalanceManager)
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _messageBody) external payable override {
        Storage storage $ = getStorage();
        require(msg.sender == $.mailbox, "Only mailbox");

        // Verify sender is authorized ChainBalanceManager
        address expectedSender = $.chainBalanceManagers[_origin];
        require(expectedSender != address(0), "Unknown origin chain");
        require(_sender == bytes32(uint256(uint160(expectedSender))), "Invalid sender");

        // Decode message type
        uint8 messageType = abi.decode(_messageBody, (uint8));

        if (messageType == HyperlaneMessages.DEPOSIT_MESSAGE) {
            _handleDepositMessage(_origin, _messageBody);
        } else {
            revert("Unknown message type");
        }
    }

    // Handle deposit notification from source chain
    function _handleDepositMessage(uint32 _origin, bytes calldata _messageBody) internal {
        HyperlaneMessages.DepositMessage memory message = abi.decode(_messageBody, (HyperlaneMessages.DepositMessage));

        Storage storage $ = getStorage();

        // Replay protection
        bytes32 messageId = keccak256(abi.encodePacked(_origin, message.user, message.nonce));
        require(!$.processedMessages[messageId], "Message already processed");
        $.processedMessages[messageId] = true;

        // Credit user's balance (synthetic token)
        Currency syntheticCurrency = Currency.wrap(message.syntheticToken);
        uint256 currencyId = syntheticCurrency.toId();

        $.balanceOf[message.user][currencyId] += message.amount;

        emit CrossChainDepositReceived(message.user, syntheticCurrency, message.amount, _origin);
        emit Deposit(message.user, currencyId, message.amount);
    }

    // Request withdrawal to source chain (burns synthetic, sends message)
    function requestWithdraw(
        Currency syntheticCurrency,
        uint256 amount,
        uint32 targetChainId,
        address recipient
    ) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();
        address targetChainBM = $.chainBalanceManagers[targetChainId];
        require(targetChainBM != address(0), "Target chain not supported");

        // Burn from user's balance
        uint256 currencyId = syntheticCurrency.toId();
        require($.balanceOf[msg.sender][currencyId] >= amount, "Insufficient balance");
        $.balanceOf[msg.sender][currencyId] -= amount;

        // Get user nonce and increment
        uint256 currentNonce = $.userNonces[msg.sender]++;

        // Create withdraw message
        HyperlaneMessages.WithdrawMessage memory message = HyperlaneMessages.WithdrawMessage({
            messageType: HyperlaneMessages.WITHDRAW_MESSAGE,
            syntheticToken: Currency.unwrap(syntheticCurrency),
            recipient: recipient,
            amount: amount,
            targetChainId: targetChainId,
            nonce: currentNonce
        });

        // Send cross-chain message
        bytes memory messageBody = abi.encode(message);
        bytes32 recipientAddress = bytes32(uint256(uint160(targetChainBM)));

        IMailbox($.mailbox).dispatch(targetChainId, recipientAddress, messageBody);

        emit CrossChainWithdrawSent(msg.sender, syntheticCurrency, amount, targetChainId);
        emit Withdrawal(msg.sender, currencyId, amount);
    }

    // View functions for cross-chain
    function getMailboxConfig() external view returns (address mailbox, uint32 localDomain) {
        Storage storage $ = getStorage();
        return ($.mailbox, $.localDomain);
    }

    function getChainBalanceManager(
        uint32 chainId
    ) external view returns (address) {
        return getStorage().chainBalanceManagers[chainId];
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

    // Cross-chain events
    event CrossChainDepositReceived(
        address indexed user, Currency indexed currency, uint256 amount, uint32 sourceChain
    );
    event CrossChainWithdrawSent(address indexed user, Currency indexed currency, uint256 amount, uint32 targetChain);
    event ChainBalanceManagerSet(uint32 indexed chainId, address indexed chainBalanceManager);
}
