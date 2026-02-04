// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title UnifiedLiquidityBridgeStorage
 * @dev EIP-1967-style storage layout for UnifiedLiquidityBridge.
 *
 * Slot derivation (matches the pattern used by ChainBalanceManagerStorage):
 *   bytes32(uint256(keccak256("scalex.clob.storage.unifiedliquiditybridge")) - 1)
 *
 * All amounts are in USDC native decimals (6).
 */
abstract contract UnifiedLiquidityBridgeStorage {
    // Inline computation -- identical pattern to ChainBalanceManagerStorage.
    bytes32 private constant STORAGE_SLOT =
        bytes32(uint256(keccak256("scalex.clob.storage.unifiedliquiditybridge")) - 1);

    struct Storage {
        // -------------------------------------------------------
        // Vault accounting
        // -------------------------------------------------------
        /// Per-user unified USDC balance on Arc.
        mapping(address => uint256) unifiedBalance;
        /// Total USDC held in this contract (redundant with ERC20.balanceOf but
        /// kept for O(1) view without an external call).
        uint256 totalVault;

        // -------------------------------------------------------
        // Cross-chain config
        // -------------------------------------------------------
        /// Hyperlane mailbox on Arc.
        address mailbox;
        /// Hyperlane domain ID of THIS chain (Arc = 5042002).
        uint32 localDomain;
        /// Hyperlane domain ID of Mantle (5003).
        uint32 mantleDomain;
        /// MantleSideChainManager contract address on Mantle.
        address mantleManager;

        // -------------------------------------------------------
        // Circle Gateway integration
        // -------------------------------------------------------
        /// Set of addresses allowed to call depositViaGateway
        /// (typically the Circle Gateway Minter on Arc).
        mapping(address => bool) authorizedDepositors;
        /// Consumed Gateway attestation nonces -- replay guard.
        mapping(bytes32 => bool) usedGatewayNonces;

        // -------------------------------------------------------
        // Replay protection for Hyperlane messages
        // -------------------------------------------------------
        /// Monotonic per-user nonce incremented on every outbound dispatch.
        mapping(address => uint256) userNonces;
        /// Set of already-processed inbound Hyperlane message IDs.
        mapping(bytes32 => bool) processedMessages;
        /// Processed inbound nonces keyed by (sourceChainId, nonce) to enforce
        /// the per-sender monotonic nonce carried inside every message payload.
        mapping(uint32 => mapping(uint256 => bool)) processedNonces;

        // -------------------------------------------------------
        // USDC token address on Arc
        // -------------------------------------------------------
        address usdc;

        // -------------------------------------------------------
        // Emergency shortfall tracking
        // -------------------------------------------------------
        /// Accumulated USDC withdrawn by the owner via withdrawToRecipient
        /// without a matching user-balance deduction.  Tracked so that the
        /// total obligation (sum of unifiedBalance) minus emergencyShortfall
        /// equals the amount still backed by the vault.
        uint256 emergencyShortfall;
    }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}
