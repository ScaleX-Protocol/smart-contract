// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PoolManager} from "@scalexcore/PoolManager.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {ScaleXRouter} from "@scalexcore/ScaleXRouter.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {IOracle} from "@scalexcore/interfaces/IOracle.sol";
import {PoolKey, PoolId} from "@scalexcore/libraries/Pool.sol";

contract DeployPhase3 is Script {
    struct Phase3Deployment {
        address WETH_Quote_Pool;
        address WBTC_Quote_Pool;
        address GOLD_Quote_Pool;
        address SILVER_Quote_Pool;
        address GOOGLE_Quote_Pool;
        address NVIDIA_Quote_Pool;
        address MNT_Quote_Pool;
        address APPLE_Quote_Pool;
        address deployer;
        uint256 timestamp;
        uint256 blockNumber;
    }

    function run() external returns (Phase3Deployment memory deployment) {
        console.log("=== PHASE 3: TRADING POOLS CREATION ===");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        
        // Load addresses from deployment file
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deploymentPath = string.concat(root, "/deployments/", chainIdStr, ".json");
        
        if (!vm.exists(deploymentPath)) {
            revert("Deployment file not found. Run phases 1-2 first.");
        }
        
        // Load quote currency config from environment
        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        string memory syntheticQuoteSymbol = string.concat("sx", quoteSymbol);

        string memory json = vm.readFile(deploymentPath);
        address poolManager = _extractAddress(json, "PoolManager");
        address scaleXRouter = _extractAddress(json, "ScaleXRouter");
        address balanceManager = _extractAddress(json, "BalanceManager");
        address oracle = _extractAddress(json, "Oracle");

        // Load synthetic quote token dynamically (sxUSDC, sxIDRX, etc.)
        address sxQuote = _extractAddress(json, syntheticQuoteSymbol);
        address sxWETH = _extractAddress(json, "sxWETH");
        address sxWBTC = _extractAddress(json, "sxWBTC");
        address sxGOLD = _extractAddress(json, "sxGOLD");
        address sxSILVER = _extractAddress(json, "sxSILVER");
        address sxGOOGLE = _extractAddress(json, "sxGOOGLE");
        address sxNVIDIA = _extractAddress(json, "sxNVIDIA");
        address sxMNT = _extractAddress(json, "sxMNT");
        address sxAPPLE = _extractAddress(json, "sxAPPLE");

        console.log("Loaded addresses:");
        console.log("  PoolManager:", poolManager);
        console.log("  ScaleXRouter:", scaleXRouter);
        console.log("  BalanceManager:", balanceManager);
        console.log("  Oracle:", oracle);
        console.log(string.concat("  ", syntheticQuoteSymbol, ":"), sxQuote);
        console.log("  sxWETH:", sxWETH);
        console.log("  sxWBTC:", sxWBTC);
        console.log("  sxGOLD:", sxGOLD);
        console.log("  sxSILVER:", sxSILVER);
        console.log("  sxGOOGLE:", sxGOOGLE);
        console.log("  sxNVIDIA:", sxNVIDIA);
        console.log("  sxMNT:", sxMNT);
        console.log("  sxAPPLE:", sxAPPLE);

        // Validate addresses
        require(poolManager != address(0), "PoolManager address is zero");
        require(balanceManager != address(0), "BalanceManager address is zero");
        require(oracle != address(0), "Oracle address is zero");
        require(sxQuote != address(0), string.concat(syntheticQuoteSymbol, " address is zero"));
        require(sxWETH != address(0), "sxWETH address is zero");
        require(sxWBTC != address(0), "sxWBTC address is zero");
        require(sxGOLD != address(0), "sxGOLD address is zero");
        require(sxSILVER != address(0), "sxSILVER address is zero");
        require(sxGOOGLE != address(0), "sxGOOGLE address is zero");
        require(sxNVIDIA != address(0), "sxNVIDIA address is zero");
        require(sxMNT != address(0), "sxMNT address is zero");
        require(sxAPPLE != address(0), "sxAPPLE address is zero");

        // Check if pools already exist before broadcasting
        PoolManager pm = PoolManager(poolManager);
        console.log("Step 1: Checking existing pools...");

        // Check WETH/{QUOTE} pool
        IPoolManager.Pool memory wethQuotePool = pm.getPool(
            pm.createPoolKey(Currency.wrap(sxWETH), Currency.wrap(sxQuote))
        );
        address wethQuoteOrderBook = address(wethQuotePool.orderBook);

        // Check WBTC/{QUOTE} pool
        IPoolManager.Pool memory wbtcQuotePool = pm.getPool(
            pm.createPoolKey(Currency.wrap(sxWBTC), Currency.wrap(sxQuote))
        );
        address wbtcQuoteOrderBook = address(wbtcQuotePool.orderBook);

        // Check GOLD/{QUOTE} pool
        IPoolManager.Pool memory goldQuotePool = pm.getPool(
            pm.createPoolKey(Currency.wrap(sxGOLD), Currency.wrap(sxQuote))
        );
        address goldQuoteOrderBook = address(goldQuotePool.orderBook);

        // Check SILVER/{QUOTE} pool
        IPoolManager.Pool memory silverQuotePool = pm.getPool(
            pm.createPoolKey(Currency.wrap(sxSILVER), Currency.wrap(sxQuote))
        );
        address silverQuoteOrderBook = address(silverQuotePool.orderBook);

        // Check GOOGLE/{QUOTE} pool
        IPoolManager.Pool memory googleQuotePool = pm.getPool(
            pm.createPoolKey(Currency.wrap(sxGOOGLE), Currency.wrap(sxQuote))
        );
        address googleQuoteOrderBook = address(googleQuotePool.orderBook);

        // Check NVIDIA/{QUOTE} pool
        IPoolManager.Pool memory nvidiaQuotePool = pm.getPool(
            pm.createPoolKey(Currency.wrap(sxNVIDIA), Currency.wrap(sxQuote))
        );
        address nvidiaQuoteOrderBook = address(nvidiaQuotePool.orderBook);

        // Check MNT/{QUOTE} pool
        IPoolManager.Pool memory mntQuotePool = pm.getPool(
            pm.createPoolKey(Currency.wrap(sxMNT), Currency.wrap(sxQuote))
        );
        address mntQuoteOrderBook = address(mntQuotePool.orderBook);

        // Check APPLE/{QUOTE} pool
        IPoolManager.Pool memory appleQuotePool = pm.getPool(
            pm.createPoolKey(Currency.wrap(sxAPPLE), Currency.wrap(sxQuote))
        );
        address appleQuoteOrderBook = address(appleQuotePool.orderBook);

        bool wethQuoteExists = wethQuoteOrderBook != address(0);
        bool wbtcQuoteExists = wbtcQuoteOrderBook != address(0);
        bool goldQuoteExists = goldQuoteOrderBook != address(0);
        bool silverQuoteExists = silverQuoteOrderBook != address(0);
        bool googleQuoteExists = googleQuoteOrderBook != address(0);
        bool nvidiaQuoteExists = nvidiaQuoteOrderBook != address(0);
        bool mntQuoteExists = mntQuoteOrderBook != address(0);
        bool appleQuoteExists = appleQuoteOrderBook != address(0);

        if (wethQuoteExists) {
            console.log(string.concat("[OK] WETH/", quoteSymbol, " pool already exists:"), wethQuoteOrderBook);
        } else {
            console.log(string.concat("WETH/", quoteSymbol, " pool needs to be created"));
        }

        if (wbtcQuoteExists) {
            console.log(string.concat("[OK] WBTC/", quoteSymbol, " pool already exists:"), wbtcQuoteOrderBook);
        } else {
            console.log(string.concat("WBTC/", quoteSymbol, " pool needs to be created"));
        }

        if (goldQuoteExists) {
            console.log(string.concat("[OK] GOLD/", quoteSymbol, " pool already exists:"), goldQuoteOrderBook);
        } else {
            console.log(string.concat("GOLD/", quoteSymbol, " pool needs to be created"));
        }

        if (silverQuoteExists) {
            console.log(string.concat("[OK] SILVER/", quoteSymbol, " pool already exists:"), silverQuoteOrderBook);
        } else {
            console.log(string.concat("SILVER/", quoteSymbol, " pool needs to be created"));
        }

        if (googleQuoteExists) {
            console.log(string.concat("[OK] GOOGLE/", quoteSymbol, " pool already exists:"), googleQuoteOrderBook);
        } else {
            console.log(string.concat("GOOGLE/", quoteSymbol, " pool needs to be created"));
        }

        if (nvidiaQuoteExists) {
            console.log(string.concat("[OK] NVIDIA/", quoteSymbol, " pool already exists:"), nvidiaQuoteOrderBook);
        } else {
            console.log(string.concat("NVIDIA/", quoteSymbol, " pool needs to be created"));
        }

        if (mntQuoteExists) {
            console.log(string.concat("[OK] MNT/", quoteSymbol, " pool already exists:"), mntQuoteOrderBook);
        } else {
            console.log(string.concat("MNT/", quoteSymbol, " pool needs to be created"));
        }

        if (appleQuoteExists) {
            console.log(string.concat("[OK] APPLE/", quoteSymbol, " pool already exists:"), appleQuoteOrderBook);
        } else {
            console.log(string.concat("APPLE/", quoteSymbol, " pool needs to be created"));
        }

        // Configure Oracle and authorize existing pools if needed
        if (wethQuoteExists || wbtcQuoteExists || goldQuoteExists || silverQuoteExists ||
            googleQuoteExists || nvidiaQuoteExists || mntQuoteExists || appleQuoteExists) {
            console.log("Starting broadcast to configure existing pools...");
            vm.startBroadcast(deployerPrivateKey);

            BalanceManager bm = BalanceManager(balanceManager);

            // Step 3.5: Ensure existing OrderBooks are authorized in BalanceManager
            console.log("Step 3.5: Ensuring OrderBooks are authorized in BalanceManager...");

            if (wethQuoteExists) {
                // Note: BalanceManager doesn't have isAuthorizedOperator view, so we always try to set
                // The function is idempotent so it's safe to call multiple times
                bm.setAuthorizedOperator(wethQuoteOrderBook, true);
                console.log(string.concat("[OK] WETH/", quoteSymbol, " OrderBook authorized in BalanceManager"));
            }

            if (wbtcQuoteExists) {
                bm.setAuthorizedOperator(wbtcQuoteOrderBook, true);
                console.log(string.concat("[OK] WBTC/", quoteSymbol, " OrderBook authorized in BalanceManager"));
            }

            if (goldQuoteExists) {
                bm.setAuthorizedOperator(goldQuoteOrderBook, true);
                console.log(string.concat("[OK] GOLD/", quoteSymbol, " OrderBook authorized in BalanceManager"));
            }

            if (silverQuoteExists) {
                bm.setAuthorizedOperator(silverQuoteOrderBook, true);
                console.log(string.concat("[OK] SILVER/", quoteSymbol, " OrderBook authorized in BalanceManager"));
            }

            if (googleQuoteExists) {
                bm.setAuthorizedOperator(googleQuoteOrderBook, true);
                console.log(string.concat("[OK] GOOGLE/", quoteSymbol, " OrderBook authorized in BalanceManager"));
            }

            if (nvidiaQuoteExists) {
                bm.setAuthorizedOperator(nvidiaQuoteOrderBook, true);
                console.log(string.concat("[OK] NVIDIA/", quoteSymbol, " OrderBook authorized in BalanceManager"));
            }

            if (mntQuoteExists) {
                bm.setAuthorizedOperator(mntQuoteOrderBook, true);
                console.log(string.concat("[OK] MNT/", quoteSymbol, " OrderBook authorized in BalanceManager"));
            }

            if (appleQuoteExists) {
                bm.setAuthorizedOperator(appleQuoteOrderBook, true);
                console.log(string.concat("[OK] APPLE/", quoteSymbol, " OrderBook authorized in BalanceManager"));
            }

            // Step 4: Configure Oracle in all OrderBooks
            console.log("Step 4: Configuring Oracle in OrderBooks...");

            if (wethQuoteExists) {
                address currentOracle = IOrderBook(wethQuoteOrderBook).oracle();
                if (currentOracle == address(0)) {
                    IOrderBook(wethQuoteOrderBook).setOracle(oracle);
                    console.log(string.concat("[OK] Oracle configured in WETH/", quoteSymbol, " OrderBook"));
                } else {
                    console.log(string.concat("[SKIP] WETH/", quoteSymbol, " OrderBook already has Oracle configured"));
                }
            }

            if (wbtcQuoteExists) {
                address currentOracle = IOrderBook(wbtcQuoteOrderBook).oracle();
                if (currentOracle == address(0)) {
                    IOrderBook(wbtcQuoteOrderBook).setOracle(oracle);
                    console.log(string.concat("[OK] Oracle configured in WBTC/", quoteSymbol, " OrderBook"));
                } else {
                    console.log(string.concat("[SKIP] WBTC/", quoteSymbol, " OrderBook already has Oracle configured"));
                }
            }

            if (goldQuoteExists) {
                address currentOracle = IOrderBook(goldQuoteOrderBook).oracle();
                if (currentOracle == address(0)) {
                    IOrderBook(goldQuoteOrderBook).setOracle(oracle);
                    console.log(string.concat("[OK] Oracle configured in GOLD/", quoteSymbol, " OrderBook"));
                } else {
                    console.log(string.concat("[SKIP] GOLD/", quoteSymbol, " OrderBook already has Oracle configured"));
                }
            }

            if (silverQuoteExists) {
                address currentOracle = IOrderBook(silverQuoteOrderBook).oracle();
                if (currentOracle == address(0)) {
                    IOrderBook(silverQuoteOrderBook).setOracle(oracle);
                    console.log(string.concat("[OK] Oracle configured in SILVER/", quoteSymbol, " OrderBook"));
                } else {
                    console.log(string.concat("[SKIP] SILVER/", quoteSymbol, " OrderBook already has Oracle configured"));
                }
            }

            if (googleQuoteExists) {
                address currentOracle = IOrderBook(googleQuoteOrderBook).oracle();
                if (currentOracle == address(0)) {
                    IOrderBook(googleQuoteOrderBook).setOracle(oracle);
                    console.log(string.concat("[OK] Oracle configured in GOOGLE/", quoteSymbol, " OrderBook"));
                } else {
                    console.log(string.concat("[SKIP] GOOGLE/", quoteSymbol, " OrderBook already has Oracle configured"));
                }
            }

            if (nvidiaQuoteExists) {
                address currentOracle = IOrderBook(nvidiaQuoteOrderBook).oracle();
                if (currentOracle == address(0)) {
                    IOrderBook(nvidiaQuoteOrderBook).setOracle(oracle);
                    console.log(string.concat("[OK] Oracle configured in NVIDIA/", quoteSymbol, " OrderBook"));
                } else {
                    console.log(string.concat("[SKIP] NVIDIA/", quoteSymbol, " OrderBook already has Oracle configured"));
                }
            }

            if (mntQuoteExists) {
                address currentOracle = IOrderBook(mntQuoteOrderBook).oracle();
                if (currentOracle == address(0)) {
                    IOrderBook(mntQuoteOrderBook).setOracle(oracle);
                    console.log(string.concat("[OK] Oracle configured in MNT/", quoteSymbol, " OrderBook"));
                } else {
                    console.log(string.concat("[SKIP] MNT/", quoteSymbol, " OrderBook already has Oracle configured"));
                }
            }

            if (appleQuoteExists) {
                address currentOracle = IOrderBook(appleQuoteOrderBook).oracle();
                if (currentOracle == address(0)) {
                    IOrderBook(appleQuoteOrderBook).setOracle(oracle);
                    console.log(string.concat("[OK] Oracle configured in APPLE/", quoteSymbol, " OrderBook"));
                } else {
                    console.log(string.concat("[SKIP] APPLE/", quoteSymbol, " OrderBook already has Oracle configured"));
                }
            }

            console.log("[OK] Oracle configuration completed");

            // Step 5: Verify Oracle is set correctly
            console.log("Step 5: Verifying Oracle configuration...");

            if (wethQuoteExists) {
                address wethQuoteOracle = IOrderBook(wethQuoteOrderBook).oracle();
                console.log(string.concat("WETH/", quoteSymbol, " OrderBook Oracle:"), vm.toString(wethQuoteOracle));
                require(wethQuoteOracle == oracle, string.concat("WETH/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] WETH/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (wbtcQuoteExists) {
                address wbtcQuoteOracle = IOrderBook(wbtcQuoteOrderBook).oracle();
                console.log(string.concat("WBTC/", quoteSymbol, " OrderBook Oracle:"), vm.toString(wbtcQuoteOracle));
                require(wbtcQuoteOracle == oracle, string.concat("WBTC/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] WBTC/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (goldQuoteExists) {
                address goldQuoteOracle = IOrderBook(goldQuoteOrderBook).oracle();
                console.log(string.concat("GOLD/", quoteSymbol, " OrderBook Oracle:"), vm.toString(goldQuoteOracle));
                require(goldQuoteOracle == oracle, string.concat("GOLD/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] GOLD/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (silverQuoteExists) {
                address silverQuoteOracle = IOrderBook(silverQuoteOrderBook).oracle();
                console.log(string.concat("SILVER/", quoteSymbol, " OrderBook Oracle:"), vm.toString(silverQuoteOracle));
                require(silverQuoteOracle == oracle, string.concat("SILVER/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] SILVER/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (googleQuoteExists) {
                address googleQuoteOracle = IOrderBook(googleQuoteOrderBook).oracle();
                console.log(string.concat("GOOGLE/", quoteSymbol, " OrderBook Oracle:"), vm.toString(googleQuoteOracle));
                require(googleQuoteOracle == oracle, string.concat("GOOGLE/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] GOOGLE/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (nvidiaQuoteExists) {
                address nvidiaQuoteOracle = IOrderBook(nvidiaQuoteOrderBook).oracle();
                console.log(string.concat("NVIDIA/", quoteSymbol, " OrderBook Oracle:"), vm.toString(nvidiaQuoteOracle));
                require(nvidiaQuoteOracle == oracle, string.concat("NVIDIA/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] NVIDIA/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (mntQuoteExists) {
                address mntQuoteOracle = IOrderBook(mntQuoteOrderBook).oracle();
                console.log(string.concat("MNT/", quoteSymbol, " OrderBook Oracle:"), vm.toString(mntQuoteOracle));
                require(mntQuoteOracle == oracle, string.concat("MNT/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] MNT/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (appleQuoteExists) {
                address appleQuoteOracle = IOrderBook(appleQuoteOrderBook).oracle();
                console.log(string.concat("APPLE/", quoteSymbol, " OrderBook Oracle:"), vm.toString(appleQuoteOracle));
                require(appleQuoteOracle == oracle, string.concat("APPLE/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] APPLE/", quoteSymbol, " OrderBook Oracle verified"));
            }

            console.log("[OK] All Oracle configurations verified");

            vm.stopBroadcast();
        }

        // Only broadcast if we need to create pools
        if (!wethQuoteExists || !wbtcQuoteExists || !goldQuoteExists || !silverQuoteExists ||
            !googleQuoteExists || !nvidiaQuoteExists || !mntQuoteExists || !appleQuoteExists) {
            console.log("Starting broadcast to create missing pools...");
            vm.startBroadcast(deployerPrivateKey);

            // Step 2: Set router in PoolManager first
            console.log("Step 2: Setting router in PoolManager...");
            pm.setRouter(scaleXRouter);
            console.log("[OK] Router set in PoolManager");

            // Step 3: Create trading rules
            // Load dynamic minimum trade amount based on quote currency decimals
            uint256 quoteDecimals = vm.envUint("QUOTE_DECIMALS");
            uint128 minUnit = uint128(10 ** quoteDecimals);  // 1 unit of quote currency

            IOrderBook.TradingRules memory tradingRules = IOrderBook.TradingRules({
                minTradeAmount: minUnit,          // 1 quote unit minimum
                minAmountMovement: minUnit,       // 1 quote unit minimum movement
                minPriceMovement: minUnit,        // 1 quote unit minimum price movement
                minOrderSize: minUnit * 5         // 5 quote units minimum order size
            });

            if (!wethQuoteExists) {
                console.log(string.concat("Creating new WETH/", quoteSymbol, " pool..."));
                PoolId wethQuotePoolId = pm.createPool(
                    Currency.wrap(sxWETH),      // base currency (WETH)
                    Currency.wrap(sxQuote),     // quote currency (dynamic)
                    tradingRules
                );

                // Get the OrderBook address from the newly created pool
                wethQuotePool = pm.getPool(
                    pm.createPoolKey(Currency.wrap(sxWETH), Currency.wrap(sxQuote))
                );
                wethQuoteOrderBook = address(wethQuotePool.orderBook);

                console.log(string.concat("[OK] WETH/", quoteSymbol, " pool created with OrderBook:"), wethQuoteOrderBook);

                // Authorize OrderBook in BalanceManager (critical for lock/unlock/transfer)
                BalanceManager(balanceManager).setAuthorizedOperator(wethQuoteOrderBook, true);
                console.log(string.concat("[OK] WETH/", quoteSymbol, " OrderBook authorized in BalanceManager"));

                // Configure Oracle for newly created pool
                IOrderBook(wethQuoteOrderBook).setOracle(oracle);
                console.log(string.concat("[OK] Oracle configured in WETH/", quoteSymbol, " OrderBook"));

                // Verify Oracle
                address wethQuoteOracle = IOrderBook(wethQuoteOrderBook).oracle();
                require(wethQuoteOracle == oracle, string.concat("WETH/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] WETH/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (!wbtcQuoteExists) {
                console.log(string.concat("Creating new WBTC/", quoteSymbol, " pool..."));
                PoolId wbtcQuotePoolId = pm.createPool(
                    Currency.wrap(sxWBTC),      // base currency (WBTC)
                    Currency.wrap(sxQuote),     // quote currency (dynamic)
                    tradingRules
                );

                // Get the OrderBook address from the newly created pool
                wbtcQuotePool = pm.getPool(
                    pm.createPoolKey(Currency.wrap(sxWBTC), Currency.wrap(sxQuote))
                );
                wbtcQuoteOrderBook = address(wbtcQuotePool.orderBook);

                console.log(string.concat("[OK] WBTC/", quoteSymbol, " pool created with OrderBook:"), wbtcQuoteOrderBook);

                // Authorize OrderBook in BalanceManager (critical for lock/unlock/transfer)
                BalanceManager(balanceManager).setAuthorizedOperator(wbtcQuoteOrderBook, true);
                console.log(string.concat("[OK] WBTC/", quoteSymbol, " OrderBook authorized in BalanceManager"));

                // Configure Oracle for newly created pool
                IOrderBook(wbtcQuoteOrderBook).setOracle(oracle);
                console.log(string.concat("[OK] Oracle configured in WBTC/", quoteSymbol, " OrderBook"));

                // Verify Oracle
                address wbtcQuoteOracle = IOrderBook(wbtcQuoteOrderBook).oracle();
                require(wbtcQuoteOracle == oracle, string.concat("WBTC/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] WBTC/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (!goldQuoteExists) {
                console.log(string.concat("Creating new GOLD/", quoteSymbol, " pool..."));
                PoolId goldQuotePoolId = pm.createPool(
                    Currency.wrap(sxGOLD),
                    Currency.wrap(sxQuote),
                    tradingRules
                );
                goldQuotePool = pm.getPool(pm.createPoolKey(Currency.wrap(sxGOLD), Currency.wrap(sxQuote)));
                goldQuoteOrderBook = address(goldQuotePool.orderBook);
                console.log(string.concat("[OK] GOLD/", quoteSymbol, " pool created with OrderBook:"), goldQuoteOrderBook);
                BalanceManager(balanceManager).setAuthorizedOperator(goldQuoteOrderBook, true);
                console.log(string.concat("[OK] GOLD/", quoteSymbol, " OrderBook authorized in BalanceManager"));
                IOrderBook(goldQuoteOrderBook).setOracle(oracle);
                console.log(string.concat("[OK] Oracle configured in GOLD/", quoteSymbol, " OrderBook"));
                address goldQuoteOracle = IOrderBook(goldQuoteOrderBook).oracle();
                require(goldQuoteOracle == oracle, string.concat("GOLD/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] GOLD/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (!silverQuoteExists) {
                console.log(string.concat("Creating new SILVER/", quoteSymbol, " pool..."));
                PoolId silverQuotePoolId = pm.createPool(
                    Currency.wrap(sxSILVER),
                    Currency.wrap(sxQuote),
                    tradingRules
                );
                silverQuotePool = pm.getPool(pm.createPoolKey(Currency.wrap(sxSILVER), Currency.wrap(sxQuote)));
                silverQuoteOrderBook = address(silverQuotePool.orderBook);
                console.log(string.concat("[OK] SILVER/", quoteSymbol, " pool created with OrderBook:"), silverQuoteOrderBook);
                BalanceManager(balanceManager).setAuthorizedOperator(silverQuoteOrderBook, true);
                console.log(string.concat("[OK] SILVER/", quoteSymbol, " OrderBook authorized in BalanceManager"));
                IOrderBook(silverQuoteOrderBook).setOracle(oracle);
                console.log(string.concat("[OK] Oracle configured in SILVER/", quoteSymbol, " OrderBook"));
                address silverQuoteOracle = IOrderBook(silverQuoteOrderBook).oracle();
                require(silverQuoteOracle == oracle, string.concat("SILVER/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] SILVER/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (!googleQuoteExists) {
                console.log(string.concat("Creating new GOOGLE/", quoteSymbol, " pool..."));
                PoolId googleQuotePoolId = pm.createPool(
                    Currency.wrap(sxGOOGLE),
                    Currency.wrap(sxQuote),
                    tradingRules
                );
                googleQuotePool = pm.getPool(pm.createPoolKey(Currency.wrap(sxGOOGLE), Currency.wrap(sxQuote)));
                googleQuoteOrderBook = address(googleQuotePool.orderBook);
                console.log(string.concat("[OK] GOOGLE/", quoteSymbol, " pool created with OrderBook:"), googleQuoteOrderBook);
                BalanceManager(balanceManager).setAuthorizedOperator(googleQuoteOrderBook, true);
                console.log(string.concat("[OK] GOOGLE/", quoteSymbol, " OrderBook authorized in BalanceManager"));
                IOrderBook(googleQuoteOrderBook).setOracle(oracle);
                console.log(string.concat("[OK] Oracle configured in GOOGLE/", quoteSymbol, " OrderBook"));
                address googleQuoteOracle = IOrderBook(googleQuoteOrderBook).oracle();
                require(googleQuoteOracle == oracle, string.concat("GOOGLE/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] GOOGLE/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (!nvidiaQuoteExists) {
                console.log(string.concat("Creating new NVIDIA/", quoteSymbol, " pool..."));
                PoolId nvidiaQuotePoolId = pm.createPool(
                    Currency.wrap(sxNVIDIA),
                    Currency.wrap(sxQuote),
                    tradingRules
                );
                nvidiaQuotePool = pm.getPool(pm.createPoolKey(Currency.wrap(sxNVIDIA), Currency.wrap(sxQuote)));
                nvidiaQuoteOrderBook = address(nvidiaQuotePool.orderBook);
                console.log(string.concat("[OK] NVIDIA/", quoteSymbol, " pool created with OrderBook:"), nvidiaQuoteOrderBook);
                BalanceManager(balanceManager).setAuthorizedOperator(nvidiaQuoteOrderBook, true);
                console.log(string.concat("[OK] NVIDIA/", quoteSymbol, " OrderBook authorized in BalanceManager"));
                IOrderBook(nvidiaQuoteOrderBook).setOracle(oracle);
                console.log(string.concat("[OK] Oracle configured in NVIDIA/", quoteSymbol, " OrderBook"));
                address nvidiaQuoteOracle = IOrderBook(nvidiaQuoteOrderBook).oracle();
                require(nvidiaQuoteOracle == oracle, string.concat("NVIDIA/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] NVIDIA/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (!mntQuoteExists) {
                console.log(string.concat("Creating new MNT/", quoteSymbol, " pool..."));
                PoolId mntQuotePoolId = pm.createPool(
                    Currency.wrap(sxMNT),
                    Currency.wrap(sxQuote),
                    tradingRules
                );
                mntQuotePool = pm.getPool(pm.createPoolKey(Currency.wrap(sxMNT), Currency.wrap(sxQuote)));
                mntQuoteOrderBook = address(mntQuotePool.orderBook);
                console.log(string.concat("[OK] MNT/", quoteSymbol, " pool created with OrderBook:"), mntQuoteOrderBook);
                BalanceManager(balanceManager).setAuthorizedOperator(mntQuoteOrderBook, true);
                console.log(string.concat("[OK] MNT/", quoteSymbol, " OrderBook authorized in BalanceManager"));
                IOrderBook(mntQuoteOrderBook).setOracle(oracle);
                console.log(string.concat("[OK] Oracle configured in MNT/", quoteSymbol, " OrderBook"));
                address mntQuoteOracle = IOrderBook(mntQuoteOrderBook).oracle();
                require(mntQuoteOracle == oracle, string.concat("MNT/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] MNT/", quoteSymbol, " OrderBook Oracle verified"));
            }

            if (!appleQuoteExists) {
                console.log(string.concat("Creating new APPLE/", quoteSymbol, " pool..."));
                PoolId appleQuotePoolId = pm.createPool(
                    Currency.wrap(sxAPPLE),
                    Currency.wrap(sxQuote),
                    tradingRules
                );
                appleQuotePool = pm.getPool(pm.createPoolKey(Currency.wrap(sxAPPLE), Currency.wrap(sxQuote)));
                appleQuoteOrderBook = address(appleQuotePool.orderBook);
                console.log(string.concat("[OK] APPLE/", quoteSymbol, " pool created with OrderBook:"), appleQuoteOrderBook);
                BalanceManager(balanceManager).setAuthorizedOperator(appleQuoteOrderBook, true);
                console.log(string.concat("[OK] APPLE/", quoteSymbol, " OrderBook authorized in BalanceManager"));
                IOrderBook(appleQuoteOrderBook).setOracle(oracle);
                console.log(string.concat("[OK] Oracle configured in APPLE/", quoteSymbol, " OrderBook"));
                address appleQuoteOracle = IOrderBook(appleQuoteOrderBook).oracle();
                require(appleQuoteOracle == oracle, string.concat("APPLE/", quoteSymbol, " OrderBook Oracle not set correctly"));
                console.log(string.concat("[OK] APPLE/", quoteSymbol, " OrderBook Oracle verified"));
            }

            console.log("[OK] OrderBook router configuration completed (automatic during pool creation)");

            vm.stopBroadcast();
        }

        // Step 6: Configure Oracle tokens
        _configureOracleTokens(deployerPrivateKey, oracle, sxQuote, sxWETH, sxWBTC,
                               wethQuoteOrderBook, wbtcQuoteOrderBook);

        // Step 6b: Configure RWA Oracle tokens
        _configureOracleRWATokens(deployerPrivateKey, oracle,
                                  sxGOLD, sxSILVER, sxGOOGLE, sxNVIDIA, sxMNT, sxAPPLE,
                                  goldQuoteOrderBook, silverQuoteOrderBook, googleQuoteOrderBook,
                                  nvidiaQuoteOrderBook, mntQuoteOrderBook, appleQuoteOrderBook);

        // Update deployment file with pool addresses
        _updateDeploymentFile(
            deploymentPath,
            quoteSymbol,
            wethQuoteOrderBook,
            wbtcQuoteOrderBook,
            goldQuoteOrderBook,
            silverQuoteOrderBook,
            googleQuoteOrderBook,
            nvidiaQuoteOrderBook,
            mntQuoteOrderBook,
            appleQuoteOrderBook,
            deployer
        );

        deployment = Phase3Deployment({
            WETH_Quote_Pool: wethQuoteOrderBook,
            WBTC_Quote_Pool: wbtcQuoteOrderBook,
            GOLD_Quote_Pool: goldQuoteOrderBook,
            SILVER_Quote_Pool: silverQuoteOrderBook,
            GOOGLE_Quote_Pool: googleQuoteOrderBook,
            NVIDIA_Quote_Pool: nvidiaQuoteOrderBook,
            MNT_Quote_Pool: mntQuoteOrderBook,
            APPLE_Quote_Pool: appleQuoteOrderBook,
            deployer: deployer,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
        
        console.log("=== PHASE 3 COMPLETED ===");
        console.log("Trading pools created successfully!");
        
        return deployment;
    }
    
    function _configureOracleTokens(
        uint256 deployerPrivateKey,
        address oracle,
        address sxQuote,
        address sxWETH,
        address sxWBTC,
        address wethQuoteOrderBook,
        address wbtcQuoteOrderBook
    ) internal {
        // Configure crypto tokens only - RWA tokens handled separately
        _configureOracleCryptoTokens(deployerPrivateKey, oracle, sxQuote, sxWETH, sxWBTC, wethQuoteOrderBook, wbtcQuoteOrderBook);
    }

    function _configureOracleRWATokens(
        uint256 deployerPrivateKey,
        address oracle,
        address sxGOLD,
        address sxSILVER,
        address sxGOOGLE,
        address sxNVIDIA,
        address sxMNT,
        address sxAPPLE,
        address goldQuoteOrderBook,
        address silverQuoteOrderBook,
        address googleQuoteOrderBook,
        address nvidiaQuoteOrderBook,
        address mntQuoteOrderBook,
        address appleQuoteOrderBook
    ) internal {
        console.log("Step 6b: Configuring Oracle RWA tokens...");

        IOracle oracleContract = IOracle(oracle);

        vm.startBroadcast(deployerPrivateKey);

        // Configure GOLD
        _configureSingleRWAToken(oracleContract, sxGOLD, goldQuoteOrderBook, 2650e6, "GOLD");

        // Configure SILVER
        _configureSingleRWAToken(oracleContract, sxSILVER, silverQuoteOrderBook, 30e6, "SILVER");

        // Configure GOOGLE
        _configureSingleRWAToken(oracleContract, sxGOOGLE, googleQuoteOrderBook, 180e6, "GOOGLE");

        // Configure NVIDIA
        _configureSingleRWAToken(oracleContract, sxNVIDIA, nvidiaQuoteOrderBook, 140e6, "NVIDIA");

        // Configure MNT
        _configureSingleRWAToken(oracleContract, sxMNT, mntQuoteOrderBook, 1e6, "MNT");

        // Configure APPLE
        _configureSingleRWAToken(oracleContract, sxAPPLE, appleQuoteOrderBook, 230e6, "APPLE");

        vm.stopBroadcast();

        console.log("[OK] All RWA tokens configured in Oracle");
    }

    function _configureSingleRWAToken(
        IOracle oracleContract,
        address token,
        address orderBook,
        uint256 initialPrice,
        string memory tokenName
    ) private {
        if (token == address(0)) {
            console.log("[SKIP]", tokenName, "token not deployed");
            return;
        }

        try oracleContract.getSpotPrice(token) returns (uint256 price) {
            if (price > 0) {
                console.log("[OK]", tokenName, "already configured with price:", price / 1e6);
                return;
            }
        } catch {}

        // Add token
        oracleContract.addToken(token, 0);
        console.log("[OK]", tokenName, "added to Oracle");

        // Set OrderBook
        if (orderBook != address(0)) {
            oracleContract.setTokenOrderBook(token, orderBook);
            console.log("[OK]", tokenName, "OrderBook set:", orderBook);
        }

        // Initialize price
        oracleContract.initializePrice(token, initialPrice);
        console.log("[OK]", tokenName, "price initialized: $", initialPrice / 1e6);

        // Verify
        uint256 verifiedPrice = oracleContract.getSpotPrice(token);
        require(verifiedPrice == initialPrice, string(abi.encodePacked(tokenName, " price verification failed")));
    }

    function _configureOracleCryptoTokens(
        uint256 deployerPrivateKey,
        address oracle,
        address sxUSDC,
        address sxWETH,
        address sxWBTC,
        address wethUsdcOrderBook,
        address wbtcUsdcOrderBook
    ) internal {
        console.log("Step 6: Configuring Oracle tokens...");

        IOracle oracleContract = IOracle(oracle);

        // Check if tokens are already configured by trying to get their prices
        // If price is 0, token needs to be configured
        bool sxUSDCConfigured = false;
        bool sxWETHConfigured = false;
        bool sxWBTCConfigured = false;

        try oracleContract.getSpotPrice(sxUSDC) returns (uint256 price) {
            sxUSDCConfigured = price > 0;
        } catch {}

        try oracleContract.getSpotPrice(sxWETH) returns (uint256 price) {
            sxWETHConfigured = price > 0;
        } catch {}

        try oracleContract.getSpotPrice(sxWBTC) returns (uint256 price) {
            sxWBTCConfigured = price > 0;
        } catch {}

        if (sxUSDCConfigured && sxWETHConfigured && sxWBTCConfigured) {
            console.log("[SKIP] All crypto Oracle tokens already configured");
            return;
        }

        vm.startBroadcast(deployerPrivateKey);

        // Add tokens to Oracle
        if (!sxUSDCConfigured) {
            oracleContract.addToken(sxUSDC, 0);
            console.log("[OK] sxUSDC added to Oracle");
        }

        if (!sxWETHConfigured) {
            oracleContract.addToken(sxWETH, 0);
            console.log("[OK] sxWETH added to Oracle");
        }

        if (!sxWBTCConfigured) {
            oracleContract.addToken(sxWBTC, 0);
            console.log("[OK] sxWBTC added to Oracle");
        }

        // Set OrderBooks for tokens (for price discovery)
        if (!sxWETHConfigured) {
            oracleContract.setTokenOrderBook(sxWETH, wethUsdcOrderBook);
            console.log("[OK] sxWETH OrderBook set in Oracle");
        }

        if (!sxWBTCConfigured) {
            oracleContract.setTokenOrderBook(sxWBTC, wbtcUsdcOrderBook);
            console.log("[OK] sxWBTC OrderBook set in Oracle");
        }

        // Initialize prices (for bootstrapping before any trades)
        if (!sxWETHConfigured) {
            oracleContract.initializePrice(sxWETH, 3000e6); // $3000 per WETH
            console.log("[OK] sxWETH price initialized: $3000");
        }

        if (!sxWBTCConfigured) {
            oracleContract.initializePrice(sxWBTC, 95000e6); // $95000 per WBTC
            console.log("[OK] sxWBTC price initialized: $95000");
        }

        if (!sxUSDCConfigured) {
            oracleContract.initializePrice(sxUSDC, 1e6); // $1 per USDC
            console.log("[OK] sxUSDC price initialized: $1");
        }

        vm.stopBroadcast();

        // Verify configuration
        console.log("Verifying Oracle crypto token configuration...");

        uint256 sxWETHPrice = oracleContract.getSpotPrice(sxWETH);
        console.log("sxWETH spot price:", sxWETHPrice);
        require(sxWETHPrice == 3000e6, "sxWETH price incorrect");

        uint256 sxUSDCPrice = oracleContract.getSpotPrice(sxUSDC);
        console.log("sxUSDC spot price:", sxUSDCPrice);
        require(sxUSDCPrice == 1e6, "sxUSDC price incorrect");

        uint256 sxWBTCPrice = oracleContract.getSpotPrice(sxWBTC);
        console.log("sxWBTC spot price:", sxWBTCPrice);
        require(sxWBTCPrice == 95000e6, "sxWBTC price incorrect");

        console.log("[OK] Oracle crypto token configuration completed");
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        // Simple JSON parsing to extract address value
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes.concat('"', bytes(key), '"');
        
        uint256 keyIndex = _findSubstring(jsonBytes, keyBytes);
        if (keyIndex == type(uint256).max) {
            return address(0); // Key not found
        }
        
        // Find colon after key
        uint256 colonIndex = keyIndex + keyBytes.length;
        while (colonIndex < jsonBytes.length && jsonBytes[colonIndex] != ':') {
            colonIndex++;
        }
        if (colonIndex >= jsonBytes.length) {
            return address(0);
        }
        
        // Find opening quote after colon
        uint256 start = colonIndex + 1;
        while (start < jsonBytes.length && jsonBytes[start] != '"') {
            start++;
        }
        if (start >= jsonBytes.length) {
            return address(0);
        }
        start++; // Skip opening quote
        
        // Find closing quote
        uint256 end = start;
        while (end < jsonBytes.length && jsonBytes[end] != '"') {
            end++;
        }
        if (end >= jsonBytes.length) {
            return address(0);
        }
        
        // Extract address string and convert to address
        bytes memory addrBytes = new bytes(end - start);
        for (uint256 i = 0; i < end - start; i++) {
            addrBytes[i] = jsonBytes[start + i];
        }
        
        return _bytesToAddress(addrBytes);
    }
    
    function _findSubstring(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        uint256 needleLength = needle.length;
        if (needleLength == 0) return 0;
        
        for (uint256 i = 0; i <= haystack.length - needleLength; i++) {
            bool found = true;
            for (uint256 j = 0; j < needleLength; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }
        
        return type(uint256).max; // Not found
    }
    
    function _bytesToAddress(bytes memory data) internal pure returns (address) {
        return address(uint160(uint256(_hexToUint(data))));
    }
    
    function _hexToUint(bytes memory data) internal pure returns (uint256) {
        uint256 result = 0;
        for (uint256 i = 0; i < data.length; i++) {
            uint8 byteValue = uint8(data[i]);
            uint256 digit;
            if (byteValue >= 48 && byteValue <= 57) {
                digit = uint256(byteValue) - 48;
            } else if (byteValue >= 97 && byteValue <= 102) {
                digit = uint256(byteValue) - 87; // a-f
            } else if (byteValue >= 65 && byteValue <= 70) {
                digit = uint256(byteValue) - 55; // A-F
            } else {
                continue; // Skip non-hex characters
            }
            result = result * 16 + digit;
        }
        return result;
    }
    
    function _updateDeploymentFile(
        string memory deploymentPath,
        string memory quoteSymbol,
        address wethQuotePool,
        address wbtcQuotePool,
        address goldQuotePool,
        address silverQuotePool,
        address googleQuotePool,
        address nvidiaQuotePool,
        address mntQuotePool,
        address appleQuotePool,
        address deployer
    ) internal {
        string memory json = vm.readFile(deploymentPath);

        // Simple approach: just write a new JSON file
        address tokenRegistry = _extractAddress(json, "TokenRegistry");
        address oracle = _extractAddress(json, "Oracle");
        address lendingManager = _extractAddress(json, "LendingManager");
        address balanceManager = _extractAddress(json, "BalanceManager");
        address poolManager = _extractAddress(json, "PoolManager");
        address scaleXRouter = _extractAddress(json, "ScaleXRouter");
        address syntheticTokenFactory = _extractAddress(json, "SyntheticTokenFactory");

        // Load quote token dynamically
        address quoteToken = _extractAddress(json, quoteSymbol);
        string memory syntheticQuoteSymbol = string.concat("sx", quoteSymbol);
        address sxQuote = _extractAddress(json, syntheticQuoteSymbol);

        address weth = _extractAddress(json, "WETH");
        address wbtc = _extractAddress(json, "WBTC");
        address gold = _extractAddress(json, "GOLD");
        address silver = _extractAddress(json, "SILVER");
        address google = _extractAddress(json, "GOOGLE");
        address nvidia = _extractAddress(json, "NVIDIA");
        address mnt = _extractAddress(json, "MNT");
        address apple = _extractAddress(json, "APPLE");
        address sxWETH = _extractAddress(json, "sxWETH");
        address sxWBTC = _extractAddress(json, "sxWBTC");
        address sxGOLD = _extractAddress(json, "sxGOLD");
        address sxSILVER = _extractAddress(json, "sxSILVER");
        address sxGOOGLE = _extractAddress(json, "sxGOOGLE");
        address sxNVIDIA = _extractAddress(json, "sxNVIDIA");
        address sxMNT = _extractAddress(json, "sxMNT");
        address sxAPPLE = _extractAddress(json, "sxAPPLE");

        // Build pool keys dynamically
        string memory wethPoolKey = string.concat("WETH_", quoteSymbol, "_Pool");
        string memory wbtcPoolKey = string.concat("WBTC_", quoteSymbol, "_Pool");
        string memory goldPoolKey = string.concat("GOLD_", quoteSymbol, "_Pool");
        string memory silverPoolKey = string.concat("SILVER_", quoteSymbol, "_Pool");
        string memory googlePoolKey = string.concat("GOOGLE_", quoteSymbol, "_Pool");
        string memory nvidiaPoolKey = string.concat("NVIDIA_", quoteSymbol, "_Pool");
        string memory mntPoolKey = string.concat("MNT_", quoteSymbol, "_Pool");
        string memory applePoolKey = string.concat("APPLE_", quoteSymbol, "_Pool");

        string memory newJson = string.concat(
            "{\n",
            '  "networkName": "localhost",\n',
            '  "TokenRegistry": "', vm.toString(tokenRegistry), '",\n',
            '  "Oracle": "', vm.toString(oracle), '",\n',
            '  "LendingManager": "', vm.toString(lendingManager), '",\n',
            '  "BalanceManager": "', vm.toString(balanceManager), '",\n',
            '  "PoolManager": "', vm.toString(poolManager), '",\n',
            '  "ScaleXRouter": "', vm.toString(scaleXRouter), '",\n',
            '  "SyntheticTokenFactory": "', vm.toString(syntheticTokenFactory), '",\n',
            '  "', quoteSymbol, '": "', vm.toString(quoteToken), '",\n',
            '  "WETH": "', vm.toString(weth), '",\n',
            '  "WBTC": "', vm.toString(wbtc), '",\n',
            '  "GOLD": "', vm.toString(gold), '",\n',
            '  "SILVER": "', vm.toString(silver), '",\n',
            '  "GOOGLE": "', vm.toString(google), '",\n',
            '  "NVIDIA": "', vm.toString(nvidia), '",\n',
            '  "MNT": "', vm.toString(mnt), '",\n',
            '  "APPLE": "', vm.toString(apple), '",\n',
            '  "', syntheticQuoteSymbol, '": "', vm.toString(sxQuote), '",\n',
            '  "sxWETH": "', vm.toString(sxWETH), '",\n',
            '  "sxWBTC": "', vm.toString(sxWBTC), '",\n',
            '  "sxGOLD": "', vm.toString(sxGOLD), '",\n',
            '  "sxSILVER": "', vm.toString(sxSILVER), '",\n',
            '  "sxGOOGLE": "', vm.toString(sxGOOGLE), '",\n',
            '  "sxNVIDIA": "', vm.toString(sxNVIDIA), '",\n',
            '  "sxMNT": "', vm.toString(sxMNT), '",\n',
            '  "sxAPPLE": "', vm.toString(sxAPPLE), '",\n',
            '  "', wethPoolKey, '": "', vm.toString(wethQuotePool), '",\n',
            '  "', wbtcPoolKey, '": "', vm.toString(wbtcQuotePool), '",\n',
            '  "', goldPoolKey, '": "', vm.toString(goldQuotePool), '",\n',
            '  "', silverPoolKey, '": "', vm.toString(silverQuotePool), '",\n',
            '  "', googlePoolKey, '": "', vm.toString(googleQuotePool), '",\n',
            '  "', nvidiaPoolKey, '": "', vm.toString(nvidiaQuotePool), '",\n',
            '  "', mntPoolKey, '": "', vm.toString(mntQuotePool), '",\n',
            '  "', applePoolKey, '": "', vm.toString(appleQuotePool), '",\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "timestamp": "', vm.toString(block.timestamp), '",\n',
            '  "blockNumber": "', vm.toString(block.number), '",\n',
            '  "deploymentComplete": true\n',
            "}"
        );

        vm.writeFile(deploymentPath, newJson);
        console.log("Deployment file updated with pool addresses");
    }
}