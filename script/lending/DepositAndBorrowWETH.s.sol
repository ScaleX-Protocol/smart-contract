// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IBalanceManager {
    function depositLocal(address token, uint256 amount, address onBehalfOf) external;
}

interface ILendingManager {
    function borrow(address token, uint256 amount) external;
    function getHealthFactor(address user) external view returns (uint256);
    function getUserDebt(address user, address token) external view returns (uint256);
    function totalLiquidity(address token) external view returns (uint256);
    function totalBorrowed(address token) external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract DepositAndBorrowWETH is Script {
    // Contract addresses (Base Sepolia)
    address constant BALANCE_MANAGER = 0xCe3C3b216dC2A3046bE3758Fa42729bca54b2b89;
    address constant LENDING_MANAGER = 0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c;
    address constant WETH = 0x8b732595a59c9a18acA0Aca3221A656Eb38158fC;

    function run() external {
        // Get parameters from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get amounts from environment (with defaults)
        uint256 depositAmount = vm.envOr("DEPOSIT_AMOUNT", uint256(200000 ether)); // Default: 200k WETH
        uint256 borrowAmount = vm.envOr("BORROW_AMOUNT", uint256(87000 ether));    // Default: 87k WETH

        console.log("=================================================================");
        console.log("DEPOSIT WETH AS COLLATERAL & BORROW WETH");
        console.log("=================================================================");
        console.log("");
        console.log("Configuration:");
        console.log("  Account:", deployer);
        console.log("  Deposit Amount:", depositAmount / 1e18, "WETH");
        console.log("  Borrow Amount:", borrowAmount / 1e18, "WETH");
        console.log("");

        // Pre-checks
        console.log("=== PRE-STATE ===");

        ILendingManager lendingManager = ILendingManager(LENDING_MANAGER);
        IERC20 weth = IERC20(WETH);

        uint256 walletBalance = weth.balanceOf(deployer);
        uint256 currentDebt = lendingManager.getUserDebt(deployer, WETH);
        uint256 currentHF = currentDebt > 0 ? lendingManager.getHealthFactor(deployer) : type(uint256).max;

        uint256 poolLiquidity = lendingManager.totalLiquidity(WETH);
        uint256 poolBorrowed = lendingManager.totalBorrowed(WETH);
        uint256 poolUtilization = poolLiquidity > 0 ? (poolBorrowed * 10000) / poolLiquidity : 0;

        console.log("Account State:");
        console.log("  WETH Balance:", walletBalance / 1e18, "WETH");
        console.log("  Current Debt:", currentDebt / 1e18, "WETH");
        if (currentHF == type(uint256).max) {
            console.log("  Health Factor: INF (no debt)");
        } else {
            console.log("  Health Factor:", currentHF / 1e18);
        }
        console.log("");
        console.log("Pool State:");
        console.log("  Total Liquidity:", poolLiquidity / 1e18, "WETH");
        console.log("  Total Borrowed:", poolBorrowed / 1e18, "WETH");
        console.log("  Utilization (bps):", poolUtilization);
        console.log("");

        // Verify we have enough WETH
        require(walletBalance >= depositAmount, "Insufficient WETH balance");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Approve WETH to BalanceManager
        console.log("=== STEP 1: Approve WETH ===");
        bool success = weth.approve(BALANCE_MANAGER, depositAmount);
        require(success, "Approval failed");
        console.log("Approved", depositAmount / 1e18, "WETH to BalanceManager");
        console.log("");

        // Step 2: Deposit WETH to BalanceManager (becomes collateral)
        console.log("=== STEP 2: Deposit WETH to BalanceManager ===");
        IBalanceManager(BALANCE_MANAGER).depositLocal(WETH, depositAmount, deployer);
        console.log("Deposited", depositAmount / 1e18, "WETH");
        console.log("(This automatically becomes collateral in LendingManager)");
        console.log("");

        // Step 3: Borrow WETH from LendingManager
        console.log("=== STEP 3: Borrow WETH from LendingManager ===");
        lendingManager.borrow(WETH, borrowAmount);
        console.log("Borrowed", borrowAmount / 1e18, "WETH");
        console.log("");

        vm.stopBroadcast();

        // Post-checks
        console.log("=== POST-STATE ===");

        uint256 newWalletBalance = weth.balanceOf(deployer);
        uint256 newDebt = lendingManager.getUserDebt(deployer, WETH);
        uint256 newHF = lendingManager.getHealthFactor(deployer);

        uint256 newPoolBorrowed = lendingManager.totalBorrowed(WETH);
        uint256 newPoolUtilization = poolLiquidity > 0 ? (newPoolBorrowed * 10000) / poolLiquidity : 0;

        console.log("Account State:");
        console.log("  WETH Balance:", newWalletBalance / 1e18, "WETH");
        console.log("  Total Debt:", newDebt / 1e18, "WETH");
        console.log("  Health Factor:", newHF / 1e18);
        console.log("");
        console.log("Pool State:");
        console.log("  Total Borrowed:", newPoolBorrowed / 1e18, "WETH");
        console.log("  Utilization (bps):", newPoolUtilization);
        console.log("");

        // Summary
        console.log("=== SUMMARY ===");
        console.log("Deposited as collateral:", depositAmount / 1e18, "WETH");
        console.log("Borrowed:", borrowAmount / 1e18, "WETH");
        int256 netChange = int256(newWalletBalance) - int256(walletBalance);
        console.log("Net WETH change:", uint256(netChange < 0 ? -netChange : netChange) / 1e18, netChange < 0 ? "(out)" : "WETH");
        console.log("Debt increased by:", (newDebt - currentDebt) / 1e18, "WETH");
        console.log("Health Factor:", newHF / 1e18);
        console.log("Pool utilization before (bps):", poolUtilization);
        console.log("Pool utilization after (bps):", newPoolUtilization);
        console.log("");
        console.log("SUCCESS: WETH deposited and borrowed!");
    }
}
