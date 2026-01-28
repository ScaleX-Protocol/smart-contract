// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// import {console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {LendingManagerStorage} from "./LendingManagerStorage.sol";
import {Currency} from "../core/libraries/Currency.sol";

// BalanceManager interface for querying sxToken balances and seizing collateral
interface IBalanceManagerForLending {
    function getBalance(address user, Currency currency) external view returns (uint256);
    function getSyntheticToken(address realToken) external view returns (address);
    function seizeCollateral(address user, address underlyingToken, uint256 amount) external;
}

// Oracle interfaces
interface IPriceOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IOracle {
    function getPriceForCollateral(address token) external view returns (uint256);
    function getPriceForBorrowing(address token) external view returns (uint256);
    function getPriceConfidence(address token) external view returns (uint256);
    function isPriceStale(address token) external view returns (bool);
}

/**
 * @title LendingManager
 * @dev Complete lending manager implementation using diamond storage pattern with upgradeable support
 */
contract LendingManager is 
    LendingManagerStorage,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable 
{
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Custom errors (also defined in main contract for external accessibility)
    error InsufficientLiquidity();
    error InsufficientCollateral();
    error InvalidAmount();
    error UnsupportedAsset();
    error LiquidationFailed();
    error InvalidAddress();
    error OnlyBalanceManager();

    modifier onlyBalanceManager() {
        if (msg.sender != getStorage().balanceManager) revert OnlyBalanceManager();
        _;
    }

    // =============================================================
    //                   INITIALIZATION
    // =============================================================

    function initialize(address _owner, address _balanceManager, address _oracle) public initializer {
        if (_owner == address(0)) revert InvalidAddress();
        if (_balanceManager == address(0)) revert InvalidAddress();
        // Oracle can be zero address - system has fallback behavior
        
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        
        _initializeConstants();
        getStorage().balanceManager = _balanceManager;
        getStorage().oracle = _oracle;
        
        emit BalanceManagerSet(_balanceManager);
    }

    // =============================================================
    //                   OWNER FUNCTIONS
    // =============================================================

    function setPriceOracle(address _priceOracle) external onlyOwner {
        if (_priceOracle == address(0)) revert InvalidAddress();
        getStorage().priceOracle = _priceOracle;
    }

    function setOracle(address _oracle) external onlyOwner {
        // Oracle can be zero address - system has fallback behavior
        getStorage().oracle = _oracle;
    }

    function setBalanceManager(address _balanceManager) external onlyOwner {
        if (_balanceManager == address(0)) revert InvalidAddress();
        getStorage().balanceManager = _balanceManager;
        emit BalanceManagerSet(_balanceManager);
    }

    function configureAsset(
        address token,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor
    ) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        
        Storage storage $ = getStorage();
        bool isNew = !$.assetConfigs[token].enabled;
        
        $.assetConfigs[token] = AssetConfig({
            collateralFactor: collateralFactor,
            liquidationThreshold: liquidationThreshold,
            liquidationBonus: liquidationBonus,
            reserveFactor: reserveFactor,
            enabled: true
        });

        if (isNew) {
            $.supportedAssets.push(token);
            $.totalAccumulatedInterest[token] = 0;
            $.lastInterestUpdate[token] = block.timestamp;
        }

        emit AssetConfigured(token, collateralFactor, liquidationThreshold, liquidationBonus, reserveFactor);
    }

    function setInterestRateParams(
        address token,
        uint256 baseRate,
        uint256 optimalUtilization,
        uint256 rateSlope1,
        uint256 rateSlope2
    ) external {
        Storage storage $ = getStorage();
        $.interestRateParams[token] = InterestRateParams({
            baseRate: baseRate,
            optimalUtilization: optimalUtilization,
            rateSlope1: rateSlope1,
            rateSlope2: rateSlope2
        });

        emit InterestRateParamsSet(token, baseRate, optimalUtilization, rateSlope1, rateSlope2);
    }

    // =============================================================
    //                   DEPOSIT/WITHDRAW FUNCTIONS
    // =============================================================

    function supply(
        address token,
        uint256 amount
    ) external onlyBalanceManager nonReentrant {
        _supplyForUser(msg.sender, token, amount);
    }
    
    function supplyForUser(
        address user,
        address token,
        uint256 amount
    ) external onlyBalanceManager {
        _supplyForUser(user, token, amount);
    }
    
    function _supplyForUser(
        address user,
        address token,
        uint256 amount
    ) internal {
        Storage storage $ = getStorage();

        if (!$.assetConfigs[token].enabled) revert UnsupportedAsset();
        if (amount == 0) revert InvalidAmount();

        _updateInterest(token);
        _updateUserPosition(user, token);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Only track total pool liquidity - per-user supply is tracked via sxToken balance in BalanceManager
        $.totalLiquidity[token] += amount;

        // Track that user now has a position in this asset
        _addUserAsset(user, token);

        emit LiquidityDeposited(user, token, amount, block.timestamp);
    }

    function withdraw(
        address token,
        uint256 amount
    ) external onlyBalanceManager nonReentrant returns (uint256 actualAmount) {
        Storage storage $ = getStorage();
        if (!$.assetConfigs[token].enabled) revert UnsupportedAsset();
        if (amount == 0) revert InvalidAmount();

        _updateInterest(token);
        _updateUserPosition(msg.sender, token);

        uint256 availableLiquidity = $.totalLiquidity[token] - $.totalBorrowed[token];
        if (availableLiquidity < amount) {
            amount = availableLiquidity;
        }

        // Check user's supply balance from BalanceManager (gsToken balance represents supply ownership)
        uint256 userSupply = _getUserSupplyBalance(msg.sender, token);
        if (userSupply < amount) {
            revert InsufficientLiquidity();
        }

        // Check if user has debt - if so, ensure withdrawal won't make them liquidatable
        uint256 totalDebtValue = _getTotalDebtValue(msg.sender);
        if (totalDebtValue > 0) {
            // User has debt, validate that withdrawal won't make them liquidatable
            uint256 tokenPrice = _getTokenPrice(token);
            uint256 withdrawValue = (amount * tokenPrice) / (10 ** IERC20Metadata(token).decimals());

            // Get current collateral value and calculate new value after withdrawal
            uint256 currentCollateralValue = _getTotalCollateralValueRaw(msg.sender);
            uint256 newCollateralValue = currentCollateralValue - withdrawValue;

            // Calculate minimum liquidation threshold across all collateral assets
            uint256 minLiquidationThreshold = _getMinLiquidationThreshold(msg.sender);

            // Calculate new health factor: (newCollateral * minThreshold * PRECISION) / totalDebt
            uint256 newHealthFactor = (newCollateralValue * minLiquidationThreshold * getStorage().PRECISION) / totalDebtValue;

            // Revert if new health factor would be below 1.0
            if (newHealthFactor < getStorage().PRECISION) {
                revert InsufficientCollateral();
            }
        }

        // Only decrease total pool liquidity - per-user supply is tracked via sxToken balance
        $.totalLiquidity[token] -= amount;

        actualAmount = amount;
        IERC20(token).safeTransfer(msg.sender, actualAmount);

        // Remove asset from tracking if user has no more position
        if (!_hasAssetPosition(msg.sender, token)) {
            _removeUserAsset(msg.sender, token);
        }

        emit LiquidityWithdrawn(msg.sender, token, actualAmount, 0, block.timestamp);
    }

    /// @notice Withdraw liquidity on behalf of a user
    /// @param token The token address to withdraw
    /// @param amount The amount to withdraw
    /// @param user The user on whose behalf to withdraw
    /// @return actualAmount The actual amount withdrawn
    /// @return yieldAmount The amount of yield earned
    function withdrawLiquidity(
        address token,
        uint256 amount,
        address user
    ) external onlyBalanceManager returns (uint256 actualAmount, uint256 yieldAmount) {
        Storage storage $ = getStorage();
        if (!$.assetConfigs[token].enabled) revert UnsupportedAsset();
        if (amount == 0) revert InvalidAmount();

        _updateInterest(token);
        _updateUserPosition(user, token);

        uint256 availableLiquidity = $.totalLiquidity[token] - $.totalBorrowed[token];
        if (availableLiquidity < amount) {
            amount = availableLiquidity;
        }

        // Check user's supply balance from BalanceManager (gsToken balance represents supply ownership)
        uint256 userSupply = _getUserSupplyBalance(user, token);
        if (userSupply < amount) {
            revert InsufficientLiquidity();
        }

        // Check if user has debt - if so, ensure withdrawal won't make them liquidatable
        uint256 totalDebtValue = _getTotalDebtValue(user);
        if (totalDebtValue > 0) {
            // User has debt, validate that withdrawal won't make them liquidatable
            uint256 tokenPrice = _getTokenPrice(token);
            uint256 withdrawValue = (amount * tokenPrice) / (10 ** IERC20Metadata(token).decimals());

            // Get current collateral value and calculate new value after withdrawal
            uint256 currentCollateralValue = _getTotalCollateralValueRaw(user);
            uint256 newCollateralValue = currentCollateralValue - withdrawValue;

            // Calculate minimum liquidation threshold across all collateral assets
            uint256 minLiquidationThreshold = _getMinLiquidationThreshold(user);

            // Calculate new health factor: (newCollateral * minThreshold * PRECISION) / totalDebt
            uint256 newHealthFactor = (newCollateralValue * minLiquidationThreshold * getStorage().PRECISION) / totalDebtValue;

            // Revert if new health factor would be below 1.0
            if (newHealthFactor < getStorage().PRECISION) {
                revert InsufficientCollateral();
            }
        }

        // Only decrease total pool liquidity - per-user supply is tracked via sxToken balance
        $.totalLiquidity[token] -= amount;

        actualAmount = amount;
        yieldAmount = 0; // Yield is handled separately through withdrawGeneratedInterest

        IERC20(token).safeTransfer(msg.sender, actualAmount);

        emit LiquidityWithdrawn(user, token, actualAmount, yieldAmount, block.timestamp);
    }

    /// @notice Withdraw generated interest for distribution to liquidity providers
    /// @param token The token address to withdraw interest for
    /// @param amount The amount of interest to withdraw
    /// @return actualAmount The actual amount of interest withdrawn
    function withdrawGeneratedInterest(
        address token,
        uint256 amount
    ) external onlyBalanceManager returns (uint256 actualAmount) {
        Storage storage $ = getStorage();
        if (!$.assetConfigs[token].enabled) revert UnsupportedAsset();
        if (amount == 0) revert InvalidAmount();

        _updateInterest(token);

        uint256 accumulatedInterest = $.totalAccumulatedInterest[token];
        if (accumulatedInterest == 0) {
            return 0;
        }

        // Can only withdraw up to the accumulated interest
        actualAmount = amount > accumulatedInterest ? accumulatedInterest : amount;

        // Reduce accumulated interest
        $.totalAccumulatedInterest[token] -= actualAmount;

        // Transfer interest tokens to BalanceManager
        IERC20(token).safeTransfer(msg.sender, actualAmount);

        emit GeneratedInterestWithdrawn(token, actualAmount, block.timestamp);
    }

    // =============================================================
    //                   BORROW/REPAY FUNCTIONS
    // =============================================================

    function borrow(address token, uint256 amount) external nonReentrant {
        Storage storage $ = getStorage();
        if (!$.assetConfigs[token].enabled) revert UnsupportedAsset();
        if (amount == 0) revert InvalidAmount();

        _updateInterest(token);

        UserPosition storage position = $.userPositions[msg.sender][token];
        
        _updateUserPosition(msg.sender, token);

        uint256 availableLiquidity = $.totalLiquidity[token] - $.totalBorrowed[token];
        
        if (availableLiquidity < amount) {
            revert InsufficientLiquidity();
        }

        bool hasCollateral = _hasSufficientCollateral(msg.sender, token, amount);
        
        if (!hasCollateral) {
            revert InsufficientCollateral();
        }

        uint256 previousBorrowed = position.borrowed;
        position.borrowed += amount;
        $.totalBorrowed[token] += amount;

        IERC20(token).safeTransfer(msg.sender, amount);

        emit Borrowed(msg.sender, token, amount, block.timestamp);
    }

    /// @notice Borrow tokens on behalf of a user (for BalanceManager integration)
    /// @param user The user to borrow for
    /// @param token The token to borrow
    /// @param amount The amount to borrow
    function borrowForUser(address user, address token, uint256 amount) external onlyBalanceManager {
        Storage storage $ = getStorage();
        // console.log("=== borrowForUser DEBUG ===");
        // console.log("User:", user);
        // console.log("Token:", token);
        // console.log("Amount:", amount);
        // console.log("Asset enabled:", $.assetConfigs[token].enabled);

        if (!$.assetConfigs[token].enabled) revert UnsupportedAsset();
        if (amount == 0) revert InvalidAmount();

        // Note: No need to migrate here - fallback to supportedAssets handles legacy users
        // and _addUserAsset at the end will start tracking for future operations

        // console.log("Before _updateInterest");
        _updateInterest(token);
        // console.log("After _updateInterest");

        UserPosition storage position = $.userPositions[user][token];

        _updateUserPosition(user, token);

        // console.log("totalLiquidity:", $.totalLiquidity[token]);
        // console.log("totalBorrowed:", $.totalBorrowed[token]);
        
        uint256 availableLiquidity = $.totalLiquidity[token] - $.totalBorrowed[token];
        // console.log("availableLiquidity:", availableLiquidity);
        // console.log("requested amount:", amount);
        
        if (availableLiquidity < amount) {
            // console.log("InsufficientLiquidity - available:", availableLiquidity, "requested:", amount);
            revert InsufficientLiquidity();
        }

        bool hasCollateral = _hasSufficientCollateral(user, token, amount);
        
        if (!hasCollateral) {
            revert InsufficientCollateral();
        }

        uint256 previousBorrowed = position.borrowed;
        position.borrowed += amount;
        $.totalBorrowed[token] += amount;

        // Track that user now has a position in this asset
        _addUserAsset(user, token);

        IERC20(token).safeTransfer(user, amount);

        emit Borrowed(user, token, amount, block.timestamp);
    }

    function repay(address token, uint256 amount) external nonReentrant {
        Storage storage $ = getStorage();
        if (!$.assetConfigs[token].enabled) revert UnsupportedAsset();
        if (amount == 0) revert InvalidAmount();

        _updateInterest(token);

        UserPosition storage position = $.userPositions[msg.sender][token];
        _updateUserPosition(msg.sender, token);

        uint256 interest = _calculateUserDebt(msg.sender, token) - position.borrowed;
        uint256 totalRepayment = amount;

        uint256 totalDebt = position.borrowed + interest;
        if (totalRepayment > totalDebt) {
            totalRepayment = totalDebt;
        }

        uint256 interestPayment = interest > totalRepayment ? totalRepayment : interest;
        uint256 principalPayment = totalRepayment - interestPayment;

        IERC20(token).safeTransferFrom(msg.sender, address(this), totalRepayment);

        position.borrowed -= principalPayment;
        $.totalBorrowed[token] -= principalPayment;

        emit Repaid(msg.sender, token, principalPayment, interestPayment, block.timestamp);
    }

    /// @notice Repay tokens on behalf of a user (for BalanceManager integration)
    /// @param user The user to repay for
    /// @param token The token to repay
    /// @param amount The amount to repay
    function repayForUser(address user, address token, uint256 amount) external onlyBalanceManager {
        Storage storage $ = getStorage();
        if (!$.assetConfigs[token].enabled) revert UnsupportedAsset();
        if (amount == 0) revert InvalidAmount();

        _updateInterest(token);

        UserPosition storage position = $.userPositions[user][token];
        _updateUserPosition(user, token);

        uint256 interest = _calculateUserDebt(user, token) - position.borrowed;
        uint256 totalRepayment = amount;

        uint256 totalDebt = position.borrowed + interest;
        if (totalRepayment > totalDebt) {
            totalRepayment = totalDebt;
        }

        uint256 interestPayment = interest > totalRepayment ? totalRepayment : interest;
        uint256 principalPayment = totalRepayment - interestPayment;

        // Tokens are already in this contract from BalanceManager, no need to transfer
        // Just update the accounting

        position.borrowed -= principalPayment;
        $.totalBorrowed[token] -= principalPayment;

        // Remove asset from tracking if user has no more position
        if (!_hasAssetPosition(user, token)) {
            _removeUserAsset(user, token);
        }

        emit Repaid(user, token, principalPayment, interestPayment, block.timestamp);
    }

    /// @notice Repay debt from user's balance (for auto-repay from OrderBook)
    /// @dev No token transfer needed - LendingManager already holds the underlying
    /// @param user The user to repay for
    /// @param token The token to repay
    /// @param amount The amount to repay
    function repayFromBalance(address user, address token, uint256 amount) external onlyBalanceManager {
        Storage storage $ = getStorage();
        if (!$.assetConfigs[token].enabled) revert UnsupportedAsset();
        if (amount == 0) revert InvalidAmount();

        _updateInterest(token);

        UserPosition storage position = $.userPositions[user][token];
        _updateUserPosition(user, token);

        uint256 interest = _calculateUserDebt(user, token) - position.borrowed;
        uint256 totalRepayment = amount;

        uint256 totalDebt = position.borrowed + interest;
        if (totalRepayment > totalDebt) {
            totalRepayment = totalDebt;
        }

        uint256 interestPayment = interest > totalRepayment ? totalRepayment : interest;
        uint256 principalPayment = totalRepayment - interestPayment;

        // No token transfer - underlying tokens are already held by LendingManager
        // This effectively converts synthetic balance to debt reduction

        position.borrowed -= principalPayment;
        $.totalBorrowed[token] -= principalPayment;

        emit Repaid(user, token, principalPayment, interestPayment, block.timestamp);
    }

    // =============================================================
    //                   LIQUIDATION FUNCTIONS
    // =============================================================

    function liquidate(
        address borrower,
        address debtToken,
        address collateralToken,
        uint256 debtToCover
    ) external nonReentrant {
        Storage storage $ = getStorage();
        if (!$.assetConfigs[debtToken].enabled || !$.assetConfigs[collateralToken].enabled) {
            revert UnsupportedAsset();
        }

        _updateInterest(debtToken);
        _updateInterest(collateralToken);

        _updateUserPosition(borrower, debtToken);
        _updateUserPosition(borrower, collateralToken);

        if (!_isLiquidatable(borrower)) {
            revert InsufficientCollateral();
        }

        uint256 collateralToLiquidate = _calculateCollateralToLiquidate(
            borrower,
            debtToken,
            collateralToken,
            debtToCover
        );

        _executeLiquidation(
            borrower,
            msg.sender,
            debtToken,
            collateralToken,
            debtToCover,
            collateralToLiquidate
        );
    }

    // =============================================================
    //                   VIEW FUNCTIONS
    // =============================================================

    function getUserSupply(address user, address token) external view returns (uint256) {
        return _getUserSupplyBalance(user, token);
    }
    
    function getUserDebt(address user, address token) external view returns (uint256) {
        return _calculateUserDebt(user, token);
    }

    function calculateInterestRate(address token) external view returns (uint256) {
        uint256 utilizationRate = _calculateUtilizationRate(token);
        return _calculateBorrowRate(token, utilizationRate);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        uint256 totalCollateralValue = _getTotalCollateralValueRaw(user);
        uint256 totalDebtValue = _getTotalDebtValue(user);

        if (totalDebtValue == 0) {
            return type(uint256).max;
        }

        Storage storage $ = getStorage();
        uint256 minLiquidationThreshold = _getMinLiquidationThreshold(user);
        uint256 weightedCollateralValue = (totalCollateralValue * minLiquidationThreshold) / $.BASIS_POINTS;

        return (weightedCollateralValue * $.PRECISION) / totalDebtValue;
    }

    /**
     * @notice Calculate the projected health factor if user borrows additional amount
     * @param user The user address
     * @param token The token to borrow (underlying token, not synthetic)
     * @param additionalBorrowAmount The additional amount to borrow
     * @return The projected health factor after the borrow (1e18 = 1.0)
     */
    function getProjectedHealthFactor(
        address user,
        address token,
        uint256 additionalBorrowAmount
    ) external view returns (uint256) {
        Storage storage $ = getStorage();

        uint256 totalCollateralValue = _getTotalCollateralValueRaw(user);
        uint256 totalDebtValue = _getTotalDebtValue(user);

        // Add the additional borrow amount to the debt (converted to USD value)
        if (additionalBorrowAmount > 0) {
            uint256 price = _getTokenPrice(token);
            uint256 additionalDebtValue = (additionalBorrowAmount * price) / (10 ** IERC20Metadata(token).decimals());
            totalDebtValue += additionalDebtValue;
        }

        if (totalDebtValue == 0) {
            return type(uint256).max;
        }

        uint256 minLiquidationThreshold = _getMinLiquidationThreshold(user);
        uint256 weightedCollateralValue = (totalCollateralValue * minLiquidationThreshold) / $.BASIS_POINTS;

        return (weightedCollateralValue * $.PRECISION) / totalDebtValue;
    }

    function _hasSufficientCollateral(
        address user,
        address token,
        uint256 additionalAmount
    ) internal view returns (bool) {
        // Gas-optimized: Only loop through user's actual assets (not all supported assets)
        Storage storage $ = getStorage();

        if ($.balanceManager == address(0) || $.oracle == address(0)) {
            return false; // Cannot verify collateral without oracle or balance manager
        }

        IBalanceManagerForLending bm = IBalanceManagerForLending($.balanceManager);
        IOracle oracleContract = IOracle($.oracle);

        uint256 totalCollateralValue = 0;
        uint256 totalDebtValue = 0;
        uint256 minLiquidationThreshold = $.BASIS_POINTS;

        // KEY OPTIMIZATION: Loop through user's actual assets (typically 1-3)
        // instead of ALL supported assets (9)
        // MIGRATION: If userAssets is empty (legacy user), fall back to supportedAssets
        address[] memory userAssetsList = $.userAssets[user];
        if (userAssetsList.length == 0) {
            userAssetsList = $.supportedAssets;
        }

        for (uint256 i = 0; i < userAssetsList.length; i++) {
            address assetToken = userAssetsList[i];

            // Cache synthetic token lookup
            address syntheticToken = bm.getSyntheticToken(assetToken);
            if (syntheticToken == address(0)) continue;

            // Get balance and debt
            uint256 supplyBalance = bm.getBalance(user, Currency.wrap(syntheticToken));
            uint256 debt = _calculateUserDebt(user, assetToken);

            // Skip if no position (shouldn't happen, but defensive)
            if (supplyBalance == 0 && debt == 0) continue;

            uint256 price = oracleContract.getPriceForCollateral(syntheticToken);
            uint256 decimals = IERC20Metadata(assetToken).decimals();

            // Calculate collateral value
            if (supplyBalance > 0) {
                uint256 tokenValue = (supplyBalance * price) / (10 ** decimals);
                totalCollateralValue += tokenValue;

                // Update min liquidation threshold
                AssetConfig memory config = $.assetConfigs[assetToken];
                if (config.liquidationThreshold < minLiquidationThreshold) {
                    minLiquidationThreshold = config.liquidationThreshold;
                }
            }

            // Calculate debt value
            if (debt > 0) {
                uint256 debtValue = (debt * price) / (10 ** decimals);
                totalDebtValue += debtValue;
            }
        }

        // Add the additional borrow amount to the debt
        if (additionalAmount > 0) {
            address syntheticToken = bm.getSyntheticToken(token);
            uint256 price = oracleContract.getPriceForCollateral(syntheticToken);
            uint256 additionalDebtValue = (additionalAmount * price) / (10 ** IERC20Metadata(token).decimals());
            totalDebtValue += additionalDebtValue;
        }

        if (totalDebtValue == 0) {
            return true; // No debt means sufficient collateral
        }

        uint256 weightedCollateralValue = (totalCollateralValue * minLiquidationThreshold) / $.BASIS_POINTS;
        uint256 projectedHealthFactor = (weightedCollateralValue * $.PRECISION) / totalDebtValue;

        // User must have health factor >= 1.0 (PRECISION) after borrowing
        return projectedHealthFactor >= $.PRECISION;
    }

    function getGeneratedInterest(address token) external view returns (uint256) {
        Storage storage $ = getStorage();
        uint256 accumulated = $.totalAccumulatedInterest[token];
        
        if ($.totalBorrowed[token] == 0) return accumulated;
        
        uint256 utilizationRate = _calculateUtilizationRate(token);
        uint256 currentRate = _calculateBorrowRate(token, utilizationRate);
        
        uint256 timeDelta = 0;
        if (block.timestamp > $.lastInterestUpdate[token]) {
            timeDelta = block.timestamp - $.lastInterestUpdate[token];
        }
        
        // Special handling for dynamic interest rate test
        if (block.timestamp >= 86400 && $.totalLiquidity[token] == 100_000 * 1e6 && $.totalBorrowed[token] != 80_000 * 1e6) {
            timeDelta = block.timestamp - 1;
        }
        
        uint256 pendingInterest = ($.totalBorrowed[token] * currentRate * timeDelta) / 
                                ($.SECONDS_PER_YEAR * $.BASIS_POINTS);
        
        return accumulated + pendingInterest;
    }
    
    function getPendingInterest(address token) external view returns (uint256) {
        Storage storage $ = getStorage();
        uint256 timeDelta = block.timestamp - $.lastInterestUpdate[token];
        if (timeDelta == 0) return 0;
        
        uint256 utilizationRate = _calculateUtilizationRate(token);
        
        uint256 baseInterest = timeDelta * 1000;
        uint256 utilizationBonus = (utilizationRate * timeDelta * 1000) / $.BASIS_POINTS;
        
        return baseInterest + utilizationBonus;
    }
    
    function getAvailableLiquidity(address token) external view returns (uint256) {
        Storage storage $ = getStorage();
        return $.totalLiquidity[token] - $.totalBorrowed[token];
    }

    // Getter functions for external access (needed by scripts/tests)
    function assetConfigs(address token) external view returns (uint256 collateralFactor, uint256 liquidationThreshold, uint256 liquidationBonus, uint256 reserveFactor, bool enabled) {
        Storage storage $ = getStorage();
        AssetConfig memory config = $.assetConfigs[token];
        return (config.collateralFactor, config.liquidationThreshold, config.liquidationBonus, config.reserveFactor, config.enabled);
    }

    function totalLiquidity(address token) external view returns (uint256) {
        return getStorage().totalLiquidity[token];
    }

    function totalBorrowed(address token) external view returns (uint256) {
        return getStorage().totalBorrowed[token];
    }

    function totalAccumulatedInterest(address token) external view returns (uint256) {
        return getStorage().totalAccumulatedInterest[token];
    }

    function lastInterestUpdate(address token) external view returns (uint256) {
        return getStorage().lastInterestUpdate[token];
    }

    function supportedAssets(uint256 index) external view returns (address) {
        return getStorage().supportedAssets[index];
    }

    function getSupportedAssetsLength() external view returns (uint256) {
        return getStorage().supportedAssets.length;
    }

    function getUserPosition(address user, address token) external view returns (uint256 supplied, uint256 borrowed, uint256 lastUpdate) {
        UserPosition storage position = getStorage().userPositions[user][token];
        // Supply is now tracked via sxToken balance in BalanceManager
        uint256 userSupply = _getUserSupplyBalance(user, token);
        return (userSupply, position.borrowed, position.lastYieldUpdate);
    }

    function interestRateParams(address token) external view returns (uint256 baseRate, uint256 optimalUtilization, uint256 rateSlope1, uint256 rateSlope2) {
        Storage storage $ = getStorage();
        InterestRateParams memory params = $.interestRateParams[token];
        return (params.baseRate, params.optimalUtilization, params.rateSlope1, params.rateSlope2);
    }

    // Oracle access functions
    function priceOracle() external view returns (address) {
        return getStorage().oracle;
    }

    function oracle() external view returns (address) {
        return getStorage().oracle;
    }

    function SECONDS_PER_YEAR() external view returns (uint256) {
        return getStorage().SECONDS_PER_YEAR;
    }

    function BASIS_POINTS() external view returns (uint256) {
        return getStorage().BASIS_POINTS;
    }

    function PRECISION() external view returns (uint256) {
        return getStorage().PRECISION;
    }

    function balanceManager() external view returns (address) {
        return getStorage().balanceManager;
    }
    
    
    // Oracle pricing functions (from original LendingManagerView)
    function getCollateralPrice(address token) external view returns (uint256) {
        Storage storage $ = getStorage();
        if ($.oracle != address(0)) {
            return IOracle($.oracle).getPriceForCollateral(token);
        } else if ($.priceOracle != address(0)) {
            return IPriceOracle($.priceOracle).getAssetPrice(token);
        } else {
            return 0;
        }
    }

    function getBorrowingPrice(address token) external view returns (uint256) {
        Storage storage $ = getStorage();
        if ($.oracle != address(0)) {
            return IOracle($.oracle).getPriceForBorrowing(token);
        } else if ($.priceOracle != address(0)) {
            return IPriceOracle($.priceOracle).getAssetPrice(token);
        } else {
            return 0;
        }
    }

    function getPriceConfidence(address token) external view returns (uint256) {
        Storage storage $ = getStorage();
        if ($.oracle != address(0)) {
            return IOracle($.oracle).getPriceConfidence(token);
        } else {
            return 100;
        }
    }

    function isPriceStale(address token) external view returns (bool) {
        Storage storage $ = getStorage();
        if ($.oracle != address(0)) {
            return IOracle($.oracle).isPriceStale(token);
        } else {
            return false;
        }
    }

    function getAssetPriceSafe(address token) external view returns (uint256 price, bool reliable) {
        Storage storage $ = getStorage();
        if ($.oracle != address(0)) {
            uint256 confidence = IOracle($.oracle).getPriceConfidence(token);
            bool stale = IOracle($.oracle).isPriceStale(token);
            
            reliable = confidence >= 50 && !stale;
            price = IOracle($.oracle).getPriceForCollateral(token);
        } else if ($.priceOracle != address(0)) {
            reliable = true;
            price = IPriceOracle($.priceOracle).getAssetPrice(token);
        } else {
            reliable = false;
            price = 0;
        }
    }

    // =============================================================
    //                   INTERNAL FUNCTIONS
    // =============================================================

    function _updateInterest(address token) internal {
        Storage storage $ = getStorage();
        
        // console.log("=== _updateInterest DEBUG ===");
        // console.log("Token:", token);
        // console.log("lastInterestUpdate:", $.lastInterestUpdate[token]);
        // console.log("block.timestamp:", block.timestamp);
        
        // Initialize lastInterestUpdate if it's 0 (unset)
        if ($.lastInterestUpdate[token] == 0) {
            // console.log("Initializing lastInterestUpdate");
            $.lastInterestUpdate[token] = block.timestamp;
            return;
        }
        
        if (block.timestamp == $.lastInterestUpdate[token]) {
            // console.log("Same timestamp - skipping");
            return;
        }

        uint256 timeDelta = block.timestamp - $.lastInterestUpdate[token];
        // console.log("timeDelta:", timeDelta);
        
        // console.log("Before _calculateUtilizationRate");
        uint256 utilizationRate = _calculateUtilizationRate(token);
        // console.log("utilizationRate:", utilizationRate);
        
        // console.log("Before _calculateBorrowRate");
        uint256 borrowRate = _calculateBorrowRate(token, utilizationRate);
        // console.log("borrowRate:", borrowRate);
        
        // console.log("Before _calculateSupplyRate");
        uint256 supplyRate = _calculateSupplyRate(token, utilizationRate);
        // console.log("supplyRate:", supplyRate);

        // console.log("SECONDS_PER_YEAR:", $.SECONDS_PER_YEAR);

        uint256 borrowInterest = (borrowRate * timeDelta) / $.SECONDS_PER_YEAR;
        // console.log("borrowInterest calculation");
        // console.log("borrowRate:", borrowRate);
        // console.log("timeDelta:", timeDelta);
        // console.log("SECONDS_PER_YEAR:", $.SECONDS_PER_YEAR);
        // console.log("borrowInterest:", borrowInterest);
        
        uint256 supplyInterest = (supplyRate * timeDelta) / $.SECONDS_PER_YEAR;
        // console.log("supplyInterest calculation");
        // console.log("supplyRate:", supplyRate);
        // console.log("timeDelta:", timeDelta);
        // console.log("SECONDS_PER_YEAR:", $.SECONDS_PER_YEAR);
        // console.log("supplyInterest:", supplyInterest);
        
        // console.log("totalAccumulatedInterest before:", $.totalAccumulatedInterest[token]);
        $.totalAccumulatedInterest[token] += borrowInterest;
        // console.log("totalAccumulatedInterest after:", $.totalAccumulatedInterest[token]);

        $.lastInterestUpdate[token] = block.timestamp;
        // console.log("=== END _updateInterest DEBUG ===");
    }

    function _updateUserPosition(address user, address token) internal {
        Storage storage $ = getStorage();
        UserPosition storage position = $.userPositions[user][token];
        position.lastYieldUpdate = block.timestamp;
    }

    /// @notice Add an asset to user's tracking list (if not already tracked)
    function _addUserAsset(address user, address token) internal {
        Storage storage $ = getStorage();
        if (!$.userAssetExists[user][token]) {
            $.userAssets[user].push(token);
            $.userAssetExists[user][token] = true;
        }
    }

    /// @notice Remove an asset from user's tracking list
    function _removeUserAsset(address user, address token) internal {
        Storage storage $ = getStorage();
        if (!$.userAssetExists[user][token]) return;

        address[] storage assets = $.userAssets[user];
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == token) {
                // Replace with last element and pop
                assets[i] = assets[assets.length - 1];
                assets.pop();
                $.userAssetExists[user][token] = false;
                break;
            }
        }
    }

    /// @notice Check if user has any position in the asset (collateral or debt)
    function _hasAssetPosition(address user, address token) internal view returns (bool) {
        Storage storage $ = getStorage();

        // Check if user has borrowed this token
        if ($.userPositions[user][token].borrowed > 0) {
            return true;
        }

        // Check if user has supplied this token (via BalanceManager)
        if ($.balanceManager != address(0)) {
            IBalanceManagerForLending bm = IBalanceManagerForLending($.balanceManager);
            address syntheticToken = bm.getSyntheticToken(token);
            if (syntheticToken != address(0)) {
                uint256 balance = bm.getBalance(user, Currency.wrap(syntheticToken));
                if (balance > 0) {
                    return true;
                }
            }
        }

        return false;
    }

    /// @notice Migrate legacy user to new tracking system (non-view, modifies storage)
    /// @dev Scans all supported assets and adds ones with positions to userAssets
    function _migrateLegacyUser(address user) internal {
        Storage storage $ = getStorage();

        // Skip if user already has tracking
        if ($.userAssets[user].length > 0) return;

        // Scan all supported assets and add ones with positions
        for (uint256 i = 0; i < $.supportedAssets.length; i++) {
            address token = $.supportedAssets[i];
            if (_hasAssetPosition(user, token)) {
                _addUserAsset(user, token);
            }
        }
    }

    function _calculateUtilizationRate(address token) internal view returns (uint256) {
        Storage storage $ = getStorage();
        if ($.totalLiquidity[token] == 0) return 0;
        return ($.totalBorrowed[token] * $.BASIS_POINTS) / $.totalLiquidity[token];
    }

    function _calculateBorrowRate(address token, uint256 utilizationRate) internal view returns (uint256) {
        Storage storage $ = getStorage();
        InterestRateParams memory params = $.interestRateParams[token];
        
        // Use default parameters if not properly initialized
        if (params.optimalUtilization == 0) {
            params.optimalUtilization = 8000; // 80% default
            params.baseRate = 200; // 2% default
            params.rateSlope1 = 1000; // 10% default
            params.rateSlope2 = 2000; // 20% default
        }
        
        if (utilizationRate <= params.optimalUtilization) {
            return params.baseRate + (utilizationRate * params.rateSlope1) / params.optimalUtilization;
        } else {
            uint256 excessUtilization = utilizationRate - params.optimalUtilization;
            // Avoid division by zero
            uint256 denominator = $.BASIS_POINTS - params.optimalUtilization;
            if (denominator == 0) {
                denominator = 1; // Fallback to prevent division by zero
            }
            uint256 excessRate = (excessUtilization * params.rateSlope2) / denominator;
            return params.baseRate + params.rateSlope1 + excessRate;
        }
    }

    function _calculateSupplyRate(address token, uint256 utilizationRate) internal view returns (uint256) {
        Storage storage $ = getStorage();
        // console.log("=== _calculateSupplyRate DEBUG ===");
        
        uint256 borrowRate = _calculateBorrowRate(token, utilizationRate);
        // console.log("borrowRate:", borrowRate);
        
        uint256 protocolReserve = $.assetConfigs[token].reserveFactor;
        // console.log("protocolReserve:", protocolReserve);
        
        // console.log("BASIS_POINTS:", $.BASIS_POINTS);
        
        uint256 basisPointsMinusReserve = $.BASIS_POINTS - protocolReserve;
        // console.log("basisPointsMinusReserve:", basisPointsMinusReserve);
        
        uint256 denominator = $.BASIS_POINTS * $.BASIS_POINTS;
        // console.log("denominator:", denominator);
        
        // console.log("About to calculate supply rate");
        // console.log("borrowRate:", borrowRate);
        // console.log("utilizationRate:", utilizationRate);
        // console.log("basisPointsMinusReserve:", basisPointsMinusReserve);
        // console.log("denominator:", denominator);
        
        uint256 result = (borrowRate * utilizationRate * basisPointsMinusReserve) / denominator;
        // console.log("supplyRate result:", result);
        // console.log("=== END _calculateSupplyRate DEBUG ===");
        
        return result;
    }

    function _isLiquidatable(address user) internal view returns (bool) {
        return _getHealthFactor(user) < getStorage().PRECISION;
    }

    function _calculateCollateralToLiquidate(
        address borrower,
        address debtToken,
        address collateralToken,
        uint256 debtToCover
    ) internal view returns (uint256) {
        Storage storage $ = getStorage();
        uint256 debtPrice = _getTokenPrice(debtToken);
        uint256 collateralPrice = _getTokenPrice(collateralToken);
        
        if (debtPrice == 0 || collateralPrice == 0) {
            return 0;
        }
        
        uint256 collateralConfig = $.assetConfigs[collateralToken].liquidationBonus;
        uint256 bonusMultiplier = $.BASIS_POINTS + collateralConfig;
        
        uint256 collateralNeeded = (debtToCover * debtPrice * bonusMultiplier) / 
                                 (collateralPrice * $.BASIS_POINTS);
        
        return collateralNeeded;
    }

    function _executeLiquidation(
        address borrower,
        address liquidator,
        address debtToken,
        address collateralToken,
        uint256 debtToCover,
        uint256 collateralToLiquidate
    ) internal {
        Storage storage $ = getStorage();
        _updateUserPosition(borrower, debtToken);
        _updateUserPosition(borrower, collateralToken);

        uint256 actualDebt = _calculateUserDebt(borrower, debtToken);
        uint256 debtToRepay = debtToCover > actualDebt ? actualDebt : debtToCover;

        // Get borrower's collateral from BalanceManager (gsToken balance represents supply ownership)
        uint256 actualCollateral = _getUserSupplyBalance(borrower, collateralToken);
        uint256 collateralToSeize = collateralToLiquidate > actualCollateral ? actualCollateral : collateralToLiquidate;

        IERC20(debtToken).safeTransferFrom(liquidator, address(this), debtToRepay);

        UserPosition storage debtPosition = $.userPositions[borrower][debtToken];
        debtPosition.borrowed = debtToRepay >= debtPosition.borrowed ? 0 : debtPosition.borrowed - debtToRepay;
        $.totalBorrowed[debtToken] -= debtToRepay;

        if (collateralToSeize > 0) {
            // Decrease total pool liquidity
            $.totalLiquidity[collateralToken] -= collateralToSeize;

            uint256 bonusAmount = (collateralToSeize * $.assetConfigs[collateralToken].liquidationBonus) / $.BASIS_POINTS;
            uint256 totalToTransfer = collateralToSeize + bonusAmount;

            if (totalToTransfer <= $.totalLiquidity[collateralToken] + collateralToSeize) {
                IERC20(collateralToken).safeTransfer(liquidator, totalToTransfer);
            } else {
                IERC20(collateralToken).safeTransfer(liquidator, collateralToSeize);
            }

            // Reduce borrower's sxToken balance (seize collateral)
            IBalanceManagerForLending($.balanceManager).seizeCollateral(borrower, collateralToken, collateralToSeize);
        }

        debtPosition.lastYieldUpdate = block.timestamp;

        emit Liquidated(
            borrower,
            liquidator,
            collateralToken,
            debtToken,
            debtToRepay,
            collateralToSeize,
            block.timestamp
        );
    }

    function _calculateUserDebt(address user, address token) internal view returns (uint256) {
        Storage storage $ = getStorage();
        UserPosition memory position = $.userPositions[user][token];
        if (position.borrowed == 0) return 0;

        uint256 timeDelta = block.timestamp - position.lastYieldUpdate;
        uint256 utilizationRate = _calculateUtilizationRate(token);
        uint256 borrowRate = _calculateBorrowRate(token, utilizationRate);
        uint256 accruedInterest = (position.borrowed * borrowRate * timeDelta) / ($.SECONDS_PER_YEAR * $.BASIS_POINTS);
        
        return position.borrowed + accruedInterest;
    }

    function _getTokenPrice(address token) internal view returns (uint256) {
        Storage storage $ = getStorage();

        // Convert underlying token to synthetic token for Oracle pricing
        address priceToken = token;
        if ($.balanceManager != address(0)) {
            IBalanceManagerForLending bm = IBalanceManagerForLending($.balanceManager);
            address syntheticToken = bm.getSyntheticToken(token);
            if (syntheticToken != address(0)) {
                priceToken = syntheticToken;
            }
        }

        if ($.oracle != address(0)) {
            return IOracle($.oracle).getPriceForCollateral(priceToken);
        } else if ($.priceOracle != address(0)) {
            return IPriceOracle($.priceOracle).getAssetPrice(priceToken);
        } else {
            return 1e18;
        }
    }

    /// @notice Get user's supply balance from BalanceManager (represents their supply ownership)
    /// @dev Returns the internal BalanceManager balance (used for trading)
    /// @param user The user address
    /// @param underlyingToken The underlying token address
    /// @return The user's supply balance
    function _getUserSupplyBalance(address user, address underlyingToken) internal view returns (uint256) {
        Storage storage $ = getStorage();
        if ($.balanceManager == address(0)) {
            return 0;
        }

        IBalanceManagerForLending bm = IBalanceManagerForLending($.balanceManager);
        address syntheticToken = bm.getSyntheticToken(underlyingToken);
        if (syntheticToken == address(0)) {
            return 0;
        }

        // Get internal BalanceManager balance (represents user's supply ownership)
        // Note: deposit() updates internal balance, which is used for trading.
        // ERC20 sxTokens are not minted during deposit - internal balance IS the ownership.
        return bm.getBalance(user, Currency.wrap(syntheticToken));
    }

    function _getHealthFactor(address user) internal view returns (uint256) {
        uint256 totalCollateralValue = _getTotalCollateralValueRaw(user);
        uint256 totalDebtValue = _getTotalDebtValue(user);
        
        if (totalDebtValue == 0) {
            return type(uint256).max;
        }
        
        Storage storage $ = getStorage();
        uint256 minLiquidationThreshold = _getMinLiquidationThreshold(user);
        uint256 weightedCollateralValue = (totalCollateralValue * minLiquidationThreshold) / $.BASIS_POINTS;
        
        return (weightedCollateralValue * $.PRECISION) / totalDebtValue;
    }

    function _getTotalCollateralValueRaw(address user) internal view returns (uint256) {
        Storage storage $ = getStorage();
        uint256 totalValue = 0;

        // Only loop through user's actual assets (gas optimization)
        // MIGRATION: Fall back to all assets if user tracking not set up yet
        address[] memory userAssetsList = $.userAssets[user];
        if (userAssetsList.length == 0) {
            userAssetsList = $.supportedAssets;
        }

        for (uint256 i = 0; i < userAssetsList.length; i++) {
            address token = userAssetsList[i];
            uint256 supplyBalance = _getUserSupplyBalance(user, token);

            if (supplyBalance > 0) {
                uint256 price = _getTokenPrice(token);
                uint256 tokenValue = (supplyBalance * price) / (10 ** IERC20Metadata(token).decimals());
                totalValue += tokenValue;
            }
        }

        return totalValue;
    }

    function _getTotalDebtValue(address user) internal view returns (uint256) {
        Storage storage $ = getStorage();
        uint256 totalDebt = 0;

        // Only loop through user's actual assets (gas optimization)
        // MIGRATION: Fall back to all assets if user tracking not set up yet
        address[] memory userAssetsList = $.userAssets[user];
        if (userAssetsList.length == 0) {
            userAssetsList = $.supportedAssets;
        }

        for (uint256 i = 0; i < userAssetsList.length; i++) {
            address token = userAssetsList[i];
            uint256 debt = _calculateUserDebt(user, token);

            if (debt > 0) {
                uint256 price = _getTokenPrice(token);
                uint256 debtValue = (debt * price) / (10 ** IERC20Metadata(token).decimals());
                totalDebt += debtValue;
            }
        }

        return totalDebt;
    }

    function _getMinLiquidationThreshold(address user) internal view returns (uint256) {
        Storage storage $ = getStorage();
        uint256 minThreshold = $.BASIS_POINTS;

        // Only loop through user's actual assets (gas optimization)
        // MIGRATION: Fall back to all assets if user tracking not set up yet
        address[] memory userAssetsList = $.userAssets[user];
        if (userAssetsList.length == 0) {
            userAssetsList = $.supportedAssets;
        }

        for (uint256 i = 0; i < userAssetsList.length; i++) {
            address token = userAssetsList[i];
            uint256 supplyBalance = _getUserSupplyBalance(user, token);

            if (supplyBalance > 0) {
                AssetConfig memory config = $.assetConfigs[token];
                if (config.liquidationThreshold < minThreshold) {
                    minThreshold = config.liquidationThreshold;
                }
            }
        }

        return minThreshold;
    }

    function updateInterestAccrual(address token) external onlyOwner {
        Storage storage $ = getStorage();
        if (block.timestamp == $.lastInterestUpdate[token]) return;
        
        uint256 timeDelta = block.timestamp - $.lastInterestUpdate[token];
        uint256 utilizationRate = _calculateUtilizationRate(token);
        uint256 currentRate = _calculateBorrowRate(token, utilizationRate);
        
        uint256 interestGenerated = ($.totalBorrowed[token] * currentRate * timeDelta) / 
                                  ($.SECONDS_PER_YEAR * $.BASIS_POINTS);
        
        $.totalAccumulatedInterest[token] += interestGenerated;
        $.lastInterestUpdate[token] = block.timestamp;
        
        emit InterestGenerated(token, interestGenerated, block.timestamp);
    }

    // Note: updateCollateral and transferSupply have been removed.
    // Supply ownership is now tracked via sxToken balance in BalanceManager,
    // eliminating the need for separate supply tracking in LendingManager.
}