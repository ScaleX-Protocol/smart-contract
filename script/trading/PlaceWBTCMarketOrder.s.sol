// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/libraries/Pool.sol";
import "../../src/mocks/MockToken.sol";

/**
 * @title MinimalWBTCMarketOrder
 * @notice Place a market BUY order from PRIVATE_KEY_2 to match against existing SELL limit order
 * Prerequisites: Run MinimalWBTCTest.s.sol first to create SELL limit order
 */
contract MinimalWBTCMarketOrder is Script, DeployHelpers {
    BalanceManager balanceManager;
    PoolManager poolManager;
    ScaleXRouter scalexRouter;

    address marketOrderWallet;  // PRIVATE_KEY_2

    function setUp() public {
        loadDeployments();
        balanceManager = BalanceManager(deployed["BalanceManager"].addr);
        poolManager = PoolManager(deployed["PoolManager"].addr);
        scalexRouter = ScaleXRouter(deployed["ScaleXRouter"].addr);
    }

    function run() public {
        uint256 marketOrderKey = getDeployerKey2();
        marketOrderWallet = vm.addr(marketOrderKey);

        console.log("=== Minimal WBTC Market Order Test ===");
        console.log("Market Order Wallet (PRIVATE_KEY_2):", marketOrderWallet);

        // Get WBTC pool
        address sxWBTC = deployed["sxWBTC"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address usdcAddr = deployed["USDC"].addr;

        Currency wbtc = Currency.wrap(sxWBTC);
        Currency usdc = Currency.wrap(sxUSDC);
        PoolKey memory poolKey = poolManager.createPoolKey(wbtc, usdc);
        IPoolManager.Pool memory pool = poolManager.getPool(poolKey);

        console.log("WBTC Pool OrderBook:", address(pool.orderBook));

        // Check best SELL price before
        IOrderBook.PriceVolume memory bestSell = pool.orderBook.getBestPrice(IOrderBook.Side.SELL);
        console.log("\n[PRE-CHECK] Best SELL price: $", bestSell.price / 1e6);
        console.log("  Volume at best price:", bestSell.volume / 1e16, "* 0.01 BTC");

        vm.startBroadcast(marketOrderKey);

        // Step 1: Mint and deposit USDC (for buying BTC)
        uint256 usdcAmount = 1000e6; // $1,000 USDC
        MockToken(usdcAddr).mint(marketOrderWallet, usdcAmount);
        IERC20(usdcAddr).approve(address(balanceManager), usdcAmount);
        balanceManager.depositLocal(usdcAddr, usdcAmount, marketOrderWallet);

        console.log("\n[STEP 1] Deposited $1,000 USDC to BalanceManager");

        // Check balances before
        uint256 wbtcBalanceBefore = balanceManager.getBalance(marketOrderWallet, Currency.wrap(sxWBTC));
        uint256 usdcBalanceBefore = balanceManager.getBalance(marketOrderWallet, Currency.wrap(sxUSDC));
        console.log("  WBTC balance before:", wbtcBalanceBefore / 1e18, "BTC");
        console.log("  USDC balance before:", usdcBalanceBefore / 1e6, "USDC");

        // Step 2: Place market BUY order
        // Quantity for market BUY = USDC amount to spend
        uint128 usdcToSpend = 1000e6; // $1,000 USDC (should buy ~0.01 BTC at $95,100)

        console.log("\n[STEP 2] Placing Market BUY order");
        console.log("  USDC to spend: $", usdcToSpend / 1e6);
        console.log("  Expected to execute against SELL @ $", bestSell.price / 1e6);

        (uint48 orderId, uint128 filled) = scalexRouter.placeMarketOrder(
            pool,
            usdcToSpend,
            IOrderBook.Side.BUY,
            0, // depositAmount=0 since we already deposited
            0  // minOutAmount=0 (no slippage protection for test)
        );

        console.log("  [RESULT] Market order ID:", orderId);
        console.log("  [RESULT] Filled amount:", filled / 1e16, "* 0.01 BTC");

        // Check balances after
        uint256 wbtcBalanceAfter = balanceManager.getBalance(marketOrderWallet, Currency.wrap(sxWBTC));
        uint256 usdcBalanceAfter = balanceManager.getBalance(marketOrderWallet, Currency.wrap(sxUSDC));

        console.log("\n[STEP 3] Balance changes:");
        console.log("  WBTC gained:", (wbtcBalanceAfter - wbtcBalanceBefore) / 1e16, "* 0.01 BTC");
        console.log("  USDC spent:", (usdcBalanceBefore - usdcBalanceAfter) / 1e6, "USDC");

        vm.stopBroadcast();

        // Verify results
        console.log("\n[VERIFICATION]");
        if (filled == 0) {
            console.log("  [FAIL] No trade executed - filled amount is 0!");
        } else if (wbtcBalanceAfter == wbtcBalanceBefore) {
            console.log("  [FAIL] WBTC balance unchanged - no BTC received!");
        } else {
            console.log("  [SUCCESS] Trade executed!");
            console.log("  Transaction hash will appear in broadcast logs");
            console.log("  Check https://sepolia.basescan.org/address/", address(pool.orderBook), "#events");
        }
    }
}
