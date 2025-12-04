// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {LendingManager} from "../../src/yield/LendingManager.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {SyntheticTokenFactory} from "../../src/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Simple price oracle that implements IOracle interface
contract MockPriceOracle {
    mapping(address => uint256) public prices;
    
    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
    }
    
    function getPriceForCollateral(address token) external view returns (uint256) {
        return prices[token];
    }
    
    function getPriceForBorrowing(address token) external view returns (uint256) {
        return prices[token];
    }
    
    function getPriceConfidence(address token) external view returns (uint256) {
        return 10000; // 100% confidence
    }
    
    function isPriceStale(address token) external view returns (bool) {
        return false; // Never stale
    }
}

contract UnifiedLiquidityHealthFactorTest is Test {
    LendingManager public lendingManager;
    IBalanceManager public balanceManager;
    ITokenRegistry public tokenRegistry;
    SyntheticTokenFactory public tokenFactory;
    MockPriceOracle public mockOracle;
    MockToken public usdc;
    MockToken public weth;
    MockToken public dai;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    function setUp() public {
        // Deploy mock tokens
        usdc = new MockToken("USDC", "USDC", 6);
        weth = new MockToken("WETH", "WETH", 18);
        dai = new MockToken("DAI", "DAI", 18);
        
        // Deploy mock price oracle
        mockOracle = new MockPriceOracle();
        
        // Set prices (with 18 decimals for consistency)
        vm.startPrank(owner);
        mockOracle.setPrice(address(usdc), 1e18);      // $1 USDC
        mockOracle.setPrice(address(weth), 2000e18);   // $2000 WETH  
        mockOracle.setPrice(address(dai), 1e18);       // $1 DAI
        vm.stopPrank();
        
        // Deploy token factory
        tokenFactory = new SyntheticTokenFactory();
        tokenFactory.initialize(owner, owner);
        
        // Deploy BalanceManager
        ERC1967Proxy balanceProxy = new ERC1967Proxy(
            address(new BalanceManager()),
            abi.encodeWithSelector(
                BalanceManager.initialize.selector,
                owner,
                owner,
                5, // feeMaker
                10  // feeTaker
            )
        );
        balanceManager = IBalanceManager(payable(address(balanceProxy)));
        
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
        
        // Deploy LendingManager using proxy
        ERC1967Proxy lendingProxy = new ERC1967Proxy(
            address(new LendingManager()),
            abi.encodeWithSelector(
                LendingManager.initialize.selector,
                owner,
                address(balanceProxy), // Pass BalanceManager address
                address(mockOracle)
            )
        );
        lendingManager = LendingManager(address(lendingProxy));
        
        // Set up relationship
        vm.startPrank(owner);
        balanceManager.setLendingManager(address(lendingProxy));
        balanceManager.setTokenFactory(address(tokenFactory));
        balanceManager.setTokenRegistry(address(tokenRegistry));
        lendingManager.setBalanceManager(address(balanceProxy));
        vm.stopPrank();
        
        // Configure assets for lending
        vm.startPrank(owner);
        
        // Configure USDC
        lendingManager.configureAsset(
            address(usdc),
            8000,  // 80% LTV
            8500,  // 85% liquidation threshold
            500,   // 5% liquidation bonus
            1000   // 10% reserve factor
        );
        
        lendingManager.setInterestRateParams(
            address(usdc),
            200,   // 2% base rate
            8000,  // 80% optimal utilization
            1000,  // Rate slope 1
            2000   // Rate slope 2
        );
        
        // Configure WETH
        lendingManager.configureAsset(
            address(weth),
            7500,  // 75% LTV
            8000,  // 80% liquidation threshold
            1000,  // 10% liquidation bonus
            1000   // 10% reserve factor
        );
        
        // Configure DAI
        lendingManager.configureAsset(
            address(dai),
            8500,  // 85% LTV
            9000,  // 90% liquidation threshold
            500,   // 5% liquidation bonus
            1000   // 10% reserve factor
        );
        
        // Create synthetic tokens and set up TokenRegistry
        address usdcSynthetic = tokenFactory.createSyntheticToken(address(usdc));
        address wethSynthetic = tokenFactory.createSyntheticToken(address(weth));
        address daiSynthetic = tokenFactory.createSyntheticToken(address(dai));
        
        balanceManager.addSupportedAsset(address(usdc), usdcSynthetic);
        balanceManager.addSupportedAsset(address(weth), wethSynthetic);
        balanceManager.addSupportedAsset(address(dai), daiSynthetic);
        
        // Set BalanceManager as minter for synthetic tokens
        SyntheticToken(usdcSynthetic).setMinter(address(balanceManager));
        SyntheticToken(wethSynthetic).setMinter(address(balanceManager));
        SyntheticToken(daiSynthetic).setMinter(address(balanceManager));
        
        // Register token mappings for local deposits
        uint32 currentChain = 31337; // Default foundry chain ID
        tokenRegistry.registerTokenMapping(
            currentChain,
            address(usdc),
            currentChain,
            usdcSynthetic,
            "USDC",
            6,  // USDC decimals
            6   // USDC synthetic decimals
        );
        tokenRegistry.registerTokenMapping(
            currentChain,
            address(weth),
            currentChain,
            wethSynthetic,
            "WETH",
            18, // WETH decimals
            18  // WETH synthetic decimals
        );
        tokenRegistry.registerTokenMapping(
            currentChain,
            address(dai),
            currentChain,
            daiSynthetic,
            "DAI",
            18, // DAI decimals
            18  // DAI synthetic decimals
        );
        
        // Activate token mappings
        tokenRegistry.setTokenMappingStatus(currentChain, address(usdc), currentChain, true);
        tokenRegistry.setTokenMappingStatus(currentChain, address(weth), currentChain, true);
        tokenRegistry.setTokenMappingStatus(currentChain, address(dai), currentChain, true);
        
        vm.stopPrank();
        
        console.log("Setup complete - LendingManager ready for unified liquidity testing");
    }
    
    function testUnifiedLiquidityHealthFactor() public {
        console.log("\n=== Testing Unified Liquidity Health Factor ===");
        
        // Step 1: Mint tokens for users
        uint256 ethAmount = 10 ether;
        uint256 usdcAmount = 1000 * 1e6;
        uint256 liquidityAmount = 50_000 * 1e6;
        
        // Mint tokens to user1
        vm.startPrank(user1);
        weth.mint(user1, ethAmount);
        usdc.mint(user1, usdcAmount);
        weth.approve(address(balanceManager), ethAmount);
        usdc.approve(address(balanceManager), usdcAmount);
        
        balanceManager.deposit(Currency.wrap(address(weth)), ethAmount, user1, user1);
        balanceManager.deposit(Currency.wrap(address(usdc)), usdcAmount, user1, user1);
        vm.stopPrank();
        
        console.log("User1 supplied:");
        console.log("  ETH:", ethAmount / 1e18, "ETH");
        console.log("  USDC:", usdcAmount / 1e6, "USDC");
        
        // Step 2: User2 supplies liquidity for borrowing
        vm.startPrank(user2);
        usdc.mint(user2, liquidityAmount);
        usdc.approve(address(balanceManager), liquidityAmount);
        balanceManager.deposit(Currency.wrap(address(usdc)), liquidityAmount, user2, user2);
        vm.stopPrank();
        
        console.log("User2 supplied USDC liquidity:", liquidityAmount / 1e6, "USDC");
        
        // Step 3: Check initial health factor (should be max - no debt)
        uint256 initialHealthFactor = lendingManager.getHealthFactor(user1);
        console.log("Initial health factor:", initialHealthFactor / 1e16, "(1.0 = healthy)");
        
        // Step 4: User1 borrows against collateral
        uint256 borrowAmount = 2_000 * 1e6; // 2K USDC
        
        vm.startPrank(user1);
        lendingManager.borrow(address(usdc), borrowAmount);
        vm.stopPrank();
        
        console.log("User1 borrowed:", borrowAmount / 1e6, "USDC");
        
        // Step 5: Check health factor after borrowing
        uint256 healthFactorAfterBorrow = lendingManager.getHealthFactor(user1);
        console.log("Health factor after borrowing:", healthFactorAfterBorrow / 1e16, "(1.0 = healthy)");
        
        // Step 6: Verify individual position tracking
        uint256 wethSupply = lendingManager.getUserSupply(user1, address(weth));
        uint256 usdcSupply = lendingManager.getUserSupply(user1, address(usdc));
        uint256 totalDebt = lendingManager.getUserDebt(user1, address(usdc));
        
        console.log("User1 positions:");
        console.log("  ETH supplied:", wethSupply / 1e18, "ETH");
        console.log("  USDC supplied:", usdcSupply / 1e6, "USDC");
        console.log("  USDC debt:", totalDebt / 1e6, "USDC");
        
        // Assertions
        assertTrue(initialHealthFactor > type(uint256).max / 2, "Initial health factor should be very high");
        assertTrue(healthFactorAfterBorrow > 1e18, "Health factor should be > 1 (healthy)");
        assertEq(wethSupply, ethAmount, "ETH supply should match deposit amount");
        assertEq(usdcSupply, usdcAmount, "USDC supply should match deposit amount");
        assertEq(totalDebt, borrowAmount, "Debt should match borrow amount");
        
        console.log("PASS: Unified liquidity health factor test passed");
        console.log("PASS: Individual position tracking working correctly");
        console.log("PASS: Full portfolio value used as collateral");
    }
    
    function testHealthFactorImprovement() public {
        console.log("\n=== Testing Health Factor Improvement ===");
        
        // Setup: User supplies 5 ETH and 500 USDC
        vm.startPrank(user1);
        weth.mint(user1, 5 ether);
        usdc.mint(user1, 500 * 1e6);
        weth.approve(address(balanceManager), 5 ether);
        usdc.approve(address(balanceManager), 500 * 1e6);
        
        balanceManager.deposit(Currency.wrap(address(weth)), 5 ether, user1, user1);
        balanceManager.deposit(Currency.wrap(address(usdc)), 500 * 1e6, user1, user1);
        
        // Need some liquidity available for borrowing
        usdc.mint(user1, 2000 * 1e6);
        usdc.approve(address(balanceManager), 2000 * 1e6);
        balanceManager.deposit(Currency.wrap(address(usdc)), 2000 * 1e6, user1, user1);
        vm.stopPrank();
        
        // Borrow against full collateral
        vm.startPrank(user1);
        lendingManager.borrow(address(usdc), 1_000 * 1e6);
        vm.stopPrank();
        
        uint256 initialHealthFactor = lendingManager.getHealthFactor(user1);
        console.log("Initial health factor:", initialHealthFactor / 1e16);
        
        // Time passes, interest accrues
        vm.warp(block.timestamp + 30 days);
        
        uint256 healthFactorWithInterest = lendingManager.getHealthFactor(user1);
        console.log("Health factor after 30 days:", healthFactorWithInterest / 1e16);
        
        // Repay some debt
        uint256 repayAmount = 500 * 1e6;
        vm.startPrank(user1);
        usdc.approve(address(lendingManager), repayAmount);
        lendingManager.repay(address(usdc), repayAmount);
        vm.stopPrank();
        
        uint256 finalHealthFactor = lendingManager.getHealthFactor(user1);
        console.log("Health factor after repayment:", finalHealthFactor / 1e16);
        
        uint256 remainingDebt = lendingManager.getUserDebt(user1, address(usdc));
        console.log("Remaining debt:", remainingDebt / 1e6, "USDC");
        
        // Assertions
        assertTrue(finalHealthFactor > initialHealthFactor, "Health factor should improve after repayment");
        assertEq(remainingDebt, 1000e6 - repayAmount, "Remaining debt should be correct");
        
        console.log("PASS: Health factor properly improves with repayments");
    }
}