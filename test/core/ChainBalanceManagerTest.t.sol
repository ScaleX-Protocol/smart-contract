// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@gtx/mocks/MockUSDC.sol";
import "@gtx/mocks/MockWETH.sol";
import "../../src/core/ChainBalanceManager.sol";
import "../../src/core/interfaces/IChainBalanceManagerErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract ChainBalanceManagerTest is Test {
    ChainBalanceManager private chainBalanceManager;
    address private owner = address(0x123);
    address private user1 = address(0x789);
    address private user2 = address(0xABC);
    address private notOwner = address(0xDEF);
    
    MockUSDC private mockUSDC;
    MockWETH private mockWETH;
    
    uint256 private initialBalance = 1000 ether;
    uint256 private initialBalanceUSDC = 1_000_000_000_000;
    uint256 private initialBalanceWETH = 1000 ether;

    function setUp() public {
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy beaconProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new ChainBalanceManager()),
            owner,
            abi.encodeCall(ChainBalanceManager.initialize, (owner))
        );

        chainBalanceManager = ChainBalanceManager(address(beaconProxy));

        mockUSDC = new MockUSDC();
        mockWETH = new MockWETH();

        mockUSDC.mint(user1, initialBalanceUSDC);
        mockWETH.mint(user1, initialBalanceWETH);
        mockUSDC.mint(user2, initialBalanceUSDC);
        mockWETH.mint(user2, initialBalanceWETH);

        vm.deal(user1, initialBalance);
        vm.deal(user2, initialBalance);
        vm.deal(owner, initialBalance);
    }

    function test_Initialize() public {
        assertEq(chainBalanceManager.owner(), owner);
    }

    function test_AddToken() public {
        vm.prank(owner);
        chainBalanceManager.addToken(address(mockUSDC));
        
        assertTrue(chainBalanceManager.isTokenWhitelisted(address(mockUSDC)));
        
        address[] memory tokens = chainBalanceManager.getWhitelistedTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(mockUSDC));
    }

    function test_AddTokenRevertIfNotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert();
        chainBalanceManager.addToken(address(mockUSDC));
    }

    function test_AddTokenRevertIfAlreadyWhitelisted() public {
        vm.prank(owner);
        chainBalanceManager.addToken(address(mockUSDC));
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IChainBalanceManagerErrors.TokenAlreadyWhitelisted.selector, address(mockUSDC)));
        chainBalanceManager.addToken(address(mockUSDC));
    }

    function test_RemoveToken() public {
        vm.prank(owner);
        chainBalanceManager.addToken(address(mockUSDC));
        
        vm.prank(owner);
        chainBalanceManager.removeToken(address(mockUSDC));
        
        assertFalse(chainBalanceManager.isTokenWhitelisted(address(mockUSDC)));
        
        address[] memory tokens = chainBalanceManager.getWhitelistedTokens();
        assertEq(tokens.length, 0);
    }

    function test_RemoveTokenRevertIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IChainBalanceManagerErrors.TokenNotFound.selector, address(mockUSDC)));
        chainBalanceManager.removeToken(address(mockUSDC));
    }

    function test_DepositETH() public {
        uint256 depositAmount = 5 ether;
        
        vm.prank(user1);
        chainBalanceManager.deposit{value: depositAmount}(address(0), depositAmount);
        
        assertEq(chainBalanceManager.getBalance(user1, address(0)), depositAmount);
        assertEq(address(chainBalanceManager).balance, depositAmount);
    }

    function test_DepositERC20() public {
        uint256 depositAmount = 1000e6; // 1000 USDC
        
        vm.prank(owner);
        chainBalanceManager.addToken(address(mockUSDC));
        
        vm.prank(user1);
        mockUSDC.approve(address(chainBalanceManager), depositAmount);
        
        vm.prank(user1);
        chainBalanceManager.deposit(address(mockUSDC), depositAmount);
        
        assertEq(chainBalanceManager.getBalance(user1, address(mockUSDC)), depositAmount);
        assertEq(mockUSDC.balanceOf(address(chainBalanceManager)), depositAmount);
    }

    function test_DepositRevertIfTokenNotWhitelisted() public {
        uint256 depositAmount = 1000e6;
        
        vm.prank(user1);
        mockUSDC.approve(address(chainBalanceManager), depositAmount);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IChainBalanceManagerErrors.TokenNotWhitelisted.selector, address(mockUSDC)));
        chainBalanceManager.deposit(address(mockUSDC), depositAmount);
    }

    function test_DepositRevertIfZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(IChainBalanceManagerErrors.ZeroAmount.selector);
        chainBalanceManager.deposit(address(0), 0);
    }

    function test_WithdrawETH() public {
        uint256 depositAmount = 5 ether;
        uint256 withdrawAmount = 2 ether;
        
        // Deposit first
        vm.prank(user1);
        chainBalanceManager.deposit{value: depositAmount}(address(0), depositAmount);
        
        uint256 userBalanceBefore = user1.balance;
        
        // Owner withdraws for user
        vm.prank(owner);
        chainBalanceManager.withdraw(address(0), withdrawAmount, user1);
        
        assertEq(chainBalanceManager.getBalance(user1, address(0)), depositAmount - withdrawAmount);
        assertEq(user1.balance, userBalanceBefore + withdrawAmount);
    }

    function test_WithdrawERC20() public {
        uint256 depositAmount = 1000e6;
        uint256 withdrawAmount = 400e6;
        
        vm.prank(owner);
        chainBalanceManager.addToken(address(mockUSDC));
        
        // Deposit first
        vm.prank(user1);
        mockUSDC.approve(address(chainBalanceManager), depositAmount);
        
        vm.prank(user1);
        chainBalanceManager.deposit(address(mockUSDC), depositAmount);
        
        uint256 userBalanceBefore = mockUSDC.balanceOf(user1);
        
        // Owner withdraws for user
        vm.prank(owner);
        chainBalanceManager.withdraw(address(mockUSDC), withdrawAmount, user1);
        
        assertEq(chainBalanceManager.getBalance(user1, address(mockUSDC)), depositAmount - withdrawAmount);
        assertEq(mockUSDC.balanceOf(user1), userBalanceBefore + withdrawAmount);
    }

    function test_WithdrawRevertIfNotOwner() public {
        uint256 depositAmount = 5 ether;
        
        vm.prank(user1);
        chainBalanceManager.deposit{value: depositAmount}(address(0), depositAmount);
        
        vm.prank(notOwner);
        vm.expectRevert();
        chainBalanceManager.withdraw(address(0), 1 ether, user1);
    }

    function test_WithdrawRevertIfInsufficientBalance() public {
        uint256 depositAmount = 5 ether;
        uint256 withdrawAmount = 10 ether;
        
        vm.prank(user1);
        chainBalanceManager.deposit{value: depositAmount}(address(0), depositAmount);
        
        vm.prank(owner);
        vm.expectRevert();
        chainBalanceManager.withdraw(address(0), withdrawAmount, user1);
    }

    function test_WithdrawRevertIfZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(IChainBalanceManagerErrors.ZeroAmount.selector);
        chainBalanceManager.withdraw(address(0), 0, user1);
    }

    function test_MultipleUsersDeposits() public {
        uint256 depositAmount1 = 3 ether;
        uint256 depositAmount2 = 7 ether;
        
        vm.prank(user1);
        chainBalanceManager.deposit{value: depositAmount1}(address(0), depositAmount1);
        
        vm.prank(user2);
        chainBalanceManager.deposit{value: depositAmount2}(address(0), depositAmount2);
        
        assertEq(chainBalanceManager.getBalance(user1, address(0)), depositAmount1);
        assertEq(chainBalanceManager.getBalance(user2, address(0)), depositAmount2);
        assertEq(address(chainBalanceManager).balance, depositAmount1 + depositAmount2);
    }

    function test_ETHAlwaysWhitelisted() public {
        assertTrue(chainBalanceManager.isTokenWhitelisted(address(0)));
    }

    function test_GetTokenCount() public {
        assertEq(chainBalanceManager.getTokenCount(), 0);
        
        vm.prank(owner);
        chainBalanceManager.addToken(address(mockUSDC));
        assertEq(chainBalanceManager.getTokenCount(), 1);
        
        vm.prank(owner);
        chainBalanceManager.addToken(address(mockWETH));
        assertEq(chainBalanceManager.getTokenCount(), 2);
        
        vm.prank(owner);
        chainBalanceManager.removeToken(address(mockUSDC));
        assertEq(chainBalanceManager.getTokenCount(), 1);
    }
}