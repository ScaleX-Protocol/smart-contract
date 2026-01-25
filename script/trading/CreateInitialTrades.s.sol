// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/ScaleXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/libraries/Pool.sol";
import "../../src/mocks/MockToken.sol";

contract CreateInitialTrades is Script, DeployHelpers {
    BalanceManager balanceManager;
    ScaleXRouter router;
    PoolManager poolManager;
    address deployer;

    function run() public {
        loadDeployments();

        balanceManager = BalanceManager(deployed["BalanceManager"].addr);
        router = ScaleXRouter(deployed["ScaleXRouter"].addr);
        poolManager = PoolManager(deployed["PoolManager"].addr);

        uint256 deployerPrivateKey = getDeployerKey();
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Create trades for each empty pool
        createTrade_WBTC_USDC();
        createTrade_GOLD_USDC();
        createTrade_SILVER_USDC();
        createTrade_GOOGLE_USDC();
        createTrade_NVIDIA_USDC();
        createTrade_MNT_USDC();
        createTrade_APPLE_USDC();

        vm.stopBroadcast();
    }

    function createTrade_WBTC_USDC() private {
        console.log("\n=== Creating Trade: sxWBTC/sxUSDC ===");
        // Real-world BTC price: ~$95,000
        // Need minimum $5M order value: 5000000 / 95000 = ~53 BTC
        // NOTE: sxWBTC has 18 decimals on-chain (not 8)
        _createMatchingOrders(
            "sxWBTC", "sxUSDC", "WBTC",
            95000e6,  // price: $95,000
            100e18,   // 100 BTC (18 decimals) - sxWBTC uses 18 decimals
            1000e8,   // mint 1000 underlying WBTC (8 decimals)
            18        // sxWBTC decimals
        );
    }

    function createTrade_GOLD_USDC() private {
        console.log("\n=== Creating Trade: sxGOLD/sxUSDC ===");
        // Real-world Gold price: ~$2,650/oz
        _createMatchingOrders(
            "sxGOLD", "sxUSDC", "GOLD",
            2650e6,   // price: $2,650
            1e17,     // 0.1 GOLD (18 decimals)
            1000e18,  // mint 1000 GOLD
            18        // GOLD decimals
        );
    }

    function createTrade_SILVER_USDC() private {
        console.log("\n=== Creating Trade: sxSILVER/sxUSDC ===");
        // Real-world Silver price: ~$30/oz
        _createMatchingOrders(
            "sxSILVER", "sxUSDC", "SILVER",
            30e6,     // price: $30
            10e18,    // 10 SILVER (18 decimals)
            10000e18, // mint 10000 SILVER
            18        // SILVER decimals
        );
    }

    function createTrade_GOOGLE_USDC() private {
        console.log("\n=== Creating Trade: sxGOOGLE/sxUSDC ===");
        // Real-world GOOGL stock: ~$180
        _createMatchingOrders(
            "sxGOOGLE", "sxUSDC", "GOOGLE",
            180e6,    // price: $180
            5e17,     // 0.5 GOOGLE (18 decimals)
            100e18,   // mint 100 GOOGLE
            18        // GOOGLE decimals
        );
    }

    function createTrade_NVIDIA_USDC() private {
        console.log("\n=== Creating Trade: sxNVIDIA/sxUSDC ===");
        // Real-world NVDA stock: ~$140
        _createMatchingOrders(
            "sxNVIDIA", "sxUSDC", "NVIDIA",
            140e6,    // price: $140
            5e17,     // 0.5 NVIDIA (18 decimals)
            100e18,   // mint 100 NVIDIA
            18        // NVIDIA decimals
        );
    }

    function createTrade_MNT_USDC() private {
        console.log("\n=== Creating Trade: sxMNT/sxUSDC ===");
        // MNT token price: ~$1
        _createMatchingOrders(
            "sxMNT", "sxUSDC", "MNT",
            1e6,      // price: $1
            1000e18,  // 1000 MNT (18 decimals)
            100000e18, // mint 100000 MNT
            18        // MNT decimals
        );
    }

    function createTrade_APPLE_USDC() private {
        console.log("\n=== Creating Trade: sxAPPLE/sxUSDC ===");
        // Real-world AAPL stock: ~$230
        _createMatchingOrders(
            "sxAPPLE", "sxUSDC", "APPLE",
            230e6,    // price: $230
            5e17,     // 0.5 APPLE (18 decimals)
            100e18,   // mint 100 APPLE
            18        // APPLE decimals
        );
    }

    function _createMatchingOrders(
        string memory syntheticSymbol,
        string memory quoteSymbol,
        string memory underlyingSymbol,
        uint128 price,
        uint128 quantity,
        uint256 mintAmount,
        uint8 tokenDecimals
    ) private {
        address sxToken = deployed[syntheticSymbol].addr;
        address sxUSDC = deployed[quoteSymbol].addr;
        address underlyingToken = deployed[underlyingSymbol].addr;
        address underlyingUSDC = deployed["USDC"].addr;

        // Get pool
        Currency token = Currency.wrap(sxToken);
        Currency usdc = Currency.wrap(sxUSDC);
        PoolKey memory poolKey = poolManager.createPoolKey(token, usdc);

        IPoolManager.Pool memory pool;
        try poolManager.getPool(poolKey) returns (IPoolManager.Pool memory retrievedPool) {
            pool = retrievedPool;
            console.log("Pool OrderBook:", address(pool.orderBook));
        } catch {
            console.log("[ERROR] Pool not found");
            return;
        }

        // Mint and deposit underlying token for SELL order
        MockToken(underlyingToken).mint(deployer, mintAmount);
        IERC20(underlyingToken).approve(address(balanceManager), mintAmount);
        balanceManager.depositLocal(underlyingToken, mintAmount, deployer);
        console.log("Deposited token for SELL order");

        // Mint and deposit USDC for BUY order
        // Calculate USDC needed: (price * quantity) / (10^tokenDecimals)
        // price is in USDC (6 decimals), quantity is in token decimals
        uint256 usdcNeeded = (uint256(price) * uint256(quantity)) / (10 ** tokenDecimals);
        MockToken(underlyingUSDC).mint(deployer, usdcNeeded);
        IERC20(underlyingUSDC).approve(address(balanceManager), usdcNeeded);
        balanceManager.depositLocal(underlyingUSDC, usdcNeeded, deployer);
        console.log("Deposited", usdcNeeded / 1e6, "USDC for BUY order");

        // Place SELL order at target price
        try router.placeLimitOrder(
            pool, price, quantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 0
        ) returns (uint48 sellOrderId) {
            console.log("[OK] SELL order placed - ID:", sellOrderId);

            // NOTE: Cannot place BUY at same price as SELL (NegativeSpreadCreated)
            // Cannot place BUY at different price (InvalidPriceIncrement)
            // Solution: Place BUY as GTC order at slightly lower price (market making spread)
            // This populates the order book which will allow trades when MM bot operates
            uint128 bidPrice = uint128((uint256(price) * 99) / 100);
            try router.placeLimitOrder(
                pool, bidPrice, quantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 0
            ) returns (uint48 orderId) {
                console.log("[OK] BUY order placed - ID:", orderId);
                console.log("[INFO] Order book populated - trades will occur when MM bot operates");
            } catch {
                console.log("[ERROR] BUY order failed");
            }
        } catch {
            console.log("[ERROR] SELL order failed");
        }
    }
}
