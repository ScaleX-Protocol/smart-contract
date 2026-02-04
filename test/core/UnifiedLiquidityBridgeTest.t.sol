// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {UnifiedLiquidityBridge} from "../../src/core/UnifiedLiquidityBridge.sol";
import {MantleSideChainManager} from "../../src/core/MantleSideChainManager.sol";
import {UnifiedLiquidityMessages} from "../../src/core/libraries/UnifiedLiquidityMessages.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/**
 * @title UnifiedLiquidityBridgeTest
 * @dev Unit tests for the Arc <-> Mantle unified liquidity bridge.
 *
 * Test layout
 * -----------
 *   1. Setup helpers -- deploy both contracts behind beacon proxies with a
 *      mock mailbox that can relay messages locally.
 *   2. Direct deposit tests (Arc side).
 *   3. Gateway deposit tests (Arc side).
 *   4. Local deposit tests (Mantle side).
 *   5. Withdrawal request flow (Mantle -> Arc).
 *   6. Cross-chain message validation (replay, origin, sender checks).
 *   7. Configuration / admin tests.
 *
 * Mock mailbox
 * ------------
 *   Forge does not include a real Hyperlane mailbox.  We deploy a trivial
 *   MockMailbox that:
 *     - Records dispatched messages.
 *     - Exposes a `relay(index)` function that calls `handle` on the
 *       destination contract, simulating Hyperlane delivery.
 *   This keeps the tests self-contained and deterministic.
 */
