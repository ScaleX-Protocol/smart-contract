// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/yield/LendingManager.sol";
import "../../src/mocks/MockToken.sol";
import "../../src/core/libraries/Pool.sol";

/**
 * @title ExecuteBorrows
 * @notice Execute borrow operations across all collateral pools using PRIVATE_KEY_2
 * @dev This script:
 *      1. Deposits collateral tokens (WBTC, GOLD, etc.) to BalanceManager
 *      2. The sxToken balance becomes collateral for borrowing
 *      3. Borrows USDC against that collateral
 *      4. Uses PRIVATE_KEY_2 (different from liquidity supplier)
 */
contract ExecuteBorrows is Script, DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "BalanceManager";
    string constant LENDING_MANAGER_ADDRESS = "LendingManager";

    // Core contracts
    BalanceManager balanceManager;
    LendingManager lendingManager;

    // Borrower wallet (PRIVATE_KEY_2)
    address borrowerWallet;

    // Borrow configuration struct
    struct BorrowConfig {
        string symbol;
        address collateralToken;     // Underlying token (e.g., WBTC)
        address sxToken;             // Synthetic token (e.g., sxWBTC)
        uint256 collateralAmount;    // Amount of collateral to deposit
        uint256 borrowAmount;        // Amount of USDC to borrow
    }

    function setUp() public {
        loadDeployments();
        loadContracts();
    }

    function loadContracts() private {
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        lendingManager = LendingManager(payable(deployed[LENDING_MANAGER_ADDRESS].addr));
    }

    function run() external {
        uint256 borrowerKey = getDeployerKey2();
        borrowerWallet = vm.addr(borrowerKey);

        console.log("===============================================");
        console.log("Executing Borrow Operations (PRIVATE_KEY_2)");
        console.log("===============================================");
        console.log("Borrower Wallet:", borrowerWallet);
        console.log("");

        address usdcAddr = deployed["USDC"].addr;

        // Define borrow configs for all collateral pools
        BorrowConfig[] memory configs = new BorrowConfig[](6);

        // WBTC: Supply 0.01 BTC (~$950) to borrow $475 USDC (50% LTV)
        configs[0] = BorrowConfig({
            symbol: "WBTC",
            collateralToken: deployed["WBTC"].addr,
            sxToken: deployed["sxWBTC"].addr,
            collateralAmount: 0.01 ether,  // 0.01 BTC (18 decimals)
            borrowAmount: 475e6            // $475 USDC
        });

        // GOLD: Supply 0.2 oz (~$890) to borrow $445 USDC (50% LTV)
        configs[1] = BorrowConfig({
            symbol: "GOLD",
            collateralToken: deployed["GOLD"].addr,
            sxToken: deployed["sxGOLD"].addr,
            collateralAmount: 0.2 ether,    // 0.2 GOLD (18 decimals)
            borrowAmount: 445e6             // $445 USDC
        });

        // SILVER: Supply 10 oz (~$780) to borrow $390 USDC (50% LTV)
        configs[2] = BorrowConfig({
            symbol: "SILVER",
            collateralToken: deployed["SILVER"].addr,
            sxToken: deployed["sxSILVER"].addr,
            collateralAmount: 10 ether,      // 10 SILVER (18 decimals)
            borrowAmount: 390e6              // $390 USDC
        });

        // GOOGLE: Supply 2 shares (~$630) to borrow $315 USDC (50% LTV)
        configs[3] = BorrowConfig({
            symbol: "GOOGLE",
            collateralToken: deployed["GOOGLE"].addr,
            sxToken: deployed["sxGOOGLE"].addr,
            collateralAmount: 2 ether,       // 2 GOOGLE (18 decimals)
            borrowAmount: 315e6              // $315 USDC
        });

        // NVIDIA: Supply 3 shares (~$570) to borrow $285 USDC (50% LTV)
        configs[4] = BorrowConfig({
            symbol: "NVIDIA",
            collateralToken: deployed["NVIDIA"].addr,
            sxToken: deployed["sxNVIDIA"].addr,
            collateralAmount: 3 ether,       // 3 NVIDIA (18 decimals)
            borrowAmount: 285e6              // $285 USDC
        });

        // APPLE: Supply 2 shares (~$530) to borrow $265 USDC (50% LTV)
        configs[5] = BorrowConfig({
            symbol: "APPLE",
            collateralToken: deployed["APPLE"].addr,
            sxToken: deployed["sxAPPLE"].addr,
            collateralAmount: 2 ether,       // 2 APPLE (18 decimals)
            borrowAmount: 265e6              // $265 USDC
        });

        vm.startBroadcast(borrowerKey);

        // Execute borrows for each pool
        uint256 totalBorrowsExecuted = 0;
        uint256 totalUsdcBorrowed = 0;

        for (uint256 i = 0; i < configs.length; i++) {
            (bool success, uint256 usdcBorrowed) =
                executeBorrow(configs[i], usdcAddr);

            if (success) {
                totalBorrowsExecuted++;
                totalUsdcBorrowed += usdcBorrowed;
            }
        }

        vm.stopBroadcast();

        console.log("\n===============================================");
        console.log("Borrow Operations Complete");
        console.log("===============================================");
        console.log("Total Borrows Executed:", totalBorrowsExecuted);
        console.log("Total USDC Borrowed: $", totalUsdcBorrowed / 1e6);
    }

    function executeBorrow(
        BorrowConfig memory config,
        address usdcAddr
    ) internal returns (
        bool success,
        uint256 usdcBorrowed
    ) {
        console.log("===============================================");
        console.log(config.symbol, " Borrow Operation");
        console.log("===============================================");

        // Step 1: Check health factor before
        try lendingManager.getHealthFactor(borrowerWallet) returns (uint256 hfBefore) {
            console.log("  Health Factor before:", hfBefore / 1e18);
        } catch {
            console.log("  Health Factor: N/A (no position yet)");
        }

        // Step 2: Mint collateral tokens
        MockToken(config.collateralToken).mint(borrowerWallet, config.collateralAmount);
        console.log("  Minted", config.collateralAmount / 1e18, config.symbol);

        // Step 3: Approve and deposit collateral to BalanceManager
        IERC20(config.collateralToken).approve(address(balanceManager), config.collateralAmount);
        balanceManager.depositLocal(config.collateralToken, config.collateralAmount, borrowerWallet);
        console.log("  Deposited to BalanceManager");

        // Step 4: Check sxToken balance (this becomes collateral)
        Currency sxToken = Currency.wrap(config.sxToken);
        uint256 sxTokenBalance = balanceManager.getBalance(borrowerWallet, sxToken);
        console.log("  sxToken balance (collateral):", sxTokenBalance / 1e18);

        // Step 5: Check health factor after deposit
        try lendingManager.getHealthFactor(borrowerWallet) returns (uint256 hfAfter) {
            console.log("  Health Factor after deposit:", hfAfter / 1e18);
        } catch {
            console.log("  Health Factor: Error reading");
        }

        // Step 6: Borrow USDC
        try balanceManager.borrowForUser(
            borrowerWallet,
            usdcAddr,
            config.borrowAmount
        ) {
            console.log("  [OK] Borrowed $", config.borrowAmount / 1e6, " USDC");
            usdcBorrowed = config.borrowAmount;
            success = true;
        } catch Error(string memory reason) {
            console.log("  [FAIL] Borrow failed:", reason);
            // Return true for collateral deposit even if borrow failed
            success = true;
            usdcBorrowed = 0;
        } catch {
            console.log("  [FAIL] Borrow failed (unknown error)");
            success = true;
            usdcBorrowed = 0;
        }

        // Step 7: Check final health factor
        try lendingManager.getHealthFactor(borrowerWallet) returns (uint256 hfFinal) {
            console.log("  Final Health Factor:", hfFinal / 1e18);
            if (hfFinal < 1e18 && hfFinal > 0) {
                console.log("  [WARNING] Health Factor below 1.0 - liquidation risk!");
            } else if (hfFinal >= 1e18) {
                console.log("  [SUCCESS] Position is healthy");
            }
        } catch {
            console.log("  Final Health Factor: Error reading");
        }

        // Step 8: Check borrowed amount
        try lendingManager.getUserDebt(borrowerWallet, usdcAddr) returns (uint256 debt) {
            console.log("  Total USDC Debt: $", debt / 1e6);
        } catch {
            console.log("  Total USDC Debt: Error reading");
        }

        console.log("");
    }
}
