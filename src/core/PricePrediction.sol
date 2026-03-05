// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IPricePrediction} from "./interfaces/IPricePrediction.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IReceiver} from "./interfaces/chainlink/IReceiver.sol";
import {PricePredictionStorage} from "./storages/PricePredictionStorage.sol";
import {Currency} from "./libraries/Currency.sol";

/// @title PricePrediction
/// @notice Yield-bearing binary price prediction markets settled via Chainlink CRE.
/// @dev Users stake sxUSDC (held in this contract's BalanceManager balance) on UP/DOWN
///      or Above/Below outcomes for a given asset's TWAP. Chainlink CRE reads Oracle.getTWAP
///      on-chain and submits a signed report via onReport(). Funds pool collectively while
///      staked (earning yield via BalanceManager's lending pool integration). Protocol fee is
///      collected on settlement; remaining balance is withdrawable by owner.
contract PricePrediction is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PricePredictionStorage,
    IPricePrediction,
    IReceiver
{
    // =============================================================
    //                        CONSTANTS
    // =============================================================

    uint256 public constant FEE_UNIT = 1_000_000; // Matches BalanceManager

    // =============================================================
    //                        CONSTRUCTOR
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // =============================================================
    //                        INITIALIZER
    // =============================================================

    function initialize(
        address _owner,
        address _balanceManager,
        address _oracle,
        address _keystoneForwarder,
        Currency _collateralCurrency,
        uint256 _protocolFeeBps,
        uint256 _minStakeAmount
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        $.balanceManager = _balanceManager;
        $.oracle = _oracle;
        $.keystoneForwarder = _keystoneForwarder;
        $.collateralCurrency = _collateralCurrency;
        $.protocolFeeBps = _protocolFeeBps;
        $.minStakeAmount = _minStakeAmount;
        $.nextMarketId = 1;
    }

    // =============================================================
    //                    ADMIN FUNCTIONS
    // =============================================================

    /// @notice Create a new prediction market. Admin only.
    /// @param baseToken The base asset address (e.g. WETH) for Oracle lookup.
    /// @param marketType Directional (UP/DOWN) or Absolute (Above/Below strike).
    /// @param strikePrice Required for Absolute markets (use 0 for Directional).
    /// @param duration Market duration in seconds (e.g. 300 = 5 minutes).
    function createMarket(
        address baseToken,
        MarketType marketType,
        uint256 strikePrice,
        uint256 duration
    ) external onlyOwner returns (uint64 marketId) {
        if (baseToken == address(0)) revert InvalidBaseToken();
        if (duration == 0) revert InvalidDuration();
        if (marketType == MarketType.Absolute && strikePrice == 0) revert StrikePriceRequired();

        IOracle oracle = IOracle(getStorage().oracle);
        if (!oracle.hasSufficientHistory(baseToken, duration)) revert InsufficientOracleHistory(baseToken);

        uint256 openingTwap = oracle.getTWAP(baseToken, duration);
        if (openingTwap == 0) revert OraclePriceUnavailable(baseToken);

        Storage storage $ = getStorage();
        marketId = $.nextMarketId++;

        Market storage market = $.markets[marketId];
        market.id = marketId;
        market.marketType = marketType;
        market.status = MarketStatus.Open;
        market.baseToken = baseToken;
        market.strikePrice = strikePrice;
        market.openingTwap = openingTwap;
        market.startTime = block.timestamp;
        market.endTime = block.timestamp + duration;

        emit MarketCreated(
            marketId,
            marketType,
            baseToken,
            strikePrice,
            openingTwap,
            block.timestamp,
            block.timestamp + duration
        );
    }

    /// @notice Cancel an open market (e.g. when one side has no participants).
    /// @dev Refund logic: users must call claim() after cancellation to recover stakes.
    function cancelMarket(uint64 marketId) external onlyOwner {
        Storage storage $ = getStorage();
        Market storage market = $.markets[marketId];

        if (market.status != MarketStatus.Open && market.status != MarketStatus.SettlementRequested) {
            revert MarketNotCancellable(marketId);
        }

        market.status = MarketStatus.Cancelled;

        string memory reason = market.totalUp == 0
            ? "No UP bets"
            : market.totalDown == 0
            ? "No DOWN bets"
            : "Admin cancelled";

        emit MarketCancelled(marketId, reason);
    }

    /// @notice Withdraw accumulated protocol fees and yield to a recipient.
    function withdrawFees(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert InvalidRecipient();
        Storage storage $ = getStorage();
        uint256 fees = $.accumulatedFees;
        if (fees == 0) revert NoFeesToWithdraw();

        $.accumulatedFees = 0;
        IBalanceManager($.balanceManager).transferFrom(address(this), to, $.collateralCurrency, fees);

        emit ProtocolFeeWithdrawn(to, fees);
    }

    function setProtocolFeeBps(uint256 feeBps) external onlyOwner {
        if (feeBps > 1000) revert FeeTooHigh(); // Max 10%
        getStorage().protocolFeeBps = feeBps;
    }

    function setMinStakeAmount(uint256 minStake) external onlyOwner {
        getStorage().minStakeAmount = minStake;
    }

    function setMaxMarketTvl(uint256 maxTvl) external onlyOwner {
        getStorage().maxMarketTvl = maxTvl;
    }

    function setAuthorizedRouter(address router, bool approved) external onlyOwner {
        getStorage().authorizedRouters[router] = approved;
    }

    function setKeystoneForwarder(address forwarder) external onlyOwner {
        if (forwarder == address(0)) revert InvalidForwarder();
        getStorage().keystoneForwarder = forwarder;
    }

    // =============================================================
    //                    USER FUNCTIONS
    // =============================================================

    /// @notice Stake sxUSDC on a market outcome.
    /// @param marketId The market to predict on.
    /// @param predictUp true = UP or Above; false = DOWN or Below.
    /// @param amount Amount of sxUSDC to stake (before feeMaker deduction).
    function predict(uint64 marketId, bool predictUp, uint256 amount) external nonReentrant {
        Storage storage $ = getStorage();
        Market storage market = $.markets[marketId];

        if (market.status != MarketStatus.Open) revert MarketNotOpen(marketId);
        if (block.timestamp >= market.endTime) revert MarketExpired(marketId);
        if (amount < $.minStakeAmount) revert StakeBelowMinimum(amount, $.minStakeAmount);

        uint256 maxTvl = $.maxMarketTvl;
        if (maxTvl > 0) {
            uint256 totalStake = market.totalUp + market.totalDown + amount;
            if (totalStake > maxTvl) revert MarketTvlExceeded(marketId, maxTvl);
        }

        // Transfer stake from user into this contract's BalanceManager balance.
        // feeMaker is charged by BalanceManager; we record the net received amount.
        IBalanceManager bm = IBalanceManager($.balanceManager);
        bm.transferFrom(msg.sender, address(this), $.collateralCurrency, amount);

        uint256 fee = amount * bm.feeMaker() / bm.getFeeUnit();
        uint256 received = amount - fee;

        Position storage position = $.positions[marketId][msg.sender];
        if (predictUp) {
            market.totalUp += received;
            position.stakeUp += received;
        } else {
            market.totalDown += received;
            position.stakeDown += received;
        }

        emit Predicted(marketId, msg.sender, predictUp, received);
    }

    /// @notice Stake sxUSDC on behalf of a user. Callable by the user themselves or an authorized router.
    function predictFor(address user, uint64 marketId, bool predictUp, uint256 amount) external nonReentrant {
        if (msg.sender != user && !getStorage().authorizedRouters[msg.sender]) revert UnauthorizedRouter(msg.sender);

        Storage storage $ = getStorage();
        Market storage market = $.markets[marketId];

        if (market.status != MarketStatus.Open) revert MarketNotOpen(marketId);
        if (block.timestamp >= market.endTime) revert MarketExpired(marketId);
        if (amount < $.minStakeAmount) revert StakeBelowMinimum(amount, $.minStakeAmount);

        uint256 maxTvl = $.maxMarketTvl;
        if (maxTvl > 0) {
            uint256 totalStake = market.totalUp + market.totalDown + amount;
            if (totalStake > maxTvl) revert MarketTvlExceeded(marketId, maxTvl);
        }

        IBalanceManager bm = IBalanceManager($.balanceManager);
        bm.transferFrom(user, address(this), $.collateralCurrency, amount);

        uint256 fee = amount * bm.feeMaker() / bm.getFeeUnit();
        uint256 received = amount - fee;

        Position storage position = $.positions[marketId][user];
        if (predictUp) {
            market.totalUp += received;
            position.stakeUp += received;
        } else {
            market.totalDown += received;
            position.stakeDown += received;
        }

        emit Predicted(marketId, user, predictUp, received);
    }

    /// @notice Claim payout on behalf of a user. Callable by the user themselves or an authorized router.
    function claimFor(address user, uint64 marketId) external nonReentrant {
        if (msg.sender != user && !getStorage().authorizedRouters[msg.sender]) revert UnauthorizedRouter(msg.sender);

        Storage storage $ = getStorage();
        Market storage market = $.markets[marketId];
        Position storage position = $.positions[marketId][user];

        if (market.status != MarketStatus.Settled && market.status != MarketStatus.Cancelled) {
            revert MarketNotClaimable(marketId);
        }
        if (position.claimed) revert AlreadyClaimed(marketId, user);
        if (position.stakeUp == 0 && position.stakeDown == 0) revert NoPosition(marketId, user);

        position.claimed = true;

        uint256 payout = _computePayout($, market, position);

        if (payout > 0) {
            IBalanceManager($.balanceManager).transferFrom(
                address(this),
                user,
                $.collateralCurrency,
                payout
            );
        }

        emit Claimed(marketId, user, payout);
    }

    /// @notice Request settlement after market end time.
    ///         Anyone can call. Emits SettlementRequested for Chainlink CRE to pick up.
    function requestSettlement(uint64 marketId) external {
        Storage storage $ = getStorage();
        Market storage market = $.markets[marketId];

        if (market.status != MarketStatus.Open) revert MarketNotOpen(marketId);
        if (block.timestamp < market.endTime) revert MarketNotEnded(marketId);

        // If one side has no bets, auto-cancel instead of settling
        if (market.totalUp == 0 || market.totalDown == 0) {
            market.status = MarketStatus.Cancelled;
            string memory reason = market.totalUp == 0 ? "No UP bets" : "No DOWN bets";
            emit MarketCancelled(marketId, reason);
            return;
        }

        market.status = MarketStatus.SettlementRequested;

        emit SettlementRequested(
            marketId,
            market.baseToken,
            market.strikePrice,
            market.openingTwap
        );
    }

    /// @notice Chainlink CRE callback — settles the market with verified outcome.
    /// @dev Called by KeystoneForwarder after BFT quorum verification.
    ///      The owner may also call directly (testing / emergency override).
    ///      Report payload: abi.encode(uint64 marketId, bool outcome)
    function onReport(bytes calldata /*metadata*/, bytes calldata report) external override {
        Storage storage $ = getStorage();
        if (msg.sender != $.keystoneForwarder && msg.sender != owner()) revert UnauthorizedForwarder(msg.sender);

        (uint64 marketId, bool outcome) = abi.decode(report, (uint64, bool));

        Market storage market = $.markets[marketId];
        if (market.status != MarketStatus.SettlementRequested) revert MarketNotPendingSettlement(marketId);

        uint256 totalUp = market.totalUp;
        uint256 totalDown = market.totalDown;
        uint256 losingSideTotal = outcome ? totalDown : totalUp;
        uint256 protocolFee = (losingSideTotal * $.protocolFeeBps) / 10000;

        market.status = MarketStatus.Settled;
        market.outcome = outcome;

        // Accumulate protocol fee (stays in address(this) BalanceManager balance)
        $.accumulatedFees += protocolFee;

        emit MarketSettled(marketId, outcome, totalUp, totalDown, protocolFee);
    }

    /// @notice Claim payout for a settled market.
    ///         Winners receive proportional share of losing side minus protocol fee.
    ///         Losers receive 0 principal (already collected as prize pool).
    ///         Cancelled markets: all participants receive their stake back.
    function claim(uint64 marketId) external nonReentrant {
        Storage storage $ = getStorage();
        Market storage market = $.markets[marketId];
        Position storage position = $.positions[marketId][msg.sender];

        if (market.status != MarketStatus.Settled && market.status != MarketStatus.Cancelled) {
            revert MarketNotClaimable(marketId);
        }
        if (position.claimed) revert AlreadyClaimed(marketId, msg.sender);
        if (position.stakeUp == 0 && position.stakeDown == 0) revert NoPosition(marketId, msg.sender);

        position.claimed = true;

        uint256 payout = _computePayout($, market, position);

        if (payout > 0) {
            IBalanceManager($.balanceManager).transferFrom(
                address(this),
                msg.sender,
                $.collateralCurrency,
                payout
            );
        }

        emit Claimed(marketId, msg.sender, payout);
    }

    /// @notice Claim multiple markets in a single transaction.
    function claimBatch(uint64[] calldata marketIds) external nonReentrant {
        Storage storage $ = getStorage();
        for (uint256 i = 0; i < marketIds.length; i++) {
            uint64 marketId = marketIds[i];
            Market storage market = $.markets[marketId];
            Position storage position = $.positions[marketId][msg.sender];

            if (market.status != MarketStatus.Settled && market.status != MarketStatus.Cancelled) continue;
            if (position.claimed) continue;
            if (position.stakeUp == 0 && position.stakeDown == 0) continue;

            position.claimed = true;
            uint256 payout = _computePayout($, market, position);

            if (payout > 0) {
                IBalanceManager($.balanceManager).transferFrom(
                    address(this),
                    msg.sender,
                    $.collateralCurrency,
                    payout
                );
            }

            emit Claimed(marketId, msg.sender, payout);
        }
    }

    // =============================================================
    //                    VIEW FUNCTIONS
    // =============================================================

    function getMarket(uint64 marketId) external view returns (Market memory) {
        return getStorage().markets[marketId];
    }

    function getPosition(uint64 marketId, address user) external view returns (Position memory) {
        return getStorage().positions[marketId][user];
    }

    function getClaimableAmount(uint64 marketId, address user) external view returns (uint256) {
        Storage storage $ = getStorage();
        Market storage market = $.markets[marketId];
        Position storage position = $.positions[marketId][user];

        if (market.status != MarketStatus.Settled && market.status != MarketStatus.Cancelled) return 0;
        if (position.claimed) return 0;
        if (position.stakeUp == 0 && position.stakeDown == 0) return 0;

        return _computePayout($, market, position);
    }

    // =============================================================
    //                    INTERNAL FUNCTIONS
    // =============================================================

    /// @notice Compute payout for a user's position in a market.
    function _computePayout(
        Storage storage $,
        Market storage market,
        Position storage position
    ) internal view returns (uint256 payout) {
        // Cancelled market: full refund of all stakes
        if (market.status == MarketStatus.Cancelled) {
            return position.stakeUp + position.stakeDown;
        }

        // Settled market
        bool outcome = market.outcome;
        uint256 winnerStake = outcome ? position.stakeUp : position.stakeDown;

        // Loser: no principal returned
        if (winnerStake == 0) return 0;

        uint256 totalWinningSide = outcome ? market.totalUp : market.totalDown;
        uint256 totalLosingSide = outcome ? market.totalDown : market.totalUp;

        // Net loser pool after protocol fee
        uint256 netLoserPool = totalLosingSide - (totalLosingSide * $.protocolFeeBps / 10000);

        // Winner receives original stake + proportional share of net loser pool
        uint256 winnings = (winnerStake * netLoserPool) / totalWinningSide;
        payout = winnerStake + winnings;
        // loserStake is forfeited (already in the prize pool) — intentionally not returned
    }

    // =============================================================
    //                    CUSTOM ERRORS
    // =============================================================

    error InvalidBaseToken();
    error InvalidDuration();
    error StrikePriceRequired();
    error InsufficientOracleHistory(address baseToken);
    error OraclePriceUnavailable(address baseToken);
    error MarketNotOpen(uint64 marketId);
    error MarketExpired(uint64 marketId);
    error MarketNotEnded(uint64 marketId);
    error MarketNotCancellable(uint64 marketId);
    error MarketNotPendingSettlement(uint64 marketId);
    error MarketNotClaimable(uint64 marketId);
    error StakeBelowMinimum(uint256 amount, uint256 minimum);
    error MarketTvlExceeded(uint64 marketId, uint256 maxTvl);
    error UnauthorizedForwarder(address sender);
    error AlreadyClaimed(uint64 marketId, address user);
    error NoPosition(uint64 marketId, address user);
    error InvalidRecipient();
    error NoFeesToWithdraw();
    error FeeTooHigh();
    error InvalidForwarder();
    error UnauthorizedRouter(address sender);
}
