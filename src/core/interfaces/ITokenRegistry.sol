// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title ITokenRegistry
 * @dev Interface for TokenRegistry contract
 */
interface ITokenRegistry {
    // Core functions
    function initialize(address _owner) external;
    
    // Token mapping management
    function registerTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address syntheticToken,
        string memory tokenName,
        uint8 sourceDecimals,
        uint8 targetDecimals
    ) external;
    
    function updateTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address newSyntheticToken
    ) external;
    
    function setTokenMappingStatus(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        bool isActive
    ) external;
    
    function removeTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId
    ) external;
    
    // Query functions
    function getTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId
    ) external view returns (
        address syntheticToken,
        string memory tokenName,
        uint8 sourceDecimals,
        uint8 targetDecimals,
        bool isActive
    );
    
    function getSyntheticToken(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId
    ) external view returns (address);
    
    function getSourceToken(
        uint32 sourceChainId,
        address syntheticToken,
        uint32 targetChainId
    ) external view returns (address);
    
    function isTokenMappingActive(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId
    ) external view returns (bool);
    
    // Amount conversion
    function convertAmount(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        uint256 amount,
        bool roundUp
    ) external view returns (uint256);
    
    function convertAmountForMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        uint256 amount,
        bool roundUp
    ) external view returns (uint256);
    
    // Legacy functions
    function getSupportedTokens() external view returns (address[] memory);
    function isTokenSupported(address token) external view returns (bool);
    function getChainTokens(uint32 sourceChainId) external view returns (address[] memory);
    
    // Upgrade functions
    function initializeUpgrade(address _newOwner, address _factory) external;
}