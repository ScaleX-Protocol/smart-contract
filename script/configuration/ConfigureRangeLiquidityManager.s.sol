// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {RangeLiquidityManager} from "@scalexcore/RangeLiquidityManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";

contract ConfigureRangeLiquidityManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address rangeLiquidityManagerAddr = vm.envAddress("RANGE_LIQUIDITY_MANAGER");
        address balanceManagerAddr = vm.envAddress("BALANCE_MANAGER");

        console.log("=== CONFIGURING RANGE LIQUIDITY MANAGER ===");
        console.log("Deployer:", deployer);
        console.log("RangeLiquidityManager:", rangeLiquidityManagerAddr);
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        IBalanceManager balanceManager = IBalanceManager(balanceManagerAddr);
        RangeLiquidityManager rangeLiquidityManager = RangeLiquidityManager(rangeLiquidityManagerAddr);

        // Step 1: Authorize RangeLiquidityManager as operator in BalanceManager
        console.log("Step 1: Authorizing RangeLiquidityManager in BalanceManager...");
        balanceManager.setAuthorizedOperator(rangeLiquidityManagerAddr, true);
        console.log("[OK] RangeLiquidityManager authorized");

        vm.stopBroadcast();

        console.log("");
        console.log("=== CONFIGURATION COMPLETE ===");
        console.log("");
        console.log("Verification:");
        console.log("  RangeLiquidityManager is now authorized to manage user balances");
        console.log("");
        console.log("The system is ready for users to create range liquidity positions!");
    }
}
