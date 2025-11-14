// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

abstract contract BalanceManagerStorage {
    // keccak256(abi.encode(uint256(keccak256("scalex.clob.storage.balancemanager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0xa0938c47b5c654ca88fd5f46a35251d66e96b0e70f06871f4be1ef4fd259f100;

    struct Storage {
        mapping(address => mapping(uint256 => uint256)) balanceOf;
        mapping(address => mapping(address => mapping(uint256 => uint256))) lockedBalanceOf;
        mapping(address => bool) authorizedOperators;
        address poolManager;
        address feeReceiver;
        uint256 feeMaker;
        uint256 feeTaker;
        uint256 feeUnit;
        
        // Cross-chain fields (following example folder pattern)
        address mailbox;                                    // Hyperlane mailbox
        uint32 localDomain;                                // This chain's domain ID  
        mapping(uint32 => address) chainBalanceManagers;   // chainId => ChainBalanceManager address
        mapping(address => uint256) userNonces;            // User nonces for replay protection
        mapping(bytes32 => bool) processedMessages;        // Prevent replay attacks
        address tokenRegistry;                              // TokenRegistry for source->synthetic mapping
        
        // Additional fields for synthetic token and asset management
        mapping(address => address) syntheticTokens;      // Real token => Synthetic token mapping
        mapping(address => bool) supportedAssets;         // Supported real assets
        address lendingManager;                            // Lending protocol manager
        address tokenFactory;                              // Synthetic token factory
        // Removed: userDepositTimes (unused storage variable)
        address[] supportedAssetsList;                     // Dynamic list of supported assets
        
        // Yield tracking fields
        mapping(address => uint256) yieldPerToken;        // underlying token => yield per token (in PRECISION)
        mapping(address => mapping(address => uint256)) userYieldCheckpoints; // user => synthetic token => yield per token checkpoint
      }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}
