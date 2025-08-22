// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TokenRegistryStorage} from "./storages/TokenRegistryStorage.sol";

/**
 * @title TokenRegistry
 * @dev Central registry for managing cross-chain token mappings and metadata
 * Maps source tokens to synthetic tokens across different chains
 */
contract TokenRegistry is Initializable, OwnableUpgradeable, TokenRegistryStorage {
    
    // Events
    event TokenMappingRegistered(
        uint32 indexed sourceChainId,
        address indexed sourceToken,
        uint32 indexed targetChainId,
        address syntheticToken,
        string symbol
    );
    event TokenMappingUpdated(
        uint32 indexed sourceChainId,
        address indexed sourceToken,
        uint32 indexed targetChainId,
        address oldSynthetic,
        address newSynthetic
    );
    event TokenMappingRemoved(
        uint32 indexed sourceChainId,
        address indexed sourceToken,
        uint32 indexed targetChainId
    );
    event TokenStatusChanged(
        uint32 indexed sourceChainId,
        address indexed sourceToken,
        uint32 indexed targetChainId,
        bool isActive
    );
    
    // Errors
    error TokenMappingNotFound(uint32 sourceChainId, address sourceToken, uint32 targetChainId);
    error TokenMappingAlreadyExists(uint32 sourceChainId, address sourceToken, uint32 targetChainId);
    error InvalidTokenAddress();
    error InvalidChainId();
    error DecimalMismatch(uint8 sourceDecimals, uint8 syntheticDecimals);
    error TokenNotActive(uint32 sourceChainId, address sourceToken, uint32 targetChainId);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        
        // Register default Espresso testnet token mappings
        _registerDefaultMappings();
    }
    
    /**
     * @dev Register a new token mapping between source and synthetic tokens
     */
    function registerTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address syntheticToken,
        string memory symbol,
        uint8 sourceDecimals,
        uint8 syntheticDecimals
    ) external onlyOwner {
        if (sourceChainId == 0 || targetChainId == 0) revert InvalidChainId();
        if (sourceToken == address(0) || syntheticToken == address(0)) revert InvalidTokenAddress();
        
        Storage storage $ = getStorage();
        
        bytes32 mappingKey = _getMappingKey(sourceChainId, sourceToken, targetChainId);
        if ($.tokenMappings[mappingKey].syntheticToken != address(0)) {
            revert TokenMappingAlreadyExists(sourceChainId, sourceToken, targetChainId);
        }
        
        // Store the mapping
        $.tokenMappings[mappingKey] = TokenMapping({
            sourceChainId: sourceChainId,
            sourceToken: sourceToken,
            targetChainId: targetChainId,
            syntheticToken: syntheticToken,
            symbol: symbol,
            sourceDecimals: sourceDecimals,
            syntheticDecimals: syntheticDecimals,
            isActive: true,
            registeredAt: block.timestamp
        });
        
        // Add to reverse mapping for lookups
        bytes32 reverseKey = _getReverseMappingKey(targetChainId, syntheticToken);
        $.reverseMappings[reverseKey] = ReverseMapping({
            sourceChainId: sourceChainId,
            sourceToken: sourceToken
        });
        
        // Add to chain mappings for enumeration
        $.chainToTokens[sourceChainId].push(sourceToken);
        
        emit TokenMappingRegistered(sourceChainId, sourceToken, targetChainId, syntheticToken, symbol);
    }
    
    /**
     * @dev Update an existing token mapping
     */
    function updateTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address newSyntheticToken,
        uint8 newSyntheticDecimals
    ) external onlyOwner {
        Storage storage $ = getStorage();
        
        bytes32 mappingKey = _getMappingKey(sourceChainId, sourceToken, targetChainId);
        TokenMapping storage tokenMapping = $.tokenMappings[mappingKey];
        
        if (tokenMapping.syntheticToken == address(0)) {
            revert TokenMappingNotFound(sourceChainId, sourceToken, targetChainId);
        }
        
        address oldSynthetic = tokenMapping.syntheticToken;
        
        // Remove old reverse mapping
        bytes32 oldReverseKey = _getReverseMappingKey(targetChainId, oldSynthetic);
        delete $.reverseMappings[oldReverseKey];
        
        // Update mapping
        tokenMapping.syntheticToken = newSyntheticToken;
        tokenMapping.syntheticDecimals = newSyntheticDecimals;
        
        // Add new reverse mapping
        bytes32 newReverseKey = _getReverseMappingKey(targetChainId, newSyntheticToken);
        $.reverseMappings[newReverseKey] = ReverseMapping({
            sourceChainId: sourceChainId,
            sourceToken: sourceToken
        });
        
        emit TokenMappingUpdated(sourceChainId, sourceToken, targetChainId, oldSynthetic, newSyntheticToken);
    }
    
    /**
     * @dev Set token mapping status (active/inactive)
     */
    function setTokenMappingStatus(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        bool isActive
    ) external onlyOwner {
        Storage storage $ = getStorage();
        
        bytes32 mappingKey = _getMappingKey(sourceChainId, sourceToken, targetChainId);
        TokenMapping storage tokenMapping = $.tokenMappings[mappingKey];
        
        if (tokenMapping.syntheticToken == address(0)) {
            revert TokenMappingNotFound(sourceChainId, sourceToken, targetChainId);
        }
        
        tokenMapping.isActive = isActive;
        
        emit TokenStatusChanged(sourceChainId, sourceToken, targetChainId, isActive);
    }
    
    /**
     * @dev Remove a token mapping
     */
    function removeTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId
    ) external onlyOwner {
        Storage storage $ = getStorage();
        
        bytes32 mappingKey = _getMappingKey(sourceChainId, sourceToken, targetChainId);
        TokenMapping storage tokenMapping = $.tokenMappings[mappingKey];
        
        if (tokenMapping.syntheticToken == address(0)) {
            revert TokenMappingNotFound(sourceChainId, sourceToken, targetChainId);
        }
        
        // Remove reverse mapping
        bytes32 reverseKey = _getReverseMappingKey(targetChainId, tokenMapping.syntheticToken);
        delete $.reverseMappings[reverseKey];
        
        // Remove main mapping
        delete $.tokenMappings[mappingKey];
        
        emit TokenMappingRemoved(sourceChainId, sourceToken, targetChainId);
    }
    
    /**
     * @dev Get token mapping information
     */
    function getTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId
    ) external view returns (TokenMapping memory) {
        Storage storage $ = getStorage();
        
        bytes32 mappingKey = _getMappingKey(sourceChainId, sourceToken, targetChainId);
        TokenMapping memory tokenMapping = $.tokenMappings[mappingKey];
        
        if (tokenMapping.syntheticToken == address(0)) {
            revert TokenMappingNotFound(sourceChainId, sourceToken, targetChainId);
        }
        
        return tokenMapping;
    }
    
    /**
     * @dev Get synthetic token address for a source token
     */
    function getSyntheticToken(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId
    ) external view returns (address) {
        Storage storage $ = getStorage();
        
        bytes32 mappingKey = _getMappingKey(sourceChainId, sourceToken, targetChainId);
        return $.tokenMappings[mappingKey].syntheticToken;
    }
    
    /**
     * @dev Get source token information from synthetic token (reverse lookup)
     */
    function getSourceToken(
        uint32 targetChainId,
        address syntheticToken
    ) external view returns (uint32 sourceChainId, address sourceToken) {
        Storage storage $ = getStorage();
        
        bytes32 reverseKey = _getReverseMappingKey(targetChainId, syntheticToken);
        ReverseMapping memory reverseMapping = $.reverseMappings[reverseKey];
        
        return (reverseMapping.sourceChainId, reverseMapping.sourceToken);
    }
    
    /**
     * @dev Check if a token mapping exists and is active
     */
    function isTokenMappingActive(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId
    ) external view returns (bool) {
        Storage storage $ = getStorage();
        
        bytes32 mappingKey = _getMappingKey(sourceChainId, sourceToken, targetChainId);
        TokenMapping memory tokenMapping = $.tokenMappings[mappingKey];
        
        return tokenMapping.syntheticToken != address(0) && tokenMapping.isActive;
    }
    
    /**
     * @dev Get all source tokens for a specific chain
     */
    function getChainTokens(uint32 sourceChainId) external view returns (address[] memory) {
        return getStorage().chainToTokens[sourceChainId];
    }
    
    /**
     * @dev Convert amount between different decimal standards
     */
    function convertAmount(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) external pure returns (uint256) {
        return _convertAmount(amount, fromDecimals, toDecimals);
    }
    
    /**
     * @dev Internal function to convert amount between different decimal standards
     */
    function _convertAmount(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals > toDecimals) {
            return amount / (10 ** (fromDecimals - toDecimals));
        } else {
            return amount * (10 ** (toDecimals - fromDecimals));
        }
    }
    
    /**
     * @dev Convert amount using token mapping decimals
     */
    function convertAmountForMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        uint256 amount,
        bool sourceToSynthetic
    ) external view returns (uint256) {
        Storage storage $ = getStorage();
        
        bytes32 mappingKey = _getMappingKey(sourceChainId, sourceToken, targetChainId);
        TokenMapping memory tokenMapping = $.tokenMappings[mappingKey];
        
        if (tokenMapping.syntheticToken == address(0)) {
            revert TokenMappingNotFound(sourceChainId, sourceToken, targetChainId);
        }
        
        if (sourceToSynthetic) {
            return _convertAmount(amount, tokenMapping.sourceDecimals, tokenMapping.syntheticDecimals);
        } else {
            return _convertAmount(amount, tokenMapping.syntheticDecimals, tokenMapping.sourceDecimals);
        }
    }
    
    /**
     * @dev Generate mapping key for storage
     */
    function _getMappingKey(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(sourceChainId, sourceToken, targetChainId));
    }
    
    /**
     * @dev Generate reverse mapping key for storage
     */
    function _getReverseMappingKey(
        uint32 targetChainId,
        address syntheticToken
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(targetChainId, syntheticToken));
    }
    
    /**
     * @dev Register default Espresso testnet token mappings
     */
    function _registerDefaultMappings() internal {
        Storage storage $ = getStorage();
        
        // Appchain USDT -> Rari gsUSDT
        bytes32 usdtKey = _getMappingKey(4661, 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516, 1918988905);
        $.tokenMappings[usdtKey] = TokenMapping({
            sourceChainId: 4661,
            sourceToken: 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516,
            targetChainId: 1918988905,
            syntheticToken: 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68,
            symbol: "gsUSDT",
            sourceDecimals: 6,
            syntheticDecimals: 6,
            isActive: true,
            registeredAt: block.timestamp
        });
        
        bytes32 usdtReverseKey = _getReverseMappingKey(1918988905, 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68);
        $.reverseMappings[usdtReverseKey] = ReverseMapping({
            sourceChainId: 4661,
            sourceToken: 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516
        });
        
        $.chainToTokens[4661].push(0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516);
        
        // Appchain WETH -> Rari gsWETH
        bytes32 wethKey = _getMappingKey(4661, 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F, 1918988905);
        $.tokenMappings[wethKey] = TokenMapping({
            sourceChainId: 4661,
            sourceToken: 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F,
            targetChainId: 1918988905,
            syntheticToken: 0xC7A1777e80982E01e07406e6C6E8B30F5968F836,
            symbol: "gsWETH",
            sourceDecimals: 18,
            syntheticDecimals: 18,
            isActive: true,
            registeredAt: block.timestamp
        });
        
        bytes32 wethReverseKey = _getReverseMappingKey(1918988905, 0xC7A1777e80982E01e07406e6C6E8B30F5968F836);
        $.reverseMappings[wethReverseKey] = ReverseMapping({
            sourceChainId: 4661,
            sourceToken: 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F
        });
        
        $.chainToTokens[4661].push(0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F);
        
        // Appchain WBTC -> Rari gsWBTC
        bytes32 wbtcKey = _getMappingKey(4661, 0xb2e9Eabb827b78e2aC66bE17327603778D117d18, 1918988905);
        $.tokenMappings[wbtcKey] = TokenMapping({
            sourceChainId: 4661,
            sourceToken: 0xb2e9Eabb827b78e2aC66bE17327603778D117d18,
            targetChainId: 1918988905,
            syntheticToken: 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF,
            symbol: "gsWBTC",
            sourceDecimals: 8,
            syntheticDecimals: 8,
            isActive: true,
            registeredAt: block.timestamp
        });
        
        bytes32 wbtcReverseKey = _getReverseMappingKey(1918988905, 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF);
        $.reverseMappings[wbtcReverseKey] = ReverseMapping({
            sourceChainId: 4661,
            sourceToken: 0xb2e9Eabb827b78e2aC66bE17327603778D117d18
        });
        
        $.chainToTokens[4661].push(0xb2e9Eabb827b78e2aC66bE17327603778D117d18);
    }
}