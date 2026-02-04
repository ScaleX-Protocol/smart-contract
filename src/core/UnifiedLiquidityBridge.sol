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
import {IUnifiedLiquidityBridge} from "./interfaces/IUnifiedLiquidityBridge.sol";
import {IMailbox} from "./interfaces/IMailbox.sol";
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";

// ---------------------------------------------------------------------------
// 3. Internal libraries
// ---------------------------------------------------------------------------
import {UnifiedLiquidityMessages} from "./libraries/UnifiedLiquidityMessages.sol";

// ---------------------------------------------------------------------------
// 4. Storage contracts
// ---------------------------------------------------------------------------
import {UnifiedLiquidityBridgeStorage} from "./storages/UnifiedLiquidityBridgeStorage.sol";

// ---------------------------------------------------------------------------
// Errors  (declared at file scope, matching the project convention in
//          ChainBalanceManager.sol)
// ---------------------------------------------------------------------------
error ULB_ZeroAmount();
error ULB_ZeroAddress();
error ULB_InsufficientBalance(address user, uint256 requested, uint256 available);
error ULB_OnlyMailbox();
error ULB_OnlyAuthorizedDepositor(address caller);
error ULB_GatewayNonceAlreadyUsed(bytes32 nonce);
error ULB_InvalidOrigin(uint32 origin);
error ULB_InvalidSender(bytes32 sender);
error ULB_MessageAlreadyProcessed(bytes32 messageId);
error ULB_InvalidMessageType(uint8 messageType);
error ULB_MantleManagerNotSet();
error ULB_MailboxNotSet();
error ULB_VaultUnderflow(uint256 currentVault, uint256 requested);
error ULB_GatewayBalanceMismatch(uint256 actualBalance, uint256 expectedMinimum);
error ULB_DuplicateNonce(uint32 sourceChain, uint256 nonce);

/**
 * @title UnifiedLiquidityBridge
 * @dev Arc-side (core chain) contract for the Arc <-> Mantle unified USDC
 *      liquidity hub.
 *
 * Responsibilities
 * -----------------
 *   1. Vault:       Holds real USDC deposited by users or minted by the Circle
 *                   Gateway.
 *   2. Accounting:  Maintains a per-user `unifiedBalance` that represents the
 *                   total USDC a user has committed across both chains.
 *   3. Messaging:   On every deposit dispatches a LIQUIDITY_DEPOSIT message to
 *                   Mantle via Hyperlane so the MantleSideChainManager can mirror
 *                   the position.
 *   4. Withdrawals: Receives LIQUIDITY_WITHDRAW messages from Mantle and
 *                   releases USDC from the vault to the specified recipient.
 *                   Also receives LIQUIDITY_DEPOSIT messages from Mantle
 *                   (originated when a user deposits locally on Mantle) and
 *                   credits the unified balance on Arc.
 *
 * Circle Gateway integration
 * --------------------------
 *   Circle does NOT support CCTP on Mantle, so the Gateway is used only for
 *   minting USDC on Arc.  The flow is:
 *     a) Off-chain: user requests a mint via the Circle Gateway.
 *     b) Off-chain: Gateway minter calls `depositViaGateway` on this contract
 *        after the attestation is verified.  The minter address must be in
 *        `authorizedDepositors`.
 *     c) On-chain:  this contract records the deposit and dispatches to Mantle.
 *
 * Upgradability
 * -------------
 *   Follows the Beacon Proxy pattern used across the rest of ScaleX.
 *   All state lives in UnifiedLiquidityBridgeStorage (EIP-1967 slot).
 */
