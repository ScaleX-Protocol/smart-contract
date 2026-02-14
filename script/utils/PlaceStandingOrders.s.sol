// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {ScaleXRouter} from "@scalexcore/ScaleXRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@scalexcore/libraries/Pool.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";

/**
 * @title PlaceStandingOrders
 * @notice Places standing limit orders to keep Oracle prices fresh
 * @dev This ensures the Oracle always has recent prices for collateral calculations
 */
contract PlaceStandingOrders is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        uint256 chainId = block.chainid;

        string memory deploymentPath = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));
        console.log("Loading deployment from:", deploymentPath);

        string memory json = vm.readFile(deploymentPath);
        address scaleXRouter = vm.parseJsonAddress(json, ".ScaleXRouter");
        address poolManager = vm.parseJsonAddress(json, ".PoolManager");
        address usdc = vm.parseJsonAddress(json, ".USDC");
        address weth = vm.parseJsonAddress(json, ".WETH");
        address sxUSDC = vm.parseJsonAddress(json, ".sxUSDC");
        address sxWETH = vm.parseJsonAddress(json, ".sxWETH");
        vm.startBroadcast(privateKey);

        console.log("Placing standing limit orders to keep Oracle prices fresh...");

        ScaleXRouter router = ScaleXRouter(scaleXRouter);
        IERC20(weth).approve(scaleXRouter, type(uint256).max);
        IERC20(usdc).approve(scaleXRouter, type(uint256).max);

        // Get pool from PoolManager using PoolKey
        PoolKey memory poolKey = PoolKey(Currency.wrap(sxWETH), Currency.wrap(sxUSDC), 20);
        IPoolManager.Pool memory pool = IPoolManager(poolManager).getPool(poolKey);

        // Place buy order for WETH at $1900 (below market)
        console.log("Placing standing buy order: 0.1 WETH @ $1900...");
        try router.placeLimitOrder(
            pool,
            1900000000, // price: $1900
            100000000000000000, // quantity: 0.1 WETH
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            190000000 // deposit: $190 USDC
        ) {
            console.log("  Success: Buy order placed");
        } catch {
            console.log("  Warning:  Buy order failed (might already have balance)");
        }

        // Place sell order for WETH at $2100 (above market)
        console.log("Placing standing sell order: 0.1 WETH @ $2100...");
        try router.placeLimitOrder(
            pool,
            2100000000, // price: $2100
            100000000000000000, // quantity: 0.1 WETH
            IOrderBook.Side.SELL,
            IOrderBook.TimeInForce.GTC,
            100000000000000000 // deposit: 0.1 WETH
        ) {
            console.log("  Success: Sell order placed");
        } catch {
            console.log("  Warning:  Sell order failed (might already have balance)");
        }

        vm.stopBroadcast();

        console.log("Standing orders placed to maintain Oracle price freshness");
    }
}
