// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface ILendingManager {
    function supply(address token, uint256 amount) external;
    function borrow(address token, uint256 amount) external;
    function getHealthFactor(address user) external view returns (uint256);
    function getUserDebt(address user, address token) external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract SupplyCollateralAndBorrowWETH is Script {
    // Base Sepolia addresses
    address constant LENDING_MANAGER = 0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c;
    address constant WETH = 0x8b732595a59c9a18acA0Aca3221A656Eb38158fC;
    address constant IDRX = 0x80FD9a0F8BCA5255692016D67E0733bf5262C142; // Quote token
    address constant WBTC = 0x54911080AB22017e1Ca55F10Ff06AE707428fb0D;

    function run() external {
        address user = vm.envAddress("USER_ADDRESS");
        uint256 wethBorrowAmount = vm.envOr("WETH_BORROW_AMOUNT", uint256(87000 ether));

        console.log("=================================================================");
        console.log("SUPPLY COLLATERAL AND BORROW WETH");
        console.log("=================================================================");
        console.log("");
        console.log("User:", user);
        console.log("Target WETH Borrow:", wethBorrowAmount / 1e18, "WETH");
        console.log("");

        ILendingManager lendingManager = ILendingManager(LENDING_MANAGER);

        // Check initial state
        console.log("=== INITIAL STATE ===");
        uint256 initialHF = lendingManager.getHealthFactor(user);
        uint256 currentWETHDebt = lendingManager.getUserDebt(user, WETH);

        console.log("Current Health Factor:", initialHF / 1e18);
        console.log("Current WETH Debt:", currentWETHDebt / 1e18, "WETH");
        console.log("");

        // Check available tokens
        console.log("=== AVAILABLE TOKENS TO SUPPLY ===");

        IERC20 weth = IERC20(WETH);
        IERC20 idrx = IERC20(IDRX);
        IERC20 wbtc = IERC20(WBTC);

        uint256 wethBalance = weth.balanceOf(user);
        uint256 idrxBalance = idrx.balanceOf(user);
        uint256 wbtcBalance = wbtc.balanceOf(user);

        console.log("WETH Balance:", wethBalance / 1e18, "WETH");
        console.log("IDRX Balance:", idrxBalance / 1e2, "IDRX"); // 2 decimals
        console.log("WBTC Balance:", wbtcBalance / 1e8, "WBTC"); // 8 decimals
        console.log("");

        // Determine what to supply as collateral
        address collateralToken;
        uint256 collateralAmount;
        string memory collateralSymbol;

        if (idrxBalance > 1000000 * 1e2) { // If we have > 1M IDRX
            collateralToken = IDRX;
            collateralAmount = 500000 * 1e2; // Supply 500K IDRX
            collateralSymbol = "IDRX";
            console.log("PLAN: Supply 500,000 IDRX as collateral");
        } else if (wethBalance > 100 * 1e18) { // If we have > 100 WETH
            collateralToken = WETH;
            collateralAmount = 50 * 1e18; // Supply 50 WETH
            collateralSymbol = "WETH";
            console.log("PLAN: Supply 50 WETH as collateral");
        } else if (wbtcBalance > 1 * 1e8) { // If we have > 1 WBTC
            collateralToken = WBTC;
            collateralAmount = 1 * 1e8; // Supply 1 WBTC
            collateralSymbol = "WBTC";
            console.log("PLAN: Supply 1 WBTC as collateral");
        } else {
            console.log("ERROR: No suitable collateral available!");
            console.log("Need at least:");
            console.log("  - 1M IDRX, OR");
            console.log("  - 100 WETH, OR");
            console.log("  - 1 WBTC");
            revert("Insufficient collateral available");
        }
        console.log("");

        vm.startBroadcast();

        // STEP 1: Approve collateral token
        console.log("=== STEP 1: APPROVE COLLATERAL ===");
        IERC20 collateral = IERC20(collateralToken);

        uint256 currentAllowance = collateral.allowance(user, LENDING_MANAGER);
        if (currentAllowance < collateralAmount) {
            console.log("Approving", collateralSymbol, "...");
            collateral.approve(LENDING_MANAGER, type(uint256).max);
            console.log("Approved!");
        } else {
            console.log("Already approved");
        }
        console.log("");

        // STEP 2: Supply collateral
        console.log("=== STEP 2: SUPPLY COLLATERAL ===");
        console.log("Supplying", collateralAmount, collateralSymbol, "...");

        try lendingManager.supply(collateralToken, collateralAmount) {
            console.log("SUCCESS: Collateral supplied!");

            uint256 newHF = lendingManager.getHealthFactor(user);
            console.log("New Health Factor:", newHF / 1e18);
            console.log("");

        } catch Error(string memory reason) {
            console.log("FAILED: Supply reverted");
            console.log("Reason:", reason);
            revert(reason);
        }

        // STEP 3: Borrow WETH
        console.log("=== STEP 3: BORROW WETH ===");
        console.log("Borrowing", wethBorrowAmount / 1e18, "WETH...");

        try lendingManager.borrow(WETH, wethBorrowAmount) {
            console.log("SUCCESS: WETH borrowed!");

            uint256 finalHF = lendingManager.getHealthFactor(user);
            uint256 finalWETHDebt = lendingManager.getUserDebt(user, WETH);

            console.log("");
            console.log("=== FINAL STATE ===");
            console.log("Final Health Factor:", finalHF / 1e18);
            console.log("Final WETH Debt:", finalWETHDebt / 1e18, "WETH");
            console.log("Borrowed Amount:", (finalWETHDebt - currentWETHDebt) / 1e18, "WETH");

        } catch Error(string memory reason) {
            console.log("FAILED: Borrow reverted");
            console.log("Reason:", reason);

            // Still show final state
            uint256 finalHF = lendingManager.getHealthFactor(user);
            console.log("Health Factor:", finalHF / 1e18);

            revert(reason);
        } catch (bytes memory lowLevelData) {
            console.log("FAILED: Borrow reverted with low-level error");
            console.logBytes(lowLevelData);
            revert("Borrow failed");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=================================================================");
        console.log("COMPLETE");
        console.log("=================================================================");
    }
}
