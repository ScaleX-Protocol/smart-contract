// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

interface IOrderBook {
    function setAutoBorrowHelper(address helper) external;
}

contract ConfigureAutoBorrowHelper is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address orderBook = 0xB45fC76ba06E4d080f9AfBC3695eE3Dea5f97f0c;
        address helper = 0x17363E986A1286EEE5D54dAD6A44B396B6262BAe;

        console.log("=== CONFIGURING AUTO-BORROW HELPER ===");
        console.log("");

        console.log("OrderBook:", orderBook);
        console.log("AutoBorrowHelper:", helper);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Setting AutoBorrowHelper on OrderBook...");
        IOrderBook(orderBook).setAutoBorrowHelper(helper);
        console.log("AutoBorrowHelper configured!");

        vm.stopBroadcast();

        console.log("");
        console.log("=== CONFIGURATION COMPLETE ===");
    }
}
