// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract FixArbitrumMailbox is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Fixing Arbitrum Sepolia Mailbox ===");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new ChainBalanceManager implementation
        ChainBalanceManager newImpl = new ChainBalanceManager();
        console.log("New Implementation:", address(newImpl));
        
        // Initialize with correct parameters
        address correctMailbox = 0x8DF6aDE95d25855ed0FB927ECD6a1D5Bb09d2145;
        uint32 rariDomain = 1918988905;
        address rariBalanceManager = 0xDf997311A013F15Df5264172f3a448B14917CFE8;
        
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,uint32,address)",
            deployer,
            correctMailbox,
            rariDomain,
            rariBalanceManager
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(newImpl), initData);
        ChainBalanceManager newCBM = ChainBalanceManager(address(proxy));
        
        console.log("ChainBalanceManager deployed at:", address(proxy));
        console.log("Correct mailbox:", correctMailbox);
        console.log("Rari domain:", rariDomain);
        console.log("Rari BalanceManager:", rariBalanceManager);
        
        // Configure tokens
        address USDT = 0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a;
        address WETH = 0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7;
        address WBTC = 0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A;
        
        address GS_USDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
        address GS_WETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address GS_WBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;
        
        // Add tokens
        newCBM.addToken(USDT);
        newCBM.addToken(WETH);
        newCBM.addToken(WBTC);
        
        // Set mappings
        newCBM.setTokenMapping(USDT, GS_USDT);
        newCBM.setTokenMapping(WETH, GS_WETH);
        newCBM.setTokenMapping(WBTC, GS_WBTC);
        
        console.log("SUCCESS: Token mappings configured");
        
        vm.stopBroadcast();
        
        console.log("=== Deployment Complete ===");
        console.log("Update deployment file with:", address(proxy));
    }
}