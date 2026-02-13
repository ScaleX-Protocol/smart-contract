// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/core/OrderBook.sol";
import "../../src/core/PoolManager.sol";

/**
 * @title UpdateOrderBookWithAgentTracking
 * @notice Deploys new OrderBook implementation with agent tracking and updates beacon
 * @dev Updates all 8 OrderBook instances via beacon upgrade
 */
contract UpdateOrderBookWithAgentTracking is Script {
    function run() external {
        // Load environment variables
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory rpcUrl = vm.envString("SCALEX_CORE_RPC");

        // Load deployment addresses
        string memory json = vm.readFile("deployments/84532.json");
        address poolManagerAddr = vm.parseJsonAddress(json, ".PoolManager");
        address orderBookBeacon = vm.parseJsonAddress(json, ".OrderBookBeacon");

        console.log("=== OrderBook Agent Tracking Update ===");
        console.log("Network: Base Sepolia (84532)");
        console.log("PoolManager:", poolManagerAddr);
        console.log("OrderBook Beacon:", orderBookBeacon);
        console.log("");

        vm.startBroadcast(deployerKey);

        // 1. Deploy new OrderBook implementation
        console.log("Step 1: Deploying new OrderBook implementation...");
        OrderBook newImplementation = new OrderBook();
        console.log("New implementation deployed at:", address(newImplementation));
        console.log("");

        // 2. Update beacon
        console.log("Step 2: Updating beacon to new implementation...");
        PoolManager poolManager = PoolManager(poolManagerAddr);

        // Get beacon from PoolManager storage (it's the owner of beacon)
        // We need to call upgradeTo on the beacon
        // The beacon address is the OrderBookBeacon from deployment

        // Call upgradeTo on the beacon (assumes UpgradeableBeacon pattern)
        (bool success, ) = orderBookBeacon.call(
            abi.encodeWithSignature("upgradeTo(address)", address(newImplementation))
        );

        require(success, "Beacon upgrade failed");
        console.log("Beacon upgraded successfully");
        console.log("");

        vm.stopBroadcast();

        // 3. Verify upgrade
        console.log("Step 3: Verifying upgrade...");
        (bool verifySuccess, bytes memory data) = orderBookBeacon.call(
            abi.encodeWithSignature("implementation()")
        );
        require(verifySuccess, "Failed to verify implementation");
        address currentImpl = abi.decode(data, (address));
        console.log("Current implementation:", currentImpl);
        console.log("Expected implementation:", address(newImplementation));
        require(currentImpl == address(newImplementation), "Implementation mismatch!");
        console.log("");

        console.log("=== Update Complete ===");
        console.log("All 8 OrderBooks now support agent tracking:");
        console.log("- agentTokenId field in Order struct");
        console.log("- executor field in Order struct");
        console.log("- Updated events: OrderPlaced, OrderCancelled");
    }
}