contract UnifiedLiquidityBridge is
    IUnifiedLiquidityBridge,
    IMessageRecipient,
    UnifiedLiquidityBridgeStorage,
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
     * @param _owner          Contract owner (multisig in production).
     * @param _usdc           USDC token address on Arc
     *                        (0x3600000000000000000000000000000000000000 on Arc testnet).
     * @param _mailbox        Hyperlane mailbox on Arc.
     * @param _mantleDomain   Hyperlane domain of Mantle (5003).
     * @param _mantleManager  MantleSideChainManager address on Mantle.
     *                        Pass address(0) if deploying before Mantle; call
     *                        setMantleManager afterwards.
     */
    function initialize(
        address _owner,
        address _usdc,
        address _mailbox,
        uint32 _mantleDomain,
        address _mantleManager
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        $.usdc = _usdc;
        $.mailbox = _mailbox;
        $.localDomain = uint32(block.chainid); // Arc = 5042002
        $.mantleDomain = _mantleDomain;
        $.mantleManager = _mantleManager;
    }

    // ----------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------

    modifier onlyMailbox() {
        if (msg.sender != getStorage().mailbox) {
            revert ULB_OnlyMailbox();
        }
        _;
    }

    // ----------------------------------------------------------
    // DEPOSIT -- direct (pull USDC from caller)
    // ----------------------------------------------------------

    /**
     * @inheritdoc IUnifiedLiquidityBridge
     */
    function deposit(uint256 amount, address recipient) external payable nonReentrant {
        if (amount == 0) revert ULB_ZeroAmount();
        if (recipient == address(0)) revert ULB_ZeroAddress();

        Storage storage $ = getStorage();

        // Pull USDC from the caller into the vault.
        IERC20($.usdc).safeTransferFrom(msg.sender, address(this), amount);

        // Credit unified balance.
        $.unifiedBalance[recipient] += amount;
        $.totalVault += amount;

        // Obtain and increment the user's nonce for replay protection.
        uint256 nonce = $.userNonces[recipient]++;

        // Dispatch LIQUIDITY_DEPOSIT to Mantle so it can mirror the position.
        _dispatchDepositToMantle(recipient, amount, nonce);

        emit Deposited(recipient, amount, nonce);
    }

    // ----------------------------------------------------------
    // DEPOSIT -- via Circle Gateway
    // ----------------------------------------------------------

    /**
     * @inheritdoc IUnifiedLiquidityBridge
     *
     * @dev The Gateway minter has already transferred USDC to this contract
     *      before calling this function.  An assertion is placed after crediting
     *      totalVault to guarantee the USDC actually arrived; if it did not the
     *      transaction reverts with ULB_GatewayBalanceMismatch.
     *
     *      The minter must be in `authorizedDepositors`.  The `gatewayNonce`
     *      must be unique per mint (enforced here for replay safety).
     */
    function depositViaGateway(uint256 amount, address recipient, bytes32 gatewayNonce) external payable nonReentrant {
        if (amount == 0) revert ULB_ZeroAmount();
        if (recipient == address(0)) revert ULB_ZeroAddress();

        Storage storage $ = getStorage();

        if (!$.authorizedDepositors[msg.sender]) {
            revert ULB_OnlyAuthorizedDepositor(msg.sender);
        }
        if ($.usedGatewayNonces[gatewayNonce]) {
            revert ULB_GatewayNonceAlreadyUsed(gatewayNonce);
        }

        // Mark nonce as consumed (Checks-Effects-Interactions).
        $.usedGatewayNonces[gatewayNonce] = true;

        // Credit unified balance and vault total.
        $.unifiedBalance[recipient] += amount;
        $.totalVault += amount;

        // --- Finding 2 fix: verify USDC actually arrived ----------------------
        // The contract's real USDC balance must be at least totalVault.  If the
        // Gateway minter did not transfer USDC before calling, this assertion
        // catches it and reverts the entire transaction.
        uint256 actualBalance = IERC20($.usdc).balanceOf(address(this));
        if (actualBalance < $.totalVault) {
            revert ULB_GatewayBalanceMismatch(actualBalance, $.totalVault);
        }
        // ----------------------------------------------------------------------

        uint256 nonce = $.userNonces[recipient]++;

        _dispatchDepositToMantle(recipient, amount, nonce);

        emit GatewayDepositRecorded(recipient, amount, gatewayNonce);
        emit Deposited(recipient, amount, nonce);
    }

    // ----------------------------------------------------------
    // WITHDRAWAL -- owner-initiated (emergency / direct)
    // ----------------------------------------------------------

    /**
     * @inheritdoc IUnifiedLiquidityBridge
     *
     * @dev Emergency withdrawal by the owner.  Because this path does not
     *      target a specific user's unifiedBalance, the withdrawn amount is
     *      recorded in `emergencyShortfall`.  Callers can query
     *      `getEmergencyShortfall()` to see the cumulative shortfall.
     */
    function withdrawToRecipient(uint256 amount, address recipient) external onlyOwner nonReentrant {
        if (amount == 0) revert ULB_ZeroAmount();
        if (recipient == address(0)) revert ULB_ZeroAddress();

        Storage storage $ = getStorage();

        // --- Finding 4 fix: explicit underflow guard before subtraction --------
        if ($.totalVault < amount) {
            revert ULB_VaultUnderflow($.totalVault, amount);
        }
        // ----------------------------------------------------------------------

        // Decrease total vault tracking.
        $.totalVault -= amount;

        // --- Finding 3 fix: record the shortfall ------------------------------
        $.emergencyShortfall += amount;
        // ----------------------------------------------------------------------

        // Transfer USDC out (Checks-Effects-Interactions: state updated above).
        IERC20($.usdc).safeTransfer(recipient, amount);

        emit EmergencyWithdraw(recipient, amount, $.emergencyShortfall);
        emit WithdrawExecuted(recipient, amount);
    }

    // ----------------------------------------------------------
    // CROSS-CHAIN MESSAGE HANDLER (Hyperlane -> this contract)
    // ----------------------------------------------------------

    /**
     * @inheritdoc IMessageRecipient
     *
     * @dev Receives LIQUIDITY_WITHDRAW and LIQUIDITY_DEPOSIT messages from
     *      Mantle.  Validates origin domain and sender address, replay guard,
     *      then routes to the appropriate internal handler.
     */
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _messageBody
    ) external payable override(IMessageRecipient, IUnifiedLiquidityBridge) onlyMailbox nonReentrant {
        Storage storage $ = getStorage();

        // Validate origin is Mantle.
        if (_origin != $.mantleDomain) {
            revert ULB_InvalidOrigin(_origin);
        }

        // Validate sender is the authorized MantleSideChainManager.
        bytes32 expectedSender = bytes32(uint256(uint160($.mantleManager)));
        if (_sender != expectedSender) {
            revert ULB_InvalidSender(_sender);
        }

        // Replay protection (message-level).
        bytes32 messageId = UnifiedLiquidityMessages.generateMessageId(_origin, _sender, _messageBody);
        if ($.processedMessages[messageId]) {
            revert ULB_MessageAlreadyProcessed(messageId);
        }
        $.processedMessages[messageId] = true;

        // Decode message type and route.
        uint8 messageType = UnifiedLiquidityMessages.decodeMessageType(_messageBody);

        if (messageType == UnifiedLiquidityMessages.LIQUIDITY_WITHDRAW) {
            _handleWithdraw(_messageBody);
        } else if (messageType == UnifiedLiquidityMessages.LIQUIDITY_DEPOSIT) {
            // --- Finding 7 fix: handle deposit messages from Mantle -----------
            _handleDeposit(_messageBody);
            // ------------------------------------------------------------------
        } else {
            revert ULB_InvalidMessageType(messageType);
        }
    }

    // ----------------------------------------------------------
    // CONFIGURATION (owner only)
    // ----------------------------------------------------------

    /// @inheritdoc IUnifiedLiquidityBridge
    function setMailbox(address _mailbox) external onlyOwner {
        Storage storage $ = getStorage();
        address old = $.mailbox;
        $.mailbox = _mailbox;
        emit MailboxUpdated(old, _mailbox);
    }

    /// @inheritdoc IUnifiedLiquidityBridge
    function setMantleManager(address _mantleManager, uint32 _mantleDomain) external onlyOwner {
        Storage storage $ = getStorage();
        address oldManager = $.mantleManager;
        uint32 oldDomain = $.mantleDomain;
        $.mantleManager = _mantleManager;
        $.mantleDomain = _mantleDomain;
        emit MantleManagerUpdated(oldDomain, oldManager, _mantleDomain, _mantleManager);
    }

    /// @inheritdoc IUnifiedLiquidityBridge
    function setAuthorizedDepositor(address depositor, bool authorized) external onlyOwner {
        getStorage().authorizedDepositors[depositor] = authorized;
        emit AuthorizedDepositorSet(depositor, authorized);
    }

    // ----------------------------------------------------------
    // VIEW
    // ----------------------------------------------------------

    /// @inheritdoc IUnifiedLiquidityBridge
    function totalVaultBalance() external view returns (uint256) {
        return getStorage().totalVault;
    }

    /// @inheritdoc IUnifiedLiquidityBridge
    function unifiedBalanceOf(address user) external view returns (uint256) {
        return getStorage().unifiedBalance[user];
    }

    /// @inheritdoc IUnifiedLiquidityBridge
    function isGatewayNonceUsed(bytes32 nonce) external view returns (bool) {
        return getStorage().usedGatewayNonces[nonce];
    }

    /// @inheritdoc IUnifiedLiquidityBridge
    function getMailbox() external view returns (address) {
        return getStorage().mailbox;
    }

    /// @inheritdoc IUnifiedLiquidityBridge
    function getMantleConfig() external view returns (uint32 domain, address manager) {
        Storage storage $ = getStorage();
        return ($.mantleDomain, $.mantleManager);
    }

    /// @inheritdoc IUnifiedLiquidityBridge
    function getEmergencyShortfall() external view returns (uint256) {
        return getStorage().emergencyShortfall;
    }

    // ----------------------------------------------------------
    // Internal helpers
    // ----------------------------------------------------------

    /**
     * @dev Encode and dispatch a LIQUIDITY_DEPOSIT message to Mantle.
     *      Quotes the Hyperlane fee first and forwards it with the dispatch call.
     *      Reverts if the mailbox or mantleManager is not configured.
     */
    function _dispatchDepositToMantle(address recipient, uint256 amount, uint256 nonce) internal {
        Storage storage $ = getStorage();

        if ($.mailbox == address(0)) revert ULB_MailboxNotSet();
        if ($.mantleManager == address(0)) revert ULB_MantleManagerNotSet();

        bytes memory body = UnifiedLiquidityMessages.encodeLiquidityDeposit(
            recipient,
            amount,
            $.localDomain,
            nonce
        );

        bytes32 recipientSlot = bytes32(uint256(uint160($.mantleManager)));

        // --- Finding 5 fix: quote and pay the Hyperlane dispatch fee ----------
        uint256 fee = IMailbox($.mailbox).quoteDispatch($.mantleDomain, recipientSlot, body);
        IMailbox($.mailbox).dispatch{value: fee}($.mantleDomain, recipientSlot, body);
        // ----------------------------------------------------------------------
    }

    /**
     * @dev Process a verified LIQUIDITY_WITHDRAW message from Mantle.
     *      Validates the nonce, deducts from totalVault, and transfers USDC
     *      to the recipient.
     */
    function _handleWithdraw(bytes calldata messageBody) internal {
        UnifiedLiquidityMessages.LiquidityWithdrawMessage memory msg_ =
            UnifiedLiquidityMessages.decodeLiquidityWithdraw(messageBody);

        Storage storage $ = getStorage();

        // --- Finding 6 fix: enforce the per-sender nonce ----------------------
        if ($.processedNonces[msg_.sourceChainId][msg_.nonce]) {
            revert ULB_DuplicateNonce(msg_.sourceChainId, msg_.nonce);
        }
        $.processedNonces[msg_.sourceChainId][msg_.nonce] = true;
        // ----------------------------------------------------------------------

        // --- Finding 4 fix: explicit underflow guard ---------------------------
        if ($.totalVault < msg_.amount) {
            revert ULB_VaultUnderflow($.totalVault, msg_.amount);
        }
        // ----------------------------------------------------------------------

        // Decrease vault total.
        $.totalVault -= msg_.amount;

        // Release USDC to the recipient (Checks-Effects-Interactions: state
        // already mutated above).
        IERC20($.usdc).safeTransfer(msg_.recipient, msg_.amount);

        emit WithdrawMessageReceived(msg_.recipient, msg_.amount, msg_.sourceChainId);
        emit WithdrawExecuted(msg_.recipient, msg_.amount);
    }

    /**
     * @dev Process a verified LIQUIDITY_DEPOSIT message from Mantle.
     *      Credits the unified balance for the specified recipient on Arc.
     *      This is the symmetric counterpart to MantleSideChainManager._handleDeposit.
     */
    function _handleDeposit(bytes calldata messageBody) internal {
        UnifiedLiquidityMessages.LiquidityDepositMessage memory msg_ =
            UnifiedLiquidityMessages.decodeLiquidityDeposit(messageBody);

        Storage storage $ = getStorage();

        // --- Finding 6 fix: enforce the per-sender nonce ----------------------
        if ($.processedNonces[msg_.sourceChainId][msg_.nonce]) {
            revert ULB_DuplicateNonce(msg_.sourceChainId, msg_.nonce);
        }
        $.processedNonces[msg_.sourceChainId][msg_.nonce] = true;
        // ----------------------------------------------------------------------

        $.unifiedBalance[msg_.recipient] += msg_.amount;

        emit DepositMessageReceived(msg_.recipient, msg_.amount, msg_.sourceChainId);
    }
}
