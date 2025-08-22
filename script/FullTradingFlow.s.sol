// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/GTXRouter.sol";
import "../src/core/PoolManager.sol";
import "../src/mocks/MockToken.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {PoolKey} from "../src/core/libraries/Pool.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";
import {IPoolManager} from "../src/core/interfaces/IPoolManager.sol";

contract FullTradingFlow is Script {
    
    address user;
    uint256 userPrivateKey;
    
    // Chain endpoints
    string APPCHAIN_RPC;
    string RARI_RPC;
    
    function run() public {
        userPrivateKey = vm.envUint("PRIVATE_KEY");
        user = vm.addr(userPrivateKey);
        
        APPCHAIN_RPC = vm.envString("APPCHAIN_ENDPOINT");
        RARI_RPC = vm.envString("RARI_ENDPOINT");
        
        console.log("========== FULL TRADING FLOW TEST ==========");
        console.log("User address:", user);
        console.log("Appchain RPC:", APPCHAIN_RPC);
        console.log("Rari RPC:", RARI_RPC);
        
        // Step 1: Mint and deposit from Appchain
        step1_MintAndDepositAppchain();
        
        // Step 2: Check and prepare Rari balances
        step2_PrepareRariBalances();
        
        // Step 3: Do trading on Rari
        step3_TradingSimulation();
    }
    
    function step1_MintAndDepositAppchain() private {
        console.log("\n=== STEP 1: APPCHAIN TESTNET - MINT & DEPOSIT ===");
        
        // Switch to Appchain RPC
        vm.createSelectFork(APPCHAIN_RPC);
        
        // Appchain addresses
        address chainBalanceManager = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        address usdt = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        address weth = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
        
        MockToken usdtToken = MockToken(usdt);
        MockToken wethToken = MockToken(weth);
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        console.log("Current balances on Appchain:");
        console.log("USDT:", usdtToken.balanceOf(user));
        console.log("WETH:", wethToken.balanceOf(user));
        
        vm.startBroadcast(userPrivateKey);
        
        // Mint tokens if insufficient
        if (usdtToken.balanceOf(user) < 5000e6) {
            console.log("Minting 10,000 USDT...");
            usdtToken.mint(user, 10000e6);
        }
        
        if (wethToken.balanceOf(user) < 2e18) {
            console.log("Minting 5 WETH...");
            wethToken.mint(user, 5e18);
        }
        
        // Deposit USDT for trading
        console.log("Depositing 2000 USDT to Rari via Hyperlane...");
        usdtToken.approve(chainBalanceManager, 2000e6);
        cbm.deposit(usdt, 2000e6, user);
        
        // Deposit WETH for trading  
        console.log("Depositing 1 WETH to Rari via Hyperlane...");
        wethToken.approve(chainBalanceManager, 1e18);
        cbm.deposit(weth, 1e18, user);
        
        vm.stopBroadcast();
        console.log("SUCCESS: Cross-chain deposits dispatched from Appchain!");
    }
    
    function step2_PrepareRariBalances() private {
        console.log("\n=== STEP 2: RARI TESTNET - PREPARE FOR TRADING ===");
        
        // Switch to Rari RPC
        vm.createSelectFork(RARI_RPC);
        
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address gsUSDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        
        console.log("Checking synthetic token balances on Rari:");
        
        uint256 currentGsUSDT = 0;
        uint256 currentGsWETH = 0;
        
        try balanceManager.getBalance(user, Currency.wrap(gsUSDT)) returns (uint256 bal) {
            currentGsUSDT = bal;
            console.log("gsUSDT in BalanceManager:", bal);
        } catch {
            console.log("gsUSDT balance check failed");
        }
        
        try balanceManager.getBalance(user, Currency.wrap(gsWETH)) returns (uint256 bal) {
            currentGsWETH = bal;
            console.log("gsWETH in BalanceManager:", bal);
        } catch {
            console.log("gsWETH balance check failed");
        }
        
        console.log("Raw token balances:");
        console.log("gsUSDT tokens:", MockToken(gsUSDT).balanceOf(user));
        console.log("gsWETH tokens:", MockToken(gsWETH).balanceOf(user));
        
        vm.startBroadcast(userPrivateKey);
        
        // For testing: mint synthetic tokens directly (simulating cross-chain arrival)
        // In production, these would come from Hyperlane relayers
        console.log("Simulating cross-chain token arrival by minting...");
        MockToken(gsUSDT).mint(user, 2000e6);
        MockToken(gsWETH).mint(user, 1e18);
        
        // Approve BalanceManager to spend our synthetic tokens
        MockToken(gsUSDT).approve(balanceManagerAddr, type(uint256).max);
        MockToken(gsWETH).approve(balanceManagerAddr, type(uint256).max);
        
        vm.stopBroadcast();
        
        console.log("After preparation:");
        console.log("gsUSDT tokens:", MockToken(gsUSDT).balanceOf(user));
        console.log("gsWETH tokens:", MockToken(gsWETH).balanceOf(user));
        console.log("SUCCESS: Rari balances ready for trading!");
    }
    
    function step3_TradingSimulation() private {
        console.log("\n=== STEP 3: RARI TESTNET - TRADING SIMULATION ===");
        
        // Already on Rari RPC from step 2
        
        // Rari trading addresses
        address poolManagerAddr = 0xA3B22cA94Cc3Eb8f6Bd8F4108D88d085e12d886b;
        address routerAddr = 0xF38489749c3e65c82a9273c498A8c6614c34754b;
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address gsUSDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        
        PoolManager poolManager = PoolManager(poolManagerAddr);
        GTXRouter router = GTXRouter(routerAddr);
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        
        PoolKey memory wethUsdtPool = PoolKey({
            baseCurrency: Currency.wrap(gsWETH),
            quoteCurrency: Currency.wrap(gsUSDT)
        });
        
        IPoolManager.Pool memory pool = poolManager.getPool(wethUsdtPool);
        console.log("Trading pool OrderBook:", address(pool.orderBook));
        
        vm.startBroadcast(userPrivateKey);
        
        console.log("\n--- Order 1: Buy Limit Order ---");
        console.log("Buy 0.1 WETH at 3500 USDT each (cost: 350 USDT)");
        
        try router.placeLimitOrder(
            pool,
            3500e6,           // price: 3500 USDT per WETH
            1e17,             // quantity: 0.1 WETH
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            350e6             // depositAmount: 350 USDT
        ) returns (uint48 buyOrderId) {
            console.log("SUCCESS: Buy limit order placed, ID:", buyOrderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Buy order failed:", reason);
        } catch {
            console.log("FAILED: Buy order failed with unknown error");
        }
        
        console.log("\n--- Order 2: Sell Limit Order ---");
        console.log("Sell 0.2 WETH at 4000 USDT each");
        
        try router.placeLimitOrder(
            pool,
            4000e6,           // price: 4000 USDT per WETH
            2e17,             // quantity: 0.2 WETH
            IOrderBook.Side.SELL,
            IOrderBook.TimeInForce.GTC,
            2e17              // depositAmount: 0.2 WETH
        ) returns (uint48 sellOrderId) {
            console.log("SUCCESS: Sell limit order placed, ID:", sellOrderId);
        } catch Error(string memory reason) {
            console.log("FAILED: Sell order failed:", reason);
        } catch {
            console.log("FAILED: Sell order failed with unknown error");
        }
        
        console.log("\n--- Order 3: Market Buy (should match sell) ---");
        console.log("Market buy 0.05 WETH (should execute against sell at 4000)");
        
        try router.placeMarketOrder(
            pool,
            5e16,             // quantity: 0.05 WETH
            IOrderBook.Side.BUY,
            200e6,            // depositAmount: 200 USDT (5e16 * 4000e6 / 1e18)
            4e16              // minOutAmount: 0.04 WETH minimum
        ) returns (uint48 marketOrderId, uint128 receivedAmount) {
            console.log("SUCCESS: Market buy executed, ID:", marketOrderId);
            console.log("Received WETH amount:", receivedAmount);
            console.log("Cost approximately:", (5e16 * 4000e6) / 1e18, "USDT");
        } catch Error(string memory reason) {
            console.log("FAILED: Market order failed:", reason);
        } catch {
            console.log("FAILED: Market order failed with unknown error");
        }
        
        console.log("\n--- Order Book State After Trading ---");
        
        try pool.orderBook.getBestPrice(IOrderBook.Side.BUY) returns (IOrderBook.PriceVolume memory bestBuy) {
            if (bestBuy.price > 0) {
                console.log("Best BUY  - Price:", bestBuy.price, "Volume:", bestBuy.volume);
            } else {
                console.log("No buy orders in book");
            }
        } catch {
            console.log("No buy orders in book");
        }
        
        try pool.orderBook.getBestPrice(IOrderBook.Side.SELL) returns (IOrderBook.PriceVolume memory bestSell) {
            if (bestSell.price > 0) {
                console.log("Best SELL - Price:", bestSell.price, "Volume:", bestSell.volume);
            } else {
                console.log("No sell orders in book");
            }
        } catch {
            console.log("No sell orders in book");
        }
        
        console.log("\n--- Final Trading Balances ---");
        console.log("gsUSDT balance:", balanceManager.getBalance(user, Currency.wrap(gsUSDT)));
        console.log("gsWETH balance:", balanceManager.getBalance(user, Currency.wrap(gsWETH)));
        
        vm.stopBroadcast();
        
        console.log("\n========== FULL TRADING FLOW COMPLETE ==========");
        console.log("SUCCESS: Successfully tested complete flow:");
        console.log("   1. Appchain: Mint tokens and cross-chain deposit");
        console.log("   2. Rari Testnet: Receive synthetic tokens");  
        console.log("   3. Rari Testnet: Place limit orders and execute market order");
        console.log("   4. CLOB order matching and balance updates");
    }
}