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
     * @dev Prices are dynamically scaled based on QUOTE_DECIMALS (env variable).
     * Environment variables like WBTC_PRICE should be in quote currency units.
     * For example: WBTC_PRICE=95000e6 for USDC (6 decimals) or WBTC_PRICE=95000e2 for IDRX (2 decimals)
     * Quote currency is determined by QUOTE_CURRENCY environment variable (defaults to USDC).
     */
    function initializePriceConfigs() private {
        // Read quote decimals from environment (defaults to 6 for USDC)
        uint8 quoteDecimals = uint8(vm.envOr("QUOTE_DECIMALS", uint256(6)));
        uint256 priceUnit = 10 ** quoteDecimals;

        // WBTC: Current price ~$95,000 (Jan 2026)
        uint128 wbtcPrice = uint128(vm.envOr("WBTC_PRICE", uint256(95000 * priceUnit)));
        uint128 wbtcSpread = uint128(200 * priceUnit);  // $200
        uint128 wbtcStep = uint128(100 * priceUnit);    // $100
        priceConfigs["WBTC"] = PriceConfig({
            oraclePrice: wbtcPrice,
            buyStartPrice: wbtcPrice - wbtcSpread,      // $200 below
            buyEndPrice: wbtcPrice - (wbtcStep),        // $100 below
            sellStartPrice: wbtcPrice + wbtcStep,       // $100 above
            sellEndPrice: wbtcPrice + wbtcSpread,       // $200 above
            priceStep: wbtcStep                         // $100 increments
        });

        // GOLD: Current price ~$4,450 (Jan 2026)
        uint128 goldPrice = uint128(vm.envOr("GOLD_PRICE", uint256(4450 * priceUnit)));
        uint128 goldSpread = uint128(50 * priceUnit);  // $50
        uint128 goldStep = uint128(10 * priceUnit);    // $10
        priceConfigs["GOLD"] = PriceConfig({
            oraclePrice: goldPrice,
            buyStartPrice: goldPrice - goldSpread,      // $50 below
            buyEndPrice: goldPrice - goldStep,          // $10 below
            sellStartPrice: goldPrice + goldStep,       // $10 above
            sellEndPrice: goldPrice + goldSpread,       // $50 above
            priceStep: goldStep                         // $10 increments
        });

        // SILVER: Current price ~$78 (Jan 2026)
        uint128 silverPrice = uint128(vm.envOr("SILVER_PRICE", uint256(78 * priceUnit)));
        uint128 silverSpread = uint128(4 * priceUnit);  // $4
        uint128 silverStep = uint128(1 * priceUnit);    // $1
        priceConfigs["SILVER"] = PriceConfig({
            oraclePrice: silverPrice,
            buyStartPrice: silverPrice - silverSpread,  // $4 below
            buyEndPrice: silverPrice - silverStep,      // $1 below
            sellStartPrice: silverPrice + silverStep,   // $1 above
            sellEndPrice: silverPrice + silverSpread,   // $4 above
            priceStep: silverStep                       // $1 increments
        });

        // GOOGL: Current price ~$314 (Jan 2026)
        uint128 googlPrice = uint128(vm.envOr("GOOGL_PRICE", uint256(314 * priceUnit)));
        uint128 googlSpread = uint128(4 * priceUnit);  // $4
        uint128 googlStep = uint128(1 * priceUnit);    // $1
        priceConfigs["GOOGLE"] = PriceConfig({
            oraclePrice: googlPrice,
            buyStartPrice: googlPrice - googlSpread,    // $4 below
            buyEndPrice: googlPrice - googlStep,        // $1 below
            sellStartPrice: googlPrice + googlStep,     // $1 above
            sellEndPrice: googlPrice + googlSpread,     // $4 above
            priceStep: googlStep                        // $1 increments
        });

        // NVDA: Current price ~$188 (Jan 2026)
        uint128 nvdaPrice = uint128(vm.envOr("NVDA_PRICE", uint256(188 * priceUnit)));
        uint128 nvdaSpread = uint128(4 * priceUnit);   // $4
        uint128 nvdaStep = uint128(1 * priceUnit);     // $1
        priceConfigs["NVIDIA"] = PriceConfig({
            oraclePrice: nvdaPrice,
            buyStartPrice: nvdaPrice - nvdaSpread,      // $4 below
            buyEndPrice: nvdaPrice - nvdaStep,          // $1 below
            sellStartPrice: nvdaPrice + nvdaStep,       // $1 above
            sellEndPrice: nvdaPrice + nvdaSpread,       // $4 above
            priceStep: nvdaStep                         // $1 increments
        });

        // MNT: Current price ~$1.05 (Jan 2026)
        // Note: Pool has $1 minimum price increment, so rounding to $1
        uint128 mntPrice = uint128(vm.envOr("MNT_PRICE", uint256(1 * priceUnit)));
        uint128 mntStep = uint128(1 * priceUnit);      // $1
        priceConfigs["MNT"] = PriceConfig({
            oraclePrice: mntPrice,
            buyStartPrice: mntPrice,                    // At market
            buyEndPrice: mntPrice,                      // Single buy order
            sellStartPrice: mntPrice + mntStep,         // $1 above
            sellEndPrice: mntPrice + (4 * mntStep),     // $4 above
            priceStep: mntStep                          // $1 increments
        });

        // AAPL: Current price ~$265 (Jan 2026)
        uint128 aaplPrice = uint128(vm.envOr("AAPL_PRICE", uint256(265 * priceUnit)));
        uint128 aaplSpread = uint128(4 * priceUnit);   // $4
        uint128 aaplStep = uint128(1 * priceUnit);     // $1
        priceConfigs["APPLE"] = PriceConfig({
            oraclePrice: aaplPrice,
            buyStartPrice: aaplPrice - aaplSpread,      // $4 below
            buyEndPrice: aaplPrice - aaplStep,          // $1 below
            sellStartPrice: aaplPrice + aaplStep,       // $1 above
            sellEndPrice: aaplPrice + aaplSpread,       // $4 above
            priceStep: aaplStep                         // $1 increments
        });

        // WETH: Current price ~$3,300 (Jan 2026)
        uint128 wethPrice = uint128(vm.envOr("WETH_PRICE", uint256(3300 * priceUnit)));
        uint128 wethSpread = uint128(50 * priceUnit);  // $50
        uint128 wethStep = uint128(10 * priceUnit);    // $10
        priceConfigs["WETH"] = PriceConfig({
            oraclePrice: wethPrice,
            buyStartPrice: wethPrice - wethSpread,      // $50 below
            buyEndPrice: wethPrice - wethStep,          // $10 below
            sellStartPrice: wethPrice + wethStep,       // $10 above
            sellEndPrice: wethPrice + wethSpread,       // $50 above
            priceStep: wethStep                         // $10 increments
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

        // Read selected markets from environment (comma-separated, e.g., "WBTC,GOLD,SILVER")
        // If empty or "ALL", fill all markets
        string memory marketsEnv = vm.envOr("MARKETS", string("ALL"));
        console.log("Selected markets:", marketsEnv);

        vm.startBroadcast(deployerPrivateKey);

        // Fill each token pool with appropriate limit orders
        // Only fill markets that are selected
        if (_isMarketSelected(marketsEnv, "WETH")) fillWETHPool();
        if (_isMarketSelected(marketsEnv, "WBTC")) fillWBTCPool();
        if (_isMarketSelected(marketsEnv, "GOLD")) fillGOLDPool();
        if (_isMarketSelected(marketsEnv, "SILVER")) fillSILVERPool();
        if (_isMarketSelected(marketsEnv, "GOOGLE")) fillGOOGLEPool();
        if (_isMarketSelected(marketsEnv, "NVIDIA")) fillNVIDIAPool();
        if (_isMarketSelected(marketsEnv, "MNT")) fillMNTPool();
        if (_isMarketSelected(marketsEnv, "APPLE")) fillAPPLEPool();

        vm.stopBroadcast();
    }

    /**
     * @notice Check if a market is selected based on MARKETS environment variable
     * @param marketsEnv The MARKETS environment variable value (comma-separated or "ALL")
     * @param market The market to check (e.g., "WBTC", "GOLD")
     * @return bool True if the market is selected
     */
    function _isMarketSelected(string memory marketsEnv, string memory market) private pure returns (bool) {
        // If "ALL" or empty, all markets are selected
        if (keccak256(bytes(marketsEnv)) == keccak256(bytes("ALL")) || bytes(marketsEnv).length == 0) {
            return true;
        }

        // Check if the market is in the comma-separated list
        bytes memory marketsBytes = bytes(marketsEnv);
        bytes memory marketBytes = bytes(market);

        uint256 marketLen = marketBytes.length;
        uint256 marketsLen = marketsBytes.length;

        if (marketsLen < marketLen) return false;

        // Search for the market in the list
        for (uint256 i = 0; i <= marketsLen - marketLen; i++) {
            // Check if we're at the start of a token (beginning or after comma)
            bool atStart = (i == 0) || (marketsBytes[i - 1] == bytes1(","));

            if (atStart) {
                bool match_ = true;
                for (uint256 j = 0; j < marketLen; j++) {
                    // Case-insensitive comparison
                    bytes1 c1 = marketsBytes[i + j];
                    bytes1 c2 = marketBytes[j];
                    // Convert to uppercase for comparison
                    if (c1 >= bytes1("a") && c1 <= bytes1("z")) {
                        c1 = bytes1(uint8(c1) - 32);
                    }
                    if (c2 >= bytes1("a") && c2 <= bytes1("z")) {
                        c2 = bytes1(uint8(c2) - 32);
                    }
                    if (c1 != c2) {
                        match_ = false;
                        break;
                    }
                }

                if (match_) {
                    // Check if we're at the end of a token (end of string or before comma)
                    bool atEnd = (i + marketLen == marketsLen) || (marketsBytes[i + marketLen] == bytes1(","));
                    if (atEnd) return true;
                }
            }
        }

        return false;
    }

    function fillWETHPool() private {
        string memory quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);
        console.log(string.concat("\n=== Filling WETH/", quoteCurrency, " Order Book ==="));

        if (!deployed["sxWETH"].isSet || !deployed[sxQuoteKey].isSet) {
            console.log("[SKIP] WETH or", quoteCurrency, "synthetic token not found");
            return;
        }

        address sxWETH = deployed["sxWETH"].addr;
        address sxQuote = deployed[sxQuoteKey].addr;
        address wethAddr = deployed["WETH"].addr;

        // Read decimals dynamically
        uint8 wethDecimals = MockToken(sxWETH).decimals();
        uint8 quoteDecimals = MockToken(sxQuote).decimals();
        uint256 priceDivisor = 10 ** quoteDecimals;

        PriceConfig memory config = priceConfigs["WETH"];
        console.log("Oracle price:", config.oraclePrice / priceDivisor);

        // Calculate amounts based on actual decimals
        uint256 orderQuantity = 1 * (10 ** (wethDecimals - 1)); // 0.1 ETH
        uint256 setupAmount = 100 * (10 ** wethDecimals);       // 100 ETH

        _fillTokenPool(
            sxWETH, sxQuote, wethAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            5,                      // 5 orders each side
            uint128(orderQuantity), // 0.1 ETH per order (dynamic decimals)
            setupAmount,            // Setup: 100 ETH (dynamic decimals)
            quoteCurrency
        );
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

        // Read decimals dynamically
        uint8 wbtcDecimals = MockToken(sxWBTC).decimals();
        uint8 quoteDecimals = MockToken(sxQuote).decimals();
        uint256 priceDivisor = 10 ** quoteDecimals;

        PriceConfig memory config = priceConfigs["WBTC"];
        console.log("Oracle price:", config.oraclePrice / priceDivisor);

        // Calculate amounts based on actual decimals
        uint256 orderQuantity = 1 * (10 ** (wbtcDecimals - 2)); // 0.01 BTC
        uint256 setupAmount = 100 * (10 ** wbtcDecimals);       // 100 BTC

        _fillTokenPool(
            sxWBTC, sxQuote, wbtcAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                      // 4 orders each side
            uint128(orderQuantity), // 0.01 BTC per order (dynamic decimals)
            setupAmount,            // Setup: 100 BTC (dynamic decimals)
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

        // Read decimals dynamically
        uint8 goldDecimals = MockToken(sxGOLD).decimals();
        uint8 quoteDecimals = MockToken(sxQuote).decimals();
        uint256 priceDivisor = 10 ** quoteDecimals;

        PriceConfig memory config = priceConfigs["GOLD"];
        console.log("Oracle price:", config.oraclePrice / priceDivisor);

        // Calculate amounts based on actual decimals
        uint256 orderQuantity = 1 * (10 ** (goldDecimals - 1)); // 0.1 GOLD
        uint256 setupAmount = 1000 * (10 ** goldDecimals);      // 1000 GOLD

        _fillTokenPool(
            sxGOLD, sxQuote, goldAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            5,                      // 5 orders each side
            uint128(orderQuantity), // 0.1 GOLD per order (dynamic decimals)
            setupAmount,            // Setup: 1000 GOLD (dynamic decimals)
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

        // Read decimals dynamically
        uint8 silverDecimals = MockToken(sxSILVER).decimals();
        uint8 quoteDecimals = MockToken(sxQuote).decimals();
        uint256 priceDivisor = 10 ** quoteDecimals;

        PriceConfig memory config = priceConfigs["SILVER"];
        console.log("Oracle price:", config.oraclePrice / priceDivisor);

        // Calculate amounts based on actual decimals
        uint256 orderQuantity = 10 * (10 ** silverDecimals);   // 10 SILVER
        uint256 setupAmount = 10000 * (10 ** silverDecimals);  // 10000 SILVER

        _fillTokenPool(
            sxSILVER, sxQuote, silverAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                      // 4 orders each side
            uint128(orderQuantity), // 10 SILVER per order (dynamic decimals)
            setupAmount,            // Setup: 10000 SILVER (dynamic decimals)
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

        // Read decimals dynamically
        uint8 googleDecimals = MockToken(sxGOOGLE).decimals();
        uint8 quoteDecimals = MockToken(sxQuote).decimals();
        uint256 priceDivisor = 10 ** quoteDecimals;

        PriceConfig memory config = priceConfigs["GOOGLE"];
        console.log("Oracle price:", config.oraclePrice / priceDivisor);

        // Calculate amounts based on actual decimals
        uint256 orderQuantity = 5 * (10 ** (googleDecimals - 1)); // 0.5 GOOGLE
        uint256 setupAmount = 100 * (10 ** googleDecimals);       // 100 GOOGLE

        _fillTokenPool(
            sxGOOGLE, sxQuote, googleAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                      // 4 orders each side
            uint128(orderQuantity), // 0.5 GOOGLE per order (dynamic decimals)
            setupAmount,            // Setup: 100 GOOGLE (dynamic decimals)
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

        // Read decimals dynamically
        uint8 nvidiaDecimals = MockToken(sxNVIDIA).decimals();
        uint8 quoteDecimals = MockToken(sxQuote).decimals();
        uint256 priceDivisor = 10 ** quoteDecimals;

        PriceConfig memory config = priceConfigs["NVIDIA"];
        console.log("Oracle price:", config.oraclePrice / priceDivisor);

        // Calculate amounts based on actual decimals
        uint256 orderQuantity = 5 * (10 ** (nvidiaDecimals - 1)); // 0.5 NVIDIA
        uint256 setupAmount = 100 * (10 ** nvidiaDecimals);       // 100 NVIDIA

        _fillTokenPool(
            sxNVIDIA, sxQuote, nvidiaAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                      // 4 orders each side
            uint128(orderQuantity), // 0.5 NVIDIA per order (dynamic decimals)
            setupAmount,            // Setup: 100 NVIDIA (dynamic decimals)
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

        // Read decimals dynamically
        uint8 mntDecimals = MockToken(sxMNT).decimals();
        uint8 quoteDecimals = MockToken(sxQuote).decimals();
        uint256 priceDivisor = 10 ** quoteDecimals;

        PriceConfig memory config = priceConfigs["MNT"];
        console.log("Oracle price:", config.oraclePrice / priceDivisor);

        // Calculate amounts based on actual decimals
        uint256 orderQuantity = 1000 * (10 ** mntDecimals);   // 1000 MNT
        uint256 setupAmount = 100000 * (10 ** mntDecimals);   // 100000 MNT

        _fillTokenPool(
            sxMNT, sxQuote, mntAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                      // 4 orders each side
            uint128(orderQuantity), // 1000 MNT per order (dynamic decimals)
            setupAmount,            // Setup: 100000 MNT (dynamic decimals)
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

        // Read decimals dynamically
        uint8 appleDecimals = MockToken(sxAPPLE).decimals();
        uint8 quoteDecimals = MockToken(sxQuote).decimals();
        uint256 priceDivisor = 10 ** quoteDecimals;

        PriceConfig memory config = priceConfigs["APPLE"];
        console.log("Oracle price:", config.oraclePrice / priceDivisor);

        // Calculate amounts based on actual decimals
        uint256 orderQuantity = 5 * (10 ** (appleDecimals - 1)); // 0.5 APPLE
        uint256 setupAmount = 100 * (10 ** appleDecimals);       // 100 APPLE

        _fillTokenPool(
            sxAPPLE, sxQuote, appleAddr,
            config.buyStartPrice, config.buyEndPrice,
            config.sellStartPrice, config.sellEndPrice,
            config.priceStep,
            4,                      // 4 orders each side
            uint128(orderQuantity), // 0.5 APPLE per order (dynamic decimals)
            setupAmount,            // Setup: 100 APPLE (dynamic decimals)
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

        // Read decimals dynamically from on-chain contracts
        uint8 baseDecimals = MockToken(syntheticToken).decimals();
        uint8 quoteDecimals = MockToken(syntheticQuote).decimals();

        console.log("[INFO] Base decimals:", baseDecimals, "Quote decimals:", quoteDecimals);
        console.log("[INFO] Order quantity:", orderQuantity, "Price:", buyEndPrice);

        // Setup funds - mint, approve and deposit underlying tokens for SELL orders
        MockToken(underlyingToken).mint(deployerAddress, setupAmount);
        IERC20(underlyingToken).approve(address(balanceManager), setupAmount);
        balanceManager.depositLocal(underlyingToken, setupAmount, deployerAddress);

        uint256 setupAmountReadable = setupAmount / (10 ** baseDecimals);
        console.log("[OK] Deposited underlying tokens:", setupAmountReadable);

        // Setup quote currency for BUY orders
        // Use baseToQuote formula: quoteAmount = (baseAmount * price) / (10 ** baseDecimals)
        // For multiple orders, sum up the quote needed for all BUY orders
        uint256 quotePerOrder = (uint256(orderQuantity) * uint256(buyEndPrice)) / (10 ** baseDecimals);
        uint256 quoteNeeded = quotePerOrder * numOrders;

        console.log("[INFO] Quote per order:", quotePerOrder, "Total quote needed:", quoteNeeded);

        address underlyingQuote = deployed[quoteCurrency].addr;
        MockToken(underlyingQuote).mint(deployerAddress, quoteNeeded);
        IERC20(underlyingQuote).approve(address(balanceManager), quoteNeeded);
        balanceManager.depositLocal(underlyingQuote, quoteNeeded, deployerAddress);

        uint256 quoteNeededReadable = quoteNeeded / (10 ** quoteDecimals);
        console.log("[OK] Deposited", quoteCurrency, "for buy orders:", quoteNeededReadable);

        // Place BUY limit orders (depositAmount=0 since we already deposited)
        uint128 currentPrice = buyStartPrice;
        uint256 priceDivisor = 10 ** quoteDecimals;
        for (uint8 i = 0; i < numOrders; i++) {
            try scalexRouter.placeLimitOrder(
                pool, currentPrice, orderQuantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 0
            ) returns (uint48 orderId) {
                console.log("  [OK] BUY order placed at price:", currentPrice / priceDivisor, "- ID:", orderId);
            } catch {
                console.log("  [FAIL] BUY order failed at price:", currentPrice / priceDivisor);
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
                console.log("  [OK] SELL order placed at price:", currentPrice / priceDivisor, "- ID:", orderId);
            } catch {
                console.log("  [FAIL] SELL order failed at price:", currentPrice / priceDivisor);
            }
            currentPrice += priceStep;
            if (currentPrice > sellEndPrice) break;
        }

        console.log("[COMPLETE] Pool filled with limit orders");
    }
}
