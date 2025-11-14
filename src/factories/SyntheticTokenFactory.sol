// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SyntheticToken} from "../token/SyntheticToken.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISyntheticERC20} from "../core/interfaces/ISyntheticERC20.sol";

/**
 * @title SyntheticTokenFactory
 * @dev Factory contract for creating and managing synthetic tokens
 */
contract SyntheticTokenFactory is Initializable, OwnableUpgradeable {
    // Errors
    error TokenAlreadyExists();
    error InvalidAddress();
    error UnauthorizedCaller();

    // Events
    event SyntheticTokenCreated(
        address indexed underlyingToken,
        address indexed syntheticToken,
        string name,
        string symbol,
        uint256 timestamp
    );
    event TokenDeployerUpdated(address indexed oldDeployer, address indexed newDeployer);

    // Storage
    mapping(address => address) public syntheticTokens; // underlyingToken -> syntheticToken
    mapping(address => address) public underlyingTokens; // syntheticToken -> underlyingToken
    address[] public allSyntheticTokens;
    address public tokenDeployer;

    function initialize(address _owner, address _tokenDeployer) public initializer {
        __Ownable_init(_owner);
        tokenDeployer = _tokenDeployer;
    }

    // =============================================================
    //                   OWNER FUNCTIONS
    // =============================================================

    function setTokenDeployer(address _tokenDeployer) external onlyOwner {
        address oldDeployer = tokenDeployer;
        tokenDeployer = _tokenDeployer;
        emit TokenDeployerUpdated(oldDeployer, _tokenDeployer);
    }

    // =============================================================
    //                   SYNTHETIC TOKEN CREATION
    // =============================================================

    function createSyntheticToken(address underlyingToken) external returns (address) {
        if (msg.sender != tokenDeployer && msg.sender != owner()) {
            revert UnauthorizedCaller();
        }
        if (underlyingToken == address(0)) revert InvalidAddress();
        if (syntheticTokens[underlyingToken] != address(0)) revert TokenAlreadyExists();

        // Create synthetic token with standardized naming
        string memory underlyingName = IERC20Metadata(underlyingToken).name();
        string memory underlyingSymbol = IERC20Metadata(underlyingToken).symbol();
        uint8 decimals = IERC20Metadata(underlyingToken).decimals();

        string memory syntheticName = string(abi.encodePacked("Synthetic ", underlyingName));
        string memory syntheticSymbol = string(abi.encodePacked("s", underlyingSymbol));

        SyntheticToken newToken = new SyntheticToken({
            _name: syntheticName,
            _symbol: syntheticSymbol,
            _decimals: decimals,
            _minter: tokenDeployer,
            _burner: tokenDeployer,
            _underlyingToken: underlyingToken
        });

        syntheticTokens[underlyingToken] = address(newToken);
        underlyingTokens[address(newToken)] = underlyingToken;
        allSyntheticTokens.push(address(newToken));

        emit SyntheticTokenCreated(
            underlyingToken,
            address(newToken),
            syntheticName,
            syntheticSymbol,
            block.timestamp
        );

        return address(newToken);
    }

    // =============================================================
    //                   VIEW FUNCTIONS
    // =============================================================

    function getSyntheticToken(address underlyingToken) external view returns (address) {
        return syntheticTokens[underlyingToken];
    }

    function getUnderlyingToken(address syntheticToken) external view returns (address) {
        return underlyingTokens[syntheticToken];
    }

    function getAllSyntheticTokens() external view returns (address[] memory) {
        return allSyntheticTokens;
    }

    function getSyntheticTokenCount() external view returns (uint256) {
        return allSyntheticTokens.length;
    }

    function tokenExists(address underlyingToken) external view returns (bool) {
        return syntheticTokens[underlyingToken] != address(0);
    }

    function getSyntheticTokenInfo(address underlyingToken) external view returns (
        address syntheticToken,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address minter,
        address burner
    ) {
        syntheticToken = syntheticTokens[underlyingToken];
        if (syntheticToken != address(0)) {
            SyntheticToken token = SyntheticToken(syntheticToken);
            (minter, burner, , ) = token.getContractInfo();
            name = token.name();
            symbol = token.symbol();
            decimals = token.decimals();
        }
    }
}