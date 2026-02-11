// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {ILendingManager} from "../../src/core/interfaces/ILendingManager.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";

/**
 * @title VerifySupplyAlignment
 * @dev Verify that BalanceManager balances align with LendingManager supplies
 *
 * Usage:
 *   forge script script/debug/VerifySupplyAlignment.s.sol:VerifySupplyAlignment \
 *     --rpc-url https://sepolia.base.org
 */
contract VerifySupplyAlignment is Script {
    // Contract addresses from deployments
    address constant BALANCE_MANAGER = 0x790269943a56275bCD054C52c47Ccb1065300106;
    address constant LENDING_MANAGER = 0xb5D168385f33F7904eE727D4c2E8DB6b9576f5c8;

    // Token addresses
    address constant USDC = 0xeFEe5DC2b274449cA3A4b4D0357cf3157158B76E;
    address constant WETH = 0x02297F21986Fa7EE7251E0Abe56667a40Fc278a5;
    address constant WBTC = 0x9976e7c455CCe03ADe3E6508FDa4b44227210B52;

    // Synthetic token addresses
    address constant sxUSDC = 0xAFC4Fb45a1671e7587aAaE1BbD6b4794461b036b;
    address constant sxWETH = 0x2adf289f748A56e92f6dfcf18cf7Ecc4e5dFaEd9;
    address constant sxWBTC = 0xcf2b03b7A3a7CD015f6c59289137aB60d857E2CE;

    // OrderBook addresses
    address constant WETH_USDC_POOL = 0x0a6CC21C61ED7e73A779E463ca28b82BE30caB93;
    address constant WBTC_USDC_POOL = 0x57F138d0E24A04E201C92b2BAd6a07bDAF0a1157;

    struct TokenInfo {
        string name;
        address underlying;
        address synthetic;
        uint8 decimals;
    }

    struct UserBalances {
        uint256 sxBalance;        // Balance in BalanceManager
        uint256 lockedBalance;    // Locked in orders
        uint256 availableBalance; // Available (sxBalance - locked)
        uint256 supply;           // Supply in LendingManager (underlying)
        uint256 debt;             // Debt in LendingManager (underlying)
    }

    function run() external view {
        console.log("==============================================");
        console.log("  Supply Alignment Verification Script");
        console.log("==============================================\n");

        // Define tokens to check
        TokenInfo[] memory tokens = new TokenInfo[](3);
        tokens[0] = TokenInfo("USDC", USDC, sxUSDC, 6);
        tokens[1] = TokenInfo("WETH", WETH, sxWETH, 18);
        tokens[2] = TokenInfo("WBTC", WBTC, sxWBTC, 8);

        // Users to check - add more as needed
        address[] memory users = new address[](5);
        users[0] = 0x0f27AceC819E7F7D9df847831C3F3DB6e237d0F2; // Example user from TX
        users[1] = 0x1DFaE30fD2c0322f834A1D30Ec24c2AaA727CE5a; // Counterparty
        users[2] = 0x27dD1eBE7D826197FD163C134E79502402Fd7cB7; // Deployer
        users[3] = 0x506B6fa189Ada984E1F98473047970f17da15AEc; // Trading Bot 1
        users[4] = 0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a; // Trader B

        IBalanceManager bm = IBalanceManager(BALANCE_MANAGER);
        ILendingManager lm = ILendingManager(LENDING_MANAGER);

        bool hasDiscrepancy = false;

        for (uint256 u = 0; u < users.length; u++) {
            address user = users[u];
            console.log("----------------------------------------------");
            console.log("User:", user);
            console.log("----------------------------------------------");

            for (uint256 t = 0; t < tokens.length; t++) {
                TokenInfo memory token = tokens[t];

                UserBalances memory bal = _getUserBalances(bm, lm, user, token, WETH_USDC_POOL);

                console.log("");
                console.log(token.name, ":");

                // Format based on decimals
                if (token.decimals == 6) {
                    console.log("  sxToken Balance:    ", bal.sxBalance / 1e6, ".", bal.sxBalance % 1e6);
                    console.log("  Locked in Orders:   ", bal.lockedBalance / 1e6, ".", bal.lockedBalance % 1e6);
                    console.log("  Available Balance:  ", bal.availableBalance / 1e6, ".", bal.availableBalance % 1e6);
                    console.log("  LM Supply:          ", bal.supply / 1e6, ".", bal.supply % 1e6);
                    console.log("  LM Debt:            ", bal.debt / 1e6, ".", bal.debt % 1e6);
                } else if (token.decimals == 18) {
                    console.log("  sxToken Balance:    ", bal.sxBalance / 1e18);
                    console.log("  Locked in Orders:   ", bal.lockedBalance / 1e18);
                    console.log("  Available Balance:  ", bal.availableBalance / 1e18);
                    console.log("  LM Supply:          ", bal.supply / 1e18);
                    console.log("  LM Debt:            ", bal.debt / 1e18);
                } else {
                    console.log("  sxToken Balance:    ", bal.sxBalance);
                    console.log("  Locked in Orders:   ", bal.lockedBalance);
                    console.log("  Available Balance:  ", bal.availableBalance);
                    console.log("  LM Supply:          ", bal.supply);
                    console.log("  LM Debt:            ", bal.debt);
                }

                // Check alignment: sxBalance should equal supply (when no borrowing)
                // Or: sxBalance = supply + borrowed - repaid
                // Net position = supply - debt
                int256 netSupply = int256(bal.supply) - int256(bal.debt);
                int256 sxBalanceInt = int256(bal.sxBalance);

                // The sxBalance should roughly equal netSupply
                // Allow small rounding differences
                int256 diff = sxBalanceInt - netSupply;
                if (diff < 0) diff = -diff;

                uint256 threshold = token.decimals == 6 ? 1e6 : (token.decimals == 18 ? 1e15 : 1e5);

                if (uint256(diff) > threshold && (bal.sxBalance > 0 || bal.supply > 0 || bal.debt > 0)) {
                    console.log("  [WARNING] Potential misalignment!");
                    console.log("  Net Supply (supply-debt):", netSupply > 0 ? uint256(netSupply) : 0);
                    console.log("  Difference:", uint256(diff));
                    hasDiscrepancy = true;
                }
            }
            console.log("");
        }

        console.log("==============================================");
        if (hasDiscrepancy) {
            console.log("  [WARNING] Found potential discrepancies!");
        } else {
            console.log("  [OK] All balances appear aligned");
        }
        console.log("==============================================");
    }

    function _getUserBalances(
        IBalanceManager bm,
        ILendingManager lm,
        address user,
        TokenInfo memory token,
        address orderBook
    ) internal view returns (UserBalances memory bal) {
        Currency syntheticCurrency = Currency.wrap(token.synthetic);

        // Get balance from BalanceManager
        try bm.getBalance(user, syntheticCurrency) returns (uint256 balance) {
            bal.sxBalance = balance;
        } catch {}

        // Get locked balance
        try bm.getLockedBalance(user, orderBook, syntheticCurrency) returns (uint256 locked) {
            bal.lockedBalance = locked;
        } catch {}

        // Get available balance
        try bm.getAvailableBalance(user, syntheticCurrency) returns (uint256 available) {
            bal.availableBalance = available;
        } catch {}

        // Get supply from LendingManager (uses underlying token)
        try lm.getUserSupply(user, token.underlying) returns (uint256 supply) {
            bal.supply = supply;
        } catch {}

        // Get debt from LendingManager
        try lm.getUserDebt(user, token.underlying) returns (uint256 debt) {
            bal.debt = debt;
        } catch {}

        return bal;
    }
}
