// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/interfaces/IPoolManager.sol";
import "../../src/core/libraries/Pool.sol";
import "../../src/mocks/MockToken.sol";
import "../../src/core/interfaces/IOrderBook.sol";

/**
 * @title MinimalNVIDIAMarketOrder
 * @notice Place market BUY order to match against existing NVIDIA SELL limit order
 */
contract MinimalNVIDIAMarketOrder is Script, DeployHelpers {
    BalanceManager balanceManager;
    PoolManager poolManager;
    ScaleXRouter scalexRouter;

    address marketOrderWallet;

    function setUp() public {
        loadDeployments();
        balanceManager = BalanceManager(deployed["BalanceManager"].addr);
        scalexRouter = ScaleXRouter(payable(deployed["ScaleXRouter"].addr));
        poolManager = PoolManager(deployed["PoolManager"].addr);
    }

    function run() external {
        uint256 marketOrderKey = vm.envUint("PRIVATE_KEY_2");
        marketOrderWallet = vm.addr(marketOrderKey);

        address sxNVIDIA = deployed["sxNVIDIA"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address usdcAddr = deployed["USDC"].addr;

        Currency nvidia = Currency.wrap(sxNVIDIA);
        Currency usdc = Currency.wrap(sxUSDC);
        PoolKey memory poolKey = poolManager.createPoolKey(nvidia, usdc);
        IPoolManager.Pool memory pool = poolManager.getPool(poolKey);

        console.log("\n=== NVIDIA Market Order Test ===");
        console.log("NVIDIA Pool OrderBook:", address(pool.orderBook));
        console.log("Market Order Wallet:", marketOrderWallet);

        vm.startBroadcast(marketOrderKey);

        // Step 1: Mint and deposit USDC for BUY order
        // Price is $190, want to buy 1 NVIDIA = need $200 USDC
        uint256 usdcAmount = 200e6; // $200 USDC (6 decimals)
        MockToken(usdcAddr).mint(marketOrderWallet, usdcAmount);
        IERC20(usdcAddr).approve(address(balanceManager), usdcAmount);
        balanceManager.depositLocal(usdcAddr, usdcAmount, marketOrderWallet);

        console.log("\n[STEP 1] Deposited $200 USDC to BalanceManager");

        // Check balance
        uint256 balance = balanceManager.getBalance(marketOrderWallet, Currency.wrap(sxUSDC));
        console.log("  sxUSDC balance:", balance / 1e6, "USDC");

        // Step 2: Place market BUY order
        // For BUY orders, quantity = USDC amount to spend (not base token quantity!)
        console.log("\n[STEP 2] Placing market BUY order for $200 USDC...");

        uint48 orderId;
        uint128 filled;
        try scalexRouter.placeMarketOrder(
            pool,
            200e6, // $200 USDC to spend (6 decimals)
            IOrderBook.Side.BUY,
            0, // depositAmount=0 since we already deposited
            0  // minOutAmount=0 for testing
        ) returns (uint48 id, uint128 _filled) {
            orderId = id;
            filled = _filled;
            console.log("  [OK] Market BUY executed - ID:", id);
            console.log("  Filled:", _filled / 1e18, "NVIDIA tokens");
        } catch Error(string memory reason) {
            console.log("  [FAIL] Market order failed:", reason);
            vm.stopBroadcast();
            return;
        } catch {
            console.log("  [FAIL] Market order failed (unknown error)");
            vm.stopBroadcast();
            return;
        }

        // Step 3: Check balances after trade
        console.log("\n[STEP 3] Checking balances after trade...");

        uint256 usdcBalanceAfter = balanceManager.getBalance(marketOrderWallet, Currency.wrap(sxUSDC));
        uint256 nvidiaBalanceAfter = balanceManager.getBalance(marketOrderWallet, Currency.wrap(sxNVIDIA));

        console.log("  USDC remaining:", usdcBalanceAfter / 1e6, "USDC");
        console.log("  NVIDIA gained:", nvidiaBalanceAfter / 1e18, "NVIDIA");

        if (filled > 0) {
            console.log("\n  [SUCCESS] Order matched successfully!");
        } else {
            console.log("\n  [WARNING] No fill occurred - check if limit orders exist");
        }

        // Check best BUY price (should have our market order if not fully filled)
        IOrderBook.PriceVolume memory bestBuy = pool.orderBook.getBestPrice(IOrderBook.Side.BUY);
        console.log("\n[VERIFICATION] Best BUY price: $", bestBuy.price / 1e6);
        console.log("  Volume at best price:", bestBuy.volume / 1e18, "NVIDIA");

        vm.stopBroadcast();
    }
}
