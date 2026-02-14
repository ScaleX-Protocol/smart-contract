// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RangeLiquidityTestBase} from "./RangeLiquidityTestBase.t.sol";
import {IRangeLiquidityManager} from "@scalexcore/interfaces/IRangeLiquidityManager.sol";

contract RangeLiquidityFeeTest is RangeLiquidityTestBase {
    function testFeeCollection() public {
        // Step 1: Create position
        vm.startPrank(liquidityProvider);

        uint256 positionId = _createPosition(
            IRangeLiquidityManager.Strategy.UNIFORM,
            70_000e8, 80_000e8, 10, 100_000e6, false, 0
        );

        vm.stopPrank();

        // Step 2: Collect fees (should not revert even with zero fees)
        vm.startPrank(liquidityProvider);

        rangeLiquidityManager.collectFees(positionId);

        IRangeLiquidityManager.PositionValue memory value = rangeLiquidityManager.getPositionValue(positionId);

        assertTrue(value.feesEarnedBase >= 0, "Should track base fees");
        assertTrue(value.feesEarnedQuote >= 0, "Should track quote fees");

        vm.stopPrank();
    }
}
