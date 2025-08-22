// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

abstract contract ChainRegistryStorage {
    // keccak256(abi.encode(uint256(keccak256("gtx.clob.storage.chainregistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x9a2f4f6c8b3e1d5a7e9f2b4c6d8e0f1a3b5c7d9e0f2a4b6c8d0e1f3a5b7c9d00;

    struct ChainConfig {
        uint32 domainId;           // Hyperlane domain identifier
        address mailbox;           // Hyperlane mailbox address on this chain
        string rpcEndpoint;        // RPC endpoint for this chain
        bool isActive;             // Whether chain is active for cross-chain operations
        string name;               // Human readable chain name
        uint256 blockTime;         // Average block time in seconds
    }

    struct Storage {
        // Mapping from chain ID to chain configuration
        mapping(uint32 => ChainConfig) chains;
        
        // Mapping from domain ID to chain ID (reverse lookup)
        mapping(uint32 => uint32) domainToChain;
        
        // Array of all registered chain IDs
        uint32[] registeredChains;
    }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}