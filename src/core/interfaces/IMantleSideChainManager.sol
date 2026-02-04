// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IMantleSideChainManager
 * @dev Interface for the Mantle-side unified liquidity manager.
 *
 * Mirror of the Arc vault.  Does NOT hold real USDC on Mantle;
 * instead it tracks per-user "mirrored" balances that represent
 * a 1:1 claim on USDC locked inside UnifiedLiquidityBridge on Arc.
 *
 * All amounts are in USDC native decimals (6).
 */
interface IMantleSideChainManager {
    // =========================================================
    //  DEPOSIT (Mantle side -- local entry point)
    // =========================================================

    /**
     * @dev Deposit USDC locally on Mantle into the manager.
     *      The contract pulls `amount` from msg.sender and dispatches
     *      a LIQUIDITY_DEPOSIT message to Arc so the bridge can mirror
     *      the position there as well.
     *      Send native value to cover the Hyperlane dispatch fee.
     * @param amount    USDC amount (6 decimals).
     * @param recipient Owner of the mirrored balance.
     */
    function depositLocal(uint256 amount, address recipient) external payable;

    // =========================================================
    //  WITHDRAWAL REQUEST (Mantle side -- called by end-users)
    // =========================================================

    /**
     * @dev Request a USDC withdrawal from the Arc vault.
     *      Deducts from the caller's mirrored balance on Mantle and
     *      dispatches a LIQUIDITY_WITHDRAW message to Arc.
     *      Arc will release USDC to `recipient` once the message is
     *      processed.
     *      Send native value to cover the Hyperlane dispatch fee.
     * @param amount    USDC amount (6 decimals).
     * @param recipient Address that will receive USDC on Arc.
     */
    function requestWithdraw(uint256 amount, address recipient) external payable;

    // =========================================================
    //  CROSS-CHAIN MESSAGE HANDLER
    // =========================================================

    /**
     * @dev Hyperlane IMessageRecipient entry point.
     *      Receives LIQUIDITY_DEPOSIT confirmations from Arc.
     */
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _messageBody) external payable;

    // =========================================================
    //  CONFIGURATION (owner only)
    // =========================================================

    function setMailbox(address _mailbox) external;
    function setArcBridge(address _arcBridge, uint32 _arcDomain) external;
    function setLocalUSDC(address _usdc) external;

    // =========================================================
    //  VIEW
    // =========================================================

    /**
     * @return The mirrored USDC balance of `user` on Mantle.
     */
    function mirroredBalanceOf(address user) external view returns (uint256);

    /**
     * @return Total mirrored supply across all users.
     */
    function totalMirroredSupply() external view returns (uint256);

    /**
     * @return The configured Hyperlane mailbox address.
     */
    function getMailbox() external view returns (address);

    /**
     * @return domain The Arc domain ID.
     * @return bridge The UnifiedLiquidityBridge address.
     */
    function getArcConfig() external view returns (uint32 domain, address bridge);

    /**
     * @return The local USDC token address on Mantle.
     */
    function getLocalUSDC() external view returns (address);

    // =========================================================
    //  EVENTS
    // =========================================================

    event LocalDeposited(address indexed recipient, uint256 amount);
    event MirroredDepositReceived(address indexed recipient, uint256 amount, uint32 indexed originDomain);
    event WithdrawRequested(address indexed requester, address indexed recipient, uint256 amount);
    event MailboxUpdated(address indexed oldMailbox, address indexed newMailbox);
    event ArcBridgeUpdated(uint32 indexed oldDomain, address indexed oldBridge, uint32 newDomain, address indexed newBridge);
    event LocalUSDCUpdated(address indexed oldUsdc, address indexed newUsdc);
}
