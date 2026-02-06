// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {LendingManager} from "../../src/yield/LendingManager.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {Oracle} from "../../src/core/Oracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title UpdateLendingWithActivitySmart
 * @dev Smart lending update that checks current positions before making changes
 *
 * Features:
 * - Checks current supply and borrow positions
 * - Calculates current utilization
 * - Only supplies/borrows what's needed to reach target utilization
 * - Shows before/after comparison
 *
 * Environment Variables: Same as UpdateLendingWithActivity.s.sol
 *
 * Usage:
 *   PRIVATE_KEY=0x... forge script script/lending/UpdateLendingWithActivitySmart.s.sol:UpdateLendingWithActivitySmart \
 *     --rpc-url http://127.0.0.1:8545 --broadcast
 */
contract UpdateLendingWithActivitySmart is Script, DeployHelpers {

    LendingManager public lendingManager;
    BalanceManager public balanceManager;
    Oracle public oracle;

    address public primaryAccount;
    address public secondaryAccount;

    // Quote currency configuration
    string public quoteCurrency;
    uint8 public quoteDecimals;
    uint256 public quoteDivisor;

    // Token configuration
    struct TokenConfig {
        string symbol;
        address tokenAddress;
        uint256 baseRate;
        uint256 optimalUtilization;
        uint256 rateSlope1;
        uint256 rateSlope2;
        uint256 targetSupply;
        uint256 targetBorrow;
    }

    struct CurrentState {
        uint256 userSupply;
        uint256 userBorrow;
        uint256 poolTotalSupply;
        uint256 poolTotalBorrow;
        uint256 currentUtilization;  // in basis points
        uint256 availableBalance;
    }

    string[] public selectedTokens;
    uint256 public targetUtilization; // Target utilization in basis points

    function run() external {
        loadDeployments();
        uint256 deployerPrivateKey = getDeployerKey();
        primaryAccount = vm.addr(deployerPrivateKey);

        try vm.envUint("PRIVATE_KEY_2") returns (uint256 key2) {
            secondaryAccount = vm.addr(key2);
        } catch {
            secondaryAccount = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        }

        console.log("=== SMART LENDING UPDATE WITH ACTIVITY ===");
        console.log("Primary Account:", primaryAccount);
        console.log("Secondary Account:", secondaryAccount);
        console.log("");

        _loadContracts();
        _parseSelectedTokens();

        console.log("=== Phase 0: Check Current Lending Positions ===");
        _checkCurrentPositions();

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n=== Phase 1: Update Interest Rate Parameters ===");
        _updateInterestRateParameters();

        console.log("\n=== Phase 2: Smart Supply (only if needed) ===");
        _smartSupplyTokens();

        console.log("\n=== Phase 3: Smart Borrow (to reach target utilization) ===");
        _smartBorrowTokens();

        vm.stopBroadcast();

        console.log("\n=== Phase 4: Verify APY Values ===");
        _verifyAPY();

        console.log("\n=== SMART LENDING UPDATE COMPLETE ===");
    }

    function _loadContracts() internal {
        console.log("=== Loading Contracts ===");

        quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("IDRX"));
        quoteDecimals = uint8(vm.envOr("QUOTE_DECIMALS", uint256(2)));
        quoteDivisor = 10**quoteDecimals;

        require(deployed["LendingManager"].isSet, "LendingManager not found");
        require(deployed["BalanceManager"].isSet, "BalanceManager not found");
        require(deployed["Oracle"].isSet, "Oracle not found");

        lendingManager = LendingManager(deployed["LendingManager"].addr);
        balanceManager = BalanceManager(deployed["BalanceManager"].addr);
        oracle = Oracle(deployed["Oracle"].addr);

        console.log("Quote Currency:", quoteCurrency);
        console.log("LendingManager:", address(lendingManager));
        console.log("BalanceManager:", address(balanceManager));
        console.log("");

        // Target utilization (default 30% = 3000 bps)
        uint256 borrowRatio = vm.envOr("BORROW_RATIO", uint256(30));
        targetUtilization = borrowRatio * 100; // Convert to basis points
        console.log("Target Utilization:", borrowRatio, "%");
        console.log("Target Utilization (bps):", targetUtilization);
        console.log("");
    }

    function _parseSelectedTokens() internal {
        string memory tokensEnv = vm.envOr("TOKENS", string("ALL"));
        string[9] memory allTokens = ["IDRX", "WETH", "WBTC", "GOLD", "SILVER", "GOOGL", "NVDA", "AAPL", "MNT"];

        for (uint i = 0; i < allTokens.length; i++) {
            if (deployed[allTokens[i]].isSet) {
                selectedTokens.push(allTokens[i]);
            }
        }

        console.log("Selected tokens:", selectedTokens.length);
        for (uint i = 0; i < selectedTokens.length; i++) {
            console.log("-", selectedTokens[i]);
        }
        console.log("");
    }

    function _checkCurrentPositions() internal view {
        console.log("Checking current lending positions for all tokens...");
        console.log("");

        for (uint i = 0; i < selectedTokens.length; i++) {
            string memory tokenSymbol = selectedTokens[i];
            address tokenAddress = deployed[tokenSymbol].addr;

            CurrentState memory state = _getCurrentState(tokenAddress);

            console.log(tokenSymbol, "Current State:");
            console.log("  Your Supply:", state.userSupply);
            console.log("  Your Borrow:", state.userBorrow);
            console.log("  Pool Total Supply:", state.poolTotalSupply);
            console.log("  Pool Total Borrow:", state.poolTotalBorrow);
            console.log("  Pool Utilization:", state.currentUtilization / 100, "%");
            console.log("  Available Balance:", state.availableBalance);

            if (state.currentUtilization >= targetUtilization) {
                console.log("  [INFO] Already at or above target utilization!");
            } else {
                uint256 needed = targetUtilization - state.currentUtilization;
                console.log("  [INFO] Need", needed / 100, "% more utilization to reach target");
            }
            console.log("");
        }
    }

    function _getCurrentState(address tokenAddress) internal view returns (CurrentState memory) {
        CurrentState memory state;

        try lendingManager.getUserSupply(primaryAccount, tokenAddress) returns (uint256 supply) {
            state.userSupply = supply;
        } catch {}

        try lendingManager.getUserDebt(primaryAccount, tokenAddress) returns (uint256 debt) {
            state.userBorrow = debt;
        } catch {}

        try lendingManager.totalLiquidity(tokenAddress) returns (uint256 totalSupply) {
            state.poolTotalSupply = totalSupply;
        } catch {}

        try lendingManager.totalBorrowed(tokenAddress) returns (uint256 totalBorrow) {
            state.poolTotalBorrow = totalBorrow;
        } catch {}

        // Calculate current utilization in basis points
        if (state.poolTotalSupply > 0) {
            state.currentUtilization = (state.poolTotalBorrow * 10000) / state.poolTotalSupply;
        }

        state.availableBalance = balanceManager.getBalance(primaryAccount, tokenAddress);

        return state;
    }

    function _updateInterestRateParameters() internal {
        for (uint i = 0; i < selectedTokens.length; i++) {
            string memory tokenSymbol = selectedTokens[i];
            address tokenAddress = deployed[tokenSymbol].addr;

            TokenConfig memory config = _getTokenConfig(tokenSymbol, tokenAddress);

            try lendingManager.setInterestRateParams(
                config.tokenAddress,
                config.baseRate,
                config.optimalUtilization,
                config.rateSlope1,
                config.rateSlope2
            ) {
                console.log("[OK]", tokenSymbol, "interest rates set");
            } catch Error(string memory reason) {
                console.log("[ERROR]", tokenSymbol, "failed:", reason);
            }
        }
    }

    function _smartSupplyTokens() internal {
        for (uint i = 0; i < selectedTokens.length; i++) {
            string memory tokenSymbol = selectedTokens[i];
            address tokenAddress = deployed[tokenSymbol].addr;

            CurrentState memory stateBefore = _getCurrentState(tokenAddress);
            TokenConfig memory config = _getTokenConfig(tokenSymbol, tokenAddress);

            // Calculate if we need to supply more
            uint256 neededSupply = 0;

            if (stateBefore.poolTotalSupply == 0 || stateBefore.currentUtilization > targetUtilization) {
                // Need to supply to bring utilization down or start fresh
                neededSupply = config.targetSupply;
            } else if (stateBefore.currentUtilization < targetUtilization) {
                // Current utilization is too low, might need more supply
                // For now, just add the configured amount
                neededSupply = config.targetSupply;
            }

            if (neededSupply == 0) {
                console.log("[SKIP]", tokenSymbol, "- no supply needed (utilization:", stateBefore.currentUtilization / 100, "%)");
                continue;
            }

            if (stateBefore.availableBalance < neededSupply) {
                console.log("[SKIP]", tokenSymbol, "- insufficient balance");
                console.log("     Need:", neededSupply, "Available:", stateBefore.availableBalance);
                continue;
            }

            // Supply tokens
            try lendingManager.supply(tokenAddress, neededSupply) {
                console.log("[OK]", tokenSymbol, "supplied:", neededSupply);

                CurrentState memory stateAfter = _getCurrentState(tokenAddress);
                console.log("     Supply:", stateBefore.userSupply, "->", stateAfter.userSupply);
                console.log("     Pool Supply:", stateBefore.poolTotalSupply, "->", stateAfter.poolTotalSupply);
            } catch Error(string memory reason) {
                console.log("[ERROR]", tokenSymbol, "supply failed:", reason);
            }
        }
    }

    function _smartBorrowTokens() internal {
        for (uint i = 0; i < selectedTokens.length; i++) {
            string memory tokenSymbol = selectedTokens[i];
            address tokenAddress = deployed[tokenSymbol].addr;

            CurrentState memory stateBefore = _getCurrentState(tokenAddress);

            // Check if we're already at or above target utilization
            if (stateBefore.currentUtilization >= targetUtilization) {
                console.log("[SKIP]", tokenSymbol, "- already at target utilization");
                console.log("     Current:", stateBefore.currentUtilization / 100, "% Target:", targetUtilization / 100, "%");
                continue;
            }

            // Calculate how much to borrow to reach target utilization
            // targetUtil = targetBorrow / poolSupply
            // targetBorrow = targetUtil * poolSupply / 10000
            uint256 targetBorrowAmount = (targetUtilization * stateBefore.poolTotalSupply) / 10000;
            uint256 neededBorrow = targetBorrowAmount > stateBefore.poolTotalBorrow
                ? targetBorrowAmount - stateBefore.poolTotalBorrow
                : 0;

            if (neededBorrow == 0) {
                console.log("[SKIP]", tokenSymbol, "- no additional borrowing needed");
                continue;
            }

            // Check borrowing power
            try lendingManager.getUserBorrowingPower(primaryAccount) returns (uint256 borrowingPower) {
                if (borrowingPower == 0) {
                    console.log("[SKIP]", tokenSymbol, "- no borrowing power (need collateral)");
                    continue;
                }

                console.log("     Borrowing Power:", borrowingPower);
                console.log("     Need to borrow:", neededBorrow, "to reach", targetUtilization / 100, "% utilization");

                // Try to borrow
                try lendingManager.borrow(tokenAddress, neededBorrow) {
                    console.log("[OK]", tokenSymbol, "borrowed:", neededBorrow);

                    CurrentState memory stateAfter = _getCurrentState(tokenAddress);
                    console.log("     Borrow:", stateBefore.userBorrow, "->", stateAfter.userBorrow);
                    console.log("     Pool Borrow:", stateBefore.poolTotalBorrow, "->", stateAfter.poolTotalBorrow);
                    console.log("     Utilization:", stateBefore.currentUtilization / 100, "% ->", stateAfter.currentUtilization / 100, "%");

                    if (stateAfter.currentUtilization >= targetUtilization) {
                        console.log("     [OK] Target utilization reached!");
                    }
                } catch Error(string memory reason) {
                    console.log("[ERROR]", tokenSymbol, "borrow failed:", reason);
                } catch {
                    console.log("[ERROR]", tokenSymbol, "borrow failed");
                }
            } catch {
                console.log("[SKIP]", tokenSymbol, "- cannot check borrowing power");
            }
        }
    }

    function _verifyAPY() internal view {
        console.log("Verifying APY calculations...");
        console.log("");

        for (uint i = 0; i < selectedTokens.length; i++) {
            string memory tokenSymbol = selectedTokens[i];
            address tokenAddress = deployed[tokenSymbol].addr;

            CurrentState memory state = _getCurrentState(tokenAddress);

            try lendingManager.calculateInterestRate(tokenAddress) returns (uint256 borrowAPY) {
                uint256 supplyAPY = (borrowAPY * state.currentUtilization) / 10000;

                console.log(tokenSymbol, ":");
                console.log("  Pool Supply:", state.poolTotalSupply);
                console.log("  Pool Borrow:", state.poolTotalBorrow);
                console.log("  Utilization:", state.currentUtilization / 100, "%");
                console.log("  Borrow APY:", borrowAPY / 100, "%");
                console.log("  Supply APY:", supplyAPY / 100, "%");

                if (supplyAPY > 0) {
                    console.log("  [OK] Supply APY is non-zero!");
                } else if (state.currentUtilization == 0) {
                    console.log("  [INFO] Supply APY is 0 (no borrowing activity)");
                } else {
                    console.log("  [WARN] Supply APY is 0 but utilization is", state.currentUtilization / 100, "%");
                }

                if (state.currentUtilization >= targetUtilization) {
                    console.log("  [OK] Target utilization reached!");
                } else {
                    console.log("  [INFO] Current utilization below target");
                }
                console.log("");
            } catch {
                console.log(tokenSymbol, "- Cannot calculate APY");
            }
        }
    }

    function _getTokenConfig(string memory tokenSymbol, address tokenAddress) internal view returns (TokenConfig memory) {
        string memory baseRateKey = string.concat(tokenSymbol, "_BASE_RATE");
        string memory optimalUtilKey = string.concat(tokenSymbol, "_OPTIMAL_UTIL");
        string memory slope1Key = string.concat(tokenSymbol, "_RATE_SLOPE1");
        string memory slope2Key = string.concat(tokenSymbol, "_RATE_SLOPE2");
        string memory supplyKey = string.concat(tokenSymbol, "_SUPPLY_AMOUNT");

        uint256 baseRate = vm.envOr(baseRateKey, _getDefaultBaseRate(tokenSymbol));
        uint256 optimalUtil = vm.envOr(optimalUtilKey, _getDefaultOptimalUtil(tokenSymbol));
        uint256 rateSlope1 = vm.envOr(slope1Key, _getDefaultSlope1(tokenSymbol));
        uint256 rateSlope2 = vm.envOr(slope2Key, _getDefaultSlope2(tokenSymbol));
        uint256 targetSupply = vm.envOr(supplyKey, _getDefaultSupplyAmount(tokenSymbol));

        // Target borrow is calculated based on target utilization
        uint256 targetBorrow = (targetSupply * targetUtilization) / 10000;

        return TokenConfig({
            symbol: tokenSymbol,
            tokenAddress: tokenAddress,
            baseRate: baseRate,
            optimalUtilization: optimalUtil,
            rateSlope1: rateSlope1,
            rateSlope2: rateSlope2,
            targetSupply: targetSupply,
            targetBorrow: targetBorrow
        });
    }

    // Default parameter functions (same as original)
    function _getDefaultBaseRate(string memory symbol) internal pure returns (uint256) {
        if (_strEq(symbol, "IDRX")) return 200;
        if (_strEq(symbol, "WETH")) return 300;
        if (_strEq(symbol, "WBTC")) return 250;
        if (_strEq(symbol, "GOLD") || _strEq(symbol, "SILVER")) return 250;
        if (_strEq(symbol, "GOOGL") || _strEq(symbol, "NVDA") || _strEq(symbol, "AAPL")) return 400;
        if (_strEq(symbol, "MNT")) return 350;
        return 300;
    }

    function _getDefaultOptimalUtil(string memory symbol) internal pure returns (uint256) {
        if (_strEq(symbol, "IDRX") || _strEq(symbol, "WETH") || _strEq(symbol, "WBTC")) return 8000;
        if (_strEq(symbol, "GOLD") || _strEq(symbol, "SILVER") || _strEq(symbol, "MNT")) return 7500;
        if (_strEq(symbol, "GOOGL") || _strEq(symbol, "NVDA") || _strEq(symbol, "AAPL")) return 7000;
        return 8000;
    }

    function _getDefaultSlope1(string memory symbol) internal pure returns (uint256) {
        if (_strEq(symbol, "IDRX")) return 1000;
        if (_strEq(symbol, "WETH")) return 1200;
        if (_strEq(symbol, "WBTC")) return 1100;
        if (_strEq(symbol, "GOLD") || _strEq(symbol, "SILVER")) return 900;
        if (_strEq(symbol, "GOOGL") || _strEq(symbol, "NVDA") || _strEq(symbol, "AAPL")) return 1500;
        if (_strEq(symbol, "MNT")) return 1300;
        return 1000;
    }

    function _getDefaultSlope2(string memory symbol) internal pure returns (uint256) {
        if (_strEq(symbol, "IDRX")) return 5000;
        if (_strEq(symbol, "WETH")) return 6000;
        if (_strEq(symbol, "WBTC")) return 5500;
        if (_strEq(symbol, "GOLD") || _strEq(symbol, "SILVER")) return 4000;
        if (_strEq(symbol, "GOOGL") || _strEq(symbol, "NVDA") || _strEq(symbol, "AAPL")) return 7000;
        if (_strEq(symbol, "MNT")) return 6500;
        return 5000;
    }

    function _getDefaultSupplyAmount(string memory symbol) internal view returns (uint256) {
        if (_strEq(symbol, "IDRX")) return 10000 * quoteDivisor;
        if (_strEq(symbol, "WETH")) return 10 * 10**18;
        if (_strEq(symbol, "WBTC")) return 1 * 10**8;
        if (_strEq(symbol, "GOLD")) return 10 * 10**18;
        if (_strEq(symbol, "SILVER")) return 100 * 10**18;
        if (_strEq(symbol, "GOOGL") || _strEq(symbol, "NVDA") || _strEq(symbol, "AAPL")) return 10 * 10**18;
        if (_strEq(symbol, "MNT")) return 1000 * 10**18;
        return 0;
    }

    function _strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
