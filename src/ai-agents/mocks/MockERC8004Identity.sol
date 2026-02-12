// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IERC8004Identity.sol";

/**
 * @title MockERC8004Identity
 * @notice Mock implementation of ERC-8004 Identity Registry for testing
 * @dev Simplified NFT-like implementation for agent identities
 */
contract MockERC8004Identity is IERC8004Identity {
    // Token ID => Owner (who owns the agent NFT)
    mapping(uint256 => address) private _owners;

    // Token ID => Agent Wallet (the wallet address the agent uses to transact)
    mapping(uint256 => address) private _agentWallets;

    // Token ID => Metadata URI
    mapping(uint256 => string) private _tokenURIs;

    // Token ID => Exists
    mapping(uint256 => bool) private _exists;

    // Owner => Token count
    mapping(address => uint256) private _balances;

    // Auto-increment token ID
    uint256 private _nextTokenId = 1;

    // Events
    event AgentWalletSet(uint256 indexed tokenId, address indexed agentWallet);

    /**
     * @notice Get the owner of an agent token
     */
    function ownerOf(uint256 tokenId) external view override returns (address) {
        require(_exists[tokenId], "Token does not exist");
        return _owners[tokenId];
    }

    /**
     * @notice Get metadata URI for an agent
     */
    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        require(_exists[tokenId], "Token does not exist");
        return _tokenURIs[tokenId];
    }

    /**
     * @notice Mint a new agent identity token
     * @param to The owner of the agent NFT (e.g., primary trader)
     * @param tokenId The token ID
     * @param metadataURI The metadata URI
     */
    function mint(address to, uint256 tokenId, string calldata metadataURI) external {
        require(to != address(0), "Mint to zero address");
        require(!_exists[tokenId], "Token already exists");

        _owners[tokenId] = to;
        _tokenURIs[tokenId] = metadataURI;
        _exists[tokenId] = true;
        _balances[to]++;

        emit Registered(tokenId, metadataURI, to);
    }

    /**
     * @notice Mint a new agent identity token with agent wallet
     * @param to The owner of the agent NFT (e.g., primary trader)
     * @param tokenId The token ID
     * @param agentWallet The wallet address controlled by the agent
     * @param metadataURI The metadata URI
     */
    function mintWithWallet(
        address to,
        uint256 tokenId,
        address agentWallet,
        string calldata metadataURI
    ) external {
        require(to != address(0), "Mint to zero address");
        require(agentWallet != address(0), "Invalid agent wallet");
        require(!_exists[tokenId], "Token already exists");

        _owners[tokenId] = to;
        _agentWallets[tokenId] = agentWallet;
        _tokenURIs[tokenId] = metadataURI;
        _exists[tokenId] = true;
        _balances[to]++;

        emit Registered(tokenId, metadataURI, to);
        emit AgentWalletSet(tokenId, agentWallet);
    }

    /**
     * @notice Mint with auto-increment ID (convenience function)
     */
    function mintAuto(address to, string calldata metadataURI) external returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        this.mint(to, tokenId, metadataURI);
    }

    /**
     * @notice Check if a token exists
     */
    function exists(uint256 tokenId) external view override returns (bool) {
        return _exists[tokenId];
    }

    /**
     * @notice Transfer agent ownership
     */
    function transferFrom(address from, address to, uint256 tokenId) external override {
        require(_exists[tokenId], "Token does not exist");
        require(_owners[tokenId] == from, "Not token owner");
        require(to != address(0), "Transfer to zero address");

        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;

        emit AgentTransferred(tokenId, from, to);
    }

    /**
     * @notice Get balance of an owner
     */
    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "Zero address");
        return _balances[owner];
    }

    /**
     * @notice Get the agent wallet address for a token
     * @param tokenId The token ID
     * @return The wallet address controlled by the agent
     */
    function getAgentWallet(uint256 tokenId) external view returns (address) {
        require(_exists[tokenId], "Token does not exist");
        return _agentWallets[tokenId];
    }

    /**
     * @notice Set the agent wallet address (only callable by owner)
     * @param tokenId The token ID
     * @param agentWallet The new agent wallet address
     * @dev In production, this would have additional security checks (e.g., only owner or admin can call)
     */
    function setAgentWallet(uint256 tokenId, address agentWallet) external {
        require(_exists[tokenId], "Token does not exist");
        require(agentWallet != address(0), "Invalid agent wallet");
        // In production, add: require(msg.sender == _owners[tokenId] || msg.sender == admin, "Not authorized");

        _agentWallets[tokenId] = agentWallet;
        emit AgentWalletSet(tokenId, agentWallet);
    }

    // ============ ERC-8004 Interface Stub Implementations ============

    function register() external returns (uint256 agentId) {
        agentId = _nextTokenId++;
        _owners[agentId] = msg.sender;
        _agentWallets[agentId] = msg.sender; // Default to owner
        _exists[agentId] = true;
        _balances[msg.sender]++;
        emit Registered(agentId, "", msg.sender);
    }

    function register(string memory agentURI) external returns (uint256 agentId) {
        agentId = _nextTokenId++;
        _owners[agentId] = msg.sender;
        _agentWallets[agentId] = msg.sender; // Default to owner
        _tokenURIs[agentId] = agentURI;
        _exists[agentId] = true;
        _balances[msg.sender]++;
        emit Registered(agentId, agentURI, msg.sender);
    }

    function register(string memory agentURI, MetadataEntry[] memory) external returns (uint256 agentId) {
        agentId = _nextTokenId++;
        _owners[agentId] = msg.sender;
        _agentWallets[agentId] = msg.sender; // Default to owner
        _tokenURIs[agentId] = agentURI;
        _exists[agentId] = true;
        _balances[msg.sender]++;
        emit Registered(agentId, agentURI, msg.sender);
    }

    function setAgentURI(uint256 agentId, string calldata newURI) external {
        require(_exists[agentId], "Token does not exist");
        require(msg.sender == _owners[agentId], "Not authorized");
        _tokenURIs[agentId] = newURI;
        emit URIUpdated(agentId, newURI, msg.sender);
    }

    function setAgentWallet(
        uint256 agentId,
        address newWallet,
        uint256,  // deadline (unused in mock)
        bytes calldata  // signature (unused in mock)
    ) external {
        require(_exists[agentId], "Token does not exist");
        require(msg.sender == _owners[agentId], "Not authorized");
        require(newWallet != address(0), "Invalid wallet");
        _agentWallets[agentId] = newWallet;
        emit AgentWalletSet(agentId, newWallet);
    }

    function unsetAgentWallet(uint256 agentId) external {
        require(_exists[agentId], "Token does not exist");
        require(msg.sender == _owners[agentId], "Not authorized");
        delete _agentWallets[agentId];
        emit AgentWalletSet(agentId, address(0));
    }

    function getMetadata(uint256, string memory) external pure returns (bytes memory) {
        return "";  // Mock: no metadata storage
    }

    function setMetadata(uint256 agentId, string memory, bytes memory) external view {
        require(_exists[agentId], "Token does not exist");
        require(msg.sender == _owners[agentId], "Not authorized");
        // Mock: no metadata storage
    }
}
