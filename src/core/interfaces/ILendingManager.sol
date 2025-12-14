// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title ILendingManager
 * @dev Interface for lending protocol management
 */
interface ILendingManager {
    function depositLiquidity(address token, uint256 amount, address user) external;
    function supplyForUser(address recipient, address token, uint256 amount) external;
    function withdrawLiquidity(address token, uint256 amount, address user) external returns (uint256, uint256);
    function withdraw(address token, uint256 amount) external;
    function withdrawGeneratedInterest(address token, uint256 amount) external;
    function updateInterestAccrual(address token) external;
    function updateCollateral(address user, address syntheticToken, uint256 amount) external;
    function borrow(address token, uint256 amount) external;
    function repay(address token, uint256 amount) external;
    function borrowForUser(address user, address token, uint256 amount) external;
    function repayForUser(address user, address token, uint256 amount) external;
    function repayFromBalance(address user, address token, uint256 amount) external;
    function liquidate(address borrower, address debtToken, address collateralToken, uint256 debtToCover) external;
    function getUserLiquidity(address user, address token) external view returns (uint256);
    function getUserDebt(address user, address token) external view returns (uint256);
    function getUserSupply(address user, address token) external view returns (uint256);
    function calculateInterestRate(address token) external view returns (uint256);
    function getGeneratedInterest(address token) external view returns (uint256);
    function configureAsset(address token, uint256 collateralFactor, uint256 liquidationThreshold, uint256 liquidationBonus, uint256 reserveFactor) external;
    function setInterestRateParams(address token, uint256 baseRate, uint256 optimalUtilization, uint256 rateSlope1, uint256 rateSlope2) external;
    function setOracle(address _oracle) external;
    
    // Additional view functions
    function getHealthFactor(address user) external view returns (uint256);
    function getAvailableLiquidity(address token) external view returns (uint256);
    function calculateYield(address user, address currency) external view returns (uint256);
}