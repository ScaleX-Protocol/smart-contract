// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {RangeLiquidityManager} from "@scalexcore/RangeLiquidityManager.sol";
import {IRangeLiquidityManager} from "@scalexcore/interfaces/IRangeLiquidityManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ClosePosition is Script {
    function run() external {
        uint256 userPrivateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(userPrivateKey);

        address rangeLiquidityManagerAddr = vm.envAddress("RANGE_LIQUIDITY_MANAGER");
        uint256 positionId = vm.envUint("POSITION_ID");

        console.log("=== CLOSING RANGE LIQUIDITY POSITION ===");
        console.log("User:", user);
        console.log("RangeLiquidityManager:", rangeLiquidityManagerAddr);
        console.log("Position ID:", positionId);
        console.log("");

        RangeLiquidityManager rangeLiquidityManager = RangeLiquidityManager(rangeLiquidityManagerAddr);

        // Get position details before closing
        IRangeLiquidityManager.RangePosition memory position = rangeLiquidityManager.getPosition(positionId);
        IRangeLiquidityManager.PositionValue memory value = rangeLiquidityManager.getPositionValue(positionId);

        console.log("Position Details:");
        console.log("  Owner:", position.owner);
        console.log("  Active:", position.isActive);
        console.log("  Created At:", position.createdAt);
        console.log("  Rebalance Count:", position.rebalanceCount);
        console.log("");

        console.log("Position Value:");
        console.log("  Total Value (Quote):", value.totalValueInQuote);
        console.log("  Base Amount:", value.baseAmount);
        console.log("  Quote Amount:", value.quoteAmount);
        console.log("  Locked in Orders:", value.lockedInOrders);
        console.log("");

        require(position.owner == user, "Not position owner");
        require(position.isActive, "Position already closed");

        // Get token balances before
        address baseToken = address(uint160(uint256(keccak256(abi.encode(position.poolKey.baseCurrency)))));
        address quoteToken = address(uint160(uint256(keccak256(abi.encode(position.poolKey.quoteCurrency)))));

        uint256 baseBalanceBefore = IERC20(baseToken).balanceOf(user);
        uint256 quoteBalanceBefore = IERC20(quoteToken).balanceOf(user);

        console.log("User Balances Before:");
        console.log("  Base Token:", baseBalanceBefore);
        console.log("  Quote Token:", quoteBalanceBefore);
        console.log("");

        vm.startBroadcast(userPrivateKey);

        // Close position
        console.log("Closing position...");
        rangeLiquidityManager.closePosition(positionId);
        console.log("[OK] Position closed!");

        vm.stopBroadcast();

        // Get token balances after
        uint256 baseBalanceAfter = IERC20(baseToken).balanceOf(user);
        uint256 quoteBalanceAfter = IERC20(quoteToken).balanceOf(user);

        console.log("");
        console.log("User Balances After:");
        console.log("  Base Token:", baseBalanceAfter);
        console.log("  Quote Token:", quoteBalanceAfter);
        console.log("");

        console.log("Received:");
        console.log("  Base Token:", baseBalanceAfter - baseBalanceBefore);
        console.log("  Quote Token:", quoteBalanceAfter - quoteBalanceBefore);

        console.log("");
        console.log("=== POSITION CLOSED SUCCESSFULLY ===");
    }
}
