// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @dev Simple mock ERC20 token for testing
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, initialSupply);
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title DeployMockTokens
 * @dev Deploy mock tokens for cross-chain testing
 */
contract DeployMockTokens is Script {
    
    function run() public {
        string memory network = vm.envString("NETWORK");
        
        vm.startBroadcast();
        
        address deployer = msg.sender;
        console.log("Deploying mock tokens on", network);
        console.log("Deployer:", deployer);
        
        // Deploy mock USDT (6 decimals)
        MockERC20 mockUSDT = new MockERC20(
            "Mock USDT",
            "mUSDT",
            6,
            1000000 * 10**6  // 1M USDT
        );
        console.log("Mock USDT deployed:", address(mockUSDT));
        
        // Deploy mock WETH (18 decimals)
        MockERC20 mockWETH = new MockERC20(
            "Mock WETH",
            "mWETH", 
            18,
            10000 * 10**18  // 10K WETH
        );
        console.log("Mock WETH deployed:", address(mockWETH));
        
        // Deploy mock WBTC (8 decimals)
        MockERC20 mockWBTC = new MockERC20(
            "Mock WBTC",
            "mWBTC",
            8,
            1000 * 10**8  // 1K WBTC
        );
        console.log("Mock WBTC deployed:", address(mockWBTC));
        
        // Mint some tokens to deployer for testing
        console.log("Initial balances:");
        console.log("mUSDT:", mockUSDT.balanceOf(deployer));
        console.log("mWETH:", mockWETH.balanceOf(deployer));
        console.log("mWBTC:", mockWBTC.balanceOf(deployer));
        
        vm.stopBroadcast();
        
        console.log("=== Mock Token Deployment Complete ===");
        console.log("Use these addresses for cross-chain testing:");
        console.log("Mock USDT:", address(mockUSDT));
        console.log("Mock WETH:", address(mockWETH));
        console.log("Mock WBTC:", address(mockWBTC));
    }
}