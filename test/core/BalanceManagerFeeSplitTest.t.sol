// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {SyntheticTokenFactory} from "../../src/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";

contract BalanceManagerFeeSplitTest is Test {
    IBalanceManager public balanceManager;
    ITokenRegistry public tokenRegistry;
    SyntheticTokenFactory public tokenFactory;
    MockToken public usdc;

    address public owner = address(0x1);
    address public feeReceiver = address(0x2);
    address public maker = address(0x3);
    address public taker = address(0x4);
    address public operator = address(0x5);

    Currency public usdcCurrency;
    address public syntheticUSDC;

    function setUp() public {
        usdc = new MockToken("USDC", "USDC", 6);
        usdcCurrency = Currency.wrap(address(usdc));

        // Deploy BalanceManager proxy
        address impl = address(new BalanceManager());
        ERC1967Proxy proxy = new ERC1967Proxy(
            impl,
            abi.encodeWithSelector(
                BalanceManager.initialize.selector,
                owner,
                feeReceiver,
                5,   // feeMaker = 5/1000 = 0.5%
                10   // feeTaker = 10/1000 = 1.0%
            )
        );
        balanceManager = IBalanceManager(payable(address(proxy)));

        // Deploy TokenFactory
        tokenFactory = new SyntheticTokenFactory();
        tokenFactory.initialize(owner, owner);

        // Deploy TokenRegistry
        address tokenRegistryImpl = address(new TokenRegistry());
        ERC1967Proxy tokenRegistryProxy = new ERC1967Proxy(
            tokenRegistryImpl,
            abi.encodeWithSelector(TokenRegistry.initialize.selector, owner)
        );
        tokenRegistry = ITokenRegistry(address(tokenRegistryProxy));

        vm.startPrank(owner);

        // Create synthetic token and register
        syntheticUSDC = tokenFactory.createSyntheticToken(address(usdc));
        balanceManager.addSupportedAsset(address(usdc), syntheticUSDC);

        // Set minter/burner
        SyntheticToken(syntheticUSDC).setMinter(address(balanceManager));
        SyntheticToken(syntheticUSDC).setBurner(address(balanceManager));

        // Register token mapping
        uint32 chain = 31337;
        tokenRegistry.registerTokenMapping(chain, address(usdc), chain, syntheticUSDC, "USDC", 6, 6);
        tokenRegistry.setTokenMappingStatus(chain, address(usdc), chain, true);

        balanceManager.setTokenFactory(address(tokenFactory));
        balanceManager.setTokenRegistry(address(tokenRegistry));

        // Set protocol fee and authorize operator
        balanceManager.setFeeProtocol(3); // 0.3% protocol fee
        balanceManager.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        // Fund maker and taker via deposit
        usdc.mint(maker, 100_000 * 1e6);
        usdc.mint(taker, 100_000 * 1e6);

        vm.startPrank(maker);
        usdc.approve(address(balanceManager), type(uint256).max);
        balanceManager.deposit(usdcCurrency, 50_000 * 1e6, maker, maker);
        vm.stopPrank();

        vm.startPrank(taker);
        usdc.approve(address(balanceManager), type(uint256).max);
        balanceManager.deposit(usdcCurrency, 50_000 * 1e6, taker, taker);
        vm.stopPrank();
    }

    function test_TransferLockedFrom_FeeSplit() public {
        uint256 amount = 10_000 * 1e6;

        // Lock maker's balance (simulating a limit order)
        vm.prank(operator);
        balanceManager.lock(maker, usdcCurrency, amount);

        // Record balances before
        uint256 takerBefore = balanceManager.getBalance(taker, usdcCurrency);
        uint256 makerBefore = balanceManager.getBalance(maker, usdcCurrency);
        uint256 protocolBefore = balanceManager.getBalance(feeReceiver, usdcCurrency);

        // Execute: transferLockedFrom (maker's locked → taker, with fee split)
        vm.prank(operator);
        balanceManager.transferLockedFrom(maker, taker, usdcCurrency, amount);

        // Calculate expected values (feeUnit = 1000)
        uint256 totalFee = amount * 10 / 1000;       // 1.0% = 100 USDC
        uint256 protocolFee = amount * 3 / 1000;      // 0.3% = 30 USDC
        uint256 makerReward = totalFee - protocolFee;  // 0.7% = 70 USDC

        // Verify taker gets amount minus total fee (unchanged behavior)
        uint256 takerAfter = balanceManager.getBalance(taker, usdcCurrency);
        assertEq(takerAfter - takerBefore, amount - totalFee, "Taker should receive amount - totalFee");

        // Verify protocol gets only its portion
        uint256 protocolAfter = balanceManager.getBalance(feeReceiver, usdcCurrency);
        assertEq(protocolAfter - protocolBefore, protocolFee, "Protocol should receive protocolFee only");

        // Verify maker gets rebate
        uint256 makerAfter = balanceManager.getBalance(maker, usdcCurrency);
        assertEq(makerAfter - makerBefore, makerReward, "Maker should receive makerReward rebate");

        // Verify no tokens lost
        assertEq(totalFee, protocolFee + makerReward, "protocolFee + makerReward must equal totalFee");

        console.log("transferLockedFrom fee split:");
        console.log("  Amount:", amount / 1e6, "USDC");
        console.log("  Total fee:", totalFee / 1e6, "USDC");
        console.log("  Protocol fee:", protocolFee / 1e6, "USDC");
        console.log("  Maker reward:", makerReward / 1e6, "USDC");
    }

    function test_TransferFrom_FeeSplit() public {
        uint256 amount = 10_000 * 1e6;

        // Record balances before
        uint256 makerBefore = balanceManager.getBalance(maker, usdcCurrency);
        uint256 takerBefore = balanceManager.getBalance(taker, usdcCurrency);
        uint256 protocolBefore = balanceManager.getBalance(feeReceiver, usdcCurrency);

        // Execute: transferFrom (taker → maker, with fee split)
        vm.prank(operator);
        balanceManager.transferFrom(taker, maker, usdcCurrency, amount);

        // Calculate expected values
        uint256 protocolFee = amount * 3 / 1000;       // 0.3% = 30 USDC

        // Verify taker loses full amount
        uint256 takerAfter = balanceManager.getBalance(taker, usdcCurrency);
        assertEq(takerBefore - takerAfter, amount, "Taker should lose full amount");

        // Verify maker gets amount minus only protocol fee
        uint256 makerAfter = balanceManager.getBalance(maker, usdcCurrency);
        assertEq(makerAfter - makerBefore, amount - protocolFee, "Maker should receive amount - protocolFee");

        // Verify protocol gets only its portion
        uint256 protocolAfter = balanceManager.getBalance(feeReceiver, usdcCurrency);
        assertEq(protocolAfter - protocolBefore, protocolFee, "Protocol should receive protocolFee only");

        console.log("transferFrom fee split:");
        console.log("  Amount:", amount / 1e6, "USDC");
        console.log("  Protocol fee:", protocolFee / 1e6, "USDC");
        console.log("  Maker receives:", (amount - protocolFee) / 1e6, "USDC");
    }

    function test_FeeProtocol_Zero_AllToMaker() public {
        // Set feeProtocol to 0: maker gets ALL of the fee
        vm.prank(owner);
        balanceManager.setFeeProtocol(0);

        uint256 amount = 10_000 * 1e6;

        vm.prank(operator);
        balanceManager.lock(maker, usdcCurrency, amount);

        uint256 makerBefore = balanceManager.getBalance(maker, usdcCurrency);
        uint256 protocolBefore = balanceManager.getBalance(feeReceiver, usdcCurrency);

        vm.prank(operator);
        balanceManager.transferLockedFrom(maker, taker, usdcCurrency, amount);

        uint256 totalFee = amount * 10 / 1000; // 100 USDC

        // Protocol gets nothing
        uint256 protocolAfter = balanceManager.getBalance(feeReceiver, usdcCurrency);
        assertEq(protocolAfter - protocolBefore, 0, "Protocol should get 0 when feeProtocol=0");

        // Maker gets all the fee as reward
        uint256 makerAfter = balanceManager.getBalance(maker, usdcCurrency);
        assertEq(makerAfter - makerBefore, totalFee, "Maker should get entire fee when feeProtocol=0");
    }

    function test_FeeProtocol_EqualToFeeTaker_AllToProtocol() public {
        // First set feeMaker equal to feeTaker so feeProtocol can match both
        vm.startPrank(owner);
        balanceManager.setFees(10, 10); // feeMaker=10, feeTaker=10
        balanceManager.setFeeProtocol(10); // feeProtocol = feeTaker = feeMaker
        vm.stopPrank();

        uint256 amount = 10_000 * 1e6;

        vm.prank(operator);
        balanceManager.lock(maker, usdcCurrency, amount);

        uint256 makerBefore = balanceManager.getBalance(maker, usdcCurrency);
        uint256 protocolBefore = balanceManager.getBalance(feeReceiver, usdcCurrency);

        vm.prank(operator);
        balanceManager.transferLockedFrom(maker, taker, usdcCurrency, amount);

        uint256 totalFee = amount * 10 / 1000; // 100 USDC

        // Protocol gets everything
        uint256 protocolAfter = balanceManager.getBalance(feeReceiver, usdcCurrency);
        assertEq(protocolAfter - protocolBefore, totalFee, "Protocol should get entire fee");

        // Maker gets nothing
        uint256 makerAfter = balanceManager.getBalance(maker, usdcCurrency);
        assertEq(makerAfter - makerBefore, 0, "Maker should get 0 when feeProtocol=feeTaker");
    }

    function test_SetFeeProtocol_Validation() public {
        // Should revert when feeProtocol > feeMaker (feeMaker=5 < feeTaker=10)
        vm.prank(owner);
        vm.expectRevert("feeProtocol > feeMaker");
        balanceManager.setFeeProtocol(6); // feeMaker is 5

        // Should revert when feeProtocol > feeTaker
        vm.startPrank(owner);
        balanceManager.setFees(15, 10); // feeMaker=15, feeTaker=10
        vm.expectRevert("feeProtocol > feeTaker");
        balanceManager.setFeeProtocol(11); // feeTaker is 10
        vm.stopPrank();

        // Should succeed when feeProtocol <= min(feeMaker, feeTaker)
        vm.prank(owner);
        balanceManager.setFeeProtocol(5);
        assertEq(balanceManager.feeProtocol(), 5);
    }

    function test_SetFees_AdjustsFeeProtocol() public {
        // Set feeProtocol to max allowed (min of feeMaker=5, feeTaker=10 → 5)
        vm.startPrank(owner);
        balanceManager.setFeeProtocol(5);
        assertEq(balanceManager.feeProtocol(), 5);

        // Lower fees below feeProtocol → feeProtocol should be auto-adjusted
        balanceManager.setFees(3, 4);
        assertTrue(balanceManager.feeProtocol() <= 3, "feeProtocol should be capped to min(feeMaker, feeTaker)");
        vm.stopPrank();
    }
}
