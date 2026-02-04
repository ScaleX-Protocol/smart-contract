// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// ---------------------------------------------------------------------------
// 1. External dependencies
// ---------------------------------------------------------------------------
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ---------------------------------------------------------------------------
// 2. Internal interfaces
// ---------------------------------------------------------------------------
import {IMantleSideChainManager} from "./interfaces/IMantleSideChainManager.sol";
import {IMailbox} from "./interfaces/IMailbox.sol";
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";

// ---------------------------------------------------------------------------
// 3. Internal libraries
// ---------------------------------------------------------------------------
import {UnifiedLiquidityMessages} from "./libraries/UnifiedLiquidityMessages.sol";

// ---------------------------------------------------------------------------
// 4. Storage contracts
// ---------------------------------------------------------------------------
import {MantleSideChainManagerStorage} from "./storages/MantleSideChainManagerStorage.sol";

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------
error MSCM_ZeroAmount();
error MSCM_ZeroAddress();
error MSCM_InsufficientMirroredBalance(address user, uint256 requested, uint256 available);
error MSCM_OnlyMailbox();
error MSCM_InvalidOrigin(uint32 origin);
error MSCM_InvalidSender(bytes32 sender);
error MSCM_MessageAlreadyProcessed(bytes32 messageId);
error MSCM_InvalidMessageType(uint8 messageType);
error MSCM_ArcBridgeNotSet();
error MSCM_MailboxNotSet();
error MSCM_USDCNotSet();
error MSCM_DuplicateNonce(uint32 sourceChain, uint256 nonce);

/**
 * @title MantleSideChainManager
 * @dev Mantle-side (sidechain) manager for the Arc <-> Mantle unified USDC
 *      liquidity hub.
 *
 * Responsibilities
 * -----------------
 *   1. Mirror accounting: Maintains per-user `mirroredBalance` that reflects
 *      the USDC locked inside UnifiedLiquidityBridge on Arc.  These balances
 *      are NOT backed by local USDC on Mantle; they are claims on Arc's vault.
 *   2. Local deposits:    Users can also deposit USDC locally on Mantle.  The
 *      contract holds the local USDC and dispatches a LIQUIDITY_DEPOSIT to Arc
 *      for symmetric record-keeping.
 *   3. Withdrawal requests: Users call `requestWithdraw` to burn mirrored
 *      balance on Mantle and dispatch a LIQUIDITY_WITHDRAW to Arc.  Arc then
 *      releases real USDC to the specified recipient.
 *   4. Inbound messages:  Receives LIQUIDITY_DEPOSIT confirmations from Arc
 *      (originated when a user deposits on Arc) and credits mirrored balances.
 *
 * Design notes
 * ------------
 *   - Follows ChainBalanceManager patterns exactly: upgradeable beacon,
 *     EIP-1967 storage, onlyMailbox modifier, replay protection via
 *     processedMessages, per-user nonces.
 *   - The `handle` function only accepts messages from Arc's
 *     UnifiedLiquidityBridge (validated via origin domain + sender bytes32).
 */
