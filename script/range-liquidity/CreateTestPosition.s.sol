// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {RangeLiquidityManager} from "@scalexcore/RangeLiquidityManager.sol";
import {IRangeLiquidityManager} from "@scalexcore/interfaces/IRangeLiquidityManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@scalexcore/libraries/Currency.sol";
import {PoolKey} from "@scalexcore/libraries/Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CreateTestPosition is Script {
    using CurrencyLibrary for Currency;

    function run() external {
        uint256 userPrivateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(userPrivateKey);

        address rangeLiquidityManagerAddr = vm.envAddress("RANGE_LIQUIDITY_MANAGER");
        address balanceManagerAddr = vm.envAddress("BALANCE_MANAGER");

        // Example configuration - modify these for your test
        address baseToken = vm.envOr("BASE_TOKEN", address(0)); // e.g., WBTC
        address quoteToken = vm.envOr("QUOTE_TOKEN", address(0)); // e.g., USDC
        uint128 lowerPrice = uint128(vm.envOr("LOWER_PRICE", uint256(70_000_00000000))); // 70k
        uint128 upperPrice = uint128(vm.envOr("UPPER_PRICE", uint256(80_000_00000000))); // 80k
        uint16 tickCount = uint16(vm.envOr("TICK_COUNT", uint256(20)));
        uint256 depositAmount = vm.envOr("DEPOSIT_AMOUNT", uint256(100_000e6)); // 100k USDC
        uint16 rebalanceThreshold = uint16(vm.envOr("REBALANCE_THRESHOLD", uint256(500))); // 5%

        console.log("=== CREATING TEST RANGE LIQUIDITY POSITION ===");
        console.log("User:", user);
        console.log("RangeLiquidityManager:", rangeLiquidityManagerAddr);
        console.log("");
        console.log("Position Parameters:");
        console.log("  Base Token:", baseToken);
        console.log("  Quote Token:", quoteToken);
        console.log("  Price Range:", lowerPrice, "-", upperPrice);
        console.log("  Tick Count:", tickCount);
        console.log("  Deposit Amount:", depositAmount);
        console.log("  Strategy: UNIFORM");
        console.log("  Auto-Rebalance: true");
        console.log("  Rebalance Threshold:", rebalanceThreshold, "bps");
        console.log("");

        require(baseToken != address(0), "BASE_TOKEN not set");
        require(quoteToken != address(0), "QUOTE_TOKEN not set");

        vm.startBroadcast(userPrivateKey);

        IBalanceManager balanceManager = IBalanceManager(balanceManagerAddr);
        RangeLiquidityManager rangeLiquidityManager = RangeLiquidityManager(rangeLiquidityManagerAddr);

        // Step 1: Approve tokens
        console.log("Step 1: Approving tokens...");
        IERC20(quoteToken).approve(balanceManagerAddr, type(uint256).max);
        IERC20(baseToken).approve(balanceManagerAddr, type(uint256).max);
        console.log("[OK] Tokens approved");

        // Step 2: Create position
        console.log("Step 2: Creating position...");

        IRangeLiquidityManager.PositionParams memory params = IRangeLiquidityManager.PositionParams({
            poolKey: PoolKey({
                baseCurrency: Currency.wrap(baseToken),
                quoteCurrency: Currency.wrap(quoteToken)
            }),
            strategy: IRangeLiquidityManager.Strategy.UNIFORM,
            lowerPrice: lowerPrice,
            upperPrice: upperPrice,
            tickCount: tickCount,
            depositAmount: depositAmount,
            depositCurrency: Currency.wrap(quoteToken),
            autoRebalance: true,
            rebalanceThresholdBps: rebalanceThreshold
        });

        uint256 positionId = rangeLiquidityManager.createPosition(params);

        console.log("[OK] Position created!");
        console.log("Position ID:", positionId);

        // Step 3: Get position details
        console.log("");
        console.log("Step 3: Fetching position details...");
        IRangeLiquidityManager.RangePosition memory position = rangeLiquidityManager.getPosition(positionId);

        console.log("Position Details:");
        console.log("  Owner:", position.owner);
        console.log("  Strategy:", uint8(position.strategy));
        console.log("  Lower Price:", position.lowerPrice);
        console.log("  Upper Price:", position.upperPrice);
        console.log("  Center Price:", position.centerPriceAtCreation);
        console.log("  Tick Count:", position.tickCount);
        console.log("  Buy Orders:", position.buyOrderIds.length);
        console.log("  Sell Orders:", position.sellOrderIds.length);
        console.log("  Active:", position.isActive);
        console.log("  Created At:", position.createdAt);

        // Step 4: Get position value
        IRangeLiquidityManager.PositionValue memory value = rangeLiquidityManager.getPositionValue(positionId);
        console.log("");
        console.log("Position Value:");
        console.log("  Total Value (Quote):", value.totalValueInQuote);
        console.log("  Base Amount:", value.baseAmount);
        console.log("  Quote Amount:", value.quoteAmount);
        console.log("  Locked in Orders:", value.lockedInOrders);
        console.log("  Free Balance:", value.freeBalance);

        // Step 5: Check if can rebalance
        (bool canReb, uint256 drift) = rangeLiquidityManager.canRebalance(positionId);
        console.log("");
        console.log("Rebalance Status:");
        console.log("  Can Rebalance:", canReb);
        console.log("  Current Drift:", drift, "bps");

        vm.stopBroadcast();

        console.log("");
        console.log("=== POSITION CREATION COMPLETE ===");
        console.log("");
        console.log("Position ID:", positionId);
        console.log("");
        console.log("Next steps:");
        console.log("1. Monitor position performance");
        console.log("2. Set authorized bot:");
        console.log("   rangeLiquidityManager.setAuthorizedBot(", positionId, ", <bot_address>)");
        console.log("3. Wait for price drift and rebalance:");
        console.log("   rangeLiquidityManager.rebalancePosition(", positionId, ")");
        console.log("4. Close position when done:");
        console.log("   rangeLiquidityManager.closePosition(", positionId, ")");
    }
}
