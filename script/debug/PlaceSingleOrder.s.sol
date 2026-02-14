// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/libraries/Pool.sol";

contract PlaceSingleOrder is Script, DeployHelpers {
    function run() public {
        loadDeployments();

        // Get contracts
        address balanceManagerAddr = deployed["BalanceManager"].addr;
        address routerAddr = deployed["ScaleXRouter"].addr;
        address sxWETHAddr = deployed["sxWETH"].addr;
        address sxUSDCAddr = deployed["sxUSDC"].addr;
        address poolAddr = deployed["WETH_USDC_Pool"].addr;

        console.log("=== Contract Addresses ===");
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("Router:", routerAddr);
        console.log("sxWETH:", sxWETHAddr);
        console.log("sxUSDC:", sxUSDCAddr);
        console.log("Pool/OrderBook:", poolAddr);

        uint256 deployerPrivateKey = getDeployerKey();
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n=== Deployer Info ===");
        console.log("Deployer address:", deployer);

        // Check balances before
        BalanceManager bm = BalanceManager(balanceManagerAddr);
        uint256 wethBalance = bm.getBalance(deployer, Currency.wrap(sxWETHAddr));
        uint256 usdcBalance = bm.getBalance(deployer, Currency.wrap(sxUSDCAddr));

        console.log("\n=== Balance Manager Balances ===");
        console.log("sxWETH balance:", wethBalance / 1e18, "ETH");
        console.log("sxUSDC balance:", usdcBalance / 1e6, "USDC");

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n=== Placing SELL Limit Order ===");
        console.log("Price: 3270 USDC (3270000000 with 6 decimals)");
        console.log("Quantity: 0.01 ETH (10000000000000000 wei)");
        console.log("Side: SELL (1)");
        console.log("TimeInForce: GTC (0)");
        console.log("DepositAmount: 0 (using BalanceManager balance)");

        ScaleXRouter router = ScaleXRouter(routerAddr);

        IPoolManager.Pool memory pool = IPoolManager.Pool({
            baseCurrency: Currency.wrap(sxWETHAddr),
            quoteCurrency: Currency.wrap(sxUSDCAddr),
            orderBook: IOrderBook(poolAddr),
            feeTier: 20
        });

        try router.placeLimitOrder(
            pool,
            3270000000,  // price: $3270
            10000000000000000,  // quantity: 0.01 ETH
            IOrderBook.Side.SELL,
            IOrderBook.TimeInForce.GTC,
            0  // depositAmount: 0 (use BalanceManager)
        ) returns (uint48 orderId) {
            console.log("\n[SUCCESS] Order placed!");
            console.log("Order ID:", orderId);
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Order failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("\n[ERROR] Order failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();

        // Check balances after
        uint256 wethBalanceAfter = bm.getBalance(deployer, Currency.wrap(sxWETHAddr));
        uint256 usdcBalanceAfter = bm.getBalance(deployer, Currency.wrap(sxUSDCAddr));

        console.log("\n=== Balance Manager Balances After ===");
        console.log("sxWETH balance:", wethBalanceAfter / 1e18, "ETH");
        console.log("sxUSDC balance:", usdcBalanceAfter / 1e6, "USDC");
    }
}
