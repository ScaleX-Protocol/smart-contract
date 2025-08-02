// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/core/ChainBalanceManager.sol";
import "./DeployHelpers.s.sol";

contract AddTokensToChainBalanceManager is DeployHelpers {
    // Contract address keys
    string constant PROXY_CHAINBALANCEMANAGER = "PROXY_CHAINBALANCEMANAGER";

    // Token array for dynamic lookup
    string[] public tokenKeys = [
        "MOCK_TOKEN_USDC",
        "MOCK_TOKEN_WETH", 
        "MOCK_TOKEN_WBTC"
    ];

    error ChainBalanceManagerNotDeployed();
    error InvalidTokenAddress(address token);

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        
        loadDeployments();
        
        if (!deployed[PROXY_CHAINBALANCEMANAGER].isSet) {
            revert ChainBalanceManagerNotDeployed();
        }
        
        address chainBalanceManagerAddress = deployed[PROXY_CHAINBALANCEMANAGER].addr;
        ChainBalanceManager chainBalanceManager = ChainBalanceManager(chainBalanceManagerAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("========== ADDING TOKENS TO CHAIN BALANCE MANAGER ==========");
        console.log("ChainBalanceManager Address:", chainBalanceManagerAddress);
        console.log("Owner:", chainBalanceManager.owner());
        
        // Add common tokens - customize these addresses for your chain
        address[] memory tokensToAdd = getTokensToAdd();
        
        for (uint256 i = 0; i < tokensToAdd.length; i++) {
            address token = tokensToAdd[i];
            
            if (!chainBalanceManager.isTokenWhitelisted(token)) {
                console.log("Adding token:", token);
                chainBalanceManager.addToken(token);
                console.log("Token added successfully");
            } else {
                console.log("Token already whitelisted:", token);
            }
        }
        
        vm.stopBroadcast();
        
        console.log("\n========== WHITELIST SUMMARY ==========");
        address[] memory whitelistedTokens = chainBalanceManager.getWhitelistedTokens();
        console.log("Total whitelisted tokens:", whitelistedTokens.length);
        
        for (uint256 i = 0; i < whitelistedTokens.length; i++) {
            console.log("Token", i + 1, ":", whitelistedTokens[i]);
        }
    }
    
    function getTokensToAdd() internal view returns (address[] memory) {
        // Count available tokens first
        uint256 availableTokens = 0;
        for (uint256 i = 0; i < tokenKeys.length; i++) {
            if (deployed[tokenKeys[i]].isSet) {
                availableTokens++;
            }
        }
        
        // Create array with exact size needed
        address[] memory tokens = new address[](availableTokens);
        uint256 tokenIndex = 0;
        
        // Add tokens that exist in deployments
        for (uint256 i = 0; i < tokenKeys.length; i++) {
            if (deployed[tokenKeys[i]].isSet) {
                tokens[tokenIndex++] = deployed[tokenKeys[i]].addr;
            }
        }
        
        return tokens;
    }
    
    function addTokensByKeys(string[] memory keys) public {
        uint256 deployerPrivateKey = getDeployerKey();
        
        loadDeployments();
        
        if (!deployed[PROXY_CHAINBALANCEMANAGER].isSet) {
            revert ChainBalanceManagerNotDeployed();
        }
        
        address chainBalanceManagerAddress = deployed[PROXY_CHAINBALANCEMANAGER].addr;
        ChainBalanceManager chainBalanceManager = ChainBalanceManager(chainBalanceManagerAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("========== ADDING TOKENS BY KEYS ==========");
        console.log("ChainBalanceManager Address:", chainBalanceManagerAddress);
        
        for (uint256 i = 0; i < keys.length; i++) {
            string memory key = keys[i];
            if (deployed[key].isSet) {
                address token = deployed[key].addr;
                
                if (!chainBalanceManager.isTokenWhitelisted(token)) {
                    console.log("Adding token from key %s: %s", key, token);
                    chainBalanceManager.addToken(token);
                    console.log("Token added successfully");
                } else {
                    console.log("Token already whitelisted for key %s: %s", key, token);
                }
            } else {
                console.log("Token not found in deployments for key:", key);
            }
        }
        
        vm.stopBroadcast();
    }
    
    function addCustomTokens(address[] memory customTokens) public {
        uint256 deployerPrivateKey = getDeployerKey();
        
        loadDeployments();
        
        if (!deployed[PROXY_CHAINBALANCEMANAGER].isSet) {
            revert ChainBalanceManagerNotDeployed();
        }
        
        address chainBalanceManagerAddress = deployed[PROXY_CHAINBALANCEMANAGER].addr;
        ChainBalanceManager chainBalanceManager = ChainBalanceManager(chainBalanceManagerAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("========== ADDING CUSTOM TOKENS ==========");
        console.log("ChainBalanceManager Address:", chainBalanceManagerAddress);
        
        for (uint256 i = 0; i < customTokens.length; i++) {
            address token = customTokens[i];
            if (token == address(0)) {
                revert InvalidTokenAddress(token);
            }
            
            if (!chainBalanceManager.isTokenWhitelisted(token)) {
                console.log("Adding custom token:", token);
                chainBalanceManager.addToken(token);
                console.log("Custom token added successfully");
            } else {
                console.log("Custom token already whitelisted:", token);
            }
        }
        
        vm.stopBroadcast();
    }
    
    function addSingleToken(address token) public {
        uint256 deployerPrivateKey = getDeployerKey();
        
        loadDeployments();
        
        if (!deployed[PROXY_CHAINBALANCEMANAGER].isSet) {
            revert ChainBalanceManagerNotDeployed();
        }
        
        address chainBalanceManagerAddress = deployed[PROXY_CHAINBALANCEMANAGER].addr;
        
        ChainBalanceManager chainBalanceManager = ChainBalanceManager(chainBalanceManagerAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("========== ADDING SINGLE TOKEN ==========");
        console.log("ChainBalanceManager Address:", chainBalanceManagerAddress);
        console.log("Token to add:", token);
        
        if (!chainBalanceManager.isTokenWhitelisted(token)) {
            chainBalanceManager.addToken(token);
            console.log("Token added successfully");
        } else {
            console.log("Token already whitelisted");
        }
        
        vm.stopBroadcast();
    }
    
    function removeSingleToken(address token) public {
        uint256 deployerPrivateKey = getDeployerKey();
        
        loadDeployments();
        
        if (!deployed[PROXY_CHAINBALANCEMANAGER].isSet) {
            revert ChainBalanceManagerNotDeployed();
        }
        
        address chainBalanceManagerAddress = deployed[PROXY_CHAINBALANCEMANAGER].addr;
        
        ChainBalanceManager chainBalanceManager = ChainBalanceManager(chainBalanceManagerAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("========== REMOVING SINGLE TOKEN ==========");
        console.log("ChainBalanceManager Address:", chainBalanceManagerAddress);
        console.log("Token to remove:", token);
        
        if (chainBalanceManager.isTokenWhitelisted(token)) {
            chainBalanceManager.removeToken(token);
            console.log("Token removed successfully");
        } else {
            console.log("Token not whitelisted");
        }
        
        vm.stopBroadcast();
    }
    
    function listWhitelistedTokens() public {
        loadDeployments();
        
        if (!deployed[PROXY_CHAINBALANCEMANAGER].isSet) {
            revert ChainBalanceManagerNotDeployed();
        }
        
        address chainBalanceManagerAddress = deployed[PROXY_CHAINBALANCEMANAGER].addr;
        ChainBalanceManager chainBalanceManager = ChainBalanceManager(chainBalanceManagerAddress);
        
        console.log("========== WHITELISTED TOKENS ==========");
        console.log("ChainBalanceManager Address:", chainBalanceManagerAddress);
        
        address[] memory whitelistedTokens = chainBalanceManager.getWhitelistedTokens();
        console.log("Total whitelisted tokens:", whitelistedTokens.length);
        console.log("ETH is always whitelisted (address(0))");
        
        for (uint256 i = 0; i < whitelistedTokens.length; i++) {
            console.log("Token", i + 1, ":", whitelistedTokens[i]);
        }
    }
}