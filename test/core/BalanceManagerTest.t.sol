// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@scalex/mocks/MockUSDC.sol";
import "@scalex/mocks/MockWETH.sol";
import "@scalexcore/BalanceManager.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {SyntheticTokenFactory} from "../../src/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";

contract BalanceManagerTest is Test {
    IBalanceManager private balanceManager;
    ITokenRegistry private tokenRegistry;
    SyntheticTokenFactory private tokenFactory;
    address private owner = address(0x123);
    address private feeReceiver = address(0x456);
    address private user = address(0x789);
    address private operator = address(0xABC);
    Currency private weth;
    Currency private usdc;
    uint256 private feeMaker = 1; // 0.1%
    uint256 private feeTaker = 5; // 0.5%
    uint256 private initialBalance = 1000 ether;
    uint256 private initialBalanceUSDC = 1_000_000_000_000;
    uint256 private initialBalanceWETH = 1000 ether;
    uint256 constant FEE_UNIT = 1000;

    function setUp() public {
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy beaconProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeReceiver, feeMaker, feeTaker))
        );

        balanceManager = IBalanceManager(payable(address(beaconProxy)));

        MockUSDC mockUSDC = new MockUSDC();
        MockWETH mockWETH = new MockWETH();

        mockUSDC.mint(user, initialBalanceUSDC);
        mockWETH.mint(user, initialBalanceWETH);
        usdc = Currency.wrap(address(mockUSDC));
        weth = Currency.wrap(address(mockWETH));

        vm.deal(user, initialBalance);
        vm.deal(operator, initialBalance);
        
        // Set up TokenFactory for synthetic token creation
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
        
        // Create synthetic tokens and set up TokenRegistry
        vm.startPrank(owner);
        address wethSynthetic = tokenFactory.createSyntheticToken(Currency.unwrap(weth));
        address usdcSynthetic = tokenFactory.createSyntheticToken(Currency.unwrap(usdc));
        
        balanceManager.addSupportedAsset(Currency.unwrap(weth), wethSynthetic);
        balanceManager.addSupportedAsset(Currency.unwrap(usdc), usdcSynthetic);
        
        // Set BalanceManager as minter and burner for synthetic tokens
        SyntheticToken(wethSynthetic).setMinter(address(balanceManager));
        SyntheticToken(usdcSynthetic).setMinter(address(balanceManager));
        SyntheticToken(wethSynthetic).setBurner(address(balanceManager));
        SyntheticToken(usdcSynthetic).setBurner(address(balanceManager));
        
        // Register token mappings for local deposits
        uint32 currentChain = 31337; // Default foundry chain ID
        tokenRegistry.registerTokenMapping(
            currentChain, Currency.unwrap(weth), currentChain, wethSynthetic, "WETH", 18, 18
        );
        tokenRegistry.registerTokenMapping(
            currentChain, Currency.unwrap(usdc), currentChain, usdcSynthetic, "USDC", 6, 6
        );
        
        // Activate token mappings
        tokenRegistry.setTokenMappingStatus(currentChain, Currency.unwrap(weth), currentChain, true);
        tokenRegistry.setTokenMappingStatus(currentChain, Currency.unwrap(usdc), currentChain, true);
        
        balanceManager.setTokenFactory(address(tokenFactory));
        balanceManager.setTokenRegistry(address(tokenRegistry));
        vm.stopPrank();
    }

    function testDeposit() public {
        uint256 depositAmount = 100 ether;
        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount, user, user);
        vm.stopPrank();

        uint256 userBalance = balanceManager.getBalance(user, weth);
        assertEq(userBalance, depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        // Use depositLocal which mints synthetic tokens to the contract (vault pattern)
        balanceManager.depositLocal(Currency.unwrap(weth), depositAmount, user);
        balanceManager.withdraw(weth, withdrawAmount);
        vm.stopPrank();

        // Balance tracking is done internally in BalanceManager using synthetic token's currency ID
        address syntheticToken = balanceManager.getSyntheticToken(Currency.unwrap(weth));
        uint256 userBalance = balanceManager.getBalance(user, Currency.wrap(syntheticToken));
        assertEq(userBalance, depositAmount - withdrawAmount);
    }

    function testLock() public {
        uint256 depositAmount = 100 ether;
        uint256 lockAmount = 40 ether;

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount, user, user);
        vm.stopPrank();

        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        balanceManager.lock(user, weth, lockAmount);
        vm.stopPrank();

        uint256 userBalance = balanceManager.getBalance(user, weth);
        uint256 userLockedBalance = balanceManager.getLockedBalance(user, operator, weth);
        assertEq(userBalance, depositAmount - lockAmount);
        assertEq(userLockedBalance, lockAmount);
    }

    function testUnlock() public {
        uint256 depositAmount = 100 ether;
        uint256 lockAmount = 40 ether;

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount, user, user);
        vm.stopPrank();

        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        balanceManager.lock(user, weth, lockAmount);
        balanceManager.unlock(user, weth, lockAmount);
        vm.stopPrank();

        uint256 userBalance = balanceManager.getBalance(user, weth);
        uint256 userLockedBalance = balanceManager.getLockedBalance(user, operator, weth);
        assertEq(userBalance, depositAmount);
        assertEq(userLockedBalance, 0);
    }

    function testTransferLockedFrom() public {
        uint256 depositAmount = 100 ether;
        uint256 lockAmount = 50 ether;
        address receiver = address(0xFED);

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount, user, user);
        vm.stopPrank();

        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        balanceManager.lock(user, weth, lockAmount);
        balanceManager.transferLockedFrom(user, receiver, weth, lockAmount);
        vm.stopPrank();

        uint256 receiverBalance = balanceManager.getBalance(receiver, weth);
        assertEq(receiverBalance, lockAmount * (FEE_UNIT - feeTaker) / FEE_UNIT);
    }

    function testTransferFrom() public {
        uint256 depositAmount = 100 ether;
        uint256 transfer = 40 ether;
        address receiver = address(0xFED);

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount, user, user);
        vm.stopPrank();

        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        balanceManager.transferFrom(user, receiver, weth, transfer);
        vm.stopPrank();

        uint256 receiverBalance = balanceManager.getBalance(receiver, weth);
        assertEq(receiverBalance, transfer * (FEE_UNIT - feeMaker) / FEE_UNIT);
    }
}

