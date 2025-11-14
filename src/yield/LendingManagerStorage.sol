// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title LendingManagerStorage
 * @dev Shared storage layout and events for LendingManager system using diamond storage pattern
 */
abstract contract LendingManagerStorage {
    // keccak256(abi.encode(uint256(keccak256("scalex.clob.storage.lendingmanager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0xa0938c47b5c654ca88fd5f46a35251d66e96b0e70f06871f4be1ef4fd259f100;

    // Structs defined outside of Storage struct
    struct AssetConfig {
        uint256 collateralFactor;      // LTV in basis points (8000 = 80%)
        uint256 liquidationThreshold; // Liquidation threshold in basis points (8500 = 85%)
        uint256 liquidationBonus;     // Bonus for liquidators in basis points (500 = 5%)
        uint256 reserveFactor;        // Reserve factor for protocol in basis points (1000 = 10%)
        bool enabled;
    }

    struct UserPosition {
        uint256 supplied;           // Total supplied amount
        uint256 borrowed;           // Total borrowed amount
        uint256 lastYieldUpdate;   // Last time yield was calculated for user
    }

    struct InterestRateParams {
        uint256 baseRate;           // Base interest rate in basis points (200 = 2%)
        uint256 optimalUtilization; // Target utilization in basis points (8000 = 80%)
        uint256 rateSlope1;         // Rate slope below optimal utilization
        uint256 rateSlope2;         // Rate slope above optimal utilization
    }

    struct Storage {
        // Main storage variables
        mapping(address => AssetConfig) assetConfigs;
        mapping(address => uint256) totalLiquidity;     // token -> total supplied
        mapping(address => uint256) totalBorrowed;     // token -> total borrowed
        mapping(address => uint256) totalAccumulatedInterest; // token -> total interest generated
        mapping(address => mapping(address => UserPosition)) userPositions; // user -> token -> position

        // Interest rate parameters
        mapping(address => InterestRateParams) interestRateParams;
        mapping(address => uint256) lastInterestUpdate; // token -> last update timestamp

        // Protocol data
        address priceOracle; // Legacy oracle (deprecated)
        address oracle; // New TWAP oracle
        address balanceManager; // Only contract that can call supply/withdraw
        address[] supportedAssets;
        
        // Constants
        uint256 SECONDS_PER_YEAR;
        uint256 BASIS_POINTS;
        uint256 PRECISION;
    }

    // Events
    event LiquidityDeposited(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    event LiquidityWithdrawn(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 yield,
        uint256 timestamp
    );
    event Borrowed(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    event InterestGenerated(
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    event GeneratedInterestWithdrawn(
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    event Repaid(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 interest,
        uint256 timestamp
    );
    event Liquidated(
        address indexed borrower,
        address indexed liquidator,
        address indexed collateralToken,
        address debtToken,
        uint256 debtToCover,
        uint256 liquidatedCollateral,
        uint256 timestamp
    );
    event CollateralUpdated(
        address indexed user,
        address indexed syntheticToken,
        uint256 amount
    );
    event AssetConfigured(
        address indexed token,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor
    );
    event InterestRateParamsSet(
        address indexed token,
        uint256 baseRate,
        uint256 optimalUtilization,
        uint256 rateSlope1,
        uint256 rateSlope2
    );
    event BalanceManagerSet(address indexed balanceManager);

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }

    // Initialize constants
    function _initializeConstants() internal {
        Storage storage $ = getStorage();
        if ($.SECONDS_PER_YEAR == 0) {
            $.SECONDS_PER_YEAR = 31536000;
            $.BASIS_POINTS = 10000;
            $.PRECISION = 1e18;
        }
    }

    // Internal helper functions
    function _getTokenDecimals(address token) internal view returns (uint256) {
        try IERC20Metadata(token).decimals() returns (uint8 decimals) {
            return decimals;
        } catch {
            return 18;
        }
    }
}