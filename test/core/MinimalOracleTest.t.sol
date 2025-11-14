// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";

contract MinimalOracle {
    address public owner;
    
    constructor() {
        owner = msg.sender;
    }
    
    function getSpotPrice(address token) external pure returns (uint256) {
        return 1000 * 1e6; // Fixed price for testing
    }
    
    function updatePriceFromTrade(address token, uint128 price, uint256 volume) external {
        require(msg.sender == owner, "Unauthorized");
    }
}

contract MinimalOracleTest is Test {
    MinimalOracle public oracle;
    
    function setUp() public {
        oracle = new MinimalOracle();
    }
    
    function testBasicOracle() public {
        uint256 price = oracle.getSpotPrice(address(0x1));
        assertEq(price, 1000 * 1e6);
        
        // Test authorized update
        oracle.updatePriceFromTrade(address(0x1), 2000 * 1e6, 1000 * 1e6);
        
        // Test unauthorized update
        vm.prank(address(0x999));
        vm.expectRevert();
        oracle.updatePriceFromTrade(address(0x1), 2000 * 1e6, 1000 * 1e6);
        
        console.log("Minimal Oracle test passed!");
    }
}