// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PricePrediction} from "../../src/core/PricePrediction.sol";
import {IPricePrediction} from "../../src/core/interfaces/IPricePrediction.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import {SyntheticTokenFactory} from "../../src/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";

import "@scalex/mocks/MockUSDC.sol";

// =============================================================
//                     MOCKS
// =============================================================

/// @dev Minimal Oracle mock — returns configurable TWAP values.
contract MockOracle {
    mapping(address => uint256) public twapValues;
    mapping(address => bool) public stale;
    mapping(address => bool) public hasSufficientHistoryResult;

    function setTwap(address token, uint256 twap) external {
        twapValues[token] = twap;
    }

    function setStale(address token, bool _stale) external {
        stale[token] = _stale;
    }

    function setHasSufficientHistory(address token, bool result) external {
        hasSufficientHistoryResult[token] = result;
    }

    function getTWAP(address token, uint256 /*window*/) external view returns (uint256) {
        return twapValues[token];
    }

    function isPriceStale(address token) external view returns (bool) {
        return stale[token];
    }

    function hasSufficientHistory(address token, uint256 /*window*/) external view returns (bool) {
        return hasSufficientHistoryResult[token];
    }
}

// =============================================================
//                     TEST CONTRACT
// =============================================================

contract PricePredictionTest is Test {
    PricePrediction internal prediction;
    IBalanceManager internal balanceManager;
    MockOracle internal oracle;
    MockUSDC internal idrx;   // Real token (deposited into BalanceManager)
    address internal sxIDRX;  // Synthetic token

    address internal owner = makeAddr("owner");
    address internal feeReceiver = makeAddr("feeReceiver");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keystoneForwarder = makeAddr("keystoneForwarder");
    address internal baseToken = makeAddr("baseToken"); // e.g. WETH

    uint256 constant PROTOCOL_FEE_BPS = 200; // 2%
    uint256 constant MIN_STAKE = 10_000_000; // 10 IDRX (6 decimals)
    uint256 constant FEE_UNIT = 1_000_000;
    uint256 constant INITIAL_IDRX = 1_000_000_000_000; // 1M IDRX

    function setUp() public {
        BeaconDeployer beaconDeployer = new BeaconDeployer();

        // Deploy BalanceManager via Beacon Proxy (feeMaker=1/1_000_000, feeTaker=5/1_000_000)
        (BeaconProxy bmProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeReceiver, 1, 5))
        );
        balanceManager = IBalanceManager(address(bmProxy));

        // Deploy MockUSDC (IDRX stand-in) and SyntheticTokenFactory
        idrx = new MockUSDC();
        SyntheticTokenFactory tokenFactory = new SyntheticTokenFactory();
        tokenFactory.initialize(owner, owner);

        // Deploy TokenRegistry (required by BalanceManager)
        address tokenRegistryImpl = address(new TokenRegistry());
        ERC1967Proxy tokenRegistryProxy = new ERC1967Proxy(
            tokenRegistryImpl,
            abi.encodeWithSelector(TokenRegistry.initialize.selector, owner)
        );
        ITokenRegistry tokenRegistry = ITokenRegistry(address(tokenRegistryProxy));

        // Create synthetic IDRX (must be called as owner)
        vm.prank(owner);
        sxIDRX = tokenFactory.createSyntheticToken(address(idrx));

        // Configure BalanceManager: set factory, registry, supported asset, minter/burner
        vm.startPrank(owner);
        balanceManager.setTokenFactory(address(tokenFactory));
        balanceManager.setTokenRegistry(address(tokenRegistry));
        balanceManager.addSupportedAsset(address(idrx), sxIDRX);
        SyntheticToken(sxIDRX).setMinter(address(balanceManager));
        SyntheticToken(sxIDRX).setBurner(address(balanceManager));

        // Register token mappings for local chain deposits
        uint32 chainId = uint32(block.chainid);
        tokenRegistry.registerTokenMapping(chainId, address(idrx), chainId, sxIDRX, "IDRX", 6, 6);
        tokenRegistry.setTokenMappingStatus(chainId, address(idrx), chainId, true);
        vm.stopPrank();

        // Mint real IDRX and deposit for alice and bob (they get sxIDRX balance in BalanceManager)
        idrx.mint(alice, INITIAL_IDRX);
        idrx.mint(bob, INITIAL_IDRX);

        vm.startPrank(alice);
        idrx.approve(address(balanceManager), INITIAL_IDRX);
        balanceManager.deposit(Currency.wrap(address(idrx)), INITIAL_IDRX, alice, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        idrx.approve(address(balanceManager), INITIAL_IDRX);
        balanceManager.deposit(Currency.wrap(address(idrx)), INITIAL_IDRX, bob, bob);
        vm.stopPrank();

        // Deploy MockOracle
        oracle = new MockOracle();
        oracle.setHasSufficientHistory(baseToken, true);
        oracle.setTwap(baseToken, 3000e8); // $3000

        // Deploy PricePrediction via Beacon Proxy
        (BeaconProxy predProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new PricePrediction()),
            owner,
            abi.encodeCall(
                PricePrediction.initialize,
                (
                    owner,
                    address(balanceManager),
                    address(oracle),
                    keystoneForwarder,
                    Currency.wrap(sxIDRX),
                    PROTOCOL_FEE_BPS,
                    MIN_STAKE
                )
            )
        );
        prediction = PricePrediction(address(predProxy));

        // Authorize PricePrediction in BalanceManager (addAuthorizedOperator has no access control)
        balanceManager.addAuthorizedOperator(address(prediction));
    }

    // =============================================================
    //                   createMarket() TESTS
    // =============================================================

    function test_createMarket_directional_succeeds() public {
        vm.prank(owner);
        uint64 marketId = prediction.createMarket(baseToken, IPricePrediction.MarketType.Directional, 0, 300);

        assertEq(marketId, 1);
        IPricePrediction.Market memory market = prediction.getMarket(1);
        assertEq(market.id, 1);
        assertEq(uint8(market.marketType), uint8(IPricePrediction.MarketType.Directional));
        assertEq(uint8(market.status), uint8(IPricePrediction.MarketStatus.Open));
        assertEq(market.baseToken, baseToken);
        assertEq(market.openingTwap, 3000e8);
        assertEq(market.endTime, block.timestamp + 300);
    }

    function test_createMarket_absolute_succeeds() public {
        vm.prank(owner);
        uint64 marketId = prediction.createMarket(baseToken, IPricePrediction.MarketType.Absolute, 3500e8, 300);

        IPricePrediction.Market memory market = prediction.getMarket(marketId);
        assertEq(uint8(market.marketType), uint8(IPricePrediction.MarketType.Absolute));
        assertEq(market.strikePrice, 3500e8);
    }

    function test_createMarket_reverts_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        prediction.createMarket(baseToken, IPricePrediction.MarketType.Directional, 0, 300);
    }

    function test_createMarket_reverts_absoluteWithoutStrike() public {
        vm.prank(owner);
        vm.expectRevert(PricePrediction.StrikePriceRequired.selector);
        prediction.createMarket(baseToken, IPricePrediction.MarketType.Absolute, 0, 300);
    }

    function test_createMarket_reverts_insufficientHistory() public {
        oracle.setHasSufficientHistory(baseToken, false);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(PricePrediction.InsufficientOracleHistory.selector, baseToken));
        prediction.createMarket(baseToken, IPricePrediction.MarketType.Directional, 0, 300);
    }

    // =============================================================
    //                     predict() TESTS
    // =============================================================

    function _createOpenMarket() internal returns (uint64 marketId) {
        vm.prank(owner);
        marketId = prediction.createMarket(baseToken, IPricePrediction.MarketType.Directional, 0, 300);
    }

    function _netStake(uint256 inputAmount) internal view returns (uint256) {
        uint256 fee = inputAmount * balanceManager.feeMaker() / balanceManager.getFeeUnit();
        return inputAmount - fee;
    }

    function test_predict_up_succeeds() public {
        uint64 marketId = _createOpenMarket();
        uint256 inputAmount = 100_000_000; // 100 IDRX

        vm.prank(alice);
        prediction.predict(marketId, true, inputAmount);

        uint256 netStake = _netStake(inputAmount);
        IPricePrediction.Market memory market = prediction.getMarket(marketId);
        assertEq(market.totalUp, netStake);
        assertEq(market.totalDown, 0);

        IPricePrediction.Position memory pos = prediction.getPosition(marketId, alice);
        assertEq(pos.stakeUp, netStake);
        assertFalse(pos.claimed);
    }

    function test_predict_down_succeeds() public {
        uint64 marketId = _createOpenMarket();
        uint256 inputAmount = 50_000_000;

        vm.prank(bob);
        prediction.predict(marketId, false, inputAmount);

        IPricePrediction.Market memory market = prediction.getMarket(marketId);
        assertEq(market.totalDown, _netStake(inputAmount));
    }

    function test_predict_reverts_belowMinStake() public {
        uint64 marketId = _createOpenMarket();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(PricePrediction.StakeBelowMinimum.selector, MIN_STAKE - 1, MIN_STAKE)
        );
        prediction.predict(marketId, true, MIN_STAKE - 1);
    }

    function test_predict_reverts_afterEndTime() public {
        uint64 marketId = _createOpenMarket();
        vm.warp(block.timestamp + 301);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PricePrediction.MarketExpired.selector, marketId));
        prediction.predict(marketId, true, MIN_STAKE);
    }

    // =============================================================
    //                  requestSettlement() TESTS
    // =============================================================

    function test_requestSettlement_emitsEvent() public {
        uint64 marketId = _createOpenMarket();

        vm.prank(alice);
        prediction.predict(marketId, true, 100_000_000);
        vm.prank(bob);
        prediction.predict(marketId, false, 80_000_000);

        vm.warp(block.timestamp + 301);

        vm.expectEmit(true, false, false, true);
        emit IPricePrediction.SettlementRequested(marketId, baseToken, 0, 3000e8);
        prediction.requestSettlement(marketId);

        IPricePrediction.Market memory market = prediction.getMarket(marketId);
        assertEq(uint8(market.status), uint8(IPricePrediction.MarketStatus.SettlementRequested));
    }

    function test_requestSettlement_cancelsSingleSidedMarket() public {
        uint64 marketId = _createOpenMarket();
        // Only UP bets, no DOWN bets
        vm.prank(alice);
        prediction.predict(marketId, true, 100_000_000);

        vm.warp(block.timestamp + 301);
        prediction.requestSettlement(marketId);

        IPricePrediction.Market memory market = prediction.getMarket(marketId);
        assertEq(uint8(market.status), uint8(IPricePrediction.MarketStatus.Cancelled));
    }

    function test_requestSettlement_reverts_beforeEndTime() public {
        uint64 marketId = _createOpenMarket();
        vm.expectRevert(abi.encodeWithSelector(PricePrediction.MarketNotEnded.selector, marketId));
        prediction.requestSettlement(marketId);
    }

    // =============================================================
    //                     onReport() TESTS
    // =============================================================

    function _settleMarket(uint64 marketId, bool outcome) internal {
        vm.warp(block.timestamp + 301);
        prediction.requestSettlement(marketId);

        bytes memory report = abi.encode(marketId, outcome);
        vm.prank(keystoneForwarder);
        prediction.onReport("", report);
    }

    function test_onReport_settlesMarket() public {
        uint64 marketId = _createOpenMarket();
        vm.prank(alice);
        prediction.predict(marketId, true, 100_000_000);
        vm.prank(bob);
        prediction.predict(marketId, false, 80_000_000);

        _settleMarket(marketId, true); // UP wins

        IPricePrediction.Market memory market = prediction.getMarket(marketId);
        assertEq(uint8(market.status), uint8(IPricePrediction.MarketStatus.Settled));
        assertTrue(market.outcome);
    }

    function test_onReport_reverts_unauthorizedForwarder() public {
        uint64 marketId = _createOpenMarket();
        vm.prank(alice);
        prediction.predict(marketId, true, 100_000_000);
        vm.prank(bob);
        prediction.predict(marketId, false, 80_000_000);

        vm.warp(block.timestamp + 301);
        prediction.requestSettlement(marketId);

        bytes memory report = abi.encode(marketId, true);
        vm.prank(alice); // Not the forwarder
        vm.expectRevert(abi.encodeWithSelector(PricePrediction.UnauthorizedForwarder.selector, alice));
        prediction.onReport("", report);
    }

    // =============================================================
    //                      claim() TESTS
    // =============================================================

    function test_claim_winner_receivesPayoutMinusFee() public {
        uint64 marketId = _createOpenMarket();
        uint256 aliceInput = 500_000_000; // 500 IDRX on UP
        uint256 bobInput = 400_000_000;   // 400 IDRX on DOWN

        vm.prank(alice);
        prediction.predict(marketId, true, aliceInput);
        vm.prank(bob);
        prediction.predict(marketId, false, bobInput);

        _settleMarket(marketId, true); // UP wins

        // Net stakes recorded after feeMaker on entry
        uint256 aliceNet = _netStake(aliceInput);
        uint256 bobNet = _netStake(bobInput);
        // Expected payout = aliceNet + (aliceNet/totalUp) * (totalDown - 2% fee)
        // Since alice is sole UP bettor: aliceNet + bobNet - bobNet * protocolFee/10000
        uint256 netLoserPool = bobNet - (bobNet * PROTOCOL_FEE_BPS / 10000);
        uint256 expectedPayout = aliceNet + netLoserPool;

        uint256 balanceBefore = balanceManager.getAvailableBalance(alice, Currency.wrap(sxIDRX));
        vm.prank(alice);
        prediction.claim(marketId);
        uint256 balanceAfter = balanceManager.getAvailableBalance(alice, Currency.wrap(sxIDRX));

        // BalanceManager charges feeMaker on the exit transferFrom
        uint256 exitFee = expectedPayout * balanceManager.feeMaker() / balanceManager.getFeeUnit();
        assertEq(balanceAfter - balanceBefore, expectedPayout - exitFee, "Alice should receive payout minus exit feeMaker");
    }

    function test_claim_loser_receives_nothing() public {
        uint64 marketId = _createOpenMarket();
        vm.prank(alice);
        prediction.predict(marketId, true, 500_000_000);
        vm.prank(bob);
        prediction.predict(marketId, false, 400_000_000);

        _settleMarket(marketId, true); // UP wins, bob loses

        uint256 balanceBefore = balanceManager.getAvailableBalance(bob, Currency.wrap(sxIDRX));

        vm.prank(bob);
        prediction.claim(marketId);

        uint256 balanceAfter = balanceManager.getAvailableBalance(bob, Currency.wrap(sxIDRX));
        assertEq(balanceAfter, balanceBefore, "Loser should receive nothing");
    }

    function test_claim_reverts_alreadyClaimed() public {
        uint64 marketId = _createOpenMarket();
        vm.prank(alice);
        prediction.predict(marketId, true, 500_000_000);
        vm.prank(bob);
        prediction.predict(marketId, false, 400_000_000);

        _settleMarket(marketId, true);

        vm.prank(alice);
        prediction.claim(marketId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PricePrediction.AlreadyClaimed.selector, marketId, alice));
        prediction.claim(marketId);
    }

    function test_claim_reverts_noPosition() public {
        uint64 marketId = _createOpenMarket();
        vm.prank(alice);
        prediction.predict(marketId, true, 500_000_000);
        vm.prank(bob);
        prediction.predict(marketId, false, 400_000_000);

        _settleMarket(marketId, true);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PricePrediction.NoPosition.selector, marketId, stranger));
        prediction.claim(marketId);
    }

    // =============================================================
    //                    cancelMarket() TESTS
    // =============================================================

    function test_cancelMarket_refundsParticipants() public {
        uint64 marketId = _createOpenMarket();
        uint256 inputAmount = 100_000_000;

        vm.prank(alice);
        prediction.predict(marketId, true, inputAmount);

        // Admin cancels
        vm.prank(owner);
        prediction.cancelMarket(marketId);

        IPricePrediction.Market memory market = prediction.getMarket(marketId);
        assertEq(uint8(market.status), uint8(IPricePrediction.MarketStatus.Cancelled));

        // Claimable = net received stake (after feeMaker on entry)
        uint256 claimable = prediction.getClaimableAmount(marketId, alice);
        assertEq(claimable, _netStake(inputAmount));
    }

    function test_cancelMarket_claimRefund() public {
        uint64 marketId = _createOpenMarket();
        uint256 inputAmount = 100_000_000;
        uint256 feeMaker = balanceManager.feeMaker();
        uint256 feeUnit = balanceManager.getFeeUnit();

        vm.prank(alice);
        prediction.predict(marketId, true, inputAmount);

        // PricePrediction received: inputAmount - fee
        uint256 receivedStake = inputAmount - (inputAmount * feeMaker / feeUnit);

        vm.prank(owner);
        prediction.cancelMarket(marketId);

        uint256 balanceBefore = balanceManager.getAvailableBalance(alice, Currency.wrap(sxIDRX));

        vm.prank(alice);
        prediction.claim(marketId);

        uint256 balanceAfter = balanceManager.getAvailableBalance(alice, Currency.wrap(sxIDRX));
        // On claim, transferFrom(this, alice, receivedStake) charges feeMaker again
        uint256 exitFee = receivedStake * feeMaker / feeUnit;
        assertEq(balanceAfter - balanceBefore, receivedStake - exitFee);
    }

    // =============================================================
    //                    withdrawFees() TESTS
    // =============================================================

    function test_withdrawFees_succeeds() public {
        uint64 marketId = _createOpenMarket();
        vm.prank(alice);
        prediction.predict(marketId, true, 500_000_000);
        vm.prank(bob);
        prediction.predict(marketId, false, 400_000_000);

        _settleMarket(marketId, true);

        // Protocol fee = 400M * 2% = 8M IDRX
        uint256 expectedFee = 400_000_000 * PROTOCOL_FEE_BPS / 10000;
        address treasury = makeAddr("treasury");

        vm.prank(owner);
        prediction.withdrawFees(treasury);

        // Treasury balance should have received expectedFee minus feeMaker
        uint256 treasuryBalance = balanceManager.getAvailableBalance(treasury, Currency.wrap(sxIDRX));
        assertTrue(treasuryBalance > 0, "Treasury should have received fees");
    }

    function test_withdrawFees_reverts_noFees() public {
        vm.prank(owner);
        vm.expectRevert(PricePrediction.NoFeesToWithdraw.selector);
        prediction.withdrawFees(owner);
    }

    // =============================================================
    //                  getClaimableAmount() TESTS
    // =============================================================

    function test_getClaimableAmount_winner() public {
        uint64 marketId = _createOpenMarket();
        uint256 aliceInput = 500_000_000;
        uint256 bobInput = 400_000_000;

        vm.prank(alice);
        prediction.predict(marketId, true, aliceInput);
        vm.prank(bob);
        prediction.predict(marketId, false, bobInput);

        _settleMarket(marketId, true);

        uint256 aliceNet = _netStake(aliceInput);
        uint256 bobNet = _netStake(bobInput);
        uint256 netLoserPool = bobNet - (bobNet * PROTOCOL_FEE_BPS / 10000);
        uint256 expectedPayout = aliceNet + netLoserPool;
        assertEq(prediction.getClaimableAmount(marketId, alice), expectedPayout);
    }

    function test_getClaimableAmount_loser_returns_zero() public {
        uint64 marketId = _createOpenMarket();
        vm.prank(alice);
        prediction.predict(marketId, true, 500_000_000);
        vm.prank(bob);
        prediction.predict(marketId, false, 400_000_000);

        _settleMarket(marketId, true);

        assertEq(prediction.getClaimableAmount(marketId, bob), 0);
    }

    // =============================================================
    //                    setters TESTS (admin)
    // =============================================================

    function test_setProtocolFeeBps_succeeds() public {
        vm.prank(owner);
        prediction.setProtocolFeeBps(300); // 3%
    }

    function test_setProtocolFeeBps_reverts_tooHigh() public {
        vm.prank(owner);
        vm.expectRevert(PricePrediction.FeeTooHigh.selector);
        prediction.setProtocolFeeBps(1001); // > 10%
    }

    function test_setMinStakeAmount_succeeds() public {
        vm.prank(owner);
        prediction.setMinStakeAmount(20_000_000); // 20 IDRX
    }

    function test_setKeystoneForwarder_succeeds() public {
        address newForwarder = makeAddr("newForwarder");
        vm.prank(owner);
        prediction.setKeystoneForwarder(newForwarder);
    }

    function test_setKeystoneForwarder_reverts_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(PricePrediction.InvalidForwarder.selector);
        prediction.setKeystoneForwarder(address(0));
    }

    // =============================================================
    //                    claimBatch() TEST
    // =============================================================

    function test_claimBatch_succeeds() public {
        // Create two markets
        vm.startPrank(owner);
        uint64 m1 = prediction.createMarket(baseToken, IPricePrediction.MarketType.Directional, 0, 300);
        uint64 m2 = prediction.createMarket(baseToken, IPricePrediction.MarketType.Directional, 0, 300);
        vm.stopPrank();

        // Alice bets UP on both
        vm.startPrank(alice);
        prediction.predict(m1, true, 100_000_000);
        prediction.predict(m2, true, 100_000_000);
        vm.stopPrank();

        vm.prank(bob);
        prediction.predict(m1, false, 80_000_000);
        vm.prank(bob);
        prediction.predict(m2, false, 80_000_000);

        vm.warp(block.timestamp + 301);
        prediction.requestSettlement(m1);
        prediction.requestSettlement(m2);

        bytes memory report1 = abi.encode(m1, true);
        bytes memory report2 = abi.encode(m2, true);
        vm.startPrank(keystoneForwarder);
        prediction.onReport("", report1);
        prediction.onReport("", report2);
        vm.stopPrank();

        // Batch claim
        uint64[] memory marketIds = new uint64[](2);
        marketIds[0] = m1;
        marketIds[1] = m2;

        vm.prank(alice);
        prediction.claimBatch(marketIds);

        assertTrue(prediction.getPosition(m1, alice).claimed);
        assertTrue(prediction.getPosition(m2, alice).claimed);
    }
}
