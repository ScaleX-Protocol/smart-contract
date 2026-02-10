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

contract BorrowWETH is Script {
    address constant LENDING_MANAGER = 0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c;
    address constant WETH = 0x8b732595a59c9a18acA0Aca3221A656Eb38158fC;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 borrowAmount = vm.envOr("BORROW_AMOUNT", uint256(20000 ether));

        console.log("=== BORROW WETH ===");
        console.log("Account:", deployer);
        console.log("Borrow Amount:", borrowAmount / 1e18, "WETH");
        console.log("");

        ILendingManager lendingManager = ILendingManager(LENDING_MANAGER);

        // Pre-state
        uint256 preDebt = lendingManager.getUserDebt(deployer, WETH);
        uint256 preHF = lendingManager.getHealthFactor(deployer);
        uint256 preBorrowed = lendingManager.totalBorrowed(WETH);
        uint256 liquidity = lendingManager.totalLiquidity(WETH);

        console.log("Pre-state:");
        console.log("  Debt:", preDebt / 1e18, "WETH");
        console.log("  Health Factor:", preHF / 1e18);
        console.log("  Pool Borrowed:", preBorrowed / 1e18, "WETH");
        console.log("  Pool Utilization (bps):", (preBorrowed * 10000) / liquidity);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);
        lendingManager.borrow(WETH, borrowAmount);
        vm.stopBroadcast();

        // Post-state
        uint256 postDebt = lendingManager.getUserDebt(deployer, WETH);
        uint256 postHF = lendingManager.getHealthFactor(deployer);
        uint256 postBorrowed = lendingManager.totalBorrowed(WETH);

        console.log("Post-state:");
        console.log("  Debt:", postDebt / 1e18, "WETH");
        console.log("  Health Factor:", postHF / 1e18);
        console.log("  Pool Borrowed:", postBorrowed / 1e18, "WETH");
        console.log("  Pool Utilization (bps):", (postBorrowed * 10000) / liquidity);
        console.log("");
        console.log("SUCCESS!");
    }
}