contract UnifiedLiquidityBridgeTest is Test {
    // ----------------------------------------------------------
    // Contracts under test
    // ----------------------------------------------------------
    UnifiedLiquidityBridge arcBridge;
    MantleSideChainManager mantleManager;

    // ----------------------------------------------------------
    // Mock tokens / mailboxes
    // ----------------------------------------------------------
    MockToken usdc;             // shared 6-decimal mock USDC
    MockMailbox arcMailbox;     // deployed on "Arc" side
    MockMailbox mantleMailbox;  // deployed on "Mantle" side

    // ----------------------------------------------------------
    // Addresses
    // ----------------------------------------------------------
    address OWNER;
    address USER_A;
    address USER_B;
    address GATEWAY_MINTER;

    // ----------------------------------------------------------
    // Chain domain IDs (match production values)
    // ----------------------------------------------------------
    uint32 constant ARC_DOMAIN    = 5042002;
    uint32 constant MANTLE_DOMAIN = 5003;

    // ===========================================================
    //  SETUP
    // ===========================================================

    function setUp() public {
        OWNER          = address(this);  // test contract is the owner
        USER_A         = makeAddr("USER_A");
        USER_B         = makeAddr("USER_B");
        GATEWAY_MINTER = makeAddr("GATEWAY_MINTER");

        // --- Mock USDC (6 decimals) ---
        usdc = new MockToken("USDC Coin", "USDC", 6);

        // --- Mock mailboxes ---
        arcMailbox    = new MockMailbox();
        mantleMailbox = new MockMailbox();

        // --- Deploy UnifiedLiquidityBridge (Arc) via beacon proxy ---
        UnifiedLiquidityBridge bridgeImpl = new UnifiedLiquidityBridge();
        UpgradeableBeacon bridgeBeacon   = new UpgradeableBeacon(address(bridgeImpl), OWNER);

        // We pass address(0) for mantleManager initially; we set it after
        // MantleSideChainManager is deployed.
        BeaconProxy bridgeProxy = new BeaconProxy(
            address(bridgeBeacon),
            abi.encodeCall(
                UnifiedLiquidityBridge.initialize,
                (OWNER, address(usdc), address(arcMailbox), MANTLE_DOMAIN, address(0))
            )
        );
        arcBridge = UnifiedLiquidityBridge(address(bridgeProxy));

        // --- Deploy MantleSideChainManager (Mantle) via beacon proxy ---
        MantleSideChainManager mantleImpl = new MantleSideChainManager();
        UpgradeableBeacon mantleBeacon   = new UpgradeableBeacon(address(mantleImpl), OWNER);

        BeaconProxy mantleProxy = new BeaconProxy(
            address(mantleBeacon),
            abi.encodeCall(
                MantleSideChainManager.initialize,
                (OWNER, address(usdc), address(mantleMailbox), ARC_DOMAIN, address(arcBridge))
            )
        );
        mantleManager = MantleSideChainManager(address(mantleProxy));

        // --- Wire Arc bridge to point at MantleSideChainManager ---
        arcBridge.setMantleManager(address(mantleManager), MANTLE_DOMAIN);

        // --- Authorise the gateway minter on Arc ---
        arcBridge.setAuthorizedDepositor(GATEWAY_MINTER, true);

        // --- Point each mailbox at the other contract so relay() works ---
        arcMailbox.setDestination(address(mantleManager), MANTLE_DOMAIN);
        mantleMailbox.setDestination(address(arcBridge), ARC_DOMAIN);
    }

    // ===========================================================
    //  1. DIRECT DEPOSIT (Arc)
    // ===========================================================

    function test_deposit_creditsUnifiedBalance() public {
        uint256 amount = 1000 * 1e6; // 1000 USDC
        usdc.mint(USER_A, amount);

        vm.startPrank(USER_A);
        usdc.approve(address(arcBridge), amount);
        arcBridge.deposit(amount, USER_A);
        vm.stopPrank();

        // Balance on Arc updated.
        assertEq(arcBridge.unifiedBalanceOf(USER_A), amount);
        // Vault total updated.
        assertEq(arcBridge.totalVaultBalance(), amount);
        // USDC moved into the bridge.
        assertEq(usdc.balanceOf(address(arcBridge)), amount);
        // A Hyperlane message was dispatched.
        assertEq(arcMailbox.messageCount(), 1);
    }

    function test_deposit_revertsOnZeroAmount() public {
        vm.startPrank(USER_A);
        vm.expectRevert();
        arcBridge.deposit(0, USER_A);
        vm.stopPrank();
    }

    function test_deposit_revertsOnZeroRecipient() public {
        uint256 amount = 100 * 1e6;
        usdc.mint(USER_A, amount);

        vm.startPrank(USER_A);
        usdc.approve(address(arcBridge), amount);
        vm.expectRevert();
        arcBridge.deposit(amount, address(0));
        vm.stopPrank();
    }

    function test_deposit_multipleUsers() public {
        uint256 amountA = 500 * 1e6;
        uint256 amountB = 300 * 1e6;

        usdc.mint(USER_A, amountA);
        usdc.mint(USER_B, amountB);

        vm.startPrank(USER_A);
        usdc.approve(address(arcBridge), amountA);
        arcBridge.deposit(amountA, USER_A);
        vm.stopPrank();

        vm.startPrank(USER_B);
        usdc.approve(address(arcBridge), amountB);
        arcBridge.deposit(amountB, USER_B);
        vm.stopPrank();

        assertEq(arcBridge.unifiedBalanceOf(USER_A), amountA);
        assertEq(arcBridge.unifiedBalanceOf(USER_B), amountB);
        assertEq(arcBridge.totalVaultBalance(), amountA + amountB);
    }

    // ===========================================================
    //  2. GATEWAY DEPOSIT (Arc)
    // ===========================================================

    function test_gatewayDeposit_creditsBalance() public {
        uint256 amount = 2000 * 1e6;
        // Simulate: gateway minter transfers USDC to bridge first.
        usdc.mint(address(arcBridge), amount);

        bytes32 gatewayNonce = keccak256("test-gateway-nonce-1");

        vm.startPrank(GATEWAY_MINTER);
        arcBridge.depositViaGateway(amount, USER_A, gatewayNonce);
        vm.stopPrank();

        assertEq(arcBridge.unifiedBalanceOf(USER_A), amount);
        assertEq(arcBridge.totalVaultBalance(), amount);
        assertTrue(arcBridge.isGatewayNonceUsed(gatewayNonce));
    }

    function test_gatewayDeposit_replayRevertsOnDuplicateNonce() public {
        uint256 amount = 100 * 1e6;
        usdc.mint(address(arcBridge), amount * 2);

        bytes32 gatewayNonce = keccak256("replay-nonce");

        vm.startPrank(GATEWAY_MINTER);
        arcBridge.depositViaGateway(amount, USER_A, gatewayNonce);
        vm.expectRevert();
        arcBridge.depositViaGateway(amount, USER_A, gatewayNonce);
        vm.stopPrank();
    }

    function test_gatewayDeposit_revertsForUnauthorizedCaller() public {
        uint256 amount = 100 * 1e6;
        usdc.mint(address(arcBridge), amount);

        vm.startPrank(USER_A);  // USER_A is NOT an authorized depositor
        vm.expectRevert();
        arcBridge.depositViaGateway(amount, USER_A, keccak256("x"));
        vm.stopPrank();
    }

    // ===========================================================
    //  3. LOCAL DEPOSIT (Mantle)
    // ===========================================================

    function test_mantleLocalDeposit_creditsMirroredBalance() public {
        uint256 amount = 750 * 1e6;
        usdc.mint(USER_A, amount);

        vm.startPrank(USER_A);
        usdc.approve(address(mantleManager), amount);
        mantleManager.depositLocal(amount, USER_A);
        vm.stopPrank();

        assertEq(mantleManager.mirroredBalanceOf(USER_A), amount);
        assertEq(mantleManager.totalMirroredSupply(), amount);
        // USDC moved into manager.
        assertEq(usdc.balanceOf(address(mantleManager)), amount);
        // A message was dispatched to Arc.
        assertEq(mantleMailbox.messageCount(), 1);
    }

    function test_mantleLocalDeposit_revertsOnZeroAmount() public {
        vm.startPrank(USER_A);
        vm.expectRevert();
        mantleManager.depositLocal(0, USER_A);
        vm.stopPrank();
    }

    // ===========================================================
    //  4. WITHDRAWAL REQUEST (Mantle -> Arc)
    // ===========================================================

    function test_withdrawRequest_deductsMirroredBalance() public {
        // First give USER_A some mirrored balance.
        uint256 amount = 600 * 1e6;
        usdc.mint(USER_A, amount);

        vm.startPrank(USER_A);
        usdc.approve(address(mantleManager), amount);
        mantleManager.depositLocal(amount, USER_A);
        vm.stopPrank();

        // Now request a partial withdrawal.
        uint256 withdrawAmount = 200 * 1e6;

        vm.startPrank(USER_A);
        mantleManager.requestWithdraw(withdrawAmount, USER_B);
        vm.stopPrank();

        // Mirrored balance reduced.
        assertEq(mantleManager.mirroredBalanceOf(USER_A), amount - withdrawAmount);
        assertEq(mantleManager.totalMirroredSupply(), amount - withdrawAmount);
        // A LIQUIDITY_WITHDRAW message was dispatched.
        assertEq(mantleMailbox.messageCount(), 2); // 1 from depositLocal + 1 from requestWithdraw
    }

    function test_withdrawRequest_revertsOnInsufficientBalance() public {
        vm.startPrank(USER_A);
        vm.expectRevert();
        mantleManager.requestWithdraw(1, USER_B);
        vm.stopPrank();
    }

    // ===========================================================
    //  5. CROSS-CHAIN RELAY -- deposit mirroring (Arc -> Mantle)
    // ===========================================================

    function test_relay_depositMessage_creditsMantleMirror() public {
        uint256 amount = 400 * 1e6;
        usdc.mint(USER_A, amount);

        // Deposit on Arc.  arcMailbox records the dispatched message.
        vm.startPrank(USER_A);
        usdc.approve(address(arcBridge), amount);
        arcBridge.deposit(amount, USER_A);
        vm.stopPrank();

        // Simulate Hyperlane delivery: prank as mantleMailbox (which is the
        // mailbox configured inside MantleSideChainManager) and call handle
        // with the body that Arc dispatched.
        bytes memory body = arcMailbox.getMessageBody(0);
        bytes32 senderSlot = bytes32(uint256(uint160(address(arcBridge))));

        vm.prank(address(mantleMailbox));
        mantleManager.handle(ARC_DOMAIN, senderSlot, body);

        // Mantle mirror should now reflect the deposit.
        assertEq(mantleManager.mirroredBalanceOf(USER_A), amount);
        assertEq(mantleManager.totalMirroredSupply(), amount);
    }

    // ===========================================================
    //  6. CROSS-CHAIN RELAY -- withdraw (Mantle -> Arc)
    // ===========================================================

    function test_relay_withdrawMessage_releasesUSDCOnArc() public {
        // Seed Arc vault with USDC via gateway deposit.
        uint256 vaultSeed = 1000 * 1e6;
        usdc.mint(address(arcBridge), vaultSeed);
        bytes32 seedNonce = keccak256("seed");
        vm.prank(GATEWAY_MINTER);
        arcBridge.depositViaGateway(vaultSeed, USER_A, seedNonce);
        // Arc vault now has vaultSeed USDC and USER_A has vaultSeed unified balance.

        // Give USER_A mirrored balance on Mantle via local deposit.
        uint256 amount = 300 * 1e6;
        usdc.mint(USER_A, amount);
        vm.startPrank(USER_A);
        usdc.approve(address(mantleManager), amount);
        mantleManager.depositLocal(amount, USER_A);
        vm.stopPrank();

        // USER_A requests withdrawal of 300 USDC to USER_B on Arc.
        vm.startPrank(USER_A);
        mantleManager.requestWithdraw(amount, USER_B);
        vm.stopPrank();

        // The last message in mantleMailbox is the LIQUIDITY_WITHDRAW.
        // Simulate Hyperlane delivery: prank as arcMailbox and call handle
        // on the Arc bridge with that message body.
        uint256 lastIdx = mantleMailbox.messageCount() - 1;
        bytes memory body = mantleMailbox.getMessageBody(lastIdx);
        bytes32 senderSlot = bytes32(uint256(uint160(address(mantleManager))));

        vm.prank(address(arcMailbox));
        arcBridge.handle(MANTLE_DOMAIN, senderSlot, body);

        // USER_B should have received 300 USDC on Arc.
        assertEq(usdc.balanceOf(USER_B), amount);
    }

    // ===========================================================
    //  7. REPLAY PROTECTION
    // ===========================================================

    function test_handle_revertsOnReplayedMessage() public {
        uint256 amount = 100 * 1e6;
        usdc.mint(USER_A, amount);

        vm.startPrank(USER_A);
        usdc.approve(address(arcBridge), amount);
        arcBridge.deposit(amount, USER_A);
        vm.stopPrank();

        // Read the dispatched message from arcMailbox.
        bytes memory body = arcMailbox.getMessageBody(0);
        bytes32 senderSlot = bytes32(uint256(uint160(address(arcBridge))));

        // First delivery succeeds.
        vm.prank(address(mantleMailbox));
        mantleManager.handle(ARC_DOMAIN, senderSlot, body);

        // Second delivery of the exact same message must revert (replay guard).
        vm.prank(address(mantleMailbox));
        vm.expectRevert();
        mantleManager.handle(ARC_DOMAIN, senderSlot, body);
    }

    // ===========================================================
    //  8. INVALID ORIGIN / SENDER
    // ===========================================================

    function test_handle_revertsOnWrongOrigin() public {
        // Craft a valid LIQUIDITY_DEPOSIT message but send it from a wrong domain.
        bytes memory body = UnifiedLiquidityMessages.encodeLiquidityDeposit(
            USER_A, 100 * 1e6, 9999, 0 // sourceChainId = 9999 (not Arc)
        );
        bytes32 sender = bytes32(uint256(uint160(address(arcBridge))));

        // Call handle directly on mantleManager pretending to be the mailbox.
        vm.prank(address(mantleMailbox));
        vm.expectRevert();
        mantleManager.handle(9999, sender, body); // wrong origin domain
    }

    function test_handle_revertsOnWrongSender() public {
        bytes memory body = UnifiedLiquidityMessages.encodeLiquidityDeposit(
            USER_A, 100 * 1e6, ARC_DOMAIN, 0
        );
        // Use a bogus sender address.
        bytes32 bogus = bytes32(uint256(uint160(USER_B)));

        vm.prank(address(mantleMailbox));
        vm.expectRevert();
        mantleManager.handle(ARC_DOMAIN, bogus, body);
    }

    function test_handle_revertsOnInvalidMessageType() public {
        // Encode a message with type = 99 (unknown).
        bytes memory body = abi.encode(uint8(99), USER_A, uint256(100), uint32(ARC_DOMAIN), uint256(0));
        bytes32 sender = bytes32(uint256(uint160(address(arcBridge))));

        vm.prank(address(mantleMailbox));
        vm.expectRevert();
        mantleManager.handle(ARC_DOMAIN, sender, body);
    }

    // ===========================================================
    //  9. CONFIGURATION TESTS
    // ===========================================================

    function test_setMailbox_updatesAddress() public {
        address newMailbox = makeAddr("NewMailbox");
        arcBridge.setMailbox(newMailbox);
        assertEq(arcBridge.getMailbox(), newMailbox);
    }

    function test_setMantleManager_updatesConfig() public {
        address newManager = makeAddr("NewManager");
        arcBridge.setMantleManager(newManager, 1234);
        (uint32 dom, address mgr) = arcBridge.getMantleConfig();
        assertEq(dom, 1234);
        assertEq(mgr, newManager);
    }

    function test_setAuthorizedDepositor_toggles() public {
        address newDep = makeAddr("NewDepositor");
        arcBridge.setAuthorizedDepositor(newDep, true);

        // Should be able to call depositViaGateway now (still need USDC in vault).
        uint256 amt = 50 * 1e6;
        usdc.mint(address(arcBridge), amt);
        vm.prank(newDep);
        arcBridge.depositViaGateway(amt, USER_A, keccak256("dep-nonce"));
        assertEq(arcBridge.unifiedBalanceOf(USER_A), amt);

        // Revoke.
        arcBridge.setAuthorizedDepositor(newDep, false);
        usdc.mint(address(arcBridge), amt);
        vm.startPrank(newDep);
        vm.expectRevert();
        arcBridge.depositViaGateway(amt, USER_A, keccak256("dep-nonce-2"));
        vm.stopPrank();
    }

    function test_mantleSetArcBridge_updatesConfig() public {
        address newBridge = makeAddr("NewBridge");
        mantleManager.setArcBridge(newBridge, 7777);
        (uint32 dom, address br) = mantleManager.getArcConfig();
        assertEq(dom, 7777);
        assertEq(br, newBridge);
    }

    function test_mantleSetLocalUSDC_updatesAddress() public {
        address newUsdc = makeAddr("NewUSDC");
        mantleManager.setLocalUSDC(newUsdc);
        assertEq(mantleManager.getLocalUSDC(), newUsdc);
    }

    // ===========================================================
    //  10. OWNER-ONLY WITHDRAWAL (Arc emergency)
    // ===========================================================

    function test_withdrawToRecipient_ownerOnly() public {
        uint256 amount = 500 * 1e6;
        usdc.mint(address(arcBridge), amount);

        // Bump vault total via gateway deposit.
        vm.prank(GATEWAY_MINTER);
        arcBridge.depositViaGateway(amount, USER_A, keccak256("owner-wd"));

        // Owner withdraws directly.
        arcBridge.withdrawToRecipient(amount, USER_B);

        assertEq(usdc.balanceOf(USER_B), amount);
        assertEq(arcBridge.totalVaultBalance(), 0);
    }

    function test_withdrawToRecipient_revertsForNonOwner() public {
        uint256 amount = 100 * 1e6;
        usdc.mint(address(arcBridge), amount);

        vm.prank(GATEWAY_MINTER);
        arcBridge.depositViaGateway(amount, USER_A, keccak256("non-owner-wd"));

        vm.startPrank(USER_A);
        vm.expectRevert();
        arcBridge.withdrawToRecipient(amount, USER_B);
        vm.stopPrank();
    }

    // ===========================================================
    //  11. MANTLE -> ARC DEPOSIT RELAY  (Finding 8)
    // ===========================================================

    /**
     * @dev Calls mantleManager.depositLocal, extracts the dispatched
     *      LIQUIDITY_DEPOSIT message from the mock mailbox, relays it into
     *      arcBridge.handle(), and asserts that arcBridge.unifiedBalanceOf
     *      was credited.
     */
    function test_relay_mantleDepositMessage_creditsArcUnifiedBalance() public {
        uint256 amount = 500 * 1e6;
        usdc.mint(USER_A, amount);

        // USER_A deposits locally on Mantle.
        vm.startPrank(USER_A);
        usdc.approve(address(mantleManager), amount);
        mantleManager.depositLocal(amount, USER_A);
        vm.stopPrank();

        // mantleMailbox recorded a LIQUIDITY_DEPOSIT message destined for Arc.
        assertEq(mantleMailbox.messageCount(), 1);

        // Extract the raw message body.
        bytes memory body = mantleMailbox.getMessageBody(0);

        // The sender from Mantle's perspective is the MantleSideChainManager.
        bytes32 senderSlot = bytes32(uint256(uint160(address(mantleManager))));

        // Simulate Hyperlane delivery: prank as arcMailbox (the mailbox wired
        // inside arcBridge) and call handle on arcBridge.
        vm.prank(address(arcMailbox));
        arcBridge.handle(MANTLE_DOMAIN, senderSlot, body);

        // Arc unified balance must now reflect the deposit.
        assertEq(arcBridge.unifiedBalanceOf(USER_A), amount);
    }

    // ===========================================================
    //  12. GATEWAY BALANCE MISMATCH  (Finding 2)
    // ===========================================================

    /**
     * @dev depositViaGateway must revert if the gateway minter did NOT
     *      actually transfer USDC to this contract before calling.
     */
    function test_gatewayDeposit_revertsIfUSDCNotReceived() public {
        uint256 amount = 1000 * 1e6;
        // Do NOT mint USDC to the bridge -- simulates the minter forgetting
        // to transfer.

        bytes32 gatewayNonce = keccak256("no-usdc-nonce");

        vm.startPrank(GATEWAY_MINTER);
        vm.expectRevert();
        arcBridge.depositViaGateway(amount, USER_A, gatewayNonce);
        vm.stopPrank();
    }

    // ===========================================================
    //  13. EMERGENCY SHORTFALL TRACKING  (Finding 3)
    // ===========================================================

    function test_withdrawToRecipient_tracksEmergencyShortfall() public {
        uint256 amount = 800 * 1e6;
        usdc.mint(address(arcBridge), amount);

        // Seed vault via gateway so totalVault is non-zero.
        vm.prank(GATEWAY_MINTER);
        arcBridge.depositViaGateway(amount, USER_A, keccak256("shortfall-seed"));

        // Owner withdraws; shortfall should be recorded.
        arcBridge.withdrawToRecipient(amount, USER_B);

        assertEq(arcBridge.getEmergencyShortfall(), amount);
        assertEq(arcBridge.totalVaultBalance(), 0);
    }

    // ===========================================================
    //  14. VAULT UNDERFLOW GUARD  (Finding 4)
    // ===========================================================

    function test_withdrawToRecipient_revertsOnUnderflow() public {
        // Vault is empty; any withdrawal must revert.
        vm.expectRevert();
        arcBridge.withdrawToRecipient(1, USER_B);
    }

    // ===========================================================
    //  15. FUZZ -- deposit amount
    // ===========================================================

    function testFuzz_deposit_balanceConsistency(uint96 amount) public {
        vm.assume(amount > 0);

        usdc.mint(USER_A, amount);

        vm.startPrank(USER_A);
        usdc.approve(address(arcBridge), amount);
        arcBridge.deposit(amount, USER_A);
        vm.stopPrank();

        assertEq(arcBridge.unifiedBalanceOf(USER_A), amount);
        assertEq(arcBridge.totalVaultBalance(), amount);
        assertEq(usdc.balanceOf(address(arcBridge)), amount);
    }

    function testFuzz_mantleLocalDeposit_balanceConsistency(uint96 amount) public {
        vm.assume(amount > 0);

        usdc.mint(USER_A, amount);

        vm.startPrank(USER_A);
        usdc.approve(address(mantleManager), amount);
        mantleManager.depositLocal(amount, USER_A);
        vm.stopPrank();

        assertEq(mantleManager.mirroredBalanceOf(USER_A), amount);
        assertEq(mantleManager.totalMirroredSupply(), amount);
    }
}

