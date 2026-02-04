// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title MantleSideChainManagerStorage
 * @dev EIP-1967-style storage layout for MantleSideChainManager.
 *
 * Slot derivation (matches ChainBalanceManagerStorage pattern):
 *   bytes32(uint256(keccak256("scalex.clob.storage.mantlesidechainmanager")) - 1)
 *
 * All amounts are in USDC native decimals (6).
 */
abstract contract MantleSideChainManagerStorage {
    // Inline computation -- identical pattern to ChainBalanceManagerStorage.
    bytes32 private constant STORAGE_SLOT =
        bytes32(uint256(keccak256("scalex.clob.storage.mantlesidechainmanager")) - 1);

    struct Storage {
        // -------------------------------------------------------
        // Mirrored balance accounting
        // -------------------------------------------------------
        /// Per-user mirrored USDC balance (claim on Arc vault).
        mapping(address => uint256) mirroredBalance;
        /// Total mirrored supply across all users.
        uint256 totalMirrored;

        // -------------------------------------------------------
        // Cross-chain config
        // -------------------------------------------------------
        /// Hyperlane mailbox on Mantle.
        address mailbox;
        /// Hyperlane domain ID of THIS chain (Mantle = 5003).
        uint32 localDomain;
        /// Hyperlane domain ID of Arc (5042002).
        uint32 arcDomain;
        /// UnifiedLiquidityBridge contract address on Arc.
        address arcBridge;

        // -------------------------------------------------------
        // Local USDC on Mantle (bridged token)
        // -------------------------------------------------------
        address usdc;

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
    }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}
