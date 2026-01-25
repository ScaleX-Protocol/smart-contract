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

    // Market order configuration
    struct MarketOrderConfig {
        string symbol;
        address sxToken;
        uint256 quoteAmount;  // Quote currency to spend for BUY order
    }

    function setUp() public {
        loadDeployments();
        loadContracts();
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

        console.log("===============================================");
        console.log("Executing Market Orders (PRIVATE_KEY_2)");
        console.log("===============================================");
        console.log("Quote Currency:", quoteCurrency);
        console.log("Market Order Wallet:", marketOrderWallet);
        console.log("");

        address quoteAddr = deployed[quoteCurrency].addr;

        // Define market order configs for all pools
        MarketOrderConfig[] memory configs = new MarketOrderConfig[](8);

        // WETH: Buy ~0.5 ETH at $2,000 = need $1,000 IDRX
        configs[0] = MarketOrderConfig({
            symbol: "WETH",
            sxToken: deployed["sxWETH"].addr,
            quoteAmount:1000e6  // $1,000 IDRX
        });

        // WBTC: Buy ~0.01 BTC at $95,100 = need $1,000 IDRX
        configs[1] = MarketOrderConfig({
            symbol: "WBTC",
            sxToken: deployed["sxWBTC"].addr,
            quoteAmount:1000e6  // $1,000 IDRX
        });

        // GOLD: Buy ~0.2 oz at $4,460 = need $900 IDRX
        configs[2] = MarketOrderConfig({
            symbol: "GOLD",
            sxToken: deployed["sxGOLD"].addr,
            quoteAmount:900e6  // $900 IDRX
        });

        // SILVER: Buy ~10 oz at $79 = need $800 IDRX
        configs[3] = MarketOrderConfig({
            symbol: "SILVER",
            sxToken: deployed["sxSILVER"].addr,
            quoteAmount:800e6  // $800 IDRX
        });

        // GOOGLE: Buy 2 shares at $315 = need $650 IDRX
        configs[4] = MarketOrderConfig({
            symbol: "GOOGLE",
            sxToken: deployed["sxGOOGLE"].addr,
            quoteAmount:650e6  // $650 IDRX
        });

        // NVIDIA: Buy 3 shares at $189 = need $600 IDRX
        configs[5] = MarketOrderConfig({
            symbol: "NVIDIA",
            sxToken: deployed["sxNVIDIA"].addr,
            quoteAmount:600e6  // $600 IDRX
        });

        // MNT: Buy 200 tokens at $2 = need $400 IDRX
        configs[6] = MarketOrderConfig({
            symbol: "MNT",
            sxToken: deployed["sxMNT"].addr,
            quoteAmount:400e6  // $400 IDRX
        });

        // APPLE: Buy 2 shares at $266 = need $550 IDRX
        configs[7] = MarketOrderConfig({
            symbol: "APPLE",
            sxToken: deployed["sxAPPLE"].addr,
            quoteAmount:550e6  // $550 IDRX
        });

        vm.startBroadcast(marketOrderKey);

        // Execute market orders for each pool
        uint256 totalOrdersExecuted = 0;
        uint256 totalQuoteSpent = 0;

        for (uint256 i = 0; i < configs.length; i++) {
            (bool success, uint48 orderId, uint128 filled, uint256 quoteSpent) =
                executeMarketOrder(configs[i], quoteAddr, quoteCurrency);

            if (success) {
                totalOrdersExecuted++;
                totalQuoteSpent += quoteSpent;
            }
        }

        vm.stopBroadcast();

        console.log("\n===============================================");
        console.log("Market Orders Execution Complete");
        console.log("===============================================");
        console.log("Total Orders Executed:", totalOrdersExecuted);
        console.log("Total", quoteCurrency, "Spent: $", totalQuoteSpent / 1e6);
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
        Currency baseToken = Currency.wrap(config.sxToken);
        string memory sxQuoteKey = string.concat("sx", quoteCurrency);
        address sxQuote = deployed[sxQuoteKey].addr;
        Currency quote = Currency.wrap(sxQuote);
        PoolKey memory poolKey = poolManager.createPoolKey(baseToken, quote);
        IPoolManager.Pool memory pool = poolManager.getPool(poolKey);

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
        console.log("  Best SELL price: $", bestSell.price / 1e6);

        // Mint and deposit quote currency
        MockToken(quoteAddr).mint(marketOrderWallet, config.quoteAmount);
        IERC20(quoteAddr).approve(address(balanceManager), config.quoteAmount);
        balanceManager.depositLocal(quoteAddr, config.quoteAmount, marketOrderWallet);
        console.log("  Deposited $", config.quoteAmount / 1e6, quoteCurrency);

        // Get balance before
        uint256 quoteBalanceBefore = balanceManager.getBalance(marketOrderWallet, quote);
        uint256 tokenBalanceBefore = balanceManager.getBalance(marketOrderWallet, baseToken);

        // Place market BUY order
        try scalexRouter.placeMarketOrder(
            pool,
            uint128(config.quoteAmount),
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
            console.log("  [OK] Filled:", _filled / 1e18, config.symbol);
            console.log("  [OK]", quoteCurrency, "spent: $", quoteSpent / 1e6);
            console.log("  [OK]", config.symbol, "gained:", tokensGained / 1e18);

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

        console.log("");
    }

}
