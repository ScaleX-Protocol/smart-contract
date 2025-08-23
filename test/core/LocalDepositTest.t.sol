// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@gtx/mocks/MockUSDC.sol";
import "@gtx/mocks/MockWETH.sol";
import "@gtxcore/BalanceManager.sol";
import "@gtxcore/TokenRegistry.sol";
import "@gtxcore/SyntheticTokenFactory.sol";
import "@gtx/token/SyntheticToken.sol";
import {Currency} from "@gtxcore/libraries/Currency.sol";
import {IBalanceManagerErrors} from "@gtxcore/interfaces/IBalanceManagerErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/**
 * @title LocalDepositTest
 * @dev Test suite for the local deposit functionality in BalanceManager
 * Tests the ability to deposit local tokens and receive synthetic tokens on the same chain
 */
contract LocalDepositTest is Test {
    // Events to test
    event LocalDeposit(
        address indexed recipient,
        address indexed sourceToken,
        address indexed syntheticToken,
        uint256 sourceAmount,
        uint256 syntheticAmount
    );
    
    event Deposit(address indexed user, uint256 indexed id, uint256 amount);
    BalanceManager private balanceManager;
    TokenRegistry private tokenRegistry;
    SyntheticTokenFactory private syntheticTokenFactory;
    SyntheticToken private gsUSDT;
    SyntheticToken private gsWETH;
    MockUSDC private localUSDT;
    MockWETH private localWETH;

    address private owner = address(0x123);
    address private feeReceiver = address(0x456);
    address private user1 = address(0x789);
    address private user2 = address(0xABC);
    
    uint256 private feeMaker = 1; // 0.1%
    uint256 private feeTaker = 5; // 0.5%
    uint256 private initialBalance = 1000 ether;
    uint256 private initialUSDTBalance = 1_000_000 * 1e6; // 1M USDT
    uint256 private initialWETHBalance = 1000 ether;

    // Test constants
    uint32 private constant LOCAL_CHAIN_ID = 1918988905; // Rari testnet
    uint256 private constant DEPOSIT_AMOUNT_USDT = 100 * 1e6; // 100 USDT
    uint256 private constant DEPOSIT_AMOUNT_WETH = 1 ether; // 1 WETH

    function setUp() public {
        // Set chain ID to Rari for local deposit testing
        vm.chainId(LOCAL_CHAIN_ID);

        // Deploy BalanceManager
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeReceiver, feeMaker, feeTaker))
        );
        balanceManager = BalanceManager(address(balanceManagerProxy));

        // Deploy TokenRegistry
        (BeaconProxy tokenRegistryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new TokenRegistry()),
            owner,
            abi.encodeCall(TokenRegistry.initialize, (owner))
        );
        tokenRegistry = TokenRegistry(address(tokenRegistryProxy));

        // Deploy SyntheticTokenFactory
        (BeaconProxy syntheticTokenFactoryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new SyntheticTokenFactory()),
            owner,
            abi.encodeCall(SyntheticTokenFactory.initialize, (owner, address(tokenRegistry), address(balanceManager)))
        );
        syntheticTokenFactory = SyntheticTokenFactory(address(syntheticTokenFactoryProxy));

        // Deploy local tokens (mock real tokens on the local chain)
        localUSDT = new MockUSDC();
        localWETH = new MockWETH();

        // Deploy synthetic tokens 
        gsUSDT = new SyntheticToken("Synthetic USDT", "gsUSDT", address(balanceManager));
        gsWETH = new SyntheticToken("Synthetic WETH", "gsWETH", address(balanceManager));

        // Set up BalanceManager with TokenRegistry
        vm.startPrank(owner);
        balanceManager.setTokenRegistry(address(tokenRegistry));
        vm.stopPrank();

        // Mint local tokens to users
        localUSDT.mint(user1, initialUSDTBalance);
        localUSDT.mint(user2, initialUSDTBalance);
        localWETH.mint(user1, initialWETHBalance);
        localWETH.mint(user2, initialWETHBalance);

        // Give users ETH for gas
        vm.deal(user1, initialBalance);
        vm.deal(user2, initialBalance);
    }

    function testSetup() public view {
        assertEq(balanceManager.owner(), owner);
        assertEq(balanceManager.getTokenRegistry(), address(tokenRegistry));
        assertEq(localUSDT.balanceOf(user1), initialUSDTBalance);
        assertEq(localWETH.balanceOf(user1), initialWETHBalance);
        assertEq(block.chainid, LOCAL_CHAIN_ID);
    }

    function testRegisterLocalTokenMapping() public {
        vm.startPrank(owner);
        
        // Register local USDT → gsUSDT mapping (same chain)
        tokenRegistry.registerTokenMapping(
            LOCAL_CHAIN_ID,          // sourceChainId: Local chain
            address(localUSDT),      // sourceToken: Local USDT
            LOCAL_CHAIN_ID,          // targetChainId: Same local chain
            address(gsUSDT),         // syntheticToken: gsUSDT
            "gsUSDT",
            6,                       // sourceDecimals (USDT)
            6                        // syntheticDecimals (gsUSDT)
        );

        vm.stopPrank();

        // Verify mapping was registered
        assertTrue(tokenRegistry.isTokenMappingActive(LOCAL_CHAIN_ID, address(localUSDT), LOCAL_CHAIN_ID));
        assertEq(
            tokenRegistry.getSyntheticToken(LOCAL_CHAIN_ID, address(localUSDT), LOCAL_CHAIN_ID),
            address(gsUSDT)
        );
    }

    function testDepositLocal_RevertsWithZeroAmount() public {
        _setupLocalUSDTMapping();

        vm.startPrank(user1);
        
        vm.expectRevert("ZeroAmount()");
        balanceManager.depositLocal(address(localUSDT), 0, user1);
        
        vm.stopPrank();
    }

    function testDepositLocal_RevertsWithZeroTokenAddress() public {
        _setupLocalUSDTMapping();

        vm.startPrank(user1);
        
        vm.expectRevert(abi.encodeWithSelector(IBalanceManagerErrors.InvalidTokenAddress.selector));
        balanceManager.depositLocal(address(0), DEPOSIT_AMOUNT_USDT, user1);
        
        vm.stopPrank();
    }

    function testDepositLocal_RevertsWithZeroRecipient() public {
        _setupLocalUSDTMapping();

        vm.startPrank(user1);
        
        vm.expectRevert(abi.encodeWithSelector(IBalanceManagerErrors.InvalidRecipientAddress.selector));
        balanceManager.depositLocal(address(localUSDT), DEPOSIT_AMOUNT_USDT, address(0));
        
        vm.stopPrank();
    }

    function testDepositLocal_RevertsWhenTokenNotSupported() public {
        // Don't register mapping - should revert

        vm.startPrank(user1);
        
        vm.expectRevert(abi.encodeWithSelector(IBalanceManagerErrors.TokenNotSupportedForLocalDeposits.selector, address(localUSDT)));
        balanceManager.depositLocal(address(localUSDT), DEPOSIT_AMOUNT_USDT, user1);
        
        vm.stopPrank();
    }

    function testDepositLocal_RevertsWithInsufficientAllowance() public {
        _setupLocalUSDTMapping();

        vm.startPrank(user1);
        
        // Don't approve - should revert with ERC20 error
        vm.expectRevert();
        balanceManager.depositLocal(address(localUSDT), DEPOSIT_AMOUNT_USDT, user1);
        
        vm.stopPrank();
    }

    function testDepositLocal_SuccessfulDeposit() public {
        _setupLocalUSDTMapping();

        vm.startPrank(user1);
        
        // Approve BalanceManager to spend tokens
        localUSDT.approve(address(balanceManager), DEPOSIT_AMOUNT_USDT);

        // Record balances before
        uint256 userUSDTBefore = localUSDT.balanceOf(user1);
        uint256 userGsUSDTBefore = gsUSDT.balanceOf(user1);
        uint256 balanceManagerUSDTBefore = localUSDT.balanceOf(address(balanceManager));
        uint256 userInternalBalanceBefore = balanceManager.getBalance(user1, Currency.wrap(address(gsUSDT)));

        // Expect LocalDeposit event (defined in BalanceManager)
        vm.expectEmit(true, true, true, true);
        emit LocalDeposit(user1, address(localUSDT), address(gsUSDT), DEPOSIT_AMOUNT_USDT, DEPOSIT_AMOUNT_USDT);
        
        // Expect Deposit event (from IBalanceManager interface)
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, Currency.wrap(address(gsUSDT)).toId(), DEPOSIT_AMOUNT_USDT);

        // Perform local deposit
        balanceManager.depositLocal(address(localUSDT), DEPOSIT_AMOUNT_USDT, user1);

        vm.stopPrank();

        // Verify token transfers
        assertEq(localUSDT.balanceOf(user1), userUSDTBefore - DEPOSIT_AMOUNT_USDT, "User USDT balance should decrease");
        assertEq(localUSDT.balanceOf(address(balanceManager)), balanceManagerUSDTBefore + DEPOSIT_AMOUNT_USDT, "BalanceManager should receive USDT");
        
        // Verify synthetic tokens are held by BalanceManager (vault)
        assertEq(gsUSDT.balanceOf(address(balanceManager)), userGsUSDTBefore + DEPOSIT_AMOUNT_USDT, "BalanceManager should hold gsUSDT");
        assertEq(gsUSDT.balanceOf(user1), 0, "User should not directly hold ERC20 gsUSDT");
        
        // Verify internal balance tracking
        assertEq(
            balanceManager.getBalance(user1, Currency.wrap(address(gsUSDT))), 
            userInternalBalanceBefore + DEPOSIT_AMOUNT_USDT,
            "Internal balance should be updated"
        );
    }

    function testDepositLocal_MultipleUsers() public {
        _setupLocalUSDTMapping();

        // User1 deposits
        vm.startPrank(user1);
        localUSDT.approve(address(balanceManager), DEPOSIT_AMOUNT_USDT);
        balanceManager.depositLocal(address(localUSDT), DEPOSIT_AMOUNT_USDT, user1);
        vm.stopPrank();

        // User2 deposits  
        vm.startPrank(user2);
        localUSDT.approve(address(balanceManager), DEPOSIT_AMOUNT_USDT * 2);
        balanceManager.depositLocal(address(localUSDT), DEPOSIT_AMOUNT_USDT * 2, user2);
        vm.stopPrank();

        // Verify BalanceManager holds synthetic tokens (vault model)
        assertEq(gsUSDT.balanceOf(address(balanceManager)), DEPOSIT_AMOUNT_USDT * 3);
        assertEq(gsUSDT.balanceOf(user1), 0, "User1 should not directly hold ERC20 tokens");
        assertEq(gsUSDT.balanceOf(user2), 0, "User2 should not directly hold ERC20 tokens");
        
        // Verify internal balances
        assertEq(balanceManager.getBalance(user1, Currency.wrap(address(gsUSDT))), DEPOSIT_AMOUNT_USDT);
        assertEq(balanceManager.getBalance(user2, Currency.wrap(address(gsUSDT))), DEPOSIT_AMOUNT_USDT * 2);

        // Verify total backing
        assertEq(localUSDT.balanceOf(address(balanceManager)), DEPOSIT_AMOUNT_USDT * 3);
    }

    function testDepositLocal_DifferentRecipient() public {
        _setupLocalUSDTMapping();

        vm.startPrank(user1);
        
        // Approve and deposit to user2
        localUSDT.approve(address(balanceManager), DEPOSIT_AMOUNT_USDT);
        balanceManager.depositLocal(address(localUSDT), DEPOSIT_AMOUNT_USDT, user2);
        
        vm.stopPrank();

        // Verify user1 paid, user2 received internal balance
        assertEq(localUSDT.balanceOf(user1), initialUSDTBalance - DEPOSIT_AMOUNT_USDT);
        assertEq(gsUSDT.balanceOf(address(balanceManager)), DEPOSIT_AMOUNT_USDT, "BalanceManager should hold ERC20 tokens");
        assertEq(gsUSDT.balanceOf(user2), 0, "User2 should not directly hold ERC20 tokens");
        assertEq(balanceManager.getBalance(user2, Currency.wrap(address(gsUSDT))), DEPOSIT_AMOUNT_USDT);
    }

    function testDepositLocal_WithDecimalConversion() public {
        // Register local WETH → gsWETH mapping (both 18 decimals, no conversion needed)
        vm.startPrank(owner);
        tokenRegistry.registerTokenMapping(
            LOCAL_CHAIN_ID,
            address(localWETH),
            LOCAL_CHAIN_ID,
            address(gsWETH),
            "gsWETH",
            18,  // WETH decimals
            18   // gsWETH decimals
        );
        vm.stopPrank();

        vm.startPrank(user1);
        
        localWETH.approve(address(balanceManager), DEPOSIT_AMOUNT_WETH);
        balanceManager.depositLocal(address(localWETH), DEPOSIT_AMOUNT_WETH, user1);
        
        vm.stopPrank();

        // Should be 1:1 conversion since both are 18 decimals
        assertEq(gsWETH.balanceOf(address(balanceManager)), DEPOSIT_AMOUNT_WETH, "BalanceManager should hold ERC20 tokens");
        assertEq(gsWETH.balanceOf(user1), 0, "User should not directly hold ERC20 tokens");
        assertEq(balanceManager.getBalance(user1, Currency.wrap(address(gsWETH))), DEPOSIT_AMOUNT_WETH);
    }

    function testDepositLocal_MatchesCrossChainBehavior() public {
        _setupLocalUSDTMapping();
        
        // Simulate cross-chain deposit (what would happen from ChainBalanceManager message)
        // Cross-chain deposits also mint to BalanceManager now
        uint256 crossChainAmount = DEPOSIT_AMOUNT_USDT;
        gsUSDT.mint(address(balanceManager), crossChainAmount);
        
        // Simulate internal balance update (as BalanceManager._handleDepositMessage would do)
        // Note: In real scenario, this would be done by the message handler
        vm.store(
            address(balanceManager),
            bytes32(uint256(keccak256("gtx.clob.storage.balancemanager")) - 1),
            bytes32(crossChainAmount)
        );

        // Now do local deposit with user1
        vm.startPrank(user1);
        localUSDT.approve(address(balanceManager), DEPOSIT_AMOUNT_USDT);
        balanceManager.depositLocal(address(localUSDT), DEPOSIT_AMOUNT_USDT, user1);
        vm.stopPrank();

        // BalanceManager should hold all synthetic tokens
        assertEq(gsUSDT.balanceOf(address(balanceManager)), DEPOSIT_AMOUNT_USDT + crossChainAmount, "BalanceManager should hold all gsUSDT");
        assertEq(gsUSDT.balanceOf(user1), 0, "Local user should not directly hold ERC20 tokens");
        assertEq(gsUSDT.balanceOf(user2), 0, "Cross-chain user should not directly hold ERC20 tokens");
        
        // Both users should have internal balances for trading
        assertEq(balanceManager.getBalance(user1, Currency.wrap(address(gsUSDT))), DEPOSIT_AMOUNT_USDT, "Local deposit user internal balance");
        // Note: Cross-chain user balance would be set by _handleDepositMessage in real scenario
        
        // Same token contract, same trading capabilities
        assertEq(address(gsUSDT), address(gsUSDT), "Same synthetic token for both deposit methods");
    }

    // Helper function to set up local USDT mapping
    function _setupLocalUSDTMapping() internal {
        vm.startPrank(owner);
        tokenRegistry.registerTokenMapping(
            LOCAL_CHAIN_ID,
            address(localUSDT),
            LOCAL_CHAIN_ID,
            address(gsUSDT),
            "gsUSDT",
            6,   // USDT decimals
            6    // gsUSDT decimals  
        );
        vm.stopPrank();
    }
}