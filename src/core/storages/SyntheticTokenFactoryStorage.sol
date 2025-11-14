// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TokenRegistry} from "../TokenRegistry.sol";

abstract contract SyntheticTokenFactoryStorage {
    // keccak256(abi.encode(uint256(keccak256("scalex.clob.storage.synthetictokenfactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x8c4f9e3b2d6a1e5f7c9a3b8e1d4c7a0f3b6e9c2a5d8f1b4c7e0a3d6c9b2f5e00;

    struct SourceTokenInfo {
        uint32 sourceChainId;        // Chain ID of the source token
        address sourceToken;         // Address of the source token
        uint8 sourceDecimals;        // Decimals of the source token
        uint8 syntheticDecimals;     // Decimals of the synthetic token
        bool isActive;               // Whether this synthetic token is active
        uint256 createdAt;           // Timestamp when synthetic token was created
    }

    struct TokenCreationParams {
        uint32 sourceChainId;        // Chain ID of the source token
        address sourceToken;         // Address of the source token
        string name;                 // Name of the synthetic token
        string symbol;               // Symbol of the synthetic token
        uint8 sourceDecimals;        // Decimals of the source token
        uint8 syntheticDecimals;     // Decimals of the synthetic token
    }

    struct Storage {
        // Core contracts
        TokenRegistry tokenRegistry;        // TokenRegistry contract for managing mappings
        address bridgeReceiver;             // Address that can mint/burn synthetic tokens
        
        // Mappings: keccak256(sourceChainId, sourceToken) => syntheticToken
        mapping(bytes32 => address) sourceToSynthetic;
        
        // Reverse mappings: syntheticToken => SourceTokenInfo
        mapping(address => SourceTokenInfo) syntheticToSource;
        
        // Enumeration arrays
        address[] allSyntheticTokens;                           // All synthetic tokens
        mapping(uint32 => address[]) chainToSynthetics;         // Chain ID => synthetic tokens[]
    }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}