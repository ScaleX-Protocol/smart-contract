// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract DeployPhase1A is Script {
    struct Phase1ADeployment {
        address USDC;
        address WETH;
        address WBTC;
        address deployer;
        uint256 timestamp;
        uint256 blockNumber;
    }

    function run() external returns (Phase1ADeployment memory deployment) {
        console.log("=== PHASE 1A: TOKEN DEPLOYMENT ===");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Step 1: Deploying Mock Tokens...");
        MockToken usdc = new MockToken("USDC Coin", "USDC", 6);
        console.log("[OK] USDC deployed:", address(usdc));
        
        // Add delay between deployments
        vm.warp(block.timestamp + 5);
        
        MockToken weth = new MockToken("Wrapped Ether", "WETH", 18);
        console.log("[OK] WETH deployed:", address(weth));
        
        vm.warp(block.timestamp + 5);
        
        MockToken wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);
        console.log("[OK] WBTC deployed:", address(wbtc));
        
        // Mint initial tokens to deployer
        usdc.mint(deployer, 1_000_000 * 1e6); // 1M USDC
        weth.mint(deployer, 1_000 * 1e18); // 1K WETH
        wbtc.mint(deployer, 50 * 1e8); // 50 WBTC
        
        vm.stopBroadcast();
        
        // Save deployment data
        _saveDeployment(address(usdc), address(weth), address(wbtc), deployer);
        
        deployment = Phase1ADeployment({
            USDC: address(usdc),
            WETH: address(weth),
            WBTC: address(wbtc),
            deployer: deployer,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
        
        console.log("=== PHASE 1A COMPLETED ===");
        return deployment;
    }
    
    function _saveDeployment(address usdc, address weth, address wbtc, address deployer) internal {
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory path = string.concat(root, "/deployments/", chainIdStr, "-phase1a.json");
        
        string memory json = string.concat(
            "{\n",
            "  \"phase\": \"1a\",\n",
            "  \"USDC\": \"", vm.toString(usdc), "\",\n",
            "  \"WETH\": \"", vm.toString(weth), "\",\n",
            "  \"WBTC\": \"", vm.toString(wbtc), "\",\n",
            "  \"deployer\": \"", vm.toString(deployer), "\",\n",
            "  \"timestamp\": \"", vm.toString(block.timestamp), "\",\n",
            "  \"blockNumber\": \"", vm.toString(block.number), "\"\n",
            "}"
        );
        
        vm.writeFile(path, json);
        console.log("Phase 1A deployment data written to:", path);
    }
}