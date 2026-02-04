// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IUnifiedLiquidityBridge
 * @dev Interface for the Arc-side unified liquidity bridge.
 *
 * Terminology used throughout:
 *   - "Arc"    = core chain (chain ID 5042002).  Holds real USDC via Circle Gateway.
 *   - "Mantle" = sidechain (chain ID 5003).      Tracks mirrored USDC balances.
 *   - All amounts are in USDC native decimals (6).
 */
interface IUnifiedLiquidityBridge {
    // =========================================================
    //  DEPOSIT (Arc side -- called by end-users)
    // =========================================================

    /**
     * @dev Deposit USDC directly into the bridge vault on Arc.
     *      Pulls `amount` from msg.sender, records a unified balance,
     *      and dispatches a Hyperlane LIQUIDITY_DEPOSIT message to Mantle
     *      so the MantleSideChainManager can mirror the position.
     *      Send native value to cover the Hyperlane dispatch fee.
     * @param amount   USDC amount (6 decimals).
     * @param recipient The address that owns the unified balance (can differ from msg.sender).
     */
    function deposit(uint256 amount, address recipient) external payable;

    /**
     * @dev Record a USDC deposit that was minted by the Circle Gateway on Arc.
     *      The caller proves the mint happened by supplying the Gateway attestation
     *      nonce.  The contract verifies the nonce has not been replayed, credits
     *      the unified balance, and dispatches to Mantle.
     *      Send native value to cover the Hyperlane dispatch fee.
     * @param amount          USDC amount (6 decimals).
     * @param recipient       Owner of the unified balance.
     * @param gatewayNonce    Unique nonce issued by the Circle Gateway minter for replay protection.
     */
    function depositViaGateway(uint256 amount, address recipient, bytes32 gatewayNonce) external payable;

    // =========================================================
    //  WITHDRAWAL REQUEST (Arc side -- triggered by Mantle message)
    // =========================================================

    /**
     * @dev Withdraw USDC from the Arc vault to a recipient.
     *      Only callable by the owner (used as an emergency escape).
     *      The withdrawn amount is tracked as emergencyShortfall rather than
     *      being deducted from any specific user's unifiedBalance.
     * @param amount    USDC amount (6 decimals).
     * @param recipient Token recipient on Arc.
     */
    function withdrawToRecipient(uint256 amount, address recipient) external;

    // =========================================================
    //  CROSS-CHAIN MESSAGE HANDLER
    // =========================================================

    /**
     * @dev Hyperlane IMessageRecipient entry point.
     *      Receives LIQUIDITY_WITHDRAW and LIQUIDITY_DEPOSIT messages
     *      originating on Mantle.
     */
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _messageBody) external payable;

    // =========================================================
    //  CONFIGURATION (owner only)
    // =========================================================

    /**
     * @dev Set or update the Hyperlane mailbox address used for dispatching.
     */
    function setMailbox(address _mailbox) external;

    /**
     * @dev Set the Mantle-side MantleSideChainManager address that is the
     *      authorized cross-chain counterpart.
     */
    function setMantleManager(address _mantleManager, uint32 _mantleDomain) external;

    /**
     * @dev Whitelist or de-list an address as an authorized depositor
     *      (e.g. the Circle Gateway minter contract).
     */
    function setAuthorizedDepositor(address depositor, bool authorized) external;

    // =========================================================
    //  VIEW
    // =========================================================

    /**
     * @return The total USDC held in the Arc vault.
     */
    function totalVaultBalance() external view returns (uint256);

    /**
     * @return The unified USDC balance credited to `user` on the Arc side.
     */
    function unifiedBalanceOf(address user) external view returns (uint256);

    /**
     * @return Whether `nonce` has already been consumed (Gateway replay check).
     */
    function isGatewayNonceUsed(bytes32 nonce) external view returns (bool);

    /**
     * @return The configured Hyperlane mailbox address.
     */
    function getMailbox() external view returns (address);

    /**
     * @return domain  The Mantle domain ID.
     * @return manager The MantleSideChainManager address.
     */
    function getMantleConfig() external view returns (uint32 domain, address manager);

    /**
     * @return The cumulative USDC withdrawn by the owner via withdrawToRecipient
     *         without a corresponding user-balance deduction.
     */
    function getEmergencyShortfall() external view returns (uint256);

    // =========================================================
    //  EVENTS
    // =========================================================

    event Deposited(address indexed recipient, uint256 amount, uint256 indexed nonce);
    event GatewayDepositRecorded(address indexed recipient, uint256 amount, bytes32 indexed gatewayNonce);
    event WithdrawMessageReceived(address indexed recipient, uint256 amount, uint32 indexed originDomain);
    event DepositMessageReceived(address indexed recipient, uint256 amount, uint32 indexed originDomain);
    event WithdrawExecuted(address indexed recipient, uint256 amount);
    event EmergencyWithdraw(address indexed recipient, uint256 amount, uint256 totalShortfall);
    event MailboxUpdated(address indexed oldMailbox, address indexed newMailbox);
    event MantleManagerUpdated(uint32 indexed oldDomain, address indexed oldManager, uint32 newDomain, address indexed newManager);
    event AuthorizedDepositorSet(address indexed depositor, bool authorized);
}
