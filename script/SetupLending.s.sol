// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

interface IBalanceManager {
    function setLendingManager(address _lendingManager) external;
    function lendingManager() external view returns (address);
}

interface ILendingManager {
    function setOracle(address _oracle) external;
    function oracle() external view returns (address);
}

contract SetupLending is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address balanceManager = 0x7d01a095301eA899Cbcbe0248Ad50BbC28e7Be36;
        address lendingManager = 0x8b65E50e5Fc3eDd367010713684dD16158EEa683;
        address oracle = 0x83187ccD22D4e8DFf2358A09750331775A207E13;

        console.log("=== SETTING UP LENDING SYSTEM ===");
        console.log("");
        console.log("BalanceManager:", balanceManager);
        console.log("LendingManager:", lendingManager);
        console.log("Oracle:", oracle);
        console.log("");

        // Check current state
        address currentLM = IBalanceManager(balanceManager).lendingManager();
        console.log("Current LendingManager in BalanceManager:", currentLM);

        vm.startBroadcast(deployerPrivateKey);

        // Link LendingManager to BalanceManager
        if (currentLM != lendingManager) {
            console.log("Setting LendingManager...");
            IBalanceManager(balanceManager).setLendingManager(lendingManager);
            console.log("LendingManager linked!");
        } else {
            console.log("LendingManager already linked");
        }

        // Set Oracle for LendingManager
        try ILendingManager(lendingManager).oracle() returns (address currentOracle) {
            console.log("Current Oracle in LendingManager:", currentOracle);
            if (currentOracle != oracle) {
                console.log("Setting Oracle...");
                ILendingManager(lendingManager).setOracle(oracle);
                console.log("Oracle set!");
            } else {
                console.log("Oracle already set");
            }
        } catch {
            console.log("Setting Oracle...");
            ILendingManager(lendingManager).setOracle(oracle);
            console.log("Oracle set!");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== SETUP COMPLETE ===");
        console.log("");
        console.log("Next steps:");
        console.log("1. Deposit IDRX as collateral");
        console.log("2. Try auto-borrow WETH for your SELL order");
    }
}
