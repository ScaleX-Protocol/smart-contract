// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/ai-agents/AgentRouter.sol";
import "../src/core/interfaces/IPoolManager.sol";
import "../src/core/interfaces/IOrderBook.sol";

contract TestAgentTrade is Script {
    function run() external {
        // Load from deployments
        address agentRouter = 0x36f229515bf0e4c74165b214c56bE8c0b49a1574;
        address wethPool = 0x629A14ee7dC9D29A5EB676FBcEF94E989Bc0DEA1;
        address sxWETH = 0x498509897F5359dd8C74aecd7Ed3a44523df9B9e;
        address sxIDRX = 0x7770cA54914d53A4AC8ef4618A36139141B7546A;

        uint256 executorKey = vm.envUint("AGENT_EXECUTOR_1_KEY");
        address user = vm.envOr("TRADER_ADDRESS", vm.addr(executorKey));

        console.log("=== TESTING AGENT TRADE ===");
        console.log("AgentRouter:", agentRouter);
        console.log("OrderBook:", wethPool);
        console.log("User (trader):", user);
        console.log("Executor:", vm.addr(executorKey));
        console.log("");

        // Prepare pool struct
        IPoolManager.Pool memory pool = IPoolManager.Pool({
            orderBook: IOrderBook(wethPool),
            baseCurrency: Currency.wrap(sxWETH),
            quoteCurrency: Currency.wrap(sxIDRX)
        });

        console.log("Pool.orderBook:", address(pool.orderBook));
        console.log("Pool.baseCurrency:", Currency.unwrap(pool.baseCurrency));
        console.log("Pool.quoteCurrency:", Currency.unwrap(pool.quoteCurrency));
        console.log("");

        console.log("Order details:");
        console.log("  agentId: 100");
        console.log("  price: 300000 (3000.00 IDRX)");
        console.log("  quantity: 10000000000000000 (0.01 WETH)");
        console.log("  side: BUY (0)");
        console.log("  timeInForce: GTC (0)");
        console.log("");

        vm.startBroadcast(executorKey);

        try AgentRouter(agentRouter).executeLimitOrder(
            user,                       // user (trader)
            100,                        // strategyAgentId
            pool,                       // pool
            300000,                     // limitPrice
            10000000000000000,          // quantity (0.01 WETH)
            IOrderBook.Side.BUY,        // side
            IOrderBook.TimeInForce.GTC, // timeInForce
            false,                      // autoRepay
            false                       // autoBorrow
        ) returns (uint48 orderId) {
            console.log("SUCCESS! Order ID:", orderId);
        } catch Error(string memory reason) {
            console.log("REVERT with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("REVERT with low-level data:");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== TEST COMPLETE ===");
    }
}
