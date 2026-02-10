// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {LendingManager} from "../../src/yield/LendingManager.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {Oracle} from "../../src/core/Oracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title UpdateLendingWithActivity
 * @dev Updates interest rate parameters AND creates lending activity (deposits + borrows)
 *      to generate non-zero APY values
 *
 * Environment Variables:
 *   PRIVATE_KEY - Primary account (supplier)
 *   PRIVATE_KEY_2 - Secondary account (borrower, optional)
 *   TOKENS - Comma-separated list of tokens (default: ALL)
 *
 *   Supply amounts (in token units):
 *   - IDRX_SUPPLY_AMOUNT (default: 100000)
 *   - WETH_SUPPLY_AMOUNT (default: 10)
 *   - WBTC_SUPPLY_AMOUNT (default: 1)
 *
 *   Borrow ratios (percentage of supply to borrow):
 *   - BORROW_RATIO (default: 30 = 30% utilization)
 *
 * Usage:
 *   PRIVATE_KEY=0x... forge script script/lending/UpdateLendingWithActivity.s.sol:UpdateLendingWithActivity \
 *     --rpc-url http://127.0.0.1:8545 --broadcast
 */
contract UpdateLendingWithActivity is Script, DeployHelpers {

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
        uint256 supplyAmount;
        uint256 borrowAmount;
    }

    string[] public selectedTokens;
    uint256 public borrowRatio; // Percentage of supply to borrow (for utilization)

    function run() external {
        loadDeployments();
        uint256 deployerPrivateKey = getDeployerKey();
        primaryAccount = vm.addr(deployerPrivateKey);

        // Use PRIVATE_KEY_2 if available, otherwise use a test account
        try vm.envUint("PRIVATE_KEY_2") returns (uint256 key2) {
            secondaryAccount = vm.addr(key2);
        } catch {
            secondaryAccount = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Default test account
        }

        console.log("=== UPDATING LENDING WITH ACTIVITY ===");
        console.log("Primary Account (Supplier):", primaryAccount);
        console.log("Secondary Account (Borrower):", secondaryAccount);
        console.log("");

        _loadContracts();
        _parseSelectedTokens();

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Phase 1: Update Interest Rate Parameters ===");
        _updateInterestRateParameters();

        console.log("\n=== Phase 2: Supply Tokens to Lending Pool ===");
        _supplyTokens();

        console.log("\n=== Phase 3: Borrow Against Collateral ===");
        _borrowTokens();

        vm.stopBroadcast();

        console.log("\n=== Phase 4: Verify APY Values ===");
        _verifyAPY();

        console.log("\n=== LENDING UPDATE WITH ACTIVITY COMPLETE ===");
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
        console.log("Oracle:", address(oracle));
        console.log("");

        // Get borrow ratio (default 30% for 30% utilization)
        borrowRatio = vm.envOr("BORROW_RATIO", uint256(30));
        console.log("Target Utilization:", borrowRatio, "%");
        console.log("");
    }

    function _parseSelectedTokens() internal {
        string memory tokensEnv = vm.envOr("TOKENS", string("ALL"));

        string[9] memory allTokens = ["IDRX", "WETH", "WBTC", "GOLD", "SILVER", "GOOGL", "NVDA", "AAPL", "MNT"];

        if (keccak256(bytes(tokensEnv)) == keccak256(bytes("ALL"))) {
            for (uint i = 0; i < allTokens.length; i++) {
                if (deployed[allTokens[i]].isSet) {
                    selectedTokens.push(allTokens[i]);
                }
            }
        } else {
            // Try all tokens and add if deployed
            for (uint i = 0; i < allTokens.length; i++) {
                if (deployed[allTokens[i]].isSet) {
                    selectedTokens.push(allTokens[i]);
                }
            }
        }

        console.log("Selected tokens:", selectedTokens.length);
        for (uint i = 0; i < selectedTokens.length; i++) {
            console.log("-", selectedTokens[i]);
        }
        console.log("");
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
                console.log("     Base:", _formatBps(config.baseRate));
                console.log("     Optimal:", _formatBps(config.optimalUtilization));
                console.log("     Slope1:", _formatBps(config.rateSlope1));
                console.log("     Slope2:", _formatBps(config.rateSlope2));
            } catch Error(string memory reason) {
                console.log("[ERROR]", tokenSymbol, "failed:", reason);
            } catch {
                console.log("[ERROR]", tokenSymbol, "failed");
            }
        }
    }

    function _supplyTokens() internal {
        for (uint i = 0; i < selectedTokens.length; i++) {
            string memory tokenSymbol = selectedTokens[i];
            address tokenAddress = deployed[tokenSymbol].addr;

            TokenConfig memory config = _getTokenConfig(tokenSymbol, tokenAddress);

            if (config.supplyAmount == 0) {
                console.log("[SKIP]", tokenSymbol, "- supply amount is 0");
                continue;
            }

            // Check if user has enough balance in BalanceManager
            uint256 currentBalance = balanceManager.getBalance(primaryAccount, Currency.wrap(tokenAddress));

            if (currentBalance < config.supplyAmount) {
                console.log("[SKIP]", tokenSymbol, "- insufficient balance");
                console.log("     Required:", config.supplyAmount, "Available:", currentBalance);
                continue;
            }

            // Supply to lending pool
            try lendingManager.supply(tokenAddress, config.supplyAmount) {
                console.log("[OK]", tokenSymbol, "supplied:", config.supplyAmount);

                // Verify supply
                uint256 supplied = lendingManager.getUserSupply(primaryAccount, tokenAddress);
                console.log("     Total supply:", supplied);
            } catch Error(string memory reason) {
                console.log("[ERROR]", tokenSymbol, "supply failed:", reason);
            } catch {
                console.log("[ERROR]", tokenSymbol, "supply failed");
            }
        }
    }

    function _borrowTokens() internal {
        for (uint i = 0; i < selectedTokens.length; i++) {
            string memory tokenSymbol = selectedTokens[i];
            address tokenAddress = deployed[tokenSymbol].addr;

            TokenConfig memory config = _getTokenConfig(tokenSymbol, tokenAddress);

            if (config.borrowAmount == 0) {
                console.log("[SKIP]", tokenSymbol, "- borrow amount is 0");
                continue;
            }

            // Try to borrow (contract will check collateral automatically)
            try lendingManager.borrow(tokenAddress, config.borrowAmount) {
                console.log("[OK]", tokenSymbol, "borrowed:", config.borrowAmount);

                    // Verify borrow
                    uint256 debt = lendingManager.getUserDebt(primaryAccount, tokenAddress);
                    uint256 supplied = lendingManager.totalLiquidity(tokenAddress);
                    uint256 utilization = supplied > 0 ? (debt * 10000) / supplied : 0;

                    console.log("     Total debt:", debt);
                    console.log("     Utilization:", utilization / 100, "%");
                } catch Error(string memory reason) {
                    console.log("[ERROR]", tokenSymbol, "borrow failed:", reason);
                } catch {
                    console.log("[ERROR]", tokenSymbol, "borrow failed");
                }
        }
    }

    function _verifyAPY() internal view {
        console.log("Verifying APY calculations for each token...");
        console.log("");

        for (uint i = 0; i < selectedTokens.length; i++) {
            string memory tokenSymbol = selectedTokens[i];
            address tokenAddress = deployed[tokenSymbol].addr;

            try lendingManager.totalLiquidity(tokenAddress) returns (uint256 totalSupply) {
                try lendingManager.totalBorrowed(tokenAddress) returns (uint256 totalBorrow) {

                    uint256 utilization = totalSupply > 0 ? (totalBorrow * 10000) / totalSupply : 0;

                    try lendingManager.calculateInterestRate(tokenAddress) returns (uint256 borrowAPY) {
                        // Supply APY = Borrow APY × Utilization (simplified, no reserve factor)
                        uint256 supplyAPY = (borrowAPY * utilization) / 10000;

                        console.log(tokenSymbol, ":");
                        console.log("  Total Supply:", totalSupply);
                        console.log("  Total Borrow:", totalBorrow);
                        console.log("  Utilization:", utilization / 100, "%");
                        console.log("  Borrow APY:", borrowAPY / 100, "%");
                        console.log("  Supply APY:", supplyAPY / 100, "%");

                        if (supplyAPY > 0) {
                            console.log("  [OK] Supply APY is non-zero!");
                        } else if (utilization == 0) {
                            console.log("  [INFO] Supply APY is 0 (no borrowing activity)");
                        }
                        console.log("");
                    } catch {
                        console.log(tokenSymbol, "- Cannot calculate interest rate");
                    }
                } catch {
                    console.log(tokenSymbol, "- Cannot get total borrow");
                }
            } catch {
                console.log(tokenSymbol, "- Cannot get total supply");
            }
        }
    }

    function _getTokenConfig(string memory tokenSymbol, address tokenAddress) internal view returns (TokenConfig memory) {
        // Interest rate parameters
        string memory baseRateKey = string.concat(tokenSymbol, "_BASE_RATE");
        string memory optimalUtilKey = string.concat(tokenSymbol, "_OPTIMAL_UTIL");
        string memory slope1Key = string.concat(tokenSymbol, "_RATE_SLOPE1");
        string memory slope2Key = string.concat(tokenSymbol, "_RATE_SLOPE2");

        uint256 baseRate = vm.envOr(baseRateKey, _getDefaultBaseRate(tokenSymbol));
        uint256 optimalUtil = vm.envOr(optimalUtilKey, _getDefaultOptimalUtil(tokenSymbol));
        uint256 rateSlope1 = vm.envOr(slope1Key, _getDefaultSlope1(tokenSymbol));
        uint256 rateSlope2 = vm.envOr(slope2Key, _getDefaultSlope2(tokenSymbol));

        // Supply and borrow amounts
        string memory supplyKey = string.concat(tokenSymbol, "_SUPPLY_AMOUNT");
        string memory borrowKey = string.concat(tokenSymbol, "_BORROW_AMOUNT");

        uint256 supplyAmount = vm.envOr(supplyKey, _getDefaultSupplyAmount(tokenSymbol));
        uint256 borrowAmount = vm.envOr(borrowKey, (supplyAmount * borrowRatio) / 100);

        return TokenConfig({
            symbol: tokenSymbol,
            tokenAddress: tokenAddress,
            baseRate: baseRate,
            optimalUtilization: optimalUtil,
            rateSlope1: rateSlope1,
            rateSlope2: rateSlope2,
            supplyAmount: supplyAmount,
            borrowAmount: borrowAmount
        });
    }

    // Default interest rate parameters
    function _getDefaultBaseRate(string memory symbol) internal pure returns (uint256) {
        if (_strEq(symbol, "IDRX")) return 200;  // 2%
        if (_strEq(symbol, "WETH")) return 300;  // 3%
        if (_strEq(symbol, "WBTC")) return 250;  // 2.5%
        if (_strEq(symbol, "GOLD") || _strEq(symbol, "SILVER")) return 250;  // 2.5%
        if (_strEq(symbol, "GOOGL") || _strEq(symbol, "NVDA") || _strEq(symbol, "AAPL")) return 400;  // 4%
        if (_strEq(symbol, "MNT")) return 350;  // 3.5%
        return 300;  // 3% default
    }

    function _getDefaultOptimalUtil(string memory symbol) internal pure returns (uint256) {
        if (_strEq(symbol, "IDRX") || _strEq(symbol, "WETH") || _strEq(symbol, "WBTC")) return 8000;  // 80%
        if (_strEq(symbol, "GOLD") || _strEq(symbol, "SILVER") || _strEq(symbol, "MNT")) return 7500;  // 75%
        if (_strEq(symbol, "GOOGL") || _strEq(symbol, "NVDA") || _strEq(symbol, "AAPL")) return 7000;  // 70%
        return 8000;  // 80% default
    }

    function _getDefaultSlope1(string memory symbol) internal pure returns (uint256) {
        if (_strEq(symbol, "IDRX")) return 1000;  // 10%
        if (_strEq(symbol, "WETH")) return 1200;  // 12%
        if (_strEq(symbol, "WBTC")) return 1100;  // 11%
        if (_strEq(symbol, "GOLD") || _strEq(symbol, "SILVER")) return 900;   // 9%
        if (_strEq(symbol, "GOOGL") || _strEq(symbol, "NVDA") || _strEq(symbol, "AAPL")) return 1500;  // 15%
        if (_strEq(symbol, "MNT")) return 1300;  // 13%
        return 1000;  // 10% default
    }

    function _getDefaultSlope2(string memory symbol) internal pure returns (uint256) {
        if (_strEq(symbol, "IDRX")) return 5000;  // 50%
        if (_strEq(symbol, "WETH")) return 6000;  // 60%
        if (_strEq(symbol, "WBTC")) return 5500;  // 55%
        if (_strEq(symbol, "GOLD") || _strEq(symbol, "SILVER")) return 4000;  // 40%
        if (_strEq(symbol, "GOOGL") || _strEq(symbol, "NVDA") || _strEq(symbol, "AAPL")) return 7000;  // 70%
        if (_strEq(symbol, "MNT")) return 6500;  // 65%
        return 5000;  // 50% default
    }

    function _getDefaultSupplyAmount(string memory symbol) internal view returns (uint256) {
        if (_strEq(symbol, "IDRX")) return 10000 * quoteDivisor;  // 10,000 IDRX
        if (_strEq(symbol, "WETH")) return 10 * 10**18;  // 10 WETH
        if (_strEq(symbol, "WBTC")) return 1 * 10**8;    // 1 WBTC
        if (_strEq(symbol, "GOLD")) return 10 * 10**18;  // 10 GOLD
        if (_strEq(symbol, "SILVER")) return 100 * 10**18;  // 100 SILVER
        if (_strEq(symbol, "GOOGL") || _strEq(symbol, "NVDA") || _strEq(symbol, "AAPL")) return 10 * 10**18;  // 10 stocks
        if (_strEq(symbol, "MNT")) return 1000 * 10**18;  // 1000 MNT
        return 0;  // No default
    }

    function _strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _formatBps(uint256 bps) internal pure returns (string memory) {
        uint256 whole = bps / 100;
        uint256 decimal = bps % 100;

        if (decimal == 0) {
            return string.concat(vm.toString(whole), "%");
        } else if (decimal < 10) {
            return string.concat(vm.toString(whole), ".0", vm.toString(decimal), "%");
        } else {
            return string.concat(vm.toString(whole), ".", vm.toString(decimal), "%");
        }
    }
}
