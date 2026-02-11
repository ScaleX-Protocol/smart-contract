// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC8004Identity
 * @notice ERC-8004 Identity Registry interface for AI agent NFTs
 * @dev Based on ERC-8004 standard (https://eips.ethereum.org/EIPS/eip-8004)
 *      Identity Registry provides unique on-chain identifiers for AI agents
 */
interface IERC8004Identity {
    /**
     * @notice Get the owner of an agent token
     * @param tokenId The ERC-8004 agent token ID
     * @return owner The address that owns this agent token
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @notice Get metadata URI for an agent
     * @param tokenId The ERC-8004 agent token ID
     * @return uri Metadata URI (JSON)
     */
    function tokenURI(uint256 tokenId) external view returns (string memory uri);

    /**
     * @notice Mint a new agent identity token
     * @param to Address to mint the token to
     * @param tokenId The token ID to mint
     * @param metadataURI URI pointing to agent metadata
     */
    function mint(address to, uint256 tokenId, string calldata metadataURI) external;

    /**
     * @notice Check if a token exists
     * @param tokenId The token ID to check
     * @return exists True if token exists
     */
    function exists(uint256 tokenId) external view returns (bool exists);

    /**
     * @notice Transfer agent ownership
     * @param from Current owner
     * @param to New owner
     * @param tokenId The agent token ID
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @notice Emitted when a new agent identity is created
     */
    event AgentIdentityCreated(
        uint256 indexed tokenId,
        address indexed owner,
        string metadataURI
    );

    /**
     * @notice Emitted when agent ownership changes
     */
    event AgentTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to
    );
}
