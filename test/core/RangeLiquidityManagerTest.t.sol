// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {RangeLiquidityManager} from "@scalexcore/RangeLiquidityManager.sol";
import {IRangeLiquidityManager} from "@scalexcore/interfaces/IRangeLiquidityManager.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {ScaleXRouter} from "@scalexcore/ScaleXRouter.sol";
import {PoolManager} from "@scalexcore/PoolManager.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {OrderBook} from "@scalexcore/OrderBook.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {Currency, CurrencyLibrary} from "@scalexcore/libraries/Currency.sol";
import {PoolKey} from "@scalexcore/libraries/Pool.sol";
import {MockUSDC} from "@scalex/mocks/MockUSDC.sol";
import {MockToken} from "@scalex/mocks/MockToken.sol";
import {SyntheticTokenFactory} from "@scalex/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "@scalex/token/SyntheticToken.sol";
import {TokenRegistry} from "@scalexcore/TokenRegistry.sol";
import {ITokenRegistry} from "@scalexcore/interfaces/ITokenRegistry.sol";
import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Simple mock oracle that returns a configurable fixed price
contract SimpleMockOracle {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getSpotPrice(address token) external view returns (uint256) {
        return prices[token];
    }

    // Stubs for IOracle interface (unused in RangeLiquidityManager)
    function getTWAP(address, uint256) external pure returns (uint256) { return 0; }
    function getPriceForCollateral(address) external pure returns (uint256) { return 0; }
    function getPriceForBorrowing(address) external pure returns (uint256) { return 0; }
    function isPriceStale(address) external pure returns (bool) { return false; }
    function hasSufficientHistory(address, uint256) external pure returns (bool) { return true; }
}

