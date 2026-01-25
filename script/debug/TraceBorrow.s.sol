// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRouter {
    function borrow(address token, uint256 amount) external;
}

interface ILendingManager {
    function getUserSupply(address user, address token) external view returns (uint256);
    function getUserDebt(address user, address token) external view returns (uint256);
    function getHealthFactor(address user) external view returns (uint256);
    function getProjectedHealthFactor(address user, address token, uint256 additionalAmount) external view returns (uint256);
    function totalLiquidity(address token) external view returns (uint256);
    function totalBorrowed(address token) external view returns (uint256);
    function getAvailableLiquidity(address token) external view returns (uint256);
    function assetConfigs(address token) external view returns (uint256, uint256, uint256, uint256, bool);
    function balanceManager() external view returns (address);
    function oracle() external view returns (address);
}

interface IBalanceManager {
    function getBalance(address user, address token) external view returns (uint256);
}

interface IOracle {
    function getSpotPrice(address token) external view returns (uint256);
    function isPriceStale(address token) external view returns (bool);
}

contract TraceBorrow is Script {
    function run() external {
        uint256 chainId = block.chainid;
        string memory deploymentPath = string(abi.encodePacked("deployments/", vm.toString(chainId), ".json"));

        console.log("=== COMPREHENSIVE BORROW TRACE ===");
        console.log("Chain ID:", chainId);
        console.log("Loading deployment from:", deploymentPath);
        console.log("");

        string memory json = vm.readFile(deploymentPath);
        address USDC = vm.parseJsonAddress(json, ".USDC");
        address WETH = vm.parseJsonAddress(json, ".WETH");
        address sxUSDC = vm.parseJsonAddress(json, ".sxUSDC");
        address sxWETH = vm.parseJsonAddress(json, ".sxWETH");
        address ROUTER = vm.parseJsonAddress(json, ".ScaleXRouter");
        address LENDING_MANAGER = vm.parseJsonAddress(json, ".LendingManager");
        address BALANCE_MANAGER = vm.parseJsonAddress(json, ".BalanceManager");
        address ORACLE = vm.parseJsonAddress(json, ".Oracle");
        address USER = 0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a;

        console.log("Addresses:");
        console.log("  User:", USER);
        console.log("  ScaleXRouter:", ROUTER);
        console.log("  LendingManager:", LENDING_MANAGER);
        console.log("  BalanceManager:", BALANCE_MANAGER);
        console.log("  Oracle:", ORACLE);
        console.log("  USDC:", USDC);
        console.log("  WETH:", WETH);
        console.log("  sxUSDC:", sxUSDC);
        console.log("  sxWETH:", sxWETH);
        console.log("");

        ILendingManager lm = ILendingManager(LENDING_MANAGER);
        IBalanceManager bm = IBalanceManager(BALANCE_MANAGER);
        IOracle oracle = IOracle(ORACLE);

        // Check LendingManager configuration
        console.log("1. LendingManager Configuration:");
        address lmBalanceManager = lm.balanceManager();
        address lmOracle = lm.oracle();
        console.log("  balanceManager:", lmBalanceManager);
        console.log("  oracle:", lmOracle);
        console.log("  Config valid:", (lmBalanceManager != address(0) && lmOracle != address(0)));
        console.log("");

        // Check USDC asset config
        console.log("2. USDC Asset Configuration:");
        (uint256 collateralFactor, uint256 liquidationThreshold, uint256 liquidationBonus, uint256 reserveFactor, bool enabled) = lm.assetConfigs(USDC);
        console.log("  Enabled:", enabled);
        console.log("  Collateral Factor:", collateralFactor);
        console.log("  Liquidation Threshold:", liquidationThreshold);
        console.log("");

        // Check WETH asset config
        console.log("3. WETH Asset Configuration:");
        (collateralFactor, liquidationThreshold, liquidationBonus, reserveFactor, enabled) = lm.assetConfigs(WETH);
        console.log("  Enabled:", enabled);
        console.log("  Collateral Factor:", collateralFactor);
        console.log("  Liquidation Threshold:", liquidationThreshold);
        console.log("");

        // Check USDC liquidity
        console.log("4. USDC Liquidity Status:");
        uint256 totalLiquidity = lm.totalLiquidity(USDC);
        uint256 totalBorrowed = lm.totalBorrowed(USDC);
        uint256 available = lm.getAvailableLiquidity(USDC);
        console.log("  Total Liquidity:", totalLiquidity);
        console.log("  Total Borrowed:", totalBorrowed);
        console.log("  Available:", available);
        console.log("  Sufficient for 1000 USDC:", available >= 1000000000);
        console.log("");

        // Check user's supplies
        console.log("5. User Supply Positions:");
        uint256 userUSDCSupply = lm.getUserSupply(USER, USDC);
        uint256 userWETHSupply = lm.getUserSupply(USER, WETH);
        console.log("  USDC Supply:", userUSDCSupply);
        console.log("  WETH Supply:", userWETHSupply);
        console.log("");

        // Check user's debts
        console.log("6. User Debt Positions:");
        uint256 userUSDCDebt = lm.getUserDebt(USER, USDC);
        uint256 userWETHDebt = lm.getUserDebt(USER, WETH);
        console.log("  USDC Debt:", userUSDCDebt);
        console.log("  WETH Debt:", userWETHDebt);
        console.log("");

        // Check BalanceManager balances
        console.log("7. BalanceManager Balances:");
        uint256 sxUSDCBalance = bm.getBalance(USER, sxUSDC);
        uint256 sxWETHBalance = bm.getBalance(USER, sxWETH);
        console.log("  sxUSDC Balance:", sxUSDCBalance);
        console.log("  sxWETH Balance:", sxWETHBalance);
        console.log("");

        // Check Oracle prices
        console.log("8. Oracle Prices:");
        uint256 sxUSDCPrice = oracle.getSpotPrice(sxUSDC);
        uint256 sxWETHPrice = oracle.getSpotPrice(sxWETH);
        bool sxUSDCStale = oracle.isPriceStale(sxUSDC);
        bool sxWETHStale = oracle.isPriceStale(sxWETH);
        console.log("  sxUSDC Price:", sxUSDCPrice);
        console.log("  sxUSDC Stale:", sxUSDCStale);
        console.log("  sxWETH Price:", sxWETHPrice);
        console.log("  sxWETH Stale:", sxWETHStale);
        console.log("");

        // Check health factors
        console.log("9. Health Factors:");
        uint256 currentHF = lm.getHealthFactor(USER);
        console.log("  Current Health Factor:", currentHF);

        uint256 projectedHF = lm.getProjectedHealthFactor(USER, USDC, 1000000000);
        console.log("  Projected HF (after borrowing 1000 USDC):", projectedHF);
        console.log("  Would be healthy (>= 1e18):", projectedHF >= 1e18);
        console.log("");

        // Get user's private key from env
        uint256 userPrivateKey = vm.envUint("PRIVATE_KEY_2");

        console.log("10. ATTEMPTING BORROW...");
        console.log("  Amount: 1000 USDC (1000000000 wei)");
        console.log("");

        vm.startBroadcast(userPrivateKey);

        // Attempt to borrow 1000 USDC
        IRouter(ROUTER).borrow(USDC, 1000000000);

        vm.stopBroadcast();

        console.log("");
        console.log("[SUCCESS] Borrow completed!");

        // Check final state
        console.log("");
        console.log("11. Post-Borrow State:");
        uint256 finalUSDCDebt = lm.getUserDebt(USER, USDC);
        uint256 finalHF = lm.getHealthFactor(USER);
        console.log("  Final USDC Debt:", finalUSDCDebt);
        console.log("  Final Health Factor:", finalHF);
    }
}
