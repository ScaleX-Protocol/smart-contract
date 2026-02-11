// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IERC8004Identity.sol";

/**
 * @title MockERC8004Identity
 * @notice Mock implementation of ERC-8004 Identity Registry for testing
 * @dev Simplified NFT-like implementation for agent identities
 */
contract MockERC8004Identity is IERC8004Identity {
    // Token ID => Owner
    mapping(uint256 => address) private _owners;

    // Token ID => Metadata URI
    mapping(uint256 => string) private _tokenURIs;

    // Token ID => Exists
    mapping(uint256 => bool) private _exists;

    // Owner => Token count
    mapping(address => uint256) private _balances;

    // Auto-increment token ID
    uint256 private _nextTokenId = 1;

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
     */
    function mint(address to, uint256 tokenId, string calldata metadataURI) external override {
        require(to != address(0), "Mint to zero address");
        require(!_exists[tokenId], "Token already exists");

        _owners[tokenId] = to;
        _tokenURIs[tokenId] = metadataURI;
        _exists[tokenId] = true;
        _balances[to]++;

        emit AgentIdentityCreated(tokenId, to, metadataURI);
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
}
