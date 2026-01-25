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

    // Single wallet for all limit orders
    address deployerAddress;  // PRIVATE_KEY - places ALL limit orders (BUY and SELL)

    // Price configurations (in quote currency, 6 decimals)
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
     * @dev Prices are in quote currency (6 decimals). Uses current January 2026 market prices.
     * To override, set environment variables: WBTC_PRICE, GOLD_PRICE, SILVER_PRICE, etc.
     * Quote currency is determined by QUOTE_CURRENCY environment variable (defaults to USDC).
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
        // Load PRIVATE_KEY - used for ALL limit orders
        uint256 deployerPrivateKey = getDeployerKey();
        deployerAddress = vm.addr(deployerPrivateKey);

        string memory quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        console.log("Quote Currency:", quoteCurrency);
        console.log("Limit Order wallet:", deployerAddress);
        console.log("Note: Market orders should use PRIVATE_KEY_2 (different wallet)");

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
        string memory quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);
        console.log(string.concat("\n=== Filling WBTC/", quoteCurrency, " Order Book ==="));

        if (!deployed["sxWBTC"].isSet || !deployed[sxQuoteKey].isSet) {
            console.log("[SKIP] WBTC or", quoteCurrency, "synthetic token not found");
            return;
        }

        address sxWBTC = deployed["sxWBTC"].addr;
        address sxQuote = deployed[sxQuoteKey].addr;
        address wbtcAddr = deployed["WBTC"].addr;

        PriceConfig memory config = priceConfigs["WBTC"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxWBTC, sxQuote, wbtcAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,               // 4 orders each side
            1e16,            // 0.01 BTC per order (18 decimals for sxWBTC)
            100e18,          // Setup: 100 BTC
            quoteCurrency
        );
    }

    function fillGOLDPool() private {
        string memory quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);
        console.log(string.concat("\n=== Filling GOLD/", quoteCurrency, " Order Book ==="));

        if (!deployed["sxGOLD"].isSet || !deployed[sxQuoteKey].isSet) {
            console.log("[SKIP] GOLD or", quoteCurrency, "synthetic token not found");
            return;
        }

        address sxGOLD = deployed["sxGOLD"].addr;
        address sxQuote = deployed[sxQuoteKey].addr;
        address goldAddr = deployed["GOLD"].addr;

        PriceConfig memory config = priceConfigs["GOLD"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxGOLD, sxQuote, goldAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            5,               // 5 orders each side
            1e17,            // 0.1 GOLD per order
            1000e18,         // Setup: 1000 GOLD
            quoteCurrency
        );
    }

    function fillSILVERPool() private {
        string memory quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);
        console.log(string.concat("\n=== Filling SILVER/", quoteCurrency, " Order Book ==="));

        if (!deployed["sxSILVER"].isSet || !deployed[sxQuoteKey].isSet) {
            console.log("[SKIP] SILVER or", quoteCurrency, "synthetic token not found");
            return;
        }

        address sxSILVER = deployed["sxSILVER"].addr;
        address sxQuote = deployed[sxQuoteKey].addr;
        address silverAddr = deployed["SILVER"].addr;

        PriceConfig memory config = priceConfigs["SILVER"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxSILVER, sxQuote, silverAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                // 4 orders each side
            10e18,            // 10 SILVER per order
            10000e18,         // Setup: 10000 SILVER
            quoteCurrency
        );
    }

    function fillGOOGLEPool() private {
        string memory quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);
        console.log(string.concat("\n=== Filling GOOGLE/", quoteCurrency, " Order Book ==="));

        if (!deployed["sxGOOGLE"].isSet || !deployed[sxQuoteKey].isSet) {
            console.log("[SKIP] GOOGLE or", quoteCurrency, "synthetic token not found");
            return;
        }

        address sxGOOGLE = deployed["sxGOOGLE"].addr;
        address sxQuote = deployed[sxQuoteKey].addr;
        address googleAddr = deployed["GOOGLE"].addr;

        PriceConfig memory config = priceConfigs["GOOGLE"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxGOOGLE, sxQuote, googleAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                // 4 orders each side
            5e17,             // 0.5 GOOGLE per order
            100e18,           // Setup: 100 GOOGLE
            quoteCurrency
        );
    }

    function fillNVIDIAPool() private {
        string memory quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);
        console.log(string.concat("\n=== Filling NVIDIA/", quoteCurrency, " Order Book ==="));

        if (!deployed["sxNVIDIA"].isSet || !deployed[sxQuoteKey].isSet) {
            console.log("[SKIP] NVIDIA or", quoteCurrency, "synthetic token not found");
            return;
        }

        address sxNVIDIA = deployed["sxNVIDIA"].addr;
        address sxQuote = deployed[sxQuoteKey].addr;
        address nvidiaAddr = deployed["NVIDIA"].addr;

        PriceConfig memory config = priceConfigs["NVIDIA"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxNVIDIA, sxQuote, nvidiaAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                // 4 orders each side
            5e17,             // 0.5 NVIDIA per order
            100e18,           // Setup: 100 NVIDIA
            quoteCurrency
        );
    }

    function fillMNTPool() private {
        string memory quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);
        console.log(string.concat("\n=== Filling MNT/", quoteCurrency, " Order Book ==="));

        if (!deployed["sxMNT"].isSet || !deployed[sxQuoteKey].isSet) {
            console.log("[SKIP] MNT or", quoteCurrency, "synthetic token not found");
            return;
        }

        address sxMNT = deployed["sxMNT"].addr;
        address sxQuote = deployed[sxQuoteKey].addr;
        address mntAddr = deployed["MNT"].addr;

        PriceConfig memory config = priceConfigs["MNT"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxMNT, sxQuote, mntAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                // 4 orders each side
            1000e18,          // 1000 MNT per order
            100000e18,        // Setup: 100000 MNT
            quoteCurrency
        );
    }

    function fillAPPLEPool() private {
        string memory quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);
        console.log(string.concat("\n=== Filling APPLE/", quoteCurrency, " Order Book ==="));

        if (!deployed["sxAPPLE"].isSet || !deployed[sxQuoteKey].isSet) {
            console.log("[SKIP] APPLE or", quoteCurrency, "synthetic token not found");
            return;
        }

        address sxAPPLE = deployed["sxAPPLE"].addr;
        address sxQuote = deployed[sxQuoteKey].addr;
        address appleAddr = deployed["APPLE"].addr;

        PriceConfig memory config = priceConfigs["APPLE"];
        console.log("Oracle price:", config.oraclePrice / 1e6);

        _fillTokenPool(
            sxAPPLE, sxQuote, appleAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                // 4 orders each side
            5e17,             // 0.5 APPLE per order
            100e18,           // Setup: 100 APPLE
            quoteCurrency
        );
    }

    function _fillTokenPool(
        address syntheticToken,
        address syntheticQuote,
        address underlyingToken,
        uint128 buyStartPrice,
        uint128 buyEndPrice,
        uint128 sellStartPrice,
        uint128 sellEndPrice,
        uint128 priceStep,
        uint8 numOrders,
        uint128 orderQuantity,
        uint256 setupAmount,
        string memory quoteCurrency
    ) private {
        // Get pool
        Currency token = Currency.wrap(syntheticToken);
        Currency quote = Currency.wrap(syntheticQuote);

        PoolKey memory poolKey = poolManager.createPoolKey(token, quote);
        IPoolManager.Pool memory pool;

        try poolManager.getPool(poolKey) returns (IPoolManager.Pool memory retrievedPool) {
            pool = retrievedPool;
            console.log("[OK] Found pool at OrderBook:", address(pool.orderBook));
        } catch {
            console.log("[WARNING] Pool not found - skipping");
            return;
        }

        // Setup funds - mint, approve and deposit underlying tokens for SELL orders
        MockToken(underlyingToken).mint(deployerAddress, setupAmount);
        IERC20(underlyingToken).approve(address(balanceManager), setupAmount);
        balanceManager.depositLocal(underlyingToken, setupAmount, deployerAddress);
        console.log("[OK] Deposited underlying tokens:", setupAmount / 1e18);

        // Setup quote currency for BUY orders
        uint256 quoteNeeded = (uint256(buyEndPrice) * uint256(orderQuantity) * numOrders) / 1e18;
        address underlyingQuote = deployed[quoteCurrency].addr;
        MockToken(underlyingQuote).mint(deployerAddress, quoteNeeded);
        IERC20(underlyingQuote).approve(address(balanceManager), quoteNeeded);
        balanceManager.depositLocal(underlyingQuote, quoteNeeded, deployerAddress);
        console.log("[OK] Deposited", quoteCurrency, "for buy orders");

        // Place BUY limit orders (depositAmount=0 since we already deposited)
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

        // Place SELL limit orders (depositAmount=0 since we already deposited)
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
