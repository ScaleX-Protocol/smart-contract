// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ChainRegistryStorage} from "./storages/ChainRegistryStorage.sol";

/**
 * @title ChainRegistry
 * @dev Central registry for managing cross-chain configurations
 * Stores Hyperlane mailbox addresses, domain mappings, and chain status
 */
contract ChainRegistry is Initializable, OwnableUpgradeable, ChainRegistryStorage {
    
    // Events
    event ChainRegistered(uint32 indexed chainId, uint32 indexed domainId, address mailbox, string name);
    event ChainUpdated(uint32 indexed chainId, address oldMailbox, address newMailbox);
    event ChainStatusChanged(uint32 indexed chainId, bool isActive);
    event ChainRemoved(uint32 indexed chainId);
    
    // Errors
    error ChainNotFound(uint32 chainId);
    error ChainAlreadyExists(uint32 chainId);
    error DomainAlreadyUsed(uint32 domainId);
    error InvalidMailbox();
    error InvalidDomain();
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        
        // Register default Espresso testnet chains
        _registerDefaultChains();
    }
    
    /**
     * @dev Register a new chain configuration
     */
    function registerChain(
        uint32 chainId,
        uint32 domainId,
        address mailbox,
        string memory rpcEndpoint,
        string memory name,
        uint256 blockTime
    ) external onlyOwner {
        Storage storage $ = getStorage();
        
        if ($.chains[chainId].domainId != 0) revert ChainAlreadyExists(chainId);
        if ($.domainToChain[domainId] != 0) revert DomainAlreadyUsed(domainId);
        if (mailbox == address(0)) revert InvalidMailbox();
        if (domainId == 0) revert InvalidDomain();
        
        $.chains[chainId] = ChainConfig({
            domainId: domainId,
            mailbox: mailbox,
            rpcEndpoint: rpcEndpoint,
            isActive: true,
            name: name,
            blockTime: blockTime
        });
        
        $.domainToChain[domainId] = chainId;
        $.registeredChains.push(chainId);
        
        emit ChainRegistered(chainId, domainId, mailbox, name);
    }
    
    /**
     * @dev Update chain configuration
     */
    function updateChain(
        uint32 chainId,
        address newMailbox,
        string memory newRpcEndpoint,
        uint256 newBlockTime
    ) external onlyOwner {
        Storage storage $ = getStorage();
        
        if ($.chains[chainId].domainId == 0) revert ChainNotFound(chainId);
        if (newMailbox == address(0)) revert InvalidMailbox();
        
        address oldMailbox = $.chains[chainId].mailbox;
        
        $.chains[chainId].mailbox = newMailbox;
        $.chains[chainId].rpcEndpoint = newRpcEndpoint;
        $.chains[chainId].blockTime = newBlockTime;
        
        emit ChainUpdated(chainId, oldMailbox, newMailbox);
    }
    
    /**
     * @dev Set chain active status
     */
    function setChainStatus(uint32 chainId, bool isActive) external onlyOwner {
        Storage storage $ = getStorage();
        
        if ($.chains[chainId].domainId == 0) revert ChainNotFound(chainId);
        
        $.chains[chainId].isActive = isActive;
        emit ChainStatusChanged(chainId, isActive);
    }
    
    /**
     * @dev Remove a chain from registry
     */
    function removeChain(uint32 chainId) external onlyOwner {
        Storage storage $ = getStorage();
        
        if ($.chains[chainId].domainId == 0) revert ChainNotFound(chainId);
        
        uint32 domainId = $.chains[chainId].domainId;
        
        // Remove from domain mapping
        delete $.domainToChain[domainId];
        
        // Remove from chains mapping
        delete $.chains[chainId];
        
        // Remove from array
        for (uint256 i = 0; i < $.registeredChains.length; i++) {
            if ($.registeredChains[i] == chainId) {
                $.registeredChains[i] = $.registeredChains[$.registeredChains.length - 1];
                $.registeredChains.pop();
                break;
            }
        }
        
        emit ChainRemoved(chainId);
    }
    
    /**
     * @dev Get chain configuration by chain ID
     */
    function getChainConfig(uint32 chainId) external view returns (ChainConfig memory) {
        Storage storage $ = getStorage();
        
        if ($.chains[chainId].domainId == 0) revert ChainNotFound(chainId);
        return $.chains[chainId];
    }
    
    /**
     * @dev Get chain ID by domain ID
     */
    function getChainByDomain(uint32 domainId) external view returns (uint32) {
        return getStorage().domainToChain[domainId];
    }
    
    /**
     * @dev Get mailbox address for a chain
     */
    function getMailbox(uint32 chainId) external view returns (address) {
        Storage storage $ = getStorage();
        
        if ($.chains[chainId].domainId == 0) revert ChainNotFound(chainId);
        return $.chains[chainId].mailbox;
    }
    
    /**
     * @dev Get domain ID for a chain
     */
    function getDomainId(uint32 chainId) external view returns (uint32) {
        Storage storage $ = getStorage();
        
        if ($.chains[chainId].domainId == 0) revert ChainNotFound(chainId);
        return $.chains[chainId].domainId;
    }
    
    /**
     * @dev Check if chain is active
     */
    function isChainActive(uint32 chainId) external view returns (bool) {
        return getStorage().chains[chainId].isActive;
    }
    
    /**
     * @dev Get all registered chain IDs
     */
    function getAllChains() external view returns (uint32[] memory) {
        return getStorage().registeredChains;
    }
    
    /**
     * @dev Get all active chains
     */
    function getActiveChains() external view returns (uint32[] memory) {
        Storage storage $ = getStorage();
        
        uint32[] memory activeChains = new uint32[]($.registeredChains.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < $.registeredChains.length; i++) {
            if ($.chains[$.registeredChains[i]].isActive) {
                activeChains[count] = $.registeredChains[i];
                count++;
            }
        }
        
        // Resize array to actual count
        assembly {
            mstore(activeChains, count)
        }
        
        return activeChains;
    }
    
    /**
     * @dev Register default Espresso testnet chains
     * Based on working configurations from the example
     */
    function _registerDefaultChains() internal {
        Storage storage $ = getStorage();
        
        // Rari Testnet (Host Chain)
        $.chains[1918988905] = ChainConfig({
            domainId: 1918988905,
            mailbox: 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358,
            rpcEndpoint: "https://rari.caff.testnet.espresso.network",
            isActive: true,
            name: "Rari Testnet",
            blockTime: 2
        });
        $.domainToChain[1918988905] = 1918988905;
        $.registeredChains.push(1918988905);
        
        // Appchain Testnet (Source Chain)
        $.chains[4661] = ChainConfig({
            domainId: 4661,
            mailbox: 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1,
            rpcEndpoint: "https://appchain.caff.testnet.espresso.network",
            isActive: true,
            name: "Appchain Testnet",
            blockTime: 2
        });
        $.domainToChain[4661] = 4661;
        $.registeredChains.push(4661);
        
        // Arbitrum Sepolia (Source Chain)
        $.chains[421614] = ChainConfig({
            domainId: 421614,
            mailbox: 0x8DF6aDE95d25855ed0FB927ECD6a1D5Bb09d2145,
            rpcEndpoint: "https://arb-sepolia.g.alchemy.com/v2/jBG4sMyhez7V13jNTeQKfVfgNa54nCmF",
            isActive: true,
            name: "Arbitrum Sepolia",
            blockTime: 1
        });
        $.domainToChain[421614] = 421614;
        $.registeredChains.push(421614);
        
        // Rise Sepolia (Source Chain)
        $.chains[11155931] = ChainConfig({
            domainId: 11155931,
            mailbox: 0x1d5596b72D1E4Ae66872dDaDA512c0A9513Fc479,
            rpcEndpoint: "https://testnet.rizelabs.xyz",
            isActive: true,
            name: "Rise Sepolia",
            blockTime: 12
        });
        $.domainToChain[11155931] = 11155931;
        $.registeredChains.push(11155931);
    }
}