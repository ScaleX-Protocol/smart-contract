// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/core/AutoBorrowHelper.sol";

contract DeployAutoBorrowHelper is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("=== DEPLOYING AUTOBORROW HELPER ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        AutoBorrowHelper helper = new AutoBorrowHelper();
        console.log("AutoBorrowHelper deployed at:", address(helper));

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Next steps:");
        console.log("1. Upgrade OrderBook with new implementation");
        console.log("2. Call setAutoBorrowHelper() on OrderBook with address:", address(helper));
    }
}
