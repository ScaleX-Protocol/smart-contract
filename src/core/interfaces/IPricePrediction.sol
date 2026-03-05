// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";

interface IPricePrediction {
    // =============================================================
    //                           ENUMS
    // =============================================================

    enum MarketType {
        Directional, // UP or DOWN vs opening TWAP
        Absolute     // Above or Below a fixed strike price
    }

    enum MarketStatus {
        Open,
        SettlementRequested,
        Settled,
        Cancelled
    }

    // For Directional: UP = true, DOWN = false
    // For Absolute: Above = true, Below = false
    // (stored as bool `predictedUp` in Position)

    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct Market {
        uint64 id;
        MarketType marketType;
        MarketStatus status;
        address baseToken;       // e.g., WETH address (for Oracle lookup)
        uint256 strikePrice;     // Only used for Absolute markets (18-decimal price)
        uint256 openingTwap;     // TWAP captured at market creation (Directional baseline)
        uint256 startTime;
        uint256 endTime;
        uint256 totalUp;         // Total staked on UP / Above
        uint256 totalDown;       // Total staked on DOWN / Below
        bool outcome;            // true = UP/Above won; valid only when Settled
    }

    struct Position {
        uint256 stakeUp;         // Amount staked on UP/Above
        uint256 stakeDown;       // Amount staked on DOWN/Below
        bool claimed;
    }

    // =============================================================
    //                           EVENTS
    // =============================================================

    event MarketCreated(
        uint64 indexed marketId,
        MarketType marketType,
        address indexed baseToken,
        uint256 strikePrice,
        uint256 openingTwap,
        uint256 startTime,
        uint256 endTime
    );

    event Predicted(
        uint64 indexed marketId,
        address indexed user,
        bool predictedUp,
        uint256 amount
    );

    event SettlementRequested(
        uint64 indexed marketId,
        address indexed baseToken,
        uint256 strikePrice,
        uint256 openingTwap
    );

    event MarketSettled(
        uint64 indexed marketId,
        bool outcome,
        uint256 totalUp,
        uint256 totalDown,
        uint256 protocolFee
    );

    event Claimed(
        uint64 indexed marketId,
        address indexed user,
        uint256 payout
    );

    event MarketCancelled(uint64 indexed marketId, string reason);

    event ProtocolFeeWithdrawn(address indexed to, uint256 amount);

    // =============================================================
    //                       ADMIN FUNCTIONS
    // =============================================================

    function createMarket(
        address baseToken,
        MarketType marketType,
        uint256 strikePrice,
        uint256 duration
    ) external returns (uint64 marketId);

    function cancelMarket(uint64 marketId) external;

    function withdrawFees(address to) external;

    function setProtocolFeeBps(uint256 feeBps) external;

    function setMinStakeAmount(uint256 minStake) external;

    function setMaxMarketTvl(uint256 maxTvl) external;

    function setKeystoneForwarder(address forwarder) external;

    // =============================================================
    //                       USER FUNCTIONS
    // =============================================================

    function predict(uint64 marketId, bool predictUp, uint256 amount) external;

    function predictFor(address user, uint64 marketId, bool predictUp, uint256 amount) external;

    function requestSettlement(uint64 marketId) external;

    function claim(uint64 marketId) external;

    function claimFor(address user, uint64 marketId) external;

    function claimBatch(uint64[] calldata marketIds) external;

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    function getMarket(uint64 marketId) external view returns (Market memory);

    function getPosition(uint64 marketId, address user) external view returns (Position memory);

    function getClaimableAmount(uint64 marketId, address user) external view returns (uint256);
}
