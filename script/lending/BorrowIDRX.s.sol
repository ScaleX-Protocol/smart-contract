// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface ILendingManager {
    function borrow(address token, uint256 amount) external;
    function getHealthFactor(address user) external view returns (uint256);
    function getUserDebt(address user, address token) external view returns (uint256);
    function totalLiquidity(address token) external view returns (uint256);
    function totalBorrowed(address token) external view returns (uint256);
}

contract BorrowIDRX is Script {
    address constant LENDING_MANAGER = 0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c;
    address constant IDRX = 0x80FD9a0F8BCA5255692016D67E0733bf5262C142;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 borrowAmount = vm.envOr("BORROW_AMOUNT", uint256(1000 * 1e2)); // Default 1,000 IDRX

        console.log("=== BORROW IDRX ===");
        console.log("Account:", deployer);
        console.log("Borrow Amount:", borrowAmount / 1e2, "IDRX");
        console.log("");

        ILendingManager lendingManager = ILendingManager(LENDING_MANAGER);

        // Pre-state
        uint256 preDebt = lendingManager.getUserDebt(deployer, IDRX);
        uint256 preHF = lendingManager.getHealthFactor(deployer);
        uint256 preBorrowed = lendingManager.totalBorrowed(IDRX);
        uint256 liquidity = lendingManager.totalLiquidity(IDRX);

        console.log("Pre-state:");
        console.log("  Debt:", preDebt / 1e2, "IDRX");
        console.log("  Health Factor:", preHF / 1e18);
        console.log("  Pool Borrowed:", preBorrowed / 1e2, "IDRX");
        console.log("  Pool Liquidity:", liquidity / 1e2, "IDRX");
        if (liquidity > 0) {
            console.log("  Pool Utilization (bps):", (preBorrowed * 10000) / liquidity);
        }
        console.log("");

        vm.startBroadcast(deployerPrivateKey);
        lendingManager.borrow(IDRX, borrowAmount);
        vm.stopBroadcast();

        // Post-state
        uint256 postDebt = lendingManager.getUserDebt(deployer, IDRX);
        uint256 postHF = lendingManager.getHealthFactor(deployer);
        uint256 postBorrowed = lendingManager.totalBorrowed(IDRX);

        console.log("Post-state:");
        console.log("  Debt:", postDebt / 1e2, "IDRX");
        console.log("  Health Factor:", postHF / 1e18);
        console.log("  Pool Borrowed:", postBorrowed / 1e2, "IDRX");
        if (liquidity > 0) {
            console.log("  Pool Utilization (bps):", (postBorrowed * 10000) / liquidity);
        }
        console.log("");
        console.log("SUCCESS!");
    }
}