contract RangeLiquidityManagerTest is Test {
    using CurrencyLibrary for Currency;

    RangeLiquidityManager private rlm;
    PoolManager private poolManager;
    BalanceManager private balanceManager;
    ScaleXRouter private router;
    SimpleMockOracle private oracle;
    SyntheticTokenFactory private tokenFactory;
    ITokenRegistry private tokenRegistry;

    address private owner = address(0x1);
    address private feeReceiver = address(0x2);
    address private lp = address(0x3);
    address private bot = address(0x4);
    address private stranger = address(0x5);

    Currency private wbtc;
    Currency private usdc;
    MockToken private mockWBTC;
    MockUSDC private mockUSDC;

    uint256 private constant INITIAL_WBTC = 10e8;          // 10 WBTC
    uint256 private constant INITIAL_USDC = 1_000_000e6;   // 1M USDC
    uint128 private constant BTC_PRICE = 75_000e6;         // $75,000 (6 decimals like USDC)

    PoolKey private defaultPoolKey;
    IOrderBook.TradingRules private defaultTradingRules;

    function setUp() public {
        vm.label(owner, "Owner");
        vm.label(lp, "LP");
        vm.label(bot, "Bot");

        BeaconDeployer beaconDeployer = new BeaconDeployer();

        // --- Deploy core infrastructure ---

        // BalanceManager
        (BeaconProxy bmProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeReceiver, 1, 5)) // 0.1% maker, 0.5% taker
        );
        balanceManager = BalanceManager(payable(address(bmProxy)));

        // OrderBook beacon
        IBeacon obBeacon = new UpgradeableBeacon(address(new OrderBook()), owner);

        // PoolManager
        (BeaconProxy pmProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new PoolManager()),
            owner,
            abi.encodeCall(PoolManager.initialize, (owner, address(balanceManager), address(obBeacon)))
        );
        poolManager = PoolManager(address(pmProxy));

        // ScaleXRouter
        (BeaconProxy rProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new ScaleXRouter()),
            owner,
            abi.encodeCall(ScaleXRouter.initialize, (address(poolManager), address(balanceManager)))
        );
        router = ScaleXRouter(address(rProxy));

        // SimpleMockOracle (no proxy needed)
        oracle = new SimpleMockOracle();

        // RangeLiquidityManager
        (BeaconProxy rlmProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new RangeLiquidityManager()),
            owner,
            abi.encodeCall(RangeLiquidityManager.initialize, (address(poolManager), address(balanceManager), address(router)))
        );
        rlm = RangeLiquidityManager(address(rlmProxy));

        // --- Deploy mock tokens ---
        mockWBTC = new MockToken("Wrapped BTC", "WBTC", 8);
        mockUSDC = new MockUSDC();
        wbtc = Currency.wrap(address(mockWBTC));
        usdc = Currency.wrap(address(mockUSDC));

        // --- Token factory & registry ---
        tokenFactory = new SyntheticTokenFactory();
        tokenFactory.initialize(owner, owner);

        address trImpl = address(new TokenRegistry());
        ERC1967Proxy trProxy = new ERC1967Proxy(trImpl, abi.encodeWithSelector(TokenRegistry.initialize.selector, owner));
        tokenRegistry = ITokenRegistry(address(trProxy));

        vm.startPrank(owner);

        // Create synthetic tokens
        address sxWBTC = tokenFactory.createSyntheticToken(address(mockWBTC));
        address sxUSDC = tokenFactory.createSyntheticToken(address(mockUSDC));

        balanceManager.addSupportedAsset(address(mockWBTC), sxWBTC);
        balanceManager.addSupportedAsset(address(mockUSDC), sxUSDC);

        SyntheticToken(sxWBTC).setMinter(address(balanceManager));
        SyntheticToken(sxUSDC).setMinter(address(balanceManager));
        SyntheticToken(sxWBTC).setBurner(address(balanceManager));
        SyntheticToken(sxUSDC).setBurner(address(balanceManager));

        uint32 chainId = 31337;
        tokenRegistry.registerTokenMapping(chainId, address(mockWBTC), chainId, sxWBTC, "WBTC", 8, 8);
        tokenRegistry.registerTokenMapping(chainId, address(mockUSDC), chainId, sxUSDC, "USDC", 6, 6);
        tokenRegistry.setTokenMappingStatus(chainId, address(mockWBTC), chainId, true);
        tokenRegistry.setTokenMappingStatus(chainId, address(mockUSDC), chainId, true);

        balanceManager.setTokenFactory(address(tokenFactory));
        balanceManager.setTokenRegistry(address(tokenRegistry));
        balanceManager.setPoolManager(address(poolManager));
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.setAuthorizedOperator(address(router), true);
        balanceManager.setAuthorizedOperator(address(rlm), true);

        // --- PoolManager setup ---
        poolManager.setRouter(address(router));

        defaultTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e4,
            minAmountMovement: 1e4,
            minOrderSize: 1e6,
            minPriceMovement: 1e4
        });

        // Create pool with 0.2% fee tier
        poolManager.createPool(wbtc, usdc, defaultTradingRules, 20);

        // --- Oracle setup ---
        // Set WBTC price on mock oracle (keyed by base token address, which _getCurrentPrice uses)
        oracle.setPrice(address(mockWBTC), BTC_PRICE);

        // Set oracle on the orderbook
        defaultPoolKey = PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 20});
        IPoolManager.Pool memory pool = poolManager.getPool(defaultPoolKey);
        IOrderBook(address(pool.orderBook)).setOracle(address(oracle));

        vm.stopPrank();

        // --- Fund LP ---
        mockWBTC.mint(lp, INITIAL_WBTC);
        mockUSDC.mint(lp, INITIAL_USDC);

        vm.startPrank(lp);
        mockWBTC.approve(address(balanceManager), type(uint256).max);
        mockUSDC.approve(address(balanceManager), type(uint256).max);
        vm.stopPrank();
    }

    // ========== Helper ==========

    function _defaultParams() internal view returns (IRangeLiquidityManager.PositionParams memory) {
        return IRangeLiquidityManager.PositionParams({
            poolKey: defaultPoolKey,
            strategy: IRangeLiquidityManager.Strategy.UNIFORM,
            lowerPrice: 70_000e6,
            upperPrice: 80_000e6,
            tickCount: 10,
            tickSpacing: 50,
            depositAmount: 100_000e6,
            depositCurrency: usdc,
            autoRebalance: true,
            rebalanceThresholdBps: 500
        });
    }

    function _createDefaultPosition() internal returns (uint256) {
        vm.startPrank(lp);
        uint256 positionId = rlm.createPosition(_defaultParams());
        vm.stopPrank();
        return positionId;
    }

    // ========== createPosition ==========

    function test_createPosition_uniform() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();

        uint256 positionId = rlm.createPosition(params);

        assertEq(positionId, 1);

        IRangeLiquidityManager.RangePosition memory pos = rlm.getPosition(positionId);
        assertEq(pos.owner, lp);
        assertEq(uint8(pos.strategy), uint8(IRangeLiquidityManager.Strategy.UNIFORM));
        assertEq(pos.lowerPrice, 70_000e6);
        assertEq(pos.upperPrice, 80_000e6);
        assertEq(pos.tickCount, 10);
        assertEq(pos.tickSpacing, 50);
        assertEq(pos.initialDepositAmount, 100_000e6);
        assertTrue(pos.isActive);
        assertTrue(pos.autoRebalanceEnabled);
        assertEq(pos.rebalanceThresholdBps, 500);
        assertEq(pos.rebalanceCount, 0);
        assertTrue(pos.buyOrderIds.length > 0 || pos.sellOrderIds.length > 0);

        vm.stopPrank();
    }

    function test_createPosition_bidHeavy() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.strategy = IRangeLiquidityManager.Strategy.BID_HEAVY;

        uint256 positionId = rlm.createPosition(params);

        IRangeLiquidityManager.RangePosition memory pos = rlm.getPosition(positionId);
        assertEq(uint8(pos.strategy), uint8(IRangeLiquidityManager.Strategy.BID_HEAVY));

        vm.stopPrank();
    }

    function test_createPosition_askHeavy() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.strategy = IRangeLiquidityManager.Strategy.ASK_HEAVY;

        uint256 positionId = rlm.createPosition(params);

        IRangeLiquidityManager.RangePosition memory pos = rlm.getPosition(positionId);
        assertEq(uint8(pos.strategy), uint8(IRangeLiquidityManager.Strategy.ASK_HEAVY));

        vm.stopPrank();
    }

    function test_createPosition_withMediumFeeTier() public {
        // Create a pool with 0.5% fee tier
        vm.startPrank(owner);
        poolManager.createPool(wbtc, usdc, defaultTradingRules, 50);

        PoolKey memory medPoolKey = PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 50});
        IPoolManager.Pool memory pool = poolManager.getPool(medPoolKey);
        IOrderBook(address(pool.orderBook)).setOracle(address(oracle));
        vm.stopPrank();

        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.poolKey = medPoolKey;
        params.tickSpacing = 200;

        uint256 positionId = rlm.createPosition(params);

        IRangeLiquidityManager.RangePosition memory pos = rlm.getPosition(positionId);
        assertEq(pos.tickSpacing, 200);
        assertTrue(pos.isActive);

        vm.stopPrank();
    }

    // ========== createPosition - validation reverts ==========

    function test_createPosition_revertsInvalidPriceRange() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.lowerPrice = 80_000e6;
        params.upperPrice = 70_000e6; // lower >= upper

        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.InvalidPriceRange.selector, params.lowerPrice, params.upperPrice));
        rlm.createPosition(params);

        vm.stopPrank();
    }

    function test_createPosition_revertsEqualPriceRange() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.lowerPrice = 75_000e6;
        params.upperPrice = 75_000e6;

        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.InvalidPriceRange.selector, params.lowerPrice, params.upperPrice));
        rlm.createPosition(params);

        vm.stopPrank();
    }

    function test_createPosition_revertsZeroTickCount() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.tickCount = 0;

        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.InvalidTickCount.selector, uint16(0)));
        rlm.createPosition(params);

        vm.stopPrank();
    }

    function test_createPosition_revertsTickCountTooHigh() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.tickCount = 101;

        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.InvalidTickCount.selector, uint16(101)));
        rlm.createPosition(params);

        vm.stopPrank();
    }

    function test_createPosition_revertsInvalidTickSpacing() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.tickSpacing = 100; // Must be 50 or 200

        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.InvalidTickSpacing.selector, uint16(100)));
        rlm.createPosition(params);

        vm.stopPrank();
    }

    function test_createPosition_revertsZeroDeposit() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.depositAmount = 0;

        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.InvalidDepositAmount.selector, uint256(0)));
        rlm.createPosition(params);

        vm.stopPrank();
    }

    function test_createPosition_revertsInvalidFeeTier() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.poolKey.feeTier = 100; // Must be 20 or 50

        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.InvalidFeeTier.selector, uint24(100)));
        rlm.createPosition(params);

        vm.stopPrank();
    }

    function test_createPosition_revertsRebalanceThresholdTooHigh() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.rebalanceThresholdBps = 10001;

        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.InvalidRebalanceThreshold.selector, uint16(10001)));
        rlm.createPosition(params);

        vm.stopPrank();
    }

    function test_createPosition_revertsDuplicatePosition() public {
        _createDefaultPosition();

        vm.startPrank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(IRangeLiquidityManager.PositionAlreadyExists.selector, lp, defaultPoolKey)
        );
        rlm.createPosition(_defaultParams());
        vm.stopPrank();
    }

    // ========== closePosition ==========

    function test_closePosition() public {
        uint256 positionId = _createDefaultPosition();

        vm.prank(lp);
        rlm.closePosition(positionId);

        IRangeLiquidityManager.RangePosition memory pos = rlm.getPosition(positionId);
        assertFalse(pos.isActive);
    }

    function test_closePosition_revertsNotOwner() public {
        uint256 positionId = _createDefaultPosition();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.NotPositionOwner.selector, positionId, stranger));
        rlm.closePosition(positionId);
    }

    function test_closePosition_revertsAlreadyClosed() public {
        uint256 positionId = _createDefaultPosition();

        vm.startPrank(lp);
        rlm.closePosition(positionId);

        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.PositionNotActive.selector, positionId));
        rlm.closePosition(positionId);
        vm.stopPrank();
    }

    // ========== setAuthorizedBot / revokeBot ==========

    function test_setAuthorizedBot() public {
        uint256 positionId = _createDefaultPosition();

        vm.prank(lp);
        rlm.setAuthorizedBot(positionId, bot);

        assertEq(rlm.getPosition(positionId).authorizedBot, bot);
    }

    function test_setAuthorizedBot_revertsNotOwner() public {
        uint256 positionId = _createDefaultPosition();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.NotPositionOwner.selector, positionId, stranger));
        rlm.setAuthorizedBot(positionId, bot);
    }

    function test_revokeBot() public {
        uint256 positionId = _createDefaultPosition();

        vm.startPrank(lp);
        rlm.setAuthorizedBot(positionId, bot);
        rlm.revokeBot(positionId);
        vm.stopPrank();

        assertEq(rlm.getPosition(positionId).authorizedBot, address(0));
    }

    function test_revokeBot_revertsNotOwner() public {
        uint256 positionId = _createDefaultPosition();

        vm.prank(lp);
        rlm.setAuthorizedBot(positionId, bot);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.NotPositionOwner.selector, positionId, stranger));
        rlm.revokeBot(positionId);
    }

    // ========== collectFees ==========

    function test_collectFees_revertsNotOwner() public {
        uint256 positionId = _createDefaultPosition();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.NotPositionOwner.selector, positionId, stranger));
        rlm.collectFees(positionId);
    }

    function test_collectFees_revertsNotActive() public {
        uint256 positionId = _createDefaultPosition();

        vm.startPrank(lp);
        rlm.closePosition(positionId);

        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.PositionNotActive.selector, positionId));
        rlm.collectFees(positionId);
        vm.stopPrank();
    }

    // ========== View functions ==========

    function test_totalPositions_initial() public view {
        assertEq(rlm.totalPositions(), 0);
    }

    function test_totalPositions_afterCreate() public {
        _createDefaultPosition();
        assertEq(rlm.totalPositions(), 1);
    }

    function test_getUserPositions() public {
        _createDefaultPosition();

        uint256[] memory positions = rlm.getUserPositions(lp);
        assertEq(positions.length, 1);
        assertEq(positions[0], 1);
    }

    function test_getUserPositions_empty() public view {
        uint256[] memory positions = rlm.getUserPositions(stranger);
        assertEq(positions.length, 0);
    }

    function test_getFeeTierForPool() public view {
        assertEq(rlm.getFeeTierForPool(defaultPoolKey), 20);
    }

    function test_getFeeTierForPool_medium() public view {
        PoolKey memory medKey = PoolKey({baseCurrency: wbtc, quoteCurrency: usdc, feeTier: 50});
        assertEq(rlm.getFeeTierForPool(medKey), 50);
    }

    // ========== Protocol fee ==========

    function test_setProtocolFee() public {
        vm.prank(owner);
        rlm.setProtocolFee(20); // 0.2%

        assertEq(rlm.getProtocolFee(), 20);
    }

    function test_setProtocolFee_revertsTooHigh() public {
        vm.prank(owner);
        vm.expectRevert("Protocol fee too high");
        rlm.setProtocolFee(1001);
    }

    function test_setProtocolFee_revertsNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        rlm.setProtocolFee(20);
    }

    function test_getProtocolFee_default() public view {
        assertEq(rlm.getProtocolFee(), 10); // Default 0.1%
    }

    // ========== LP Yield ==========

    function test_getLPYield() public {
        uint256 positionId = _createDefaultPosition();

        // feeTier=20 bps, protocolFee=10 bps -> LP yield = 10 bps
        uint24 lpYield = rlm.getLPYield(positionId);
        assertEq(lpYield, 10);
    }

    function test_getLPYield_afterProtocolFeeChange() public {
        uint256 positionId = _createDefaultPosition();

        vm.prank(owner);
        rlm.setProtocolFee(5); // 0.05%

        // feeTier=20 bps, protocolFee=5 bps -> LP yield = 15 bps
        uint24 lpYield = rlm.getLPYield(positionId);
        assertEq(lpYield, 15);
    }

    // ========== Rebalance ==========

    function test_rebalance_revertsNotAuthorized() public {
        uint256 positionId = _createDefaultPosition();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.NotAuthorizedToRebalance.selector, positionId, stranger));
        rlm.rebalancePosition(positionId);
    }

    function test_rebalance_revertsNotActive() public {
        uint256 positionId = _createDefaultPosition();

        vm.startPrank(lp);
        rlm.closePosition(positionId);

        vm.expectRevert(abi.encodeWithSelector(IRangeLiquidityManager.PositionNotActive.selector, positionId));
        rlm.rebalancePosition(positionId);
        vm.stopPrank();
    }

    function test_rebalance_ownerCanAlwaysRebalance() public {
        uint256 positionId = _createDefaultPosition();

        // Owner can rebalance without threshold check
        vm.prank(lp);
        rlm.rebalancePosition(positionId);

        IRangeLiquidityManager.RangePosition memory pos = rlm.getPosition(positionId);
        assertEq(pos.rebalanceCount, 1);
    }

    function test_rebalance_botRevertsThresholdNotMet() public {
        uint256 positionId = _createDefaultPosition();

        vm.prank(lp);
        rlm.setAuthorizedBot(positionId, bot);

        // Price hasn't moved, drift=0 < threshold=500
        vm.prank(bot);
        vm.expectRevert(
            abi.encodeWithSelector(IRangeLiquidityManager.RebalanceThresholdNotMet.selector, positionId, 0, 500)
        );
        rlm.rebalancePosition(positionId);
    }

    function test_canRebalance_noAutoRebalance() public {
        vm.startPrank(lp);
        IRangeLiquidityManager.PositionParams memory params = _defaultParams();
        params.autoRebalance = false;

        uint256 positionId = rlm.createPosition(params);
        vm.stopPrank();

        (bool canReb,) = rlm.canRebalance(positionId);
        assertFalse(canReb);
    }

    function test_canRebalance_inactive() public {
        uint256 positionId = _createDefaultPosition();

        vm.prank(lp);
        rlm.closePosition(positionId);

        (bool canReb, uint256 drift) = rlm.canRebalance(positionId);
        assertFalse(canReb);
        assertEq(drift, 0);
    }
}
