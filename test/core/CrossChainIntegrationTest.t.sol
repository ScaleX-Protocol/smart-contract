// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import {IMessageRecipient} from "../../src/core/interfaces/IMessageRecipient.sol";
import {ChainBalanceManager} from "../../src/core/ChainBalanceManager.sol";
import {IBalanceManagerErrors} from "../../src/core/interfaces/IBalanceManagerErrors.sol";
import {SyntheticTokenFactory} from "../../src/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import {HyperlaneMessages} from "../../src/core/libraries/HyperlaneMessages.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockMailbox {
    event Dispatch(uint32 destinationDomain, bytes32 recipient, bytes message);
    
    function dispatch(uint32 destinationDomain, bytes32 recipient, bytes calldata messageBody) external payable returns (bytes32) {
        emit Dispatch(destinationDomain, recipient, messageBody);
        return keccak256(messageBody);
    }
}

contract CrossChainIntegrationTest is Test {
    IBalanceManager balanceManager;
    ITokenRegistry tokenRegistry;
    SyntheticTokenFactory tokenFactory;
    ChainBalanceManager chainBalanceManager;
    MockToken sourceToken;
    MockToken syntheticToken; // Legacy - will be replaced by factory token
    MockToken sourceSynthetic; // Actually created by factory
    MockMailbox mailbox;
    
    // For accessing handle function which is in IMessageRecipient interface
    IMessageRecipient messageRecipient;
    
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    
    uint32 constant RARI_DOMAIN = 1_918_988_905;
    uint32 constant APPCHAIN_DOMAIN = 4661;
    
    event CrossChainDepositReceived(address indexed user, Currency indexed currency, uint256 amount, uint32 sourceChain);
    event CrossChainWithdrawSent(address indexed user, Currency indexed currency, uint256 amount, uint32 targetChain);
    event BridgeToSynthetic(address indexed user, address indexed sourceToken, address indexed syntheticToken, uint256 amount);
    event WithdrawMessageReceived(address indexed user, address indexed token, uint256 amount);

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy tokens and mailbox
        sourceToken = new MockToken("USDC", "USDC", 6);
        // syntheticToken will be created by token factory later
        mailbox = new MockMailbox();
        
        // Deploy BalanceManager (destination chain - Rari)
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, owner, 25, 50))
        );
        balanceManager = IBalanceManager(payable(address(balanceManagerProxy)));

        // Deploy TokenRegistry and TokenFactory
        tokenFactory = new SyntheticTokenFactory();
        tokenFactory.initialize(owner, owner);
        
        // Deploy TokenRegistry
        address tokenRegistryImpl = address(new TokenRegistry());
        ERC1967Proxy tokenRegistryProxy = new ERC1967Proxy(
            tokenRegistryImpl,
            abi.encodeWithSelector(
                TokenRegistry.initialize.selector,
                owner
            )
        );
        tokenRegistry = ITokenRegistry(address(tokenRegistryProxy));
        
        // Deploy ChainBalanceManager (source chain - Appchain)
        (BeaconProxy chainBMProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new ChainBalanceManager()),
            owner,
            abi.encodeWithSignature(
                "initialize(address,address,uint32,address)",
                owner,
                address(mailbox),
                RARI_DOMAIN,
                address(balanceManager)
            )
        );
        chainBalanceManager = ChainBalanceManager(address(chainBMProxy));
        
        // Initialize cross-chain on BalanceManager
        balanceManager.initializeCrossChain(address(mailbox), RARI_DOMAIN);
        balanceManager.setChainBalanceManager(APPCHAIN_DOMAIN, address(chainBalanceManager));
        
        // Create synthetic token and set up TokenRegistry
        address sourceSyntheticAddr = tokenFactory.createSyntheticToken(address(sourceToken));
        sourceSynthetic = MockToken(sourceSyntheticAddr);
        syntheticToken = MockToken(sourceSyntheticAddr); // Set the main syntheticToken reference
        
        balanceManager.addSupportedAsset(address(sourceToken), sourceSyntheticAddr);
        
        // Set BalanceManager as minter and burner for synthetic token
        SyntheticToken(sourceSyntheticAddr).setMinter(address(balanceManager));
        SyntheticToken(sourceSyntheticAddr).setBurner(address(balanceManager));
        
        // Register token mappings for local deposits
        uint32 currentChain = 31337; // Default foundry chain ID
        tokenRegistry.registerTokenMapping(
            currentChain, address(sourceToken), currentChain, sourceSyntheticAddr, "USDC", 6, 6
        );
        
        // Also register cross-chain mappings
        tokenRegistry.registerTokenMapping(
            RARI_DOMAIN, address(sourceToken), RARI_DOMAIN, sourceSyntheticAddr, "USDC", 6, 6
        );
        
        // Activate token mappings
        tokenRegistry.setTokenMappingStatus(currentChain, address(sourceToken), currentChain, true);
        tokenRegistry.setTokenMappingStatus(RARI_DOMAIN, address(sourceToken), RARI_DOMAIN, true);
        
        balanceManager.setTokenFactory(address(tokenFactory));
        balanceManager.setTokenRegistry(address(tokenRegistry));
        messageRecipient = IMessageRecipient(address(balanceManager));
        
        // Configure ChainBalanceManager
        chainBalanceManager.addToken(address(sourceToken));
        chainBalanceManager.setTokenMapping(address(sourceToken), address(sourceSynthetic));
        
        // Setup test balances
        sourceToken.mint(user, 1000e6); // 1000 USDC
        // Note: synthetic tokens will be minted through proper deposit flow
        
        vm.stopPrank();
    }

    function test_CrossChainDeposit() public {
        uint256 depositAmount = 100e6; // 100 USDC
        
        vm.startPrank(user);
        
        // Approve and deposit to vault (this automatically bridges to synthetic)
        sourceToken.approve(address(chainBalanceManager), depositAmount);
        
        // Expect the BridgeToSynthetic event to be emitted during deposit
        vm.expectEmit(true, true, true, true);
        emit BridgeToSynthetic(user, address(sourceToken), address(syntheticToken), depositAmount);
        
        chainBalanceManager.deposit(address(sourceToken), depositAmount, user);
        
        // Verify nonce incremented
        assertEq(chainBalanceManager.getUserNonce(user), 1);
        
        vm.stopPrank();
    }

    function test_CrossChainMessageHandling() public {
        uint256 amount = 50e6; // 50 USDC
        uint256 nonce = 123;
        
        // Create deposit message (simulating message from ChainBalanceManager)
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: address(syntheticToken),
            user: user,
            amount: amount,
            sourceChainId: APPCHAIN_DOMAIN,
            nonce: nonce
        });
        
        bytes memory messageBody = abi.encode(message);
        bytes32 sender = bytes32(uint256(uint160(address(chainBalanceManager))));
        
        // Simulate Hyperlane mailbox call
        vm.startPrank(address(mailbox));
        
        vm.expectEmit(true, true, true, true);
        emit CrossChainDepositReceived(user, Currency.wrap(address(syntheticToken)), amount, APPCHAIN_DOMAIN);
        
        messageRecipient.handle(APPCHAIN_DOMAIN, bytes32(sender), messageBody);
        
        // Verify synthetic token balance credited
        assertEq(balanceManager.getBalance(user, Currency.wrap(address(sourceSynthetic))), amount);
        
        vm.stopPrank();
    }

    function test_CrossChainWithdraw() public {
        uint256 withdrawAmount = 25e6; // 25 USDC
        
        // Setup: Give user synthetic tokens
        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(address(this), true);
        
        // Give user source tokens for local deposit
        sourceToken.mint(user, 100e6);
        vm.stopPrank();
        
        // Use depositLocal which will automatically mint synthetic tokens
        vm.startPrank(user);
        sourceToken.approve(address(balanceManager), 100e6);
        balanceManager.depositLocal(address(sourceToken), 100e6, user);
        vm.stopPrank();
        
        // Verify initial balance
        assertEq(balanceManager.getBalance(user, Currency.wrap(address(sourceSynthetic))), 100e6);
        
        vm.startPrank(user);
        
        vm.expectEmit(true, true, true, true);
        emit CrossChainWithdrawSent(user, Currency.wrap(address(syntheticToken)), withdrawAmount, APPCHAIN_DOMAIN);
        
        balanceManager.requestWithdraw(
            Currency.wrap(address(syntheticToken)),
            withdrawAmount,
            APPCHAIN_DOMAIN,
            user
        );
        
        // Verify synthetic tokens burned
        assertEq(balanceManager.getBalance(user, Currency.wrap(address(syntheticToken))), 75e6);
        
        // Verify nonce incremented
        assertEq(balanceManager.getUserNonce(user), 1);
        
        vm.stopPrank();
    }

    function test_WithdrawMessageHandling() public {
        uint256 amount = 30e6; // 30 USDC
        uint256 nonce = 456;
        
        // Setup: Deposit tokens to vault first
        vm.startPrank(user);
        sourceToken.approve(address(chainBalanceManager), 100e6);
        chainBalanceManager.deposit(address(sourceToken), 100e6, user);
        vm.stopPrank();
        
        // Create withdraw message (simulating message from BalanceManager)
        HyperlaneMessages.WithdrawMessage memory message = HyperlaneMessages.WithdrawMessage({
            messageType: HyperlaneMessages.WITHDRAW_MESSAGE,
            syntheticToken: address(syntheticToken),
            recipient: user,
            amount: amount,
            targetChainId: APPCHAIN_DOMAIN,
            nonce: nonce
        });
        
        bytes memory messageBody = abi.encode(message);
        bytes32 sender = bytes32(uint256(uint160(address(balanceManager))));
        
        // Simulate Hyperlane mailbox call
        vm.startPrank(address(mailbox));
        
        vm.expectEmit(true, true, true, true);
        emit WithdrawMessageReceived(user, address(sourceToken), amount);
        
        chainBalanceManager.handle(RARI_DOMAIN, sender, messageBody);
        
        // Verify tokens unlocked for withdrawal
        assertEq(chainBalanceManager.getUnlockedBalance(user, address(sourceToken)), amount);
        
        vm.stopPrank();
        
        // User can now claim unlocked tokens
        vm.startPrank(user);
        uint256 userBalanceBefore = sourceToken.balanceOf(user);
        
        chainBalanceManager.claim(address(sourceToken), amount);
        
        assertEq(sourceToken.balanceOf(user), userBalanceBefore + amount);
        assertEq(chainBalanceManager.getUnlockedBalance(user, address(sourceToken)), 0);
        
        vm.stopPrank();
    }

    function test_ReplayProtection() public {
        uint256 amount = 10e6;
        uint256 nonce = 789;
        
        // Create message
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: address(syntheticToken),
            user: user,
            amount: amount,
            sourceChainId: APPCHAIN_DOMAIN,
            nonce: nonce
        });
        
        bytes memory messageBody = abi.encode(message);
        bytes32 sender = bytes32(uint256(uint160(address(chainBalanceManager))));
        
        vm.startPrank(address(mailbox));
        
        // First message should succeed
        messageRecipient.handle(APPCHAIN_DOMAIN, bytes32(sender), messageBody);
        assertEq(balanceManager.getBalance(user, Currency.wrap(address(sourceSynthetic))), amount);
        
        // Second identical message should fail (replay protection)
        bytes32 expectedMessageId = keccak256(abi.encodePacked(APPCHAIN_DOMAIN, user, nonce));
        vm.expectRevert(abi.encodeWithSelector(IBalanceManagerErrors.MessageAlreadyProcessed.selector, expectedMessageId));
        messageRecipient.handle(APPCHAIN_DOMAIN, bytes32(sender), messageBody);
        
        vm.stopPrank();
    }

    function test_UnauthorizedSender() public {
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: address(syntheticToken),
            user: user,
            amount: 10e6,
            sourceChainId: APPCHAIN_DOMAIN,
            nonce: 1
        });
        
        bytes memory messageBody = abi.encode(message);
        bytes32 wrongSender = bytes32(uint256(uint160(makeAddr("attacker"))));
        
        vm.startPrank(address(mailbox));
        
        bytes32 expectedSender = bytes32(uint256(uint160(address(chainBalanceManager))));
        vm.expectRevert(abi.encodeWithSelector(IBalanceManagerErrors.InvalidSender.selector, expectedSender, wrongSender));
        messageRecipient.handle(APPCHAIN_DOMAIN, bytes32(wrongSender), messageBody);
        
        vm.stopPrank();
    }

    function test_CrossChainConfiguration() public {
        // Test mailbox configuration
        (address mailboxAddr, uint32 localDomain) = balanceManager.getMailboxConfig();
        assertEq(mailboxAddr, address(mailbox));
        assertEq(localDomain, RARI_DOMAIN);
        
        // Test chain balance manager configuration
        assertEq(balanceManager.getChainBalanceManager(APPCHAIN_DOMAIN), address(chainBalanceManager));
        
        // Test token mapping
        assertEq(chainBalanceManager.getTokenMapping(address(sourceToken)), address(syntheticToken));
        assertEq(chainBalanceManager.getReverseTokenMapping(address(syntheticToken)), address(sourceToken));
    }
}