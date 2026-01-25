// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/libraries/Pool.sol";
import "../../src/core/interfaces/IOrderBook.sol";

contract CancelOldOrders is Script, DeployHelpers {
    // Contract address keys
    string constant POOL_MANAGER_ADDRESS = "PoolManager";
    string constant SCALEX_ROUTER_ADDRESS = "ScaleXRouter";

    // Core contracts
    PoolManager poolManager;
    ScaleXRouter scalexRouter;

    address deployerAddress;

    function setUp() public {
        loadDeployments();
        loadContracts();
    }

    function loadContracts() private {
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
        scalexRouter = ScaleXRouter(deployed[SCALEX_ROUTER_ADDRESS].addr);
    }

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Cancel orders in each RWA pool
        cancelPoolOrders("sxGOLD", "sxUSDC");
        cancelPoolOrders("sxSILVER", "sxUSDC");
        cancelPoolOrders("sxGOOGLE", "sxUSDC");
        cancelPoolOrders("sxNVIDIA", "sxUSDC");
        cancelPoolOrders("sxMNT", "sxUSDC");
        cancelPoolOrders("sxAPPLE", "sxUSDC");
        cancelPoolOrders("sxWBTC", "sxUSDC");

        vm.stopBroadcast();
    }

    function cancelPoolOrders(string memory syntheticSymbol, string memory quoteSymbol) private {
        console.log(string(abi.encodePacked("\n=== Canceling Orders: ", syntheticSymbol, "/", quoteSymbol, " ===")));

        if (!deployed[syntheticSymbol].isSet || !deployed[quoteSymbol].isSet) {
            console.log("[SKIP] Token not found");
            return;
        }

        address sxToken = deployed[syntheticSymbol].addr;
        address sxUSDC = deployed[quoteSymbol].addr;

        // Get pool
        Currency token = Currency.wrap(sxToken);
        Currency usdc = Currency.wrap(sxUSDC);
        PoolKey memory poolKey = poolManager.createPoolKey(token, usdc);

        IPoolManager.Pool memory pool;
        try poolManager.getPool(poolKey) returns (IPoolManager.Pool memory retrievedPool) {
            pool = retrievedPool;
            console.log("[OK] Found pool at OrderBook:", address(pool.orderBook));
        } catch {
            console.log("[SKIP] Pool not found");
            return;
        }

        // Try to cancel order IDs from 1 to 100 (covers typical deployments)
        // Only orders owned by the deployer will be cancelled
        uint256 cancelCount = 0;
        for (uint48 orderId = 1; orderId <= 100; orderId++) {
            try pool.orderBook.getOrder(orderId) returns (IOrderBook.Order memory order) {
                // Check if order exists and belongs to deployer
                if (order.user == deployerAddress &&
                    (order.status == IOrderBook.Status.OPEN || order.status == IOrderBook.Status.PARTIALLY_FILLED)) {
                    try scalexRouter.cancelOrder(pool, orderId) {
                        console.log("  [OK] Cancelled order ID:", orderId);
                        cancelCount++;
                    } catch {
                        console.log("  [FAIL] Could not cancel order ID:", orderId);
                    }
                }
            } catch {
                // Order doesn't exist, skip silently
            }
        }

        if (cancelCount == 0) {
            console.log("[INFO] No orders found to cancel");
        } else {
            console.log("[COMPLETE] Cancelled", cancelCount, "orders");
        }
    }
}
