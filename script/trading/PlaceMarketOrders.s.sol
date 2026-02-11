// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/interfaces/IPoolManager.sol";
import "../../src/core/libraries/Pool.sol";
import "../../src/mocks/MockToken.sol";
import "../../src/core/interfaces/IOrderBook.sol";

/**
 * @title PlaceMarketOrders
 * @notice Execute market BUY orders across all pools using PRIVATE_KEY_2
 * @dev This script places market BUY orders that match against SELL limit orders
 *      placed by FillOrderBooks.s.sol (using PRIVATE_KEY)
 */
contract PlaceMarketOrders is Script, DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "BalanceManager";
    string constant POOL_MANAGER_ADDRESS = "PoolManager";
    string constant SCALEX_ROUTER_ADDRESS = "ScaleXRouter";

    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    ScaleXRouter scalexRouter;

    // Market order wallet (PRIVATE_KEY_2) - different from limit order wallet
    address marketOrderWallet;

    // Quote currency configuration (read dynamically)
    uint8 quoteDecimals;
    uint256 quoteUnit;

    // Market order configuration
    struct MarketOrderConfig {
        string symbol;
        address sxToken;
        uint256 quoteAmountUsd;  // Quote currency to spend in USD (will be scaled by quoteUnit)
    }

    function setUp() public {
        loadDeployments();
        loadContracts();

        // Read quote decimals from environment (defaults to 6 for USDC)
        quoteDecimals = uint8(vm.envOr("QUOTE_DECIMALS", uint256(6)));
        quoteUnit = 10 ** quoteDecimals;
    }

    function loadContracts() private {
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
        scalexRouter = ScaleXRouter(payable(deployed[SCALEX_ROUTER_ADDRESS].addr));
    }

    function run() external {
        uint256 marketOrderKey = getDeployerKey2();
        marketOrderWallet = vm.addr(marketOrderKey);

        string memory quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));

        // Read selected markets from environment (comma-separated, e.g., "WBTC,GOLD,SILVER")
        // If empty or "ALL", execute for all markets
        string memory marketsEnv = vm.envOr("MARKETS", string("ALL"));

        console.log("===============================================");
        console.log("Executing Market Orders (PRIVATE_KEY_2)");
        console.log("===============================================");
        console.log("Quote Currency:", quoteCurrency);
        console.log("Quote Decimals:", quoteDecimals);
        console.log("Quote Unit:", quoteUnit);
        console.log("Selected Markets:", marketsEnv);
        console.log("Market Order Wallet:", marketOrderWallet);
        console.log("");

        address quoteAddr = deployed[quoteCurrency].addr;

        vm.startBroadcast(marketOrderKey);

        // Execute market orders for each pool
        uint256 totalOrdersExecuted = 0;
        uint256 totalQuoteSpent = 0;

        // WETH: Buy ~0.5 ETH at $2,000 = need $1,000
        if (_isMarketSelected(marketsEnv, "WETH") && deployed["sxWETH"].isSet) {
            MarketOrderConfig memory config = MarketOrderConfig({
                symbol: "WETH",
                sxToken: deployed["sxWETH"].addr,
                quoteAmountUsd: 1000
            });
            (bool success,,, uint256 quoteSpent) = executeMarketOrder(config, quoteAddr, quoteCurrency);
            if (success) { totalOrdersExecuted++; totalQuoteSpent += quoteSpent; }
        }

        // WBTC: Buy ~0.01 BTC at $95,100 = need $1,000
        if (_isMarketSelected(marketsEnv, "WBTC") && deployed["sxWBTC"].isSet) {
            MarketOrderConfig memory config = MarketOrderConfig({
                symbol: "WBTC",
                sxToken: deployed["sxWBTC"].addr,
                quoteAmountUsd: 1000
            });
            (bool success,,, uint256 quoteSpent) = executeMarketOrder(config, quoteAddr, quoteCurrency);
            if (success) { totalOrdersExecuted++; totalQuoteSpent += quoteSpent; }
        }

        // GOLD: Buy ~0.2 oz at $4,460 = need $900
        if (_isMarketSelected(marketsEnv, "GOLD") && deployed["sxGOLD"].isSet) {
            MarketOrderConfig memory config = MarketOrderConfig({
                symbol: "GOLD",
                sxToken: deployed["sxGOLD"].addr,
                quoteAmountUsd: 900
            });
            (bool success,,, uint256 quoteSpent) = executeMarketOrder(config, quoteAddr, quoteCurrency);
            if (success) { totalOrdersExecuted++; totalQuoteSpent += quoteSpent; }
        }

        // SILVER: Buy ~10 oz at $79 = need $800
        if (_isMarketSelected(marketsEnv, "SILVER") && deployed["sxSILVER"].isSet) {
            MarketOrderConfig memory config = MarketOrderConfig({
                symbol: "SILVER",
                sxToken: deployed["sxSILVER"].addr,
                quoteAmountUsd: 800
            });
            (bool success,,, uint256 quoteSpent) = executeMarketOrder(config, quoteAddr, quoteCurrency);
            if (success) { totalOrdersExecuted++; totalQuoteSpent += quoteSpent; }
        }

        // GOOGLE: Buy 2 shares at $315 = need $650
        if (_isMarketSelected(marketsEnv, "GOOGLE") && deployed["sxGOOGLE"].isSet) {
            MarketOrderConfig memory config = MarketOrderConfig({
                symbol: "GOOGLE",
                sxToken: deployed["sxGOOGLE"].addr,
                quoteAmountUsd: 650
            });
            (bool success,,, uint256 quoteSpent) = executeMarketOrder(config, quoteAddr, quoteCurrency);
            if (success) { totalOrdersExecuted++; totalQuoteSpent += quoteSpent; }
        }

        // NVIDIA: Buy 3 shares at $189 = need $600
        if (_isMarketSelected(marketsEnv, "NVIDIA") && deployed["sxNVIDIA"].isSet) {
            MarketOrderConfig memory config = MarketOrderConfig({
                symbol: "NVIDIA",
                sxToken: deployed["sxNVIDIA"].addr,
                quoteAmountUsd: 600
            });
            (bool success,,, uint256 quoteSpent) = executeMarketOrder(config, quoteAddr, quoteCurrency);
            if (success) { totalOrdersExecuted++; totalQuoteSpent += quoteSpent; }
        }

        // MNT: Buy 200 tokens at $2 = need $400
        if (_isMarketSelected(marketsEnv, "MNT") && deployed["sxMNT"].isSet) {
            MarketOrderConfig memory config = MarketOrderConfig({
                symbol: "MNT",
                sxToken: deployed["sxMNT"].addr,
                quoteAmountUsd: 400
            });
            (bool success,,, uint256 quoteSpent) = executeMarketOrder(config, quoteAddr, quoteCurrency);
            if (success) { totalOrdersExecuted++; totalQuoteSpent += quoteSpent; }
        }

        // APPLE: Buy 2 shares at $266 = need $550
        if (_isMarketSelected(marketsEnv, "APPLE") && deployed["sxAPPLE"].isSet) {
            MarketOrderConfig memory config = MarketOrderConfig({
                symbol: "APPLE",
                sxToken: deployed["sxAPPLE"].addr,
                quoteAmountUsd: 550
            });
            (bool success,,, uint256 quoteSpent) = executeMarketOrder(config, quoteAddr, quoteCurrency);
            if (success) { totalOrdersExecuted++; totalQuoteSpent += quoteSpent; }
        }

        vm.stopBroadcast();

        console.log("\n===============================================");
        console.log("Market Orders Execution Complete");
        console.log("===============================================");
        console.log("Total Orders Executed:", totalOrdersExecuted);
        console.log("Total", quoteCurrency, "Spent: $", totalQuoteSpent / quoteUnit);
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

    function executeMarketOrder(
        MarketOrderConfig memory config,
        address quoteAddr,
        string memory quoteCurrency
    ) internal returns (
        bool success,
        uint48 orderId,
        uint128 filled,
        uint256 quoteSpent
    ) {
        console.log("===============================================");
        console.log(config.symbol, "/", quoteCurrency, " Market Order");
        console.log("===============================================");

        // Get pool
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);
        IPoolManager.Pool memory pool = _getPool(config.sxToken, deployed[sxQuoteKey].addr);

        if (address(pool.orderBook) == address(0)) {
            console.log("  [SKIP] Pool not found");
            return (false, 0, 0, 0);
        }

        console.log("  OrderBook:", address(pool.orderBook));

        // Check best SELL price before
        IOrderBook.PriceVolume memory bestSell = pool.orderBook.getBestPrice(IOrderBook.Side.SELL);
        if (bestSell.price == 0) {
            console.log("  [SKIP] No SELL orders found");
            return (false, 0, 0, 0);
        }
        console.log("  Best SELL price: $", bestSell.price / quoteUnit);

        // Calculate actual quote amount (USD * quoteUnit)
        uint256 quoteAmount = config.quoteAmountUsd * quoteUnit;

        // Mint and deposit quote currency
        _depositQuote(quoteAddr, quoteAmount, config.quoteAmountUsd, quoteCurrency);

        // Place market BUY order and get results
        (success, orderId, filled, quoteSpent) = _placeAndLogMarketOrder(
            pool, config, quoteAmount, quoteCurrency
        );

        console.log("");
    }

    function _getPool(address sxToken, address sxQuote) internal view returns (IPoolManager.Pool memory) {
        Currency baseToken = Currency.wrap(sxToken);
        Currency quote = Currency.wrap(sxQuote);
        PoolKey memory poolKey = poolManager.createPoolKey(baseToken, quote);
        return poolManager.getPool(poolKey);
    }

    function _depositQuote(address quoteAddr, uint256 quoteAmount, uint256 quoteAmountUsd, string memory quoteCurrency) internal {
        MockToken(quoteAddr).mint(marketOrderWallet, quoteAmount);
        IERC20(quoteAddr).approve(address(balanceManager), quoteAmount);
        balanceManager.depositLocal(quoteAddr, quoteAmount, marketOrderWallet);
        console.log("  Deposited $", quoteAmountUsd, quoteCurrency);
    }

    function _placeAndLogMarketOrder(
        IPoolManager.Pool memory pool,
        MarketOrderConfig memory config,
        uint256 quoteAmount,
        string memory quoteCurrency
    ) internal returns (bool success, uint48 orderId, uint128 filled, uint256 quoteSpent) {
        // Get balances before
        Currency baseToken = Currency.wrap(config.sxToken);
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);
        Currency quote = Currency.wrap(deployed[sxQuoteKey].addr);

        uint256 quoteBalanceBefore = balanceManager.getBalance(marketOrderWallet, quote);
        uint256 tokenBalanceBefore = balanceManager.getBalance(marketOrderWallet, baseToken);

        // Read base token decimals for display
        uint256 baseUnit = 10 ** MockToken(config.sxToken).decimals();

        // Place market BUY order
        try scalexRouter.placeMarketOrder(
            pool,
            uint128(quoteAmount),
            IOrderBook.Side.BUY,
            0, // depositAmount=0 since already deposited
            0  // minOutAmount=0 for testing
        ) returns (uint48 id, uint128 _filled) {
            orderId = id;
            filled = _filled;

            // Get balance after
            uint256 quoteBalanceAfter = balanceManager.getBalance(marketOrderWallet, quote);
            uint256 tokenBalanceAfter = balanceManager.getBalance(marketOrderWallet, baseToken);

            quoteSpent = quoteBalanceBefore - quoteBalanceAfter;
            uint256 tokensGained = tokenBalanceAfter - tokenBalanceBefore;

            console.log("  [OK] Market BUY executed - ID:", id);
            console.log("  [OK] Filled:", _filled / baseUnit, config.symbol);
            console.log("  [OK]", quoteCurrency, "spent: $", quoteSpent / quoteUnit);
            console.log("  [OK]", config.symbol, "gained:", tokensGained / baseUnit);

            if (_filled > 0) {
                console.log("  [SUCCESS] Trade executed!");
                success = true;
            } else {
                console.log("  [WARNING] No fill occurred");
                success = true;
            }
        } catch Error(string memory reason) {
            console.log("  [FAIL] Market order failed:", reason);
            success = false;
        } catch {
            console.log("  [FAIL] Market order failed (unknown error)");
            success = false;
        }
    }

}
