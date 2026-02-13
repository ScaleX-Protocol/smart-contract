// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/ai-agents/AgentRouter.sol";
import "../../src/core/interfaces/IOrderBook.sol";
import "../../src/core/interfaces/IPoolManager.sol";

contract TestAgentOrderWithTracking is Script {
    function run() external {
        address agentRouter = 0x9F7D22e7065d68F689FBC4354C9f70c9a85D8982;
        address wethPool = 0x629A14ee7dC9D29A5EB676FBcEF94E989Bc0DEA1;
        address sxWETH = 0x498509897F5359dd8C74aecd7Ed3a44523df9B9e;
        address sxIDRX = 0x7770cA54914d53A4AC8ef4618A36139141B7546A;

        uint256 executorKey = vm.envUint("AGENT_EXECUTOR_1_KEY");

        console.log("=== Test Agent Order with Tracking ===");
        console.log("AgentRouter:", agentRouter);
        console.log("WETH Pool:", wethPool);
        console.log("");

        IPoolManager.Pool memory pool = IPoolManager.Pool({
            orderBook: IOrderBook(wethPool),
            baseCurrency: Currency.wrap(sxWETH),
            quoteCurrency: Currency.wrap(sxIDRX)
        });

        vm.startBroadcast(executorKey);

        try AgentRouter(agentRouter).executeLimitOrder(
            100,
            pool,
            300000,
            10000000000000000,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        ) returns (uint48 orderId) {
            console.log("SUCCESS! Order ID:", orderId);
            console.log("");

            // Read the order to verify agent tracking
            IOrderBook.Order memory order = IOrderBook(wethPool).getOrder(orderId);
            console.log("Order details:");
            console.log("  User:", order.user);
            console.log("  Agent Token ID:", order.agentTokenId);
            console.log("  Executor:", order.executor);
            console.log("  Price:", order.price);
            console.log("  Quantity:", order.quantity);

        } catch Error(string memory reason) {
            console.log("REVERT:", reason);
        } catch (bytes memory) {
            console.log("REVERT: Unknown error");
        }

        vm.stopBroadcast();
    }
}
