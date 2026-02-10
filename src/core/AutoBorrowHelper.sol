// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {Currency} from "./libraries/Currency.sol";

/**
 * @title AutoBorrowHelper
 * @notice External helper contract for auto-borrow functionality
 * @dev Extracted from OrderBook to reduce contract size
 */
contract AutoBorrowHelper {
    error InsufficientOrderBalance(uint256 have, uint256 want);
    error InsufficientCollateral(address user);
    error InsufficientHealthFactorForBorrow(uint256 projected, uint256 minimum);
    error AutoBorrowFailed(address user, address token, uint256 amount);

    /// @notice Validates that user can borrow and executes borrow if needed
    /// @param balanceManager The BalanceManager contract
    /// @param user The user address
    /// @param currency The currency needed
    /// @param requiredAmount The amount required
    /// @param autoBorrow Whether auto-borrow is enabled
    /// @return borrowed The amount that was borrowed (0 if not needed)
    function validateAndBorrowIfNeeded(
        address balanceManager,
        address user,
        Currency currency,
        uint256 requiredAmount,
        bool autoBorrow
    ) external returns (uint256 borrowed) {
        IBalanceManager bm = IBalanceManager(balanceManager);
        uint256 userBalance = bm.getBalance(user, currency);

        if (requiredAmount > userBalance) {
            if (!autoBorrow) {
                revert InsufficientOrderBalance(userBalance, requiredAmount);
            }

            uint256 shortfall = requiredAmount - userBalance;
            address syntheticToken = Currency.unwrap(currency);
            address underlyingToken = _getUnderlyingToken(bm, syntheticToken);
            address lendingManager = bm.lendingManager();

            if (lendingManager == address(0)) {
                revert InsufficientOrderBalance(userBalance, requiredAmount);
            }

            // Validate health factor
            uint256 projectedHF = ILendingManager(lendingManager).getProjectedHealthFactor(
                user,
                underlyingToken,
                shortfall
            );

            if (projectedHF < 1e18) {
                revert InsufficientHealthFactorForBorrow(projectedHF, 1e18);
            }

            // Execute borrow
            _executeBorrow(bm, lendingManager, user, underlyingToken, syntheticToken, shortfall);

            return shortfall;
        }

        return 0;
    }

    /// @notice Executes the borrow operation
    function _executeBorrow(
        IBalanceManager bm,
        address lendingManager,
        address user,
        address underlyingToken,
        address syntheticToken,
        uint256 amount
    ) private {
        if (lendingManager == address(0)) {
            revert AutoBorrowFailed(user, underlyingToken, amount);
        }

        // Borrow through BalanceManager (handles both borrow and synthetic token creation)
        try bm.borrowForUser(user, underlyingToken, amount) {
            // Success - synthetic tokens credited to user's balance
        } catch {
            revert AutoBorrowFailed(user, underlyingToken, amount);
        }
    }

    /// @notice Validates balance only (for market orders where borrow happens during matching)
    /// @dev Simpler validation without borrowing execution
    function validateBalanceOnly(
        address balanceManager,
        address user,
        Currency currency,
        uint256 requiredAmount,
        bool autoBorrow
    ) external view {
        if (!autoBorrow) {
            IBalanceManager bm = IBalanceManager(balanceManager);
            uint256 userBalance = bm.getBalance(user, currency);

            if (requiredAmount > userBalance) {
                revert InsufficientOrderBalance(userBalance, requiredAmount);
            }
        }
        // If autoBorrow is enabled, skip validation (will borrow during matching)
    }

    /// @notice Get underlying token from synthetic token
    function _getUnderlyingToken(IBalanceManager bm, address syntheticToken) private view returns (address) {
        address[] memory supportedAssets = bm.getSupportedAssets();
        for (uint256 i = 0; i < supportedAssets.length; i++) {
            if (bm.getSyntheticToken(supportedAssets[i]) == syntheticToken) {
                return supportedAssets[i];
            }
        }
        revert("Underlying token not found");
    }
}
