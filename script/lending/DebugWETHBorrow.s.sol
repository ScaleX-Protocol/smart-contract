// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface ILendingManager {
    function borrow(address token, uint256 amount) external;
    function getHealthFactor(address user) external view returns (uint256);
    function totalLiquidity(address token) external view returns (uint256);
    function totalBorrowed(address token) external view returns (uint256);
    function getUserDebt(address user, address token) external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract DebugWETHBorrow is Script {
    // Base Sepolia addresses
    address constant LENDING_MANAGER = 0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c;
    address constant WETH = 0x8b732595a59c9a18acA0Aca3221A656Eb38158fC;

    function run() external {
        // Get borrow amount from environment or use default
        uint256 borrowAmount = vm.envOr("BORROW_AMOUNT", uint256(87000 ether)); // 87,000 WETH

        address borrower = vm.envAddress("BORROWER_ADDRESS");

        console.log("=================================================================");
        console.log("WETH BORROW DEBUG SCRIPT");
        console.log("=================================================================");
        console.log("");
        console.log("Borrower:", borrower);
        console.log("Lending Manager:", LENDING_MANAGER);
        console.log("WETH Token:", WETH);
        console.log("Borrow Amount:", borrowAmount / 1e18, "WETH");
        console.log("");

        // PRE-CHECK 1: Pool State
        console.log("=== PRE-CHECK 1: WETH Pool State ===");
        ILendingManager lendingManager = ILendingManager(LENDING_MANAGER);

        uint256 totalLiquidity = lendingManager.totalLiquidity(WETH);
        uint256 totalBorrowed = lendingManager.totalBorrowed(WETH);
        uint256 available = totalLiquidity - totalBorrowed;
        uint256 utilization = totalLiquidity > 0 ? (totalBorrowed * 100) / totalLiquidity : 0;

        console.log("Total Liquidity:", totalLiquidity / 1e18, "WETH");
        console.log("Total Borrowed:", totalBorrowed / 1e18, "WETH");
        console.log("Available to Borrow:", available / 1e18, "WETH");
        console.log("Current Utilization:", utilization, "%");
        console.log("");

        if (borrowAmount > available) {
            console.log("ERROR: Borrow amount exceeds available liquidity!");
            console.log("Requested:", borrowAmount / 1e18, "WETH");
            console.log("Available:", available / 1e18, "WETH");
            console.log("Shortfall:", (borrowAmount - available) / 1e18, "WETH");
            revert("Insufficient liquidity");
        } else {
            console.log("CHECK PASSED: Sufficient liquidity available");
        }
        console.log("");

        // PRE-CHECK 2: User State
        console.log("=== PRE-CHECK 2: User State ===");

        uint256 currentBorrow = lendingManager.getUserDebt(borrower, WETH);
        uint256 healthFactorBefore = lendingManager.getHealthFactor(borrower);

        console.log("Current WETH Borrowed:", currentBorrow / 1e18, "WETH");
        console.log("Health Factor (Before):", healthFactorBefore / 1e18);
        console.log("");

        if (healthFactorBefore < 1.5 ether) {
            console.log("WARNING: Health factor below safe threshold (1.5)");
            console.log("Actual HF:", healthFactorBefore / 1e18);
        } else {
            console.log("CHECK PASSED: Health factor is safe");
        }
        console.log("");

        // PRE-CHECK 3: Skip projected health factor (need oracle prices)
        console.log("=== PRE-CHECK 3: Projected Health Factor ===");
        console.log("Skipping detailed projection (requires oracle prices)");
        console.log("Will rely on contract's health factor check");
        console.log("");

        // PRE-CHECK 4: Lending Manager State
        console.log("=== PRE-CHECK 4: Lending Manager Checks ===");

        // Check if lending manager has WETH to lend
        IERC20 weth = IERC20(WETH);
        uint256 lendingManagerBalance = weth.balanceOf(LENDING_MANAGER);
        console.log("Lending Manager WETH Balance:", lendingManagerBalance / 1e18, "WETH");

        if (borrowAmount > lendingManagerBalance) {
            console.log("ERROR: Lending Manager doesn't have enough WETH!");
            console.log("Requested:", borrowAmount / 1e18, "WETH");
            console.log("Available:", lendingManagerBalance / 1e18, "WETH");
            revert("Insufficient WETH in Lending Manager");
        } else {
            console.log("CHECK PASSED: Lending Manager has sufficient WETH");
        }
        console.log("");

        // EXECUTE BORROW
        console.log("=================================================================");
        console.log("EXECUTING BORROW");
        console.log("=================================================================");
        console.log("");

        uint256 gasBefore = gasleft();

        vm.startBroadcast();

        try lendingManager.borrow(WETH, borrowAmount) {
            console.log("SUCCESS: Borrow executed successfully!");

            uint256 gasUsed = gasBefore - gasleft();
            console.log("Gas used:", gasUsed);

            // POST-CHECK: Verify state changes
            console.log("");
            console.log("=== POST-CHECK: Verify State ===");

            uint256 newBorrow = lendingManager.getUserDebt(borrower, WETH);
            uint256 newHealthFactor = lendingManager.getHealthFactor(borrower);
            uint256 newTotalBorrowed = lendingManager.totalBorrowed(WETH);

            console.log("New WETH Borrowed:", newBorrow / 1e18, "WETH");
            console.log("New Health Factor:", newHealthFactor / 1e18);
            console.log("New Pool Total Borrowed:", newTotalBorrowed / 1e18, "WETH");
            console.log("New Pool Utilization:", (newTotalBorrowed * 100) / totalLiquidity, "%");

        } catch Error(string memory reason) {
            console.log("FAILED: Borrow reverted with reason:");
            console.log(reason);
            revert(reason);

        } catch (bytes memory lowLevelData) {
            console.log("FAILED: Borrow reverted with low-level error:");
            console.logBytes(lowLevelData);
            revert("Low-level revert");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=================================================================");
        console.log("DEBUG COMPLETE");
        console.log("=================================================================");
    }
}
