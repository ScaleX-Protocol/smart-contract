// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/interfaces/IOrderBook.sol";
import "../../src/core/interfaces/IPoolManager.sol";

contract TestOwnerOrderForComparison is Script {
    function run() external {
        address scaleXRouter = vm.parseJsonAddress(
            vm.readFile("deployments/84532.json"),
            ".ScaleXRouter"
        );
        address wethPool = 0x629A14ee7dC9D29A5EB676FBcEF94E989Bc0DEA1;

        uint256 ownerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerKey);

        console.log("=== Test Owner Order (Non-Agent) ===");
        console.log("ScaleXRouter:", scaleXRouter);
        console.log("WETH Pool:", wethPool);
        console.log("Owner:", owner);
        console.log("");

        IPoolManager.Pool memory pool = IPoolManager.Pool({
            orderBook: IOrderBook(wethPool),
            baseCurrency: Currency.wrap(0x498509897F5359dd8C74aecd7Ed3a44523df9B9e),
            quoteCurrency: Currency.wrap(0x7770cA54914d53A4AC8ef4618A36139141B7546A)
        });

        vm.startBroadcast(ownerKey);

        try ScaleXRouter(scaleXRouter).placeLimitOrder(
            pool,
            305000,  // Slightly different price to distinguish from agent order
            10000000000000000,  // 0.01 WETH
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            0  // depositAmount (assume already have balance)
        ) returns (uint48 orderId) {
            console.log("SUCCESS! Order ID:", orderId);
            console.log("");

            // Read the order to verify it's a regular (non-agent) order
            IOrderBook.Order memory order = IOrderBook(wethPool).getOrder(orderId);
            console.log("Order details:");
            console.log("  User:", order.user);
            console.log("  Agent Token ID:", order.agentTokenId, "(should be 0 for non-agent)");
            console.log("  Executor:", order.executor, "(should be owner for non-agent)");
            console.log("  Price:", order.price);
            console.log("  Quantity:", order.quantity);
            console.log("");

            if (order.agentTokenId == 0) {
                console.log("VERIFIED: This is a regular (non-agent) order");
            } else {
                console.log("WARNING: Expected agentTokenId to be 0");
            }

        } catch Error(string memory reason) {
            console.log("REVERT:", reason);
        } catch (bytes memory) {
            console.log("REVERT: Unknown error");
        }

        vm.stopBroadcast();
    }
}
