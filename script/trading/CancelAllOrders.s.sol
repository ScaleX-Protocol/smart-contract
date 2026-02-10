// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/OrderBook.sol";
import "../../src/core/libraries/Pool.sol";

contract CancelAllOrders is Script, DeployHelpers {
    string constant SCALEX_ROUTER_ADDRESS = "ScaleXRouter";
    string constant POOL_MANAGER_ADDRESS = "PoolManager";

    ScaleXRouter scalexRouter;
    PoolManager poolManager;

    function setUp() public {
        loadDeployments();
        scalexRouter = ScaleXRouter(deployed[SCALEX_ROUTER_ADDRESS].addr);
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
    }

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        address deployerAddress = vm.addr(deployerPrivateKey);

        string memory quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);

        console.log("Canceling orders for deployer:", deployerAddress);
        console.log("Quote Currency:", quoteCurrency);

        vm.startBroadcast(deployerPrivateKey);

        // Cancel orders for each pool
        cancelPoolOrders("WBTC", sxQuoteKey, deployerAddress);
        cancelPoolOrders("GOLD", sxQuoteKey, deployerAddress);
        cancelPoolOrders("SILVER", sxQuoteKey, deployerAddress);
        cancelPoolOrders("GOOGLE", sxQuoteKey, deployerAddress);
        cancelPoolOrders("NVIDIA", sxQuoteKey, deployerAddress);
        cancelPoolOrders("MNT", sxQuoteKey, deployerAddress);
        cancelPoolOrders("APPLE", sxQuoteKey, deployerAddress);

        vm.stopBroadcast();
    }

    function cancelPoolOrders(
        string memory tokenSymbol,
        string memory sxQuoteKey,
        address user
    ) private {
        string memory sxTokenKey = string.concat("sx", tokenSymbol);

        if (!deployed[sxTokenKey].isSet || !deployed[sxQuoteKey].isSet) {
            console.log("[SKIP]", tokenSymbol, "pool not found");
            return;
        }

        address sxToken = deployed[sxTokenKey].addr;
        address sxQuote = deployed[sxQuoteKey].addr;

        Currency token = Currency.wrap(sxToken);
        Currency quote = Currency.wrap(sxQuote);

        PoolKey memory poolKey = poolManager.createPoolKey(token, quote);
        IPoolManager.Pool memory pool;

        try poolManager.getPool(poolKey) returns (IPoolManager.Pool memory retrievedPool) {
            pool = retrievedPool;
        } catch {
            console.log("[SKIP]", tokenSymbol, "pool not found");
            return;
        }

        console.log(string.concat("\n=== Canceling ", tokenSymbol, " Orders ==="));

        // Try to cancel order IDs 1-50 (brute force approach)
        // In production, you'd track order IDs or query them from events
        uint256 canceledCount = 0;
        for (uint48 orderId = 1; orderId <= 50; orderId++) {
            try scalexRouter.cancelOrder(pool, orderId) {
                console.log("  [OK] Canceled order ID:", orderId);
                canceledCount++;
            } catch {
                // Order doesn't exist or not owned by user - silently skip
            }
        }

        console.log("[COMPLETE] Canceled", canceledCount, "orders for", tokenSymbol);
    }
}
