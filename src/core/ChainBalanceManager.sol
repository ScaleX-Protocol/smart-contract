// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "./libraries/Currency.sol";
import {IChainBalanceManager} from "./interfaces/IChainBalanceManager.sol";

contract ChainBalanceManager is IChainBalanceManager, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    mapping(address => mapping(address => uint256)) public balanceOf; 
    mapping(address => mapping(address => uint256)) public unlockedBalanceOf; 
    mapping(address => bool) public whitelistedTokens;
    address[] public tokenList;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
    }

    modifier onlyWhitelistedToken(address token) {
        if (!whitelistedTokens[token] && token != address(0)) {
            revert TokenNotWhitelisted(token);
        }
        _;
    }

    function addToken(address token) external onlyOwner {
        if (whitelistedTokens[token]) {
            revert TokenAlreadyWhitelisted(token);
        }
        
        whitelistedTokens[token] = true;
        tokenList.push(token);
        
        emit TokenWhitelisted(token);
    }

    function removeToken(address token) external onlyOwner {
        if (!whitelistedTokens[token]) {
            revert TokenNotFound(token);
        }
        
        whitelistedTokens[token] = false;
        
        // Remove from tokenList array
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == token) {
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                break;
            }
        }
        
        emit TokenRemoved(token);
    }

    function deposit(address token, uint256 amount) external payable nonReentrant onlyWhitelistedToken(token) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (token == address(0)) {
            // ETH deposit
            require(msg.value == amount, "Incorrect ETH amount sent");
        } else {
            // ERC20 deposit
            require(msg.value == 0, "No ETH should be sent for ERC20 deposit");
            IERC20(token).transferFrom(msg.sender, address(this), amount);
        }

        balanceOf[msg.sender][token] += amount;
        
        emit Deposit(msg.sender, token, amount);
    }

    function unlock(address token, uint256 amount, address user) external onlyOwner {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (balanceOf[user][token] < amount) {
            revert InsufficientBalance(user, uint256(uint160(token)), amount, balanceOf[user][token]);
        }

        balanceOf[user][token] -= amount;
        unlockedBalanceOf[user][token] += amount;

        emit Unlock(user, token, amount);
    }

    function withdraw(address token, uint256 amount, address user) external onlyOwner nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (balanceOf[user][token] < amount) {
            revert InsufficientBalance(user, uint256(uint160(token)), amount, balanceOf[user][token]);
        }

        balanceOf[user][token] -= amount;

        if (token == address(0)) {
            // ETH withdrawal
            payable(user).transfer(amount);
        } else {
            // ERC20 withdrawal
            IERC20(token).transfer(user, amount);
        }

        emit Withdraw(user, token, amount);
    }

    function claim(address token, uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (unlockedBalanceOf[msg.sender][token] < amount) {
            revert InsufficientUnlockedBalance(msg.sender, uint256(uint160(token)), amount, unlockedBalanceOf[msg.sender][token]);
        }

        unlockedBalanceOf[msg.sender][token] -= amount;

        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }

        emit Claim(msg.sender, token, amount);
    }

    function getBalance(address user, address token) external view returns (uint256) {
        return balanceOf[user][token];
    }

    function getUnlockedBalance(address user, address token) external view returns (uint256) {
        return unlockedBalanceOf[user][token];
    }

    function isTokenWhitelisted(address token) external view returns (bool) {
        return whitelistedTokens[token] || token == address(0); // ETH is always allowed
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        return tokenList;
    }

    function getTokenCount() external view returns (uint256) {
        return tokenList.length;
    }
}