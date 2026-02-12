// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC8004Identity
 * @notice ERC-8004 Identity Registry interface for AI agent NFTs
 * @dev Based on ERC-8004 standard (https://eips.ethereum.org/EIPS/eip-8004)
 *      Identity Registry provides unique on-chain identifiers for AI agents
 */
interface IERC8004Identity {
    struct MetadataEntry {
        string metadataKey;
        bytes metadataValue;
    }

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
     * @notice Register a new agent identity
     * @param agentURI URI pointing to agent metadata
     * @param metadata Optional metadata entries
     * @return agentId The newly created agent ID
     */
    function register(string memory agentURI, MetadataEntry[] memory metadata)
        external returns (uint256 agentId);

    /**
     * @notice Register a new agent identity with URI
     * @param agentURI URI pointing to agent metadata
     * @return agentId The newly created agent ID
     */
    function register(string memory agentURI) external returns (uint256 agentId);

    /**
     * @notice Register a new agent identity without URI
     * @return agentId The newly created agent ID
     */
    function register() external returns (uint256 agentId);

    /**
     * @notice Update the agent's metadata URI
     * @param agentId The agent token ID
     * @param newURI The new URI
     */
    function setAgentURI(uint256 agentId, string calldata newURI) external;

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
     * @notice Get the agent's wallet address (evm_address in ERC-8004)
     * @param agentId The agent token ID
     * @return The wallet address controlled by the agent
     */
    function getAgentWallet(uint256 agentId) external view returns (address);

    /**
     * @notice Set the agent's wallet address with signature verification
     * @param agentId The agent token ID
     * @param newWallet The new wallet address
     * @param deadline Signature expiry timestamp
     * @param signature EIP-712 or ERC-1271 signature from the new wallet
     */
    function setAgentWallet(
        uint256 agentId,
        address newWallet,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /**
     * @notice Clear the agent's wallet address
     * @param agentId The agent token ID
     */
    function unsetAgentWallet(uint256 agentId) external;

    /**
     * @notice Get metadata value for a key
     * @param agentId The agent token ID
     * @param metadataKey The metadata key
     * @return The metadata value
     */
    function getMetadata(uint256 agentId, string memory metadataKey)
        external view returns (bytes memory);

    /**
     * @notice Set metadata value for a key
     * @param agentId The agent token ID
     * @param metadataKey The metadata key (cannot be "agentWallet" - reserved)
     * @param metadataValue The metadata value
     */
    function setMetadata(
        uint256 agentId,
        string memory metadataKey,
        bytes memory metadataValue
    ) external;

    /**
     * @notice Emitted when a new agent identity is created
     */
    event Registered(
        uint256 indexed agentId,
        string agentURI,
        address indexed owner
    );

    /**
     * @notice Emitted when agent ownership changes
     */
    event AgentTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to
    );

    /**
     * @notice Emitted when agent URI is updated
     */
    event URIUpdated(
        uint256 indexed agentId,
        string newURI,
        address indexed updatedBy
    );

    /**
     * @notice Emitted when metadata is set
     */
    event MetadataSet(
        uint256 indexed agentId,
        string indexed indexedMetadataKey,
        string metadataKey,
        bytes metadataValue
    );
}
