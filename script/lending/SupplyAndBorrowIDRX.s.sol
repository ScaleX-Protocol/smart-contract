// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface ILendingManager {
    function supply(address token, uint256 amount) external;
    function borrow(address token, uint256 amount) external;
    function getHealthFactor(address user) external view returns (uint256);
    function getUserDebt(address user, address token) external view returns (uint256);
    function getUserSupply(address user, address token) external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IBalanceManager {
    function getBalance(address user, address token) external view returns (uint256);
    function withdraw(address token, uint256 amount) external;
}

/**
 * @title SupplyAndBorrowIDRX
 * @notice Supply IDRX as collateral and borrow IDRX to create utilization
 * @dev This creates recursive lending to generate supply APY for IDRX
 *
 * Usage:
 *   USER_ADDRESS=0x... IDRX_SUPPLY_AMOUNT=10000 IDRX_BORROW_AMOUNT=7500 \
 *   forge script script/lending/SupplyAndBorrowIDRX.s.sol:SupplyAndBorrowIDRX \
 *   --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY
 */
contract SupplyAndBorrowIDRX is Script {
    // Base Sepolia addresses
    address constant LENDING_MANAGER = 0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c;
    address constant BALANCE_MANAGER = 0x5Da30f60E7a1b263Fe47269a8266043ee1CFB70d;
    address constant IDRX = 0x80FD9a0F8BCA5255692016D67E0733bf5262C142;

    function run() external {
        address user = vm.envAddress("USER_ADDRESS");
        uint256 supplyAmount = vm.envOr("IDRX_SUPPLY_AMOUNT", uint256(10000)) * 1e2; // 2 decimals
        uint256 borrowAmount = vm.envOr("IDRX_BORROW_AMOUNT", uint256(7500)) * 1e2;  // 2 decimals

        console.log("=================================================================");
        console.log("SUPPLY AND BORROW IDRX (RECURSIVE LENDING)");
        console.log("=================================================================");
        console.log("");
        console.log("User:", user);
        console.log("Supply Amount:", supplyAmount / 1e2, "IDRX");
        console.log("Borrow Amount:", borrowAmount / 1e2, "IDRX");
        console.log("Net Contribution:", (supplyAmount - borrowAmount) / 1e2, "IDRX");
        console.log("");

        ILendingManager lendingManager = ILendingManager(LENDING_MANAGER);
        IBalanceManager balanceManager = IBalanceManager(BALANCE_MANAGER);
        IERC20 idrx = IERC20(IDRX);

        // Check initial state
        console.log("=== INITIAL STATE ===");
        uint256 walletBalance = idrx.balanceOf(user);
        uint256 initialSupply = lendingManager.getUserSupply(user, IDRX);
        uint256 initialDebt = lendingManager.getUserDebt(user, IDRX);
        uint256 initialHF = lendingManager.getHealthFactor(user);

        console.log("Wallet Balance:", walletBalance / 1e2, "IDRX");
        console.log("Current Supply:", initialSupply / 1e2, "IDRX");
        console.log("Current Debt:", initialDebt / 1e2, "IDRX");
        console.log("Health Factor:", initialHF / 1e18);
        console.log("");

        // Check if wallet has enough IDRX
        if (walletBalance < supplyAmount) {
            console.log("ERROR: Insufficient IDRX in wallet!");
            console.log("  Wallet Balance:", walletBalance / 1e2, "IDRX");
            console.log("  Need:", supplyAmount / 1e2, "IDRX");
            console.log("  Please withdraw from BalanceManager first");
            revert("Insufficient IDRX balance");
        }

        vm.startBroadcast();

        // STEP 1: Approve IDRX
        console.log("=== STEP 1: APPROVE IDRX ===");
        uint256 currentAllowance = idrx.allowance(user, LENDING_MANAGER);
        if (currentAllowance < supplyAmount) {
            console.log("Approving IDRX...");
            idrx.approve(LENDING_MANAGER, type(uint256).max);
            console.log("Approved!");
        } else {
            console.log("Already approved");
        }
        console.log("");

        // STEP 2: Supply IDRX
        console.log("=== STEP 2: SUPPLY IDRX ===");
        console.log("Supplying", supplyAmount / 1e2, "IDRX...");

        try lendingManager.supply(IDRX, supplyAmount) {
            console.log("SUCCESS: IDRX supplied!");

            uint256 newSupply = lendingManager.getUserSupply(user, IDRX);
            uint256 newHF = lendingManager.getHealthFactor(user);
            console.log("Total Supply:", newSupply / 1e2, "IDRX");
            console.log("Health Factor:", newHF / 1e18);
            console.log("");

        } catch Error(string memory reason) {
            console.log("FAILED: Supply reverted");
            console.log("Reason:", reason);
            revert(reason);
        }

        // STEP 3: Borrow IDRX
        console.log("=== STEP 3: BORROW IDRX ===");
        console.log("Borrowing", borrowAmount / 1e2, "IDRX...");

        try lendingManager.borrow(IDRX, borrowAmount) {
            console.log("SUCCESS: IDRX borrowed!");

            uint256 finalSupply = lendingManager.getUserSupply(user, IDRX);
            uint256 finalDebt = lendingManager.getUserDebt(user, IDRX);
            uint256 finalHF = lendingManager.getHealthFactor(user);

            console.log("");
            console.log("=== FINAL STATE ===");
            console.log("Total Supply:", finalSupply / 1e2, "IDRX");
            console.log("Total Debt:", finalDebt / 1e2, "IDRX");
            console.log("Net Contribution:", (finalSupply - finalDebt) / 1e2, "IDRX");
            console.log("Health Factor:", finalHF / 1e18);
            console.log("");
            console.log("This creates:");
            console.log("  - Pool receives:", (supplyAmount - borrowAmount) / 1e2, "IDRX net liquidity");
            console.log("  - Utilization increases by:", borrowAmount / 1e2, "IDRX borrowed");
            console.log("  - Supply APY will be generated from borrow interest");

        } catch Error(string memory reason) {
            console.log("FAILED: Borrow reverted");
            console.log("Reason:", reason);

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
        console.log("COMPLETE - IDRX RECURSIVE LENDING ESTABLISHED");
        console.log("=================================================================");
    }
}
