// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/yield/LendingManager.sol";
import "../../src/core/interfaces/IBalanceManager.sol";

contract DebugHealthFactor is Script {
    function run() external view {
        address user = 0xC21C5b2d33b791BEb51360a6dcb592ECdE37DB2C;
        address lendingManager = 0x17D803b6Bb4ECF60e8f8b60f4489afdA1743e021;
        address weth = 0x8b732595a59c9a18acA0Aca3221A656Eb38158fC; // WETH address
        address idrx = 0x80FD9a0F8BCA5255692016D67E0733bf5262C142; // IDRX address

        // The amount user is trying to borrow (0.025648 WETH in wei)
        uint256 borrowAmount = 25648196098739855;

        console.log("=== DEBUGGING HEALTH FACTOR CALCULATION ===");
        console.log("User:", user);
        console.log("Borrow Amount (WETH wei):", borrowAmount);
        console.log("Borrow Amount (WETH):", borrowAmount / 1e18);
        console.log("");

        // Get LendingManager
        LendingManager lm = LendingManager(lendingManager);

        // Get current user position
        console.log("=== CURRENT POSITION ===");
        uint256 currentHF = lm.getHealthFactor(user);
        console.log("Current Health Factor:", currentHF);
        console.log("Current Health Factor (scaled):", currentHF / 1e18);
        console.log("");

        // Get user's supplies
        console.log("=== USER SUPPLIES ===");
        uint256 idrxSupply = lm.getUserSupply(user, idrx);
        uint256 wethSupply = lm.getUserSupply(user, weth);
        console.log("IDRX Supply:", idrxSupply);
        console.log("WETH Supply:", wethSupply);
        console.log("");

        // Get user's debts
        console.log("=== USER DEBTS ===");
        uint256 idrxDebt = lm.getUserDebt(user, idrx);
        uint256 wethDebt = lm.getUserDebt(user, weth);
        console.log("IDRX Debt:", idrxDebt);
        console.log("WETH Debt:", wethDebt);
        console.log("");

        // Get oracle prices
        console.log("=== ORACLE PRICES ===");
        IOracle oracle = IOracle(lm.oracle());
        uint256 idrxPrice = oracle.getPriceForCollateral(idrx);
        uint256 wethPrice = oracle.getPriceForCollateral(weth);
        console.log("IDRX Price (8 decimals):", idrxPrice);
        console.log("WETH Price (8 decimals):", wethPrice);
        console.log("IDRX Price USD:", idrxPrice / 1e8);
        console.log("WETH Price USD:", wethPrice / 1e8);
        console.log("");

        // Calculate collateral value
        console.log("=== COLLATERAL VALUE CALCULATION ===");
        uint256 idrxCollateralValue = (idrxSupply * idrxPrice) / 1e18; // Assuming 18 decimals for IDRX
        console.log("IDRX Collateral Value (8 decimals):", idrxCollateralValue);
        console.log("IDRX Collateral Value USD:", idrxCollateralValue / 1e8);
        console.log("");

        // Calculate projected debt value
        console.log("=== PROJECTED DEBT VALUE ===");
        uint256 currentDebtValue = (wethDebt * wethPrice) / 1e18;
        uint256 additionalDebtValue = (borrowAmount * wethPrice) / 1e18;
        uint256 totalProjectedDebt = currentDebtValue + additionalDebtValue;
        console.log("Current Debt Value (8 decimals):", currentDebtValue);
        console.log("Additional Debt Value (8 decimals):", additionalDebtValue);
        console.log("Total Projected Debt (8 decimals):", totalProjectedDebt);
        console.log("Additional Debt Value USD:", additionalDebtValue / 1e8);
        console.log("Total Projected Debt USD:", totalProjectedDebt / 1e8);
        console.log("");

        // Get projected health factor
        console.log("=== PROJECTED HEALTH FACTOR ===");
        uint256 projectedHF = lm.getProjectedHealthFactor(user, weth, borrowAmount);
        console.log("Projected HF (raw):", projectedHF);
        console.log("Projected HF (decimal):", projectedHF / 1e16); // Display as percentage
        console.log("Projected HF / 1e18:", projectedHF / 1e18);
        console.log("");

        // Manual calculation
        console.log("=== MANUAL CALCULATION ===");
        console.log("Formula: HF = (collateralValue * liquidationThreshold / 10000 * 1e18) / debtValue");
        console.log("Liquidation Threshold (IDRX): 85% = 8500 basis points");

        if (totalProjectedDebt > 0) {
            // Assuming BASIS_POINTS = 10000 and liquidation threshold = 8500 (85%)
            uint256 weightedCollateral = (idrxCollateralValue * 8500) / 10000;
            uint256 manualHF = (weightedCollateral * 1e18) / totalProjectedDebt;
            console.log("Weighted Collateral:", weightedCollateral);
            console.log("Weighted Collateral USD:", weightedCollateral / 1e8);
            console.log("Manual HF Calculation:", manualHF);
            console.log("Manual HF / 1e18:", manualHF / 1e18);
        }

        console.log("");
        console.log("=== DIAGNOSIS ===");
        if (projectedHF < 1e18) {
            console.log("FAILED: Projected HF < 1.0");
            console.log("Health factor too low for this borrow!");

            // Calculate max safe borrow
            uint256 maxSafeBorrowValue = (idrxCollateralValue * 8500) / 10000;
            uint256 maxSafeBorrowWETH = (maxSafeBorrowValue * 1e18) / wethPrice;
            console.log("Max Safe Borrow Value USD:", maxSafeBorrowValue / 1e8);
            console.log("Max Safe Borrow WETH:", maxSafeBorrowWETH);
            console.log("Max Safe Borrow WETH (decimal):", maxSafeBorrowWETH / 1e18);
        } else {
            console.log("PASSED: Projected HF >= 1.0");
        }
    }

    function getOracle() external view returns (address) {
        address lendingManager = 0x17D803b6Bb4ECF60e8f8b60f4489afdA1743e021;
        LendingManager lm = LendingManager(lendingManager);
        return lm.oracle();
    }
}