contract MantleSideChainManager is
    IMantleSideChainManager,
    IMessageRecipient,
    MantleSideChainManagerStorage,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using UnifiedLiquidityMessages for *;

    // ----------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ----------------------------------------------------------
    // Initialiser
    // ----------------------------------------------------------

    /**
     * @dev Deploy-time initialisation (called once through the Beacon Proxy).
     * @param _owner        Contract owner.
     * @param _usdc         Local USDC token address on Mantle.
     *                      Pass address(0) if USDC is not yet available; call
     *                      setLocalUSDC afterwards.
     * @param _mailbox      Hyperlane mailbox on Mantle.
     * @param _arcDomain    Hyperlane domain of Arc (5042002).
     * @param _arcBridge    UnifiedLiquidityBridge address on Arc.
     *                      Pass address(0) if deploying before Arc; call
     *                      setArcBridge afterwards.
     */
    function initialize(
        address _owner,
        address _usdc,
        address _mailbox,
        uint32 _arcDomain,
        address _arcBridge
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        $.usdc = _usdc;
        $.mailbox = _mailbox;
        $.localDomain = uint32(block.chainid); // Mantle = 5003
        $.arcDomain = _arcDomain;
        $.arcBridge = _arcBridge;
    }

    // ----------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------

    modifier onlyMailbox() {
        if (msg.sender != getStorage().mailbox) {
            revert MSCM_OnlyMailbox();
        }
        _;
    }

    // ----------------------------------------------------------
    // LOCAL DEPOSIT (Mantle side)
    // ----------------------------------------------------------

    /**
     * @inheritdoc IMantleSideChainManager
     *
     * @dev Pulls local USDC from the caller, credits mirrored balance, and
     *      dispatches a LIQUIDITY_DEPOSIT to Arc for symmetric record-keeping.
     */
    function depositLocal(uint256 amount, address recipient) external payable nonReentrant {
        if (amount == 0) revert MSCM_ZeroAmount();
        if (recipient == address(0)) revert MSCM_ZeroAddress();

        Storage storage $ = getStorage();
        if ($.usdc == address(0)) revert MSCM_USDCNotSet();

        // Pull local USDC into this contract.
        IERC20($.usdc).safeTransferFrom(msg.sender, address(this), amount);

        // Credit the mirrored balance.
        $.mirroredBalance[recipient] += amount;
        $.totalMirrored += amount;

        // Nonce for replay protection.
        uint256 nonce = $.userNonces[recipient]++;

        // Notify Arc of the deposit.
        _dispatchDepositToArc(recipient, amount, nonce);

        emit LocalDeposited(recipient, amount);
    }

    // ----------------------------------------------------------
    // WITHDRAWAL REQUEST (Mantle side -- calls Arc)
    // ----------------------------------------------------------

    /**
     * @inheritdoc IMantleSideChainManager
     *
     * @dev Burns the caller's mirrored balance on Mantle and dispatches a
     *      LIQUIDITY_WITHDRAW to Arc.  Arc will release real USDC to
     *      `recipient`.
     */
    function requestWithdraw(uint256 amount, address recipient) external payable nonReentrant {
        if (amount == 0) revert MSCM_ZeroAmount();
        if (recipient == address(0)) revert MSCM_ZeroAddress();

        Storage storage $ = getStorage();

        // Check-Effects-Interactions: validate and mutate state first.
        uint256 balance = $.mirroredBalance[msg.sender];
        if (balance < amount) {
            revert MSCM_InsufficientMirroredBalance(msg.sender, amount, balance);
        }

        $.mirroredBalance[msg.sender] -= amount;
        $.totalMirrored -= amount;

        uint256 nonce = $.userNonces[msg.sender]++;

        // Dispatch LIQUIDITY_WITHDRAW to Arc.
        _dispatchWithdrawToArc(recipient, amount, nonce);

        emit WithdrawRequested(msg.sender, recipient, amount);
    }

    // ----------------------------------------------------------
    // CROSS-CHAIN MESSAGE HANDLER (Hyperlane -> this contract)
    // ----------------------------------------------------------

    /**
     * @inheritdoc IMessageRecipient
     *
     * @dev Receives LIQUIDITY_DEPOSIT messages from Arc.  Validates origin
     *      and sender, then credits the mirrored balance.
     */
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _messageBody
    ) external payable override(IMessageRecipient, IMantleSideChainManager) onlyMailbox nonReentrant {
        Storage storage $ = getStorage();

        // Validate origin is Arc.
        if (_origin != $.arcDomain) {
            revert MSCM_InvalidOrigin(_origin);
        }

        // Validate sender is the authorized UnifiedLiquidityBridge on Arc.
        bytes32 expectedSender = bytes32(uint256(uint160($.arcBridge)));
        if (_sender != expectedSender) {
            revert MSCM_InvalidSender(_sender);
        }

        // Replay protection.
        bytes32 messageId = UnifiedLiquidityMessages.generateMessageId(_origin, _sender, _messageBody);
        if ($.processedMessages[messageId]) {
            revert MSCM_MessageAlreadyProcessed(messageId);
        }
        $.processedMessages[messageId] = true;

        // Decode message type.
        uint8 messageType = UnifiedLiquidityMessages.decodeMessageType(_messageBody);

        if (messageType == UnifiedLiquidityMessages.LIQUIDITY_DEPOSIT) {
            _handleDeposit(_messageBody);
        } else {
            revert MSCM_InvalidMessageType(messageType);
        }
    }

    // ----------------------------------------------------------
    // CONFIGURATION (owner only)
    // ----------------------------------------------------------

    /// @inheritdoc IMantleSideChainManager
    function setMailbox(address _mailbox) external onlyOwner {
        Storage storage $ = getStorage();
        address old = $.mailbox;
        $.mailbox = _mailbox;
        emit MailboxUpdated(old, _mailbox);
    }

    /// @inheritdoc IMantleSideChainManager
    function setArcBridge(address _arcBridge, uint32 _arcDomain) external onlyOwner {
        Storage storage $ = getStorage();
        address oldBridge = $.arcBridge;
        uint32 oldDomain = $.arcDomain;
        $.arcBridge = _arcBridge;
        $.arcDomain = _arcDomain;
        emit ArcBridgeUpdated(oldDomain, oldBridge, _arcDomain, _arcBridge);
    }

    /// @inheritdoc IMantleSideChainManager
    function setLocalUSDC(address _usdc) external onlyOwner {
        Storage storage $ = getStorage();
        address old = $.usdc;
        $.usdc = _usdc;
        emit LocalUSDCUpdated(old, _usdc);
    }

    // ----------------------------------------------------------
    // VIEW
    // ----------------------------------------------------------

    /// @inheritdoc IMantleSideChainManager
    function mirroredBalanceOf(address user) external view returns (uint256) {
        return getStorage().mirroredBalance[user];
    }

    /// @inheritdoc IMantleSideChainManager
    function totalMirroredSupply() external view returns (uint256) {
        return getStorage().totalMirrored;
    }

    /// @inheritdoc IMantleSideChainManager
    function getMailbox() external view returns (address) {
        return getStorage().mailbox;
    }

    /// @inheritdoc IMantleSideChainManager
    function getArcConfig() external view returns (uint32 domain, address bridge) {
        Storage storage $ = getStorage();
        return ($.arcDomain, $.arcBridge);
    }

    /// @inheritdoc IMantleSideChainManager
    function getLocalUSDC() external view returns (address) {
        return getStorage().usdc;
    }

    // ----------------------------------------------------------
    // Internal helpers
    // ----------------------------------------------------------

    /**
     * @dev Encode and dispatch a LIQUIDITY_DEPOSIT message to Arc.
     */
    function _dispatchDepositToArc(address recipient, uint256 amount, uint256 nonce) internal {
        Storage storage $ = getStorage();

        if ($.mailbox == address(0)) revert MSCM_MailboxNotSet();
        if ($.arcBridge == address(0)) revert MSCM_ArcBridgeNotSet();

        bytes memory body = UnifiedLiquidityMessages.encodeLiquidityDeposit(
            recipient,
            amount,
            $.localDomain,
            nonce
        );

        bytes32 recipientSlot = bytes32(uint256(uint160($.arcBridge)));

        // Quote and pay the Hyperlane dispatch fee.
        uint256 fee = IMailbox($.mailbox).quoteDispatch($.arcDomain, recipientSlot, body);
        IMailbox($.mailbox).dispatch{value: fee}($.arcDomain, recipientSlot, body);
    }

    /**
     * @dev Encode and dispatch a LIQUIDITY_WITHDRAW message to Arc.
     */
    function _dispatchWithdrawToArc(address recipient, uint256 amount, uint256 nonce) internal {
        Storage storage $ = getStorage();

        if ($.mailbox == address(0)) revert MSCM_MailboxNotSet();
        if ($.arcBridge == address(0)) revert MSCM_ArcBridgeNotSet();

        bytes memory body = UnifiedLiquidityMessages.encodeLiquidityWithdraw(
            recipient,
            amount,
            $.localDomain,
            nonce
        );

        bytes32 recipientSlot = bytes32(uint256(uint160($.arcBridge)));

        // Quote and pay the Hyperlane dispatch fee.
        uint256 fee = IMailbox($.mailbox).quoteDispatch($.arcDomain, recipientSlot, body);
        IMailbox($.mailbox).dispatch{value: fee}($.arcDomain, recipientSlot, body);
    }

    /**
     * @dev Process a verified LIQUIDITY_DEPOSIT message from Arc.
     *      Validates the per-sender nonce, then credits the mirrored balance
     *      for the specified recipient.
     */
    function _handleDeposit(bytes calldata messageBody) internal {
        UnifiedLiquidityMessages.LiquidityDepositMessage memory msg_ =
            UnifiedLiquidityMessages.decodeLiquidityDeposit(messageBody);

        Storage storage $ = getStorage();

        // Enforce per-sender nonce (Finding 6).
        if ($.processedNonces[msg_.sourceChainId][msg_.nonce]) {
            revert MSCM_DuplicateNonce(msg_.sourceChainId, msg_.nonce);
        }
        $.processedNonces[msg_.sourceChainId][msg_.nonce] = true;

        $.mirroredBalance[msg_.recipient] += msg_.amount;
        $.totalMirrored += msg_.amount;

        emit MirroredDepositReceived(msg_.recipient, msg_.amount, msg_.sourceChainId);
    }
}