// ===========================================================
//  MockMailbox -- minimal Hyperlane mailbox stand-in
// ===========================================================

/**
 * @dev Records every `dispatch` call so tests can replay messages into
 *      destination contracts via `relay`.
 */
contract MockMailbox {
    struct Message {
        uint32 destination;
        bytes32 recipient;
        bytes body;
    }

    Message[] public messages;

    // Default destination for relay() convenience.
    address public destContract;
    uint32 public destDomain;

    event Dispatched(uint32 indexed destination, bytes32 indexed recipient, bytes body);

    function setDestination(address _contract, uint32 _domain) external {
        destContract = _contract;
        destDomain = _domain;
    }

    /**
     * @dev Mimics IMailbox.dispatch -- stores the message.
     */
    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) external payable returns (bytes32 messageId) {
        messages.push(Message(destinationDomain, recipientAddress, messageBody));
        messageId = keccak256(abi.encodePacked(block.timestamp, messages.length));
        emit Dispatched(destinationDomain, recipientAddress, messageBody);
    }

    /**
     * @dev Mimics IMailbox.quoteDispatch (returns 0 for tests).
     */
    function quoteDispatch(
        uint32,
        bytes32,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }

    function messageCount() external view returns (uint256) {
        return messages.length;
    }

    /**
     * @dev Return the raw body of the message at the given index.
     */
    function getMessageBody(uint256 index) external view returns (bytes memory) {
        return messages[index].body;
    }

    /**
     * @dev Deliver message at `index` to a specific target contract.
     *      `originDomain`  -- the domain we claim the message originated from.
     *      `originSender`  -- the address that called dispatch (packed as bytes32).
     *      `target`        -- the IMessageRecipient to call handle() on.
     */
    function relay(
        uint256 index,
        uint32 originDomain,
        address originSender,
        address target
    ) external {
        Message memory m = messages[index];
        bytes32 senderSlot = bytes32(uint256(uint160(originSender)));

        // Call handle on the target (as if we are the mailbox on the destination).
        // The target's onlyMailbox modifier checks msg.sender == its configured mailbox.
        // For tests we call directly; the test setUp wired each contract's mailbox to
        // the corresponding MockMailbox instance.  So we must prank as the correct mailbox.
        // We determine which mailbox based on the target.
        (bool success, ) = target.call(
            abi.encodeWithSignature(
                "handle(uint32,bytes32,bytes)",
                originDomain,
                senderSlot,
                m.body
            )
        );
        require(success, "MockMailbox.relay: handle() reverted");
    }
}
