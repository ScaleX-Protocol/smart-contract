// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../../src/mocks/MockToken.sol";
import "../../src/core/resolvers/PoolManagerResolver.sol";

contract MarketOrderRWAPools is Script, DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "BalanceManager";
    string constant POOL_MANAGER_ADDRESS = "PoolManager";
    string constant SCALEX_ROUTER_ADDRESS = "ScaleXRouter";

    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    ScaleXRouter scalexRouter;
    PoolManagerResolver poolManagerResolver;

    address deployerAddress;

    function setUp() public {
        loadDeployments();
        loadContracts();
        poolManagerResolver = new PoolManagerResolver();
    }

    function loadContracts() private {
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
        scalexRouter = ScaleXRouter(deployed[SCALEX_ROUTER_ADDRESS].addr);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_2");
        deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Execute market orders on each RWA pool
        tradeGOLDPool();
        tradeSILVERPool();
        tradeGOOGLEPool();
        tradeNVIDIAPool();
        tradeMNTPool();
        tradeAPPLEPool();

        vm.stopBroadcast();
        console.log("\n=== RWA Market Orders Executed Successfully ===");
    }

    function tradeGOLDPool() private {
        console.log("\n=== Executing Market Orders on GOLD/USDC ===");

        if (!deployed["sxGOLD"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] GOLD or USDC synthetic token not found");
            return;
        }

        address sxGOLD = deployed["sxGOLD"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address goldAddr = deployed["GOLD"].addr;
        address usdcAddr = deployed["USDC"].addr;

        // Oracle price: $2,650
        // Limit buy orders: $2,600 - $2,640
        // Limit sell orders: $2,660 - $2,700
        // Market sell @ ~$2630 will hit buy orders
        // Market buy @ ~$2670 will hit sell orders

        _executeMarketOrders(
            sxGOLD, sxUSDC, goldAddr, usdcAddr,
            5e16,    // 0.05 GOLD for sell order
            5e16,    // 0.05 GOLD for buy order
            150e6    // ~150 USDC (~0.05 GOLD * $2670)
        );
    }

    function tradeSILVERPool() private {
        console.log("\n=== Executing Market Orders on SILVER/USDC ===");

        if (!deployed["sxSILVER"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] SILVER or USDC synthetic token not found");
            return;
        }

        address sxSILVER = deployed["sxSILVER"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address silverAddr = deployed["SILVER"].addr;
        address usdcAddr = deployed["USDC"].addr;

        // Oracle price: $30
        // Limit buy orders: $29.00 - $29.80
        // Limit sell orders: $30.20 - $31.00
        // Market sell @ ~$29.50 will hit buy orders
        // Market buy @ ~$30.50 will hit sell orders

        _executeMarketOrders(
            sxSILVER, sxUSDC, silverAddr, usdcAddr,
            5e18,    // 5 SILVER for sell order
            5e18,    // 5 SILVER for buy order
            155e6    // ~155 USDC (~5 SILVER * $31)
        );
    }

    function tradeGOOGLEPool() private {
        console.log("\n=== Executing Market Orders on GOOGLE/USDC ===");

        if (!deployed["sxGOOGLE"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] GOOGLE or USDC synthetic token not found");
            return;
        }

        address sxGOOGLE = deployed["sxGOOGLE"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address googleAddr = deployed["GOOGLE"].addr;
        address usdcAddr = deployed["USDC"].addr;

        // Oracle price: $180
        // Limit buy orders: $176 - $178
        // Limit sell orders: $182 - $184
        // Market sell @ ~$177 will hit buy orders
        // Market buy @ ~$183 will hit sell orders

        _executeMarketOrders(
            sxGOOGLE, sxUSDC, googleAddr, usdcAddr,
            25e16,   // 0.25 GOOGLE for sell order
            25e16,   // 0.25 GOOGLE for buy order
            50e6     // ~50 USDC (~0.25 GOOGLE * $184)
        );
    }

    function tradeNVIDIAPool() private {
        console.log("\n=== Executing Market Orders on NVIDIA/USDC ===");

        if (!deployed["sxNVIDIA"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] NVIDIA or USDC synthetic token not found");
            return;
        }

        address sxNVIDIA = deployed["sxNVIDIA"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address nvidiaAddr = deployed["NVIDIA"].addr;
        address usdcAddr = deployed["USDC"].addr;

        // Oracle price: $140
        // Limit buy orders: $136 - $138
        // Limit sell orders: $142 - $144
        // Market sell @ ~$137 will hit buy orders
        // Market buy @ ~$143 will hit sell orders

        _executeMarketOrders(
            sxNVIDIA, sxUSDC, nvidiaAddr, usdcAddr,
            25e16,   // 0.25 NVIDIA for sell order
            25e16,   // 0.25 NVIDIA for buy order
            40e6     // ~40 USDC (~0.25 NVIDIA * $144)
        );
    }

    function tradeMNTPool() private {
        console.log("\n=== Executing Market Orders on MNT/USDC ===");

        if (!deployed["sxMNT"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] MNT or USDC synthetic token not found");
            return;
        }

        address sxMNT = deployed["sxMNT"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address mntAddr = deployed["MNT"].addr;
        address usdcAddr = deployed["USDC"].addr;

        // Oracle price: $1
        // Limit buy orders: $0.95 - $0.99
        // Limit sell orders: $1.01 - $1.05
        // Market sell @ ~$0.97 will hit buy orders
        // Market buy @ ~$1.03 will hit sell orders

        _executeMarketOrders(
            sxMNT, sxUSDC, mntAddr, usdcAddr,
            500e18,  // 500 MNT for sell order
            500e18,  // 500 MNT for buy order
            550e6    // ~550 USDC (~500 MNT * $1.05)
        );
    }

    function tradeAPPLEPool() private {
        console.log("\n=== Executing Market Orders on APPLE/USDC ===");

        if (!deployed["sxAPPLE"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] APPLE or USDC synthetic token not found");
            return;
        }

        address sxAPPLE = deployed["sxAPPLE"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address appleAddr = deployed["APPLE"].addr;
        address usdcAddr = deployed["USDC"].addr;

        // Oracle price: $230
        // Limit buy orders: $225 - $228
        // Limit sell orders: $232 - $235
        // Market sell @ ~$226 will hit buy orders
        // Market buy @ ~$233 will hit sell orders

        _executeMarketOrders(
            sxAPPLE, sxUSDC, appleAddr, usdcAddr,
            25e16,   // 0.25 APPLE for sell order
            25e16,   // 0.25 APPLE for buy order
            60e6     // ~60 USDC (~0.25 APPLE * $235)
        );
    }

    function _executeMarketOrders(
        address syntheticToken,
        address syntheticUSDC,
        address underlyingToken,
        address underlyingUSDC,
        uint128 sellQuantity,
        uint128 buyQuantity,
        uint256 usdcNeeded
    ) private {
        // Get pool
        Currency token = Currency.wrap(syntheticToken);
        Currency usdc = Currency.wrap(syntheticUSDC);

        PoolKey memory poolKey = poolManager.createPoolKey(token, usdc);
        IPoolManager.Pool memory pool;

        try poolManager.getPool(poolKey) returns (IPoolManager.Pool memory retrievedPool) {
            pool = retrievedPool;
            console.log("[OK] Found pool at OrderBook:", address(pool.orderBook));
        } catch {
            console.log("[WARNING] Pool not found - skipping");
            return;
        }

        // Setup funds - mint and deposit underlying tokens
        // Mint tokens for sell order
        MockToken(underlyingToken).mint(deployerAddress, sellQuantity);
        IERC20(underlyingToken).approve(address(balanceManager), sellQuantity);
        balanceManager.depositLocal(underlyingToken, sellQuantity, deployerAddress);
        console.log("[OK] Deposited", sellQuantity / 1e18, "tokens for SELL order");

        // Mint USDC for buy order
        MockToken(underlyingUSDC).mint(deployerAddress, usdcNeeded);
        IERC20(underlyingUSDC).approve(address(balanceManager), usdcNeeded);
        balanceManager.depositLocal(underlyingUSDC, usdcNeeded, deployerAddress);
        console.log("[OK] Deposited", usdcNeeded / 1e6, "USDC for BUY order");

        // Place market SELL order (sells token for USDC, hits BUY limit orders)
        try scalexRouter.placeMarketOrder(
            pool,
            sellQuantity,
            IOrderBook.Side.SELL,
            0,  // Using BalanceManager funds
            0   // No min output for testing
        ) returns (uint48 sellOrderId, uint128 sellFilled) {
            console.log("  [OK] Market SELL executed - ID:", sellOrderId, "Filled:", sellFilled / 1e18);
        } catch Error(string memory reason) {
            console.log("  [FAIL] Market SELL failed:", reason);
        } catch {
            console.log("  [FAIL] Market SELL failed");
        }

        // Place market BUY order (buys token with USDC, hits SELL limit orders)
        try scalexRouter.placeMarketOrder(
            pool,
            buyQuantity,
            IOrderBook.Side.BUY,
            0,  // Using BalanceManager funds
            0   // No min output for testing
        ) returns (uint48 buyOrderId, uint128 buyFilled) {
            console.log("  [OK] Market BUY executed - ID:", buyOrderId, "Filled:", buyFilled / 1e18);
        } catch Error(string memory reason) {
            console.log("  [FAIL] Market BUY failed:", reason);
        } catch {
            console.log("  [FAIL] Market BUY failed");
        }

        console.log("[COMPLETE] Market orders executed");
    }
}
