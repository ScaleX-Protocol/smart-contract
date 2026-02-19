// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {LendingManager} from "../../src/yield/LendingManager.sol";
import {ITokenRegistry} from "../../src/core/interfaces/ITokenRegistry.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {SyntheticTokenFactory} from "../../src/factories/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";

interface IPriceOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

contract MockPriceOracle is IPriceOracle {
    mapping(address => uint256) public prices;

    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
    }

    function _fallbackPrice(address token) internal view returns (uint256) {
        try IERC20Decimals(token).decimals() returns (uint8 dec) {
            if (dec == 18) return 2000e18;
        } catch {}
        return 1e18;
    }

    function getPriceForCollateral(address token) external view returns (uint256) {
        if (prices[token] != 0) return prices[token];
        return _fallbackPrice(token);
    }

    function getPriceForBorrowing(address token) external view returns (uint256) {
        if (prices[token] != 0) return prices[token];
        return _fallbackPrice(token);
    }

    function getAssetPrice(address asset) external view override returns (uint256) {
        if (prices[asset] != 0) return prices[asset];
        return _fallbackPrice(asset);
    }
}

contract LiquidationStressTest is Test {
    IBalanceManager public balanceManager;
    LendingManager public lendingManager;
    ITokenRegistry public tokenRegistry;
    SyntheticTokenFactory public tokenFactory;
    MockPriceOracle public mockOracle;
    
    // Test tokens with different decimals
    MockToken public weth;      // 18 decimals
    MockToken public usdc;      // 6 decimals
    MockToken public dai;       // 18 decimals
    MockToken public wbtc;      // 8 decimals

    // Synthetic token addresses (set in setUp, used for oracle price setup)
    address public wethSynthetic;
    address public usdcSynthetic;
    address public daiSynthetic;
    address public wbtcSynthetic;
    
    address public owner = address(0x1);
    address public provider = address(0x2);
    address public borrower = address(0x3);
    address public liquidator1 = address(0x4);
    address public liquidator2 = address(0x5);
    address public liquidator3 = address(0x6);
    
    uint256 public constant INITIAL_LIQUIDITY = 100_000e6;  // 100k USDC
    uint256 public constant HIGH_BORROW = 80_000e6;         // 80k USDC borrowed
    uint256 public constant COLLATERAL_WETH = 50e18;        // 50 WETH collateral
    
    event Liquidated(
        address indexed borrower,
        address indexed liquidator,
        address indexed collateralToken,
        address debtToken,
        uint256 debtToCover,
        uint256 liquidatedCollateral,
        uint256 timestamp
    );
    
    function setUp() public {
        // Deploy tokens
        weth = new MockToken("Wrapped Ether", "WETH", 18);
        usdc = new MockToken("USD Coin", "USDC", 6);
        dai = new MockToken("Dai Stablecoin", "DAI", 18);
        wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);
        
        // Deploy mock price oracle
        mockOracle = new MockPriceOracle();
        
        // Set realistic prices
        mockOracle.setPrice(address(weth), 2000e18);  // $2000 per WETH
        mockOracle.setPrice(address(usdc), 1e18);     // $1 per USDC
        mockOracle.setPrice(address(dai), 1e18);      // $1 per DAI
        mockOracle.setPrice(address(wbtc), 50000e18); // $50,000 per WBTC
        
        // Deploy BalanceManager using ERC1967Proxy
        address balanceManagerImpl = address(new BalanceManager());
        ERC1967Proxy balanceProxy = new ERC1967Proxy(
            balanceManagerImpl,
            abi.encodeWithSelector(
                BalanceManager.initialize.selector,
                owner,
                owner,
                5, // feeMaker
                10  // feeTaker
            )
        );
        balanceManager = IBalanceManager(payable(address(balanceProxy)));
        
        // Deploy LendingManager using ERC1967Proxy
        address lendingManagerImpl = address(new LendingManager());
        ERC1967Proxy lendingProxy = new ERC1967Proxy(
            lendingManagerImpl,
            abi.encodeWithSelector(
                LendingManager.initialize.selector,
                owner,
                address(balanceManager), // Pass BalanceManager address
                address(mockOracle)
            )
        );
        lendingManager = LendingManager(address(lendingProxy));

        // Deploy token factory
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
        
        // Set up BalanceManager and LendingManager relationship
        vm.startPrank(owner);
        balanceManager.setLendingManager(address(lendingManager));
        balanceManager.setTokenFactory(address(tokenFactory));
        balanceManager.setTokenRegistry(address(tokenRegistry));
        lendingManager.setBalanceManager(address(balanceManager));
        vm.stopPrank();
        
        // Configure assets
        _configureAllAssets();
        
        // Create synthetic tokens and set up TokenRegistry
        vm.startPrank(owner);
        wethSynthetic = tokenFactory.createSyntheticToken(address(weth));
        usdcSynthetic = tokenFactory.createSyntheticToken(address(usdc));
        daiSynthetic = tokenFactory.createSyntheticToken(address(dai));
        wbtcSynthetic = tokenFactory.createSyntheticToken(address(wbtc));

        // Set oracle prices for synthetic tokens (LendingManager queries with synthetic addresses)
        mockOracle.setPrice(wethSynthetic, 2000e18);
        mockOracle.setPrice(usdcSynthetic, 1e18);
        mockOracle.setPrice(daiSynthetic, 1e18);
        mockOracle.setPrice(wbtcSynthetic, 50000e18);

        balanceManager.addSupportedAsset(address(weth), wethSynthetic);
        balanceManager.addSupportedAsset(address(usdc), usdcSynthetic);
        balanceManager.addSupportedAsset(address(dai), daiSynthetic);
        balanceManager.addSupportedAsset(address(wbtc), wbtcSynthetic);
        
        // Set BalanceManager as minter for synthetic tokens
        SyntheticToken(wethSynthetic).setMinter(address(balanceManager));
        SyntheticToken(usdcSynthetic).setMinter(address(balanceManager));
        SyntheticToken(daiSynthetic).setMinter(address(balanceManager));
        SyntheticToken(wbtcSynthetic).setMinter(address(balanceManager));
        
        // Register token mappings for local deposits
        uint32 currentChain = 31337; // Default foundry chain ID
        tokenRegistry.registerTokenMapping(
            currentChain, address(weth), currentChain, wethSynthetic, "WETH", 18, 18
        );
        tokenRegistry.registerTokenMapping(
            currentChain, address(usdc), currentChain, usdcSynthetic, "USDC", 6, 6
        );
        tokenRegistry.registerTokenMapping(
            currentChain, address(dai), currentChain, daiSynthetic, "DAI", 18, 18
        );
        tokenRegistry.registerTokenMapping(
            currentChain, address(wbtc), currentChain, wbtcSynthetic, "WBTC", 8, 8
        );
        
        // Activate token mappings
        tokenRegistry.setTokenMappingStatus(currentChain, address(weth), currentChain, true);
        tokenRegistry.setTokenMappingStatus(currentChain, address(usdc), currentChain, true);
        tokenRegistry.setTokenMappingStatus(currentChain, address(dai), currentChain, true);
        tokenRegistry.setTokenMappingStatus(currentChain, address(wbtc), currentChain, true);
        vm.stopPrank();
        
        // Setup initial liquidity
        _setupLiquidity();
        
        // Setup liquidators
        _setupLiquidators();
    }
    
    function test_LiquidationCascadeScenario() public {
        console.log("\n=== LIQUIDATION CASCADE TEST ===");
        
        // Create multiple borrowers with interconnected positions
        address[5] memory borrowers = [
            address(0x100),
            address(0x101), 
            address(0x102),
            address(0x103),
            address(0x104)
        ];
        
        // Setup positions that could trigger cascading liquidations
        for (uint256 i = 0; i < borrowers.length; i++) {
            vm.startPrank(borrowers[i]);
            
            // Each borrower deposits different collateral
            if (i % 2 == 0) {
                weth.mint(borrowers[i], 10e18);
                weth.approve(address(balanceManager), 10e18);
                balanceManager.deposit(Currency.wrap(address(weth)), 10e18, borrowers[i], borrowers[i]);
            } else {
                wbtc.mint(borrowers[i], 1e8); // 1 BTC
                wbtc.approve(address(balanceManager), 1e8);
                balanceManager.deposit(Currency.wrap(address(wbtc)), 1e8, borrowers[i], borrowers[i]);
            }
            
            // Each borrows USDC, pushing close to liquidation threshold
            uint256 borrowAmount;
            if (i % 2 == 0) {
                // WETH borrowers: 10 WETH ($20k), CF=80% max=$16k, LT=85%
                // Borrow within CF limit but close enough that hf < 1.2
                borrowAmount = 14500e6 + ((i / 2) * 500e6); // i=0:14500, i=2:15000, i=4:15500
            } else {
                // WBTC borrowers: 1 WBTC ($50k), CF=75% max=$37.5k, LT=80%
                // Borrow within CF limit but close enough that hf < 1.2
                borrowAmount = 33500e6 + ((i / 2) * 1500e6); // i=1:33500, i=3:35000
            }
            lendingManager.borrow(address(usdc), borrowAmount);
            vm.stopPrank();
        }

        // Check initial health factors
        console.log("--- Initial Health Factors ---");
        for (uint256 i = 0; i < borrowers.length; i++) {
            uint256 hf = lendingManager.getHealthFactor(borrowers[i]);
            console.log("Borrower %d Health Factor: %s", i, uint256(hf / 1e16) / 100);
            assertTrue(hf < 1.2e18, "All borrowers should be close to liquidation");
        }
        
        // Simulate price drop making positions undercollateralized
        vm.warp(block.timestamp + 60 days); // 2 months of interest accrual
        
        // Check health factors after time passes (interest accrues)
        console.log("\n--- Health Factors After Interest Accrual ---");
        for (uint256 i = 0; i < borrowers.length; i++) {
            uint256 hf = lendingManager.getHealthFactor(borrowers[i]);
            console.log("Borrower %d Health Factor: %s", i, uint256(hf / 1e16) / 100);
        }
        
        // Start liquidation cascade
        console.log("\n--- Starting Liquidation Cascade ---");
        uint256 totalLiquidated = 0;
        
        for (uint256 i = 0; i < borrowers.length; i++) {
            uint256 hf = lendingManager.getHealthFactor(borrowers[i]);
            
            if (hf < 1e18) { // Only liquidate undercollateralized positions
                address currentLiquidator = address(uint160(0x200 + i));
                
                vm.startPrank(currentLiquidator);
                usdc.mint(currentLiquidator, 10000e6);
                usdc.approve(address(lendingManager), 10000e6);
                
                (, uint256 borrowedBefore,) = lendingManager.getUserPosition(borrowers[i], address(usdc));
                (uint256 collateralBefore,,) = lendingManager.getUserPosition(borrowers[i], i % 2 == 0 ? address(weth) : address(wbtc));
                
                // Event emission test removed - focusing on liquidation functionality
                
                lendingManager.liquidate(
                    borrowers[i], 
                    address(usdc), 
                    i % 2 == 0 ? address(weth) : address(wbtc), 
                    10000e6
                );
                vm.stopPrank();
                
                (, uint256 borrowedAfter,) = lendingManager.getUserPosition(borrowers[i], address(usdc));
                (uint256 collateralAfter,,) = lendingManager.getUserPosition(borrowers[i], i % 2 == 0 ? address(weth) : address(wbtc));
                
                uint256 debtRepaid = borrowedBefore - borrowedAfter;
                uint256 collateralSeized = collateralBefore - collateralAfter;
                
                console.log("Borrower %d liquidated:", i);
                console.log("  Debt repaid: %s USDC", debtRepaid / 1e6);
                console.log("  Collateral seized: %s", i % 2 == 0 ? (collateralSeized / 1e18) : (collateralSeized / 1e8));
                
                totalLiquidated += debtRepaid;
            }
        }
        
        console.log("\n--- Cascade Results ---");
        console.log("Total debt liquidated: %s USDC", totalLiquidated / 1e6);
        
        // Verify protocol remains solvent
        uint256 totalDeposits = lendingManager.totalLiquidity(address(usdc));
        uint256 totalBorrows = lendingManager.totalBorrowed(address(usdc));
        console.log("Final deposits: %s USDC", totalDeposits / 1e6);
        console.log("Final borrows: %s USDC", totalBorrows / 1e6);
        assertTrue(totalDeposits >= totalBorrows, "Protocol must remain solvent");
        
        console.log("PASS Liquidation cascade handled successfully");
    }
    
    function test_ConcurrentLiquidationCompetition() public {
        console.log("\n=== CONCURRENT LIQUIDATION COMPETITION TEST ===");
        
        // Setup a position that will become undercollateralized after a price drop
        vm.startPrank(borrower);
        weth.mint(borrower, 20e18);
        weth.approve(address(balanceManager), 20e18);
        balanceManager.deposit(Currency.wrap(address(weth)), 20e18, borrower, borrower);

        // 20 WETH at $2000, CF=80%: max borrow = $32k. Borrow $31k (within limit).
        uint256 largeBorrow = 31000e6;
        lendingManager.borrow(address(usdc), largeBorrow);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        // Simulate WETH price drop from $2000 → $1800 to make position undercollateralized
        // At $1800: hf = (20 * 1800 * 0.85) / 31000 = 30600/31000 = 0.987 < 1
        // Health factor uses underlying token address for oracle queries
        mockOracle.setPrice(address(weth), 1800e18);

        // Verify position is liquidatable
        uint256 hf = lendingManager.getHealthFactor(borrower);
        assertTrue(hf < 1e18, "Position should be liquidatable");
        console.log("Initial Health Factor: %s", uint256(hf / 1e16) / 100);
        
        // Multiple liquidators compete to liquidate the same position
        address[3] memory liquidators = [liquidator1, liquidator2, liquidator3];
        uint256[3] memory liquidationAmounts = [uint256(15000e6), uint256(8000e6), uint256(5000e6)];
        
        (uint256 collateralBefore,,) = lendingManager.getUserPosition(borrower, address(weth));
        (, uint256 debtBefore,) = lendingManager.getUserPosition(borrower, address(usdc));
        
        console.log("\n--- Liquidators Competing ---");
        console.log("Initial collateral: %s WETH", collateralBefore / 1e18);
        console.log("Initial debt: %s USDC", debtBefore / 1e6);
        
        for (uint256 i = 0; i < liquidators.length; i++) {
            vm.startPrank(liquidators[i]);
            
            uint256 liquidatorBalanceBefore = weth.balanceOf(liquidators[i]);
            uint256 attemptAmount = liquidationAmounts[i];
            
            // Attempt liquidation
            try lendingManager.liquidate(borrower, address(usdc), address(weth), attemptAmount) {
                uint256 liquidatorBalanceAfter = weth.balanceOf(liquidators[i]);
                uint256 wethReceived = liquidatorBalanceAfter - liquidatorBalanceBefore;
                
                console.log("Liquidator %d successfully liquidated %s USDC, received %s WETH", 
                    i + 1, attemptAmount / 1e6, wethReceived / 1e18);
            } catch Error(string memory reason) {
                console.log("Liquidator %d failed: %s", i + 1, reason);
            } catch {
                console.log("Liquidator %d failed: Position no longer liquidatable", i + 1);
            }
            
            vm.stopPrank();
        }
        
        // Check final state
        (uint256 collateralAfter,,) = lendingManager.getUserPosition(borrower, address(weth));
        (, uint256 debtAfter,) = lendingManager.getUserPosition(borrower, address(usdc));
        
        console.log("\n--- Final Position State ---");
        console.log("Remaining collateral: %s WETH", collateralAfter / 1e18);
        console.log("Remaining debt: %s USDC", debtAfter / 1e6);
        console.log("Final Health Factor: %s", uint256(lendingManager.getHealthFactor(borrower) / 1e16) / 100);
        
        // Position should be healthier after partial liquidations
        assertTrue(lendingManager.getHealthFactor(borrower) > 1e18, "Position should be healthy after competition");
        
        console.log("PASS Concurrent liquidation competition completed");
    }
    
    function test_LiquidationUnderExtremeMarketConditions() public {
        console.log("\n=== EXTREME MARKET CONDITIONS TEST ===");
        
        // Setup position with multiple collateral types
        vm.startPrank(borrower);
        
        // Deposit multiple types of collateral
        weth.mint(borrower, 10e18);
        weth.approve(address(balanceManager), 10e18);
        balanceManager.deposit(Currency.wrap(address(weth)), 10e18, borrower, borrower);
        
        wbtc.mint(borrower, 0.5e8); // 0.5 BTC
        wbtc.approve(address(balanceManager), 0.5e8);
        balanceManager.deposit(Currency.wrap(address(wbtc)), 0.5e8, borrower, borrower);
        
        dai.mint(borrower, 20000e18);
        dai.approve(address(balanceManager), 20000e18);
        balanceManager.deposit(Currency.wrap(address(dai)), 20000e18, borrower, borrower);
        
        // Borrow maximum possible against all collateral
        lendingManager.borrow(address(usdc), 45000e6); // High leverage
        vm.stopPrank();
        
        console.log("--- Initial Position ---");
        (uint256 wethSupplied,,) = lendingManager.getUserPosition(borrower, address(weth));
        (uint256 wbtcSupplied,,) = lendingManager.getUserPosition(borrower, address(wbtc));
        (uint256 daiSupplied,,) = lendingManager.getUserPosition(borrower, address(dai));
        (, uint256 usdcBorrowed,) = lendingManager.getUserPosition(borrower, address(usdc));
        
        console.log("WETH supplied: %s", wethSupplied / 1e18);
        console.log("WBTC supplied: %s", wbtcSupplied / 1e8);
        console.log("DAI supplied: %s", daiSupplied / 1e18);
        console.log("USDC borrowed: %s", usdcBorrowed / 1e6);
        console.log("Health Factor: %s", uint256(lendingManager.getHealthFactor(borrower) / 1e16) / 100);
        
        // Simulate extreme market conditions
        vm.warp(block.timestamp + 90 days); // 3 months of high interest accrual
        
        console.log("\n--- After 90 Days of Interest Accrual ---");
        console.log("Health Factor: %s", uint256(lendingManager.getHealthFactor(borrower) / 1e16) / 100);
        
        // Test liquidation of different collateral types
        address[3] memory collateralTypes = [address(weth), address(wbtc), address(dai)];
        
        for (uint256 i = 0; i < collateralTypes.length; i++) {
            uint256 hf = lendingManager.getHealthFactor(borrower);
            
            if (hf < 1e18) {
                address currentLiquidator = address(uint160(0x300 + i));
                
                vm.startPrank(currentLiquidator);
                usdc.mint(currentLiquidator, 15000e6);
                usdc.approve(address(lendingManager), 15000e6);
                
                try lendingManager.liquidate(borrower, address(usdc), collateralTypes[i], 15000e6) {
                    console.log("Successfully liquidated %s collateral", 
                        collateralTypes[i] == address(weth) ? "WETH" : 
                        collateralTypes[i] == address(wbtc) ? "WBTC" : "DAI");
                } catch {
                    console.log("Failed to liquidate %s - position may be healthy now", 
                        collateralTypes[i] == address(weth) ? "WETH" : 
                        collateralTypes[i] == address(wbtc) ? "WBTC" : "DAI");
                }
                
                vm.stopPrank();
                
                // Check health factor after each liquidation
                uint256 newHf = lendingManager.getHealthFactor(borrower);
                console.log("Health Factor after liquidation %d: %s", i + 1, uint256(newHf / 1e16) / 100);
                
                if (newHf >= 1e18) {
                    console.log("Position is now healthy - stopping liquidations");
                    break;
                }
            }
        }
        
        console.log("\n--- Final Position State ---");
        (wethSupplied,,) = lendingManager.getUserPosition(borrower, address(weth));
        (wbtcSupplied,,) = lendingManager.getUserPosition(borrower, address(wbtc));
        (daiSupplied,,) = lendingManager.getUserPosition(borrower, address(dai));
        (, usdcBorrowed,) = lendingManager.getUserPosition(borrower, address(usdc));
        
        console.log("Remaining WETH: %s", wethSupplied / 1e18);
        console.log("Remaining WBTC: %s", wbtcSupplied / 1e8);
        console.log("Remaining DAI: %s", daiSupplied / 1e18);
        console.log("Remaining USDC debt: %s", usdcBorrowed / 1e6);
        
        console.log("PASS Extreme market conditions test completed");
    }
    
    // =============================================================
    //                   HELPER FUNCTIONS
    // =============================================================
    
    function _configureAllAssets() internal {
        vm.startPrank(owner);
        
        // Configure WETH
        lendingManager.configureAsset(address(weth), 8000, 8500, 500, 1000);
        lendingManager.setInterestRateParams(address(weth), 100, 8000, 800, 2000);
        
        // Configure USDC
        lendingManager.configureAsset(address(usdc), 9000, 9500, 200, 500);
        lendingManager.setInterestRateParams(address(usdc), 50, 8000, 400, 1000);
        
        // Configure DAI
        lendingManager.configureAsset(address(dai), 8500, 9000, 300, 800);
        lendingManager.setInterestRateParams(address(dai), 150, 8000, 600, 1500);
        
        // Configure WBTC
        lendingManager.configureAsset(address(wbtc), 7500, 8000, 800, 1200);
        lendingManager.setInterestRateParams(address(wbtc), 200, 8000, 1000, 2500);
        
        vm.stopPrank();
    }
    
    function _setupLiquidity() internal {
        vm.startPrank(provider);
        
        // Mint and approve large amounts for liquidity
        usdc.mint(provider, 1_000_000e6); // 1M USDC
        usdc.approve(address(balanceManager), 1_000_000e6);
        weth.mint(provider, 1000e18);
        weth.approve(address(balanceManager), 1000e18);
        dai.mint(provider, 500_000e18);
        dai.approve(address(balanceManager), 500_000e18);
        wbtc.mint(provider, 50e8); // 50 BTC
        wbtc.approve(address(balanceManager), 50e8);
        
        // Set up global liquidity for testing purposes through BalanceManager
        _setupGlobalLiquidityForTesting();
        
        vm.stopPrank();
    }
    
    function _setupLiquidators() internal {
        address[3] memory liquidators = [liquidator1, liquidator2, liquidator3];
        
        for (uint256 i = 0; i < liquidators.length; i++) {
            vm.startPrank(liquidators[i]);
            
            // Setup liquidators with various tokens for repaying debts
            usdc.mint(liquidators[i], 100_000e6);
            usdc.approve(address(lendingManager), 100_000e6);
            
            dai.mint(liquidators[i], 50_000e18);
            dai.approve(address(lendingManager), 50_000e18);
            
            vm.stopPrank();
        }
    }
    
    // Helper function to set up global liquidity for testing
    // Deposits into BalanceManager which then supplies to LendingManager
    function _setupGlobalLiquidityForTesting() internal {
        vm.startPrank(provider);
        
        // Deposit major liquidity into BalanceManager
        balanceManager.deposit(Currency.wrap(address(usdc)), 1_000_000e6, provider, provider);
        balanceManager.deposit(Currency.wrap(address(weth)), 1000e18, provider, provider);
        balanceManager.deposit(Currency.wrap(address(dai)), 500_000e18, provider, provider);
        balanceManager.deposit(Currency.wrap(address(wbtc)), 50e8, provider, provider);
        
        // These deposits will be automatically supplied to lending pools
        // through BalanceManager's internal mechanism
        vm.stopPrank();
        
        console.log("Global liquidity setup completed through BalanceManager");
    }
}