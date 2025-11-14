// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISyntheticERC20} from "../core/interfaces/ISyntheticERC20.sol";

/**
 * @title SyntheticToken
 * @dev ERC20 token representing 1:1 claim on underlying assets in lending protocol
 */
contract SyntheticToken is ERC20, Ownable, ISyntheticERC20 {
    // Errors
    error OnlyMinter();
    error OnlyBurner();
    error InvalidAddress();
    error InsufficientBalance();

    // State variables
    address public minter;
    address public burner;
    address public underlyingToken;

    // Events
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event MinterUpdated(address indexed oldMinter, address indexed newMinter);
    event BurnerUpdated(address indexed oldBurner, address indexed newBurner);
    event UnderlyingTokenUpdated(address indexed oldToken, address indexed newToken);

    /**
     * @dev Constructor
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _minter,
        address _burner,
        address _underlyingToken
    ) ERC20(_name, _symbol) Ownable(_burner) {
        minter = _minter;
        burner = _burner;
        underlyingToken = _underlyingToken;
    }

    /**
     * @dev Mint synthetic tokens (only authorized minter)
     */
    function mint(address to, uint256 amount) external virtual {
        if (msg.sender != minter && msg.sender != owner()) revert OnlyMinter();
        if (to == address(0)) revert InvalidAddress();

        _mint(to, amount);
        emit Mint(to, amount);
    }

    /**
     * @dev Burn synthetic tokens (only authorized burner)
     */
    function burn(address from, uint256 amount) external virtual {
        if (msg.sender != burner && msg.sender != owner()) revert OnlyBurner();
        if (from == address(0)) revert InvalidAddress();

        uint256 balance = balanceOf(from);
        if (balance < amount) revert InsufficientBalance();

        _burn(from, amount);
        emit Burn(from, amount);
    }

    /**
     * @dev Update minter address
     */
    function setMinter(address newMinter) external virtual onlyOwner {
        address oldMinter = minter;
        minter = newMinter;
        emit MinterUpdated(oldMinter, newMinter);
    }

    /**
     * @dev Update burner address
     */
    function setBurner(address newBurner) external onlyOwner {
        address oldBurner = burner;
        burner = newBurner;
        _transferOwnership(newBurner);
        emit BurnerUpdated(oldBurner, newBurner);
    }

    /**
     * @dev Update underlying token address
     */
    function setUnderlyingToken(address newUnderlyingToken) external onlyOwner {
        address oldToken = underlyingToken;
        underlyingToken = newUnderlyingToken;
        emit UnderlyingTokenUpdated(oldToken, newUnderlyingToken);
    }

    // Override transfer functions to make synthetic tokens non-transferable
    function transfer(address to, uint256 amount) public pure override returns (bool) {
        revert("Synthetic tokens are non-transferable");
    }

    function transferFrom(address from, address to, uint256 amount) public pure override returns (bool) {
        revert("Synthetic tokens are non-transferable");
    }

    function approve(address spender, uint256 amount) public pure override returns (bool) {
        revert("Synthetic tokens are non-transferable");
    }

    /**
     * @dev Get contract information
     */
    function getContractInfo() external view returns (
        address _minter,
        address _burner,
        address _underlyingToken,
        uint256 _totalSupply
    ) {
        return (minter, burner, underlyingToken, totalSupply());
    }
}