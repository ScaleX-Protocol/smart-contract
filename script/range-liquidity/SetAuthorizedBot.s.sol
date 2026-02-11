// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {RangeLiquidityManager} from "@scalexcore/RangeLiquidityManager.sol";

contract SetAuthorizedBot is Script {
    function run() external {
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPrivateKey);

        address rangeLiquidityManagerAddr = vm.envAddress("RANGE_LIQUIDITY_MANAGER");
        uint256 positionId = vm.envUint("POSITION_ID");
        address botAddress = vm.envAddress("BOT_ADDRESS");

        console.log("=== SETTING AUTHORIZED BOT ===");
        console.log("Owner:", owner);
        console.log("RangeLiquidityManager:", rangeLiquidityManagerAddr);
        console.log("Position ID:", positionId);
        console.log("Bot Address:", botAddress);
        console.log("");

        RangeLiquidityManager rangeLiquidityManager = RangeLiquidityManager(rangeLiquidityManagerAddr);

        vm.startBroadcast(ownerPrivateKey);

        console.log("Authorizing bot...");
        rangeLiquidityManager.setAuthorizedBot(positionId, botAddress);
        console.log("[OK] Bot authorized!");

        vm.stopBroadcast();

        console.log("");
        console.log("=== BOT AUTHORIZATION COMPLETE ===");
        console.log("");
        console.log("The bot can now rebalance position", positionId);
        console.log("when price drift exceeds the threshold.");
    }
}
