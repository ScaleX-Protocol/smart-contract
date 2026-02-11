// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./MarketOrderBook.sol";

/**
 * @title PlaceSellOrdersWorkaround
 * @notice Places SELL limit orders at high prices compatible with old 6-decimal BUY orders
 * @dev This is a workaround until old orders are cleaned up
 */
contract PlaceSellOrdersWorkaround is MarketOrderBook {

    // Override to only place SELL limit orders, no market orders
    function run() public override {
        setUp();

        loadDeployments();
        uint256 deployerPrivateKey = getDeployerKey();

        console.log("\n=== Placing SELL Limit Orders (Workaround for 6-decimal BUY orders) ===\n");

        vm.startBroadcast(deployerPrivateKey);

        // Get currency objects
        Currency weth = Currency.wrap(address(synthWETH));
        Currency quote = Currency.wrap(address(synthQuote));

        // Get pool
        IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, quote, address(poolManager));

        // Place SELL limit orders at prices compatible with old 6-decimal BUY orders
        // Old BUY orders are at: 1,980,000,000 (1980 IDRX * 1e6)
        // New SELL orders at: 2,000,000,000+ (using 6-decimal format to match)

        uint128[] memory sellPrices = new uint128[](10);
        sellPrices[0] = 2_000_000_000; // 2000 IDRX (6 decimals)
        sellPrices[1] = 2_010_000_000; // 2010 IDRX
        sellPrices[2] = 2_020_000_000; // 2020 IDRX
        sellPrices[3] = 2_030_000_000; // 2030 IDRX
        sellPrices[4] = 2_040_000_000; // 2040 IDRX
        sellPrices[5] = 2_050_000_000; // 2050 IDRX
        sellPrices[6] = 2_060_000_000; // 2060 IDRX
        sellPrices[7] = 2_070_000_000; // 2070 IDRX
        sellPrices[8] = 2_080_000_000; // 2080 IDRX
        sellPrices[9] = 2_090_000_000; // 2090 IDRX

        uint128 quantity = 5e15; // 0.005 ETH per order

        console.log("Placing 10 SELL orders from 2,000,000,000 to 2,090,000,000 (6-decimal format)");

        for (uint i = 0; i < sellPrices.length; i++) {
            try scalexRouter.placeLimitOrder(
                pool,
                quantity,
                sellPrices[i],
                IOrderBook.Side.SELL,
                address(0),
                bytes32(0)
            ) returns (uint48 orderId) {
                console.log("  [OK] Placed SELL order ID:", orderId, "at price:", sellPrices[i]);
            } catch Error(string memory reason) {
                console.log("  [FAIL] Failed at price:", sellPrices[i], "- Reason:", reason);
            } catch {
                console.log("  [FAIL] Failed at price:", sellPrices[i]);
            }
        }

        vm.stopBroadcast();

        console.log("\n[OK] SELL orders placement complete!");
        console.log("Market BUY orders should now be able to execute.\n");
    }
}
