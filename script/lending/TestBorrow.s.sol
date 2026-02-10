// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {LendingManager} from "../../src/yield/LendingManager.sol";
import "../utils/DeployHelpers.s.sol";

contract TestBorrow is Script, DeployHelpers {
    function run() external {
        loadDeployments();
        uint256 privateKey = getDeployerKey();
        address deployer = vm.addr(privateKey);

        console.log("Deployer:", deployer);

        require(deployed["LendingManager"].isSet, "LendingManager not found");
        require(deployed["WETH"].isSet, "WETH not found");

        LendingManager lendingManager = LendingManager(deployed["LendingManager"].addr);
        address weth = deployed["WETH"].addr;

        // Check current state
        console.log("\n=== Current State ===");
        uint256 userSupply = lendingManager.getUserSupply(deployer, weth);
        console.log("User Supply:", userSupply);

        uint256 healthFactor = lendingManager.getHealthFactor(deployer);
        console.log("Health Factor:", healthFactor);

        uint256 totalLiquidity = lendingManager.totalLiquidity(weth);
        uint256 totalBorrowed = lendingManager.totalBorrowed(weth);
        console.log("Total Liquidity:", totalLiquidity);
        console.log("Total Borrowed:", totalBorrowed);
        console.log("Available:", totalLiquidity - totalBorrowed);

        // Try to borrow 1 WETH
        uint256 borrowAmount = 1 ether;
        console.log("\n=== Attempting to Borrow ===");
        console.log("Amount:", borrowAmount);

        vm.startBroadcast(privateKey);

        try lendingManager.borrow(weth, borrowAmount) {
            console.log("[SUCCESS] Borrowed 1 WETH");

            uint256 newBorrow = lendingManager.getUserBorrow(deployer, weth);
            console.log("New Borrow Balance:", newBorrow);
        } catch Error(string memory reason) {
            console.log("[ERROR] Borrow failed:");
            console.log(reason);
        } catch (bytes memory lowLevelData) {
            console.log("[ERROR] Borrow failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();
    }
}
