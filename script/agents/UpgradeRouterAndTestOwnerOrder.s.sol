// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/interfaces/IOrderBook.sol";
import "../../src/core/interfaces/IPoolManager.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeRouterAndTestOwnerOrder is Script {
    function run() external {
        uint256 ownerKey = vm.envUint("PRIVATE_KEY");

        // Addresses
        address scaleXBeacon = 0x69084de99fBb3cA68683F540249FB815b9854863;
        address scaleXRouter = 0xc882b5af2B1AFB37CDe4D1f696fb112979cf98EE;
        address wethPool = 0x629A14ee7dC9D29A5EB676FBcEF94E989Bc0DEA1;

        console.log("=== Step 1: Deploy New ScaleXRouter Implementation ===");
        console.log("Beacon:", scaleXBeacon);
        console.log("");

        vm.startBroadcast(ownerKey);

        // Deploy new implementation
        ScaleXRouter newImpl = new ScaleXRouter();
        console.log("New Implementation:", address(newImpl));

        // Upgrade ScaleXRouter beacon
        UpgradeableBeacon(scaleXBeacon).upgradeTo(address(newImpl));
        console.log("ScaleXRouter beacon upgraded");
        console.log("");

        // Authorize ScaleXRouter on OrderBook
        console.log("=== Step 2: Authorize ScaleXRouter on OrderBook ===");
        address poolManager = 0x630D8C79407CB90e0AFE68E3841eadd3F94Fc81F;
        (bool success, ) = poolManager.call(
            abi.encodeWithSignature("addAuthorizedRouterToOrderBook(address,address)", wethPool, scaleXRouter)
        );
        require(success, "Failed to authorize router");
        console.log("ScaleXRouter authorized on WETH pool");
        console.log("");

        console.log("=== Step 3: Place Owner Order ===");

        IPoolManager.Pool memory pool = IPoolManager.Pool({
            orderBook: IOrderBook(wethPool),
            baseCurrency: Currency.wrap(0x498509897F5359dd8C74aecd7Ed3a44523df9B9e),
            quoteCurrency: Currency.wrap(0x7770cA54914d53A4AC8ef4618A36139141B7546A)
        });

        uint48 orderId = ScaleXRouter(scaleXRouter).placeLimitOrder(
            pool,
            305000,  // Slightly different price
            10000000000000000,  // 0.01 WETH
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            0  // depositAmount
        );

        console.log("SUCCESS! Owner Order ID:", orderId);
        console.log("");

        // Read the order to compare with agent order
        IOrderBook.Order memory order = IOrderBook(wethPool).getOrder(orderId);
        console.log("=== Order Comparison ===");
        console.log("User:", order.user);
        console.log("Agent Token ID:", order.agentTokenId, "(0 = non-agent order)");
        console.log("Executor:", order.executor, "(should be owner)");
        console.log("Price:", order.price);
        console.log("Quantity:", order.quantity);
        console.log("");

        if (order.agentTokenId == 0 && order.executor == vm.addr(ownerKey)) {
            console.log("VERIFIED: Regular owner order (non-agent)");
        }

        vm.stopBroadcast();
    }
}
