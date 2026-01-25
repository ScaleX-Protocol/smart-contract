// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/libraries/Pool.sol";
import "../../src/core/resolvers/PoolManagerResolver.sol";
import "../../src/mocks/MockToken.sol";

contract FillOrderBooks is Script, DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "BalanceManager";
    string constant POOL_MANAGER_ADDRESS = "PoolManager";
    string constant SCALEX_ROUTER_ADDRESS = "ScaleXRouter";

    // Price configuration struct
    struct PriceConfig {
        uint128 oraclePrice;
        uint128 buyStartPrice;
        uint128 buyEndPrice;
        uint128 sellStartPrice;
        uint128 sellEndPrice;
        uint128 priceStep;
    }

    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    ScaleXRouter scalexRouter;
    PoolManagerResolver poolManagerResolver;

    address deployerAddress;

    // Price configurations (in USDC, 6 decimals)
    mapping(string => PriceConfig) public priceConfigs;

    function setUp() public {
        loadDeployments();
        loadContracts();
        poolManagerResolver = new PoolManagerResolver();
        initializePriceConfigs();
    }

    function loadContracts() private {
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
        scalexRouter = ScaleXRouter(deployed[SCALEX_ROUTER_ADDRESS].addr);
    }

    /**
     * @notice Initialize default price configurations
     * @dev Prices are in USDC (6 decimals). Uses current January 2026 market prices.
     * To override, set environment variables: WBTC_PRICE, GOLD_PRICE, SILVER_PRICE, etc.
     */
    function initializePriceConfigs() private {
        // WBTC: Current price ~$95,000 (Jan 2026)
        uint128 wbtcPrice = uint128(vm.envOr("WBTC_PRICE", uint256(95000e6)));
        priceConfigs["WBTC"] = PriceConfig({
            oraclePrice: wbtcPrice,
            buyStartPrice: wbtcPrice - 200e6,  // $200 below
            buyEndPrice: wbtcPrice - 100e6,    // $100 below
            sellStartPrice: wbtcPrice + 100e6, // $100 above
            sellEndPrice: wbtcPrice + 200e6,   // $200 above
            priceStep: 100e6                   // $100 increments
        });

        // GOLD: Current price ~$4,450 (Jan 2026)
        uint128 goldPrice = uint128(vm.envOr("GOLD_PRICE", uint256(4450e6)));
        priceConfigs["GOLD"] = PriceConfig({
            oraclePrice: goldPrice,
            buyStartPrice: goldPrice - 50e6,  // $50 below
            buyEndPrice: goldPrice - 10e6,     // $10 below
            sellStartPrice: goldPrice + 10e6,  // $10 above
            sellEndPrice: goldPrice + 50e6,    // $50 above
            priceStep: 10e6                    // $10 increments
        });

        // SILVER: Current price ~$78 (Jan 2026)
        uint128 silverPrice = uint128(vm.envOr("SILVER_PRICE", uint256(78e6)));
        priceConfigs["SILVER"] = PriceConfig({
            oraclePrice: silverPrice,
            buyStartPrice: silverPrice - 4e6,  // $4 below
            buyEndPrice: silverPrice - 1e6,    // $1 below
            sellStartPrice: silverPrice + 1e6, // $1 above
            sellEndPrice: silverPrice + 4e6,   // $4 above
            priceStep: 1e6                     // $1 increments
        });

        // GOOGL: Current price ~$314 (Jan 2026)
        uint128 googlPrice = uint128(vm.envOr("GOOGL_PRICE", uint256(314e6)));
        priceConfigs["GOOGLE"] = PriceConfig({
            oraclePrice: googlPrice,
            buyStartPrice: googlPrice - 4e6,   // $4 below
            buyEndPrice: googlPrice - 1e6,     // $1 below
            sellStartPrice: googlPrice + 1e6,  // $1 above
            sellEndPrice: googlPrice + 4e6,    // $4 above
            priceStep: 1e6                     // $1 increments
        });

        // NVDA: Current price ~$188 (Jan 2026)
        uint128 nvdaPrice = uint128(vm.envOr("NVDA_PRICE", uint256(188e6)));
        priceConfigs["NVIDIA"] = PriceConfig({
            oraclePrice: nvdaPrice,
            buyStartPrice: nvdaPrice - 4e6,    // $4 below
            buyEndPrice: nvdaPrice - 1e6,      // $1 below
            sellStartPrice: nvdaPrice + 1e6,   // $1 above
            sellEndPrice: nvdaPrice + 4e6,     // $4 above
            priceStep: 1e6                     // $1 increments
        });

        // MNT: Current price ~$1.05 (Jan 2026)
        // Note: Pool has $1 minimum price increment, so rounding to $1
        uint128 mntPrice = uint128(vm.envOr("MNT_PRICE", uint256(1e6))); // $1 with 6 decimals
        priceConfigs["MNT"] = PriceConfig({
            oraclePrice: mntPrice,
            buyStartPrice: mntPrice,           // At market
            buyEndPrice: mntPrice,             // Single buy order
            sellStartPrice: mntPrice + 1e6,    // $1 above
            sellEndPrice: mntPrice + 4e6,      // $4 above
            priceStep: 1e6                     // $1 increments
        });

        // AAPL: Current price ~$265 (Jan 2026)
        uint128 aaplPrice = uint128(vm.envOr("AAPL_PRICE", uint256(265e6)));
        priceConfigs["APPLE"] = PriceConfig({
            oraclePrice: aaplPrice,
            buyStartPrice: aaplPrice - 4e6,    // $4 below
            buyEndPrice: aaplPrice - 1e6,      // $1 below
            sellStartPrice: aaplPrice + 1e6,   // $1 above
            sellEndPrice: aaplPrice + 4e6,     // $4 above
            priceStep: 1e6                     // $1 increments
        });
    }

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Fill each token pool with appropriate limit orders (all except ETH)
        fillWBTCPool();
        fillGOLDPool();
        fillSILVERPool();
        fillGOOGLEPool();
        fillNVIDIAPool();
        fillMNTPool();
        fillAPPLEPool();

        vm.stopBroadcast();
    }

    function fillWBTCPool() private {
        console.log("\n=== Filling WBTC/USDC Order Book ===");

        if (!deployed["sxWBTC"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] WBTC or USDC synthetic token not found");
            return;
        }

        address sxWBTC = deployed["sxWBTC"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address wbtcAddr = deployed["WBTC"].addr;

        PriceConfig memory config = priceConfigs["WBTC"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxWBTC, sxUSDC, wbtcAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,               // 4 orders each side
            1e16,            // 0.01 BTC per order (18 decimals for sxWBTC)
            100e18           // Setup: 100 BTC
        );
    }

    function fillGOLDPool() private {
        console.log("\n=== Filling GOLD/USDC Order Book ===");

        if (!deployed["sxGOLD"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] GOLD or USDC synthetic token not found");
            return;
        }

        address sxGOLD = deployed["sxGOLD"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address goldAddr = deployed["GOLD"].addr;

        PriceConfig memory config = priceConfigs["GOLD"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxGOLD, sxUSDC, goldAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            5,               // 5 orders each side
            1e17,            // 0.1 GOLD per order
            1000e18          // Setup: 1000 GOLD
        );
    }

    function fillSILVERPool() private {
        console.log("\n=== Filling SILVER/USDC Order Book ===");

        if (!deployed["sxSILVER"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] SILVER or USDC synthetic token not found");
            return;
        }

        address sxSILVER = deployed["sxSILVER"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address silverAddr = deployed["SILVER"].addr;

        PriceConfig memory config = priceConfigs["SILVER"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxSILVER, sxUSDC, silverAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                // 4 orders each side
            10e18,            // 10 SILVER per order
            10000e18          // Setup: 10000 SILVER
        );
    }

    function fillGOOGLEPool() private {
        console.log("\n=== Filling GOOGLE/USDC Order Book ===");

        if (!deployed["sxGOOGLE"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] GOOGLE or USDC synthetic token not found");
            return;
        }

        address sxGOOGLE = deployed["sxGOOGLE"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address googleAddr = deployed["GOOGLE"].addr;

        PriceConfig memory config = priceConfigs["GOOGLE"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxGOOGLE, sxUSDC, googleAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                // 4 orders each side
            5e17,             // 0.5 GOOGLE per order
            100e18            // Setup: 100 GOOGLE
        );
    }

    function fillNVIDIAPool() private {
        console.log("\n=== Filling NVIDIA/USDC Order Book ===");

        if (!deployed["sxNVIDIA"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] NVIDIA or USDC synthetic token not found");
            return;
        }

        address sxNVIDIA = deployed["sxNVIDIA"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address nvidiaAddr = deployed["NVIDIA"].addr;

        PriceConfig memory config = priceConfigs["NVIDIA"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxNVIDIA, sxUSDC, nvidiaAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                // 4 orders each side
            5e17,             // 0.5 NVIDIA per order
            100e18            // Setup: 100 NVIDIA
        );
    }

    function fillMNTPool() private {
        console.log("\n=== Filling MNT/USDC Order Book ===");

        if (!deployed["sxMNT"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] MNT or USDC synthetic token not found");
            return;
        }

        address sxMNT = deployed["sxMNT"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address mntAddr = deployed["MNT"].addr;

        PriceConfig memory config = priceConfigs["MNT"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxMNT, sxUSDC, mntAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                // 4 orders each side
            1000e18,          // 1000 MNT per order
            100000e18         // Setup: 100000 MNT
        );
    }

    function fillAPPLEPool() private {
        console.log("\n=== Filling APPLE/USDC Order Book ===");

        if (!deployed["sxAPPLE"].isSet || !deployed["sxUSDC"].isSet) {
            console.log("[SKIP] APPLE or USDC synthetic token not found");
            return;
        }

        address sxAPPLE = deployed["sxAPPLE"].addr;
        address sxUSDC = deployed["sxUSDC"].addr;
        address appleAddr = deployed["APPLE"].addr;

        PriceConfig memory config = priceConfigs["APPLE"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxAPPLE, sxUSDC, appleAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                // 4 orders each side
            5e17,             // 0.5 APPLE per order
            100e18            // Setup: 100 APPLE
        );
    }

    function _fillTokenPool(
        address syntheticToken,
        address syntheticUSDC,
        address underlyingToken,
        uint128 buyStartPrice,
        uint128 buyEndPrice,
        uint128 sellStartPrice,
        uint128 sellEndPrice,
        uint128 priceStep,
        uint8 numOrders,
        uint128 orderQuantity,
        uint256 setupAmount
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

        // Setup funds - mint underlying tokens
        MockToken(underlyingToken).mint(deployerAddress, setupAmount);
        console.log("[OK] Minted underlying tokens:", setupAmount / 1e18);

        // Approve and deposit to BalanceManager
        IERC20(underlyingToken).approve(address(balanceManager), setupAmount);
        balanceManager.depositLocal(underlyingToken, setupAmount, deployerAddress);
        console.log("[OK] Deposited to BalanceManager");

        // Setup USDC for buying
        uint256 usdcNeeded = (uint256(buyEndPrice) * uint256(orderQuantity) * numOrders) / 1e18;
        address underlyingUSDC = deployed["USDC"].addr;
        MockToken(underlyingUSDC).mint(deployerAddress, usdcNeeded);
        IERC20(underlyingUSDC).approve(address(balanceManager), usdcNeeded);
        balanceManager.depositLocal(underlyingUSDC, usdcNeeded, deployerAddress);
        console.log("[OK] Setup USDC for buy orders");

        // Place buy orders
        uint128 currentPrice = buyStartPrice;
        for (uint8 i = 0; i < numOrders; i++) {
            try scalexRouter.placeLimitOrder(
                pool, currentPrice, orderQuantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 0
            ) returns (uint48 orderId) {
                console.log("  [OK] BUY order placed at price:", currentPrice / 1e6, "- ID:", orderId);
            } catch {
                console.log("  [FAIL] BUY order failed at price:", currentPrice / 1e6);
            }
            currentPrice += priceStep;
            if (currentPrice > buyEndPrice) break;
        }

        // Place sell orders
        currentPrice = sellStartPrice;
        for (uint8 i = 0; i < numOrders; i++) {
            try scalexRouter.placeLimitOrder(
                pool, currentPrice, orderQuantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 0
            ) returns (uint48 orderId) {
                console.log("  [OK] SELL order placed at price:", currentPrice / 1e6, "- ID:", orderId);
            } catch {
                console.log("  [FAIL] SELL order failed at price:", currentPrice / 1e6);
            }
            currentPrice += priceStep;
            if (currentPrice > sellEndPrice) break;
        }

        console.log("[COMPLETE] Pool filled with limit orders");
    }
}
