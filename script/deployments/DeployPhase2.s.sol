// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {TokenRegistry} from "@scalexcore/TokenRegistry.sol";
import {SyntheticTokenFactory} from "@scalexcore/SyntheticTokenFactory.sol";
import {SyntheticToken} from "@scalex/token/SyntheticToken.sol";
import {LendingManager} from "@scalex/yield/LendingManager.sol";
import {ScaleXRouter} from "@scalexcore/ScaleXRouter.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {PoolManager} from "@scalexcore/PoolManager.sol";

contract DeployPhase2 is Script {

    struct DeploymentAddresses {
        address tokenRegistry;
        address oracle;
        address lendingManager;
        address balanceManager;
        address poolManager;
        address scaleXRouter;
        address syntheticTokenFactory;
    }

    struct QuoteCurrencyConfig {
        string symbol;
        address tokenAddress;
        uint8 decimals;
        string syntheticSymbol;
    }

    struct BaseTokenAddresses {
        address weth;
        address wbtc;
        address gold;
        address silver;
        address google;
        address nvidia;
        address mnt;
        address apple;
    }

    struct SyntheticTokens {
        address sxQuote;
        address sxWETH;
        address sxWBTC;
        address sxGOLD;
        address sxSILVER;
        address sxGOOGLE;
        address sxNVIDIA;
        address sxMNT;
        address sxAPPLE;
    }

    function _loadDeploymentAddresses() internal view returns (DeploymentAddresses memory) {
        return DeploymentAddresses({
            tokenRegistry: vm.envAddress("TOKEN_REGISTRY_ADDRESS"),
            oracle: vm.envAddress("ORACLE_ADDRESS"),
            lendingManager: vm.envAddress("LENDING_MANAGER_ADDRESS"),
            balanceManager: vm.envAddress("BALANCE_MANAGER_ADDRESS"),
            poolManager: vm.envAddress("POOL_MANAGER_ADDRESS"),
            scaleXRouter: vm.envAddress("SCALEX_ROUTER_ADDRESS"),
            syntheticTokenFactory: vm.envAddress("SYNTHETIC_TOKEN_FACTORY_ADDRESS")
        });
    }

    function _loadQuoteCurrencyConfig() internal view returns (QuoteCurrencyConfig memory) {
        string memory symbol = vm.envString("QUOTE_SYMBOL");
        return QuoteCurrencyConfig({
            symbol: symbol,
            tokenAddress: vm.envAddress("QUOTE_TOKEN_ADDRESS"),
            decimals: uint8(vm.envUint("QUOTE_DECIMALS")),
            syntheticSymbol: string.concat("sx", symbol)
        });
    }

    function _loadBaseTokenAddresses() internal view returns (BaseTokenAddresses memory) {
        return BaseTokenAddresses({
            weth: vm.envAddress("WETH_ADDRESS"),
            wbtc: vm.envAddress("WBTC_ADDRESS"),
            gold: vm.envAddress("GOLD_ADDRESS"),
            silver: vm.envAddress("SILVER_ADDRESS"),
            google: vm.envAddress("GOOGLE_ADDRESS"),
            nvidia: vm.envAddress("NVIDIA_ADDRESS"),
            mnt: vm.envAddress("MNT_ADDRESS"),
            apple: vm.envAddress("APPLE_ADDRESS")
        });
    }

    function _configureTokenRegistry(
        address tokenRegistry,
        address syntheticTokenFactory,
        address deployer
    ) internal {
        TokenRegistry(tokenRegistry).initializeUpgrade(deployer, syntheticTokenFactory);
    }

    function _initializeCoreContracts(
        DeploymentAddresses memory deployment
    ) internal {
        BalanceManager bm = BalanceManager(deployment.balanceManager);
        PoolManager pm = PoolManager(deployment.poolManager);
        ScaleXRouter router = ScaleXRouter(deployment.scaleXRouter);
        LendingManager lm = LendingManager(deployment.lendingManager);

        bm.setPoolManager(address(pm));
        bm.setLendingManager(address(lm));
        bm.setTokenRegistry(deployment.tokenRegistry);
        bm.setAuthorizedOperator(address(router), true);
        bm.setAuthorizedOperator(address(pm), true);

        lm.setBalanceManager(address(bm));
        router.setLendingManager(address(lm));
        pm.setRouter(address(router));
    }

    function _createSyntheticToken(
        SyntheticTokenFactory factory,
        uint32 chainId,
        address baseToken,
        string memory symbol,
        uint8 decimals
    ) internal returns (address) {
        return factory.createSyntheticToken(
            chainId,
            baseToken,
            chainId,
            symbol,
            symbol,
            decimals,
            decimals
        );
    }

    function _createAllSyntheticTokens(
        address syntheticTokenFactory,
        QuoteCurrencyConfig memory quoteConfig,
        BaseTokenAddresses memory baseTokens
    ) internal returns (SyntheticTokens memory syntheticTokens) {
        SyntheticTokenFactory factory = SyntheticTokenFactory(syntheticTokenFactory);
        uint32 chainId = uint32(block.chainid);

        syntheticTokens.sxQuote = _createSyntheticToken(
            factory, chainId, quoteConfig.tokenAddress, quoteConfig.syntheticSymbol, quoteConfig.decimals
        );
        syntheticTokens.sxWETH = _createSyntheticToken(factory, chainId, baseTokens.weth, "sxWETH", 18);
        syntheticTokens.sxWBTC = _createSyntheticToken(factory, chainId, baseTokens.wbtc, "sxWBTC", 8);
        syntheticTokens.sxGOLD = _createSyntheticToken(factory, chainId, baseTokens.gold, "sxGOLD", 18);
        syntheticTokens.sxSILVER = _createSyntheticToken(factory, chainId, baseTokens.silver, "sxSILVER", 18);
        syntheticTokens.sxGOOGLE = _createSyntheticToken(factory, chainId, baseTokens.google, "sxGOOGLE", 18);
        syntheticTokens.sxNVIDIA = _createSyntheticToken(factory, chainId, baseTokens.nvidia, "sxNVIDIA", 18);
        syntheticTokens.sxMNT = _createSyntheticToken(factory, chainId, baseTokens.mnt, "sxMNT", 18);
        syntheticTokens.sxAPPLE = _createSyntheticToken(factory, chainId, baseTokens.apple, "sxAPPLE", 18);
    }

    function _setMinters(
        address balanceManager,
        SyntheticTokens memory syntheticTokens
    ) internal {
        SyntheticToken(syntheticTokens.sxQuote).setMinter(balanceManager);
        SyntheticToken(syntheticTokens.sxWETH).setMinter(balanceManager);
        SyntheticToken(syntheticTokens.sxWBTC).setMinter(balanceManager);
        SyntheticToken(syntheticTokens.sxGOLD).setMinter(balanceManager);
        SyntheticToken(syntheticTokens.sxSILVER).setMinter(balanceManager);
        SyntheticToken(syntheticTokens.sxGOOGLE).setMinter(balanceManager);
        SyntheticToken(syntheticTokens.sxNVIDIA).setMinter(balanceManager);
        SyntheticToken(syntheticTokens.sxMNT).setMinter(balanceManager);
        SyntheticToken(syntheticTokens.sxAPPLE).setMinter(balanceManager);
    }

    function _addSupportedAssets(
        address balanceManager,
        QuoteCurrencyConfig memory quoteConfig,
        BaseTokenAddresses memory baseTokens,
        SyntheticTokens memory syntheticTokens
    ) internal {
        BalanceManager bm = BalanceManager(balanceManager);

        bm.addSupportedAsset(quoteConfig.tokenAddress, syntheticTokens.sxQuote);
        bm.addSupportedAsset(baseTokens.weth, syntheticTokens.sxWETH);
        bm.addSupportedAsset(baseTokens.wbtc, syntheticTokens.sxWBTC);
        bm.addSupportedAsset(baseTokens.gold, syntheticTokens.sxGOLD);
        bm.addSupportedAsset(baseTokens.silver, syntheticTokens.sxSILVER);
        bm.addSupportedAsset(baseTokens.google, syntheticTokens.sxGOOGLE);
        bm.addSupportedAsset(baseTokens.nvidia, syntheticTokens.sxNVIDIA);
        bm.addSupportedAsset(baseTokens.mnt, syntheticTokens.sxMNT);
        bm.addSupportedAsset(baseTokens.apple, syntheticTokens.sxAPPLE);
    }

    function _configureLendingAssets(
        address lendingManager,
        QuoteCurrencyConfig memory quoteConfig,
        BaseTokenAddresses memory baseTokens
    ) internal {
        LendingManager lm = LendingManager(lendingManager);

        _configureQuoteLending(lm, quoteConfig);
        _configureCryptoLending(lm, baseTokens);
        _configureRWALending(lm, baseTokens);
    }

    function _configureQuoteLending(
        LendingManager lm,
        QuoteCurrencyConfig memory quoteConfig
    ) internal {
        uint256 quoteCF = vm.envUint("QUOTE_COLLATERAL_FACTOR");
        uint256 quoteLT = vm.envUint("QUOTE_LIQUIDATION_THRESHOLD");
        uint256 quoteLB = vm.envUint("QUOTE_LIQUIDATION_BONUS");
        uint256 quoteRF = vm.envUint("QUOTE_RESERVE_FACTOR");

        lm.configureAsset(quoteConfig.tokenAddress, quoteCF, quoteLT, quoteLB, quoteRF);
    }

    function _configureCryptoLending(
        LendingManager lm,
        BaseTokenAddresses memory baseTokens
    ) internal {
        // WETH: 70% CF, 85% LT, 8% LB, 10% RF
        lm.configureAsset(baseTokens.weth, 7000, 8500, 800, 1000);

        // WBTC: 65% CF, 85% LT, 8% LB, 10% RF
        lm.configureAsset(baseTokens.wbtc, 6500, 8500, 800, 1000);
    }

    function _configureRWALending(
        LendingManager lm,
        BaseTokenAddresses memory baseTokens
    ) internal {
        // GOLD: 60% CF, 70% LT, 12% LB, 18% RF
        lm.configureAsset(baseTokens.gold, 6000, 7000, 1200, 1800);

        // SILVER: 60% CF, 70% LT, 12% LB, 18% RF
        lm.configureAsset(baseTokens.silver, 6000, 7000, 1200, 1800);

        // GOOGLE: 65% CF, 75% LT, 10% LB, 15% RF
        lm.configureAsset(baseTokens.google, 6500, 7500, 1000, 1500);

        // NVIDIA: 65% CF, 75% LT, 10% LB, 15% RF
        lm.configureAsset(baseTokens.nvidia, 6500, 7500, 1000, 1500);

        // MNT: 60% CF, 70% LT, 12% LB, 18% RF
        lm.configureAsset(baseTokens.mnt, 6000, 7000, 1200, 1800);

        // APPLE: 65% CF, 75% LT, 10% LB, 15% RF
        lm.configureAsset(baseTokens.apple, 6500, 7500, 1000, 1500);
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("=== PHASE 2: CONFIGURATION AND SETUP ===");
        console.log("Deployer address:", deployer);

        // Load all addresses from environment - grouped into structs
        DeploymentAddresses memory deployment = _loadDeploymentAddresses();
        QuoteCurrencyConfig memory quoteConfig = _loadQuoteCurrencyConfig();
        BaseTokenAddresses memory baseTokens = _loadBaseTokenAddresses();

        console.log("Loaded Phase 1 deployment:");
        console.log("  TokenRegistry:", deployment.tokenRegistry);
        console.log("  LendingManager:", deployment.lendingManager);
        console.log("  BalanceManager:", deployment.balanceManager);
        console.log("  ScaleXRouter:", deployment.scaleXRouter);
        console.log("  SyntheticTokenFactory:", deployment.syntheticTokenFactory);
        console.log("  Quote Token:", quoteConfig.tokenAddress);
        console.log("  WETH:", baseTokens.weth);
        console.log("  WBTC:", baseTokens.wbtc);
        console.log("  GOLD:", baseTokens.gold);
        console.log("  SILVER:", baseTokens.silver);
        console.log("  GOOGLE:", baseTokens.google);
        console.log("  NVIDIA:", baseTokens.nvidia);
        console.log("  MNT:", baseTokens.mnt);
        console.log("  APPLE:", baseTokens.apple);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Configure TokenRegistry
        console.log("Step 1: Configuring TokenRegistry...");
        _configureTokenRegistry(deployment.tokenRegistry, deployment.syntheticTokenFactory, deployer);
        console.log("[OK] TokenRegistry configured");

        // Step 2: Initialize core contract relationships
        console.log("Step 2: Initializing core contracts...");
        _initializeCoreContracts(deployment);
        console.log("[OK] Core contracts initialized");

        // Step 3-5: Create and configure synthetic tokens
        console.log("Step 3: Creating synthetic tokens...");
        SyntheticTokens memory syntheticTokens = _createAllSyntheticTokens(
            deployment.syntheticTokenFactory,
            quoteConfig,
            baseTokens
        );
        console.log("[OK] Synthetic tokens created");

        console.log("Step 4: Setting minters...");
        _setMinters(deployment.balanceManager, syntheticTokens);
        console.log("[OK] Minters set");

        console.log("Step 5: Adding supported assets...");
        _addSupportedAssets(deployment.balanceManager, quoteConfig, baseTokens, syntheticTokens);
        console.log("[OK] Supported assets added");

        // Step 6: Configure lending assets
        console.log("Step 6: Configuring lending assets...");
        _configureLendingAssets(deployment.lendingManager, quoteConfig, baseTokens);
        console.log("[OK] Lending assets configured");

        vm.stopBroadcast();

        // Write final deployment data
        console.log("Writing final deployment data...");
        _writeFinalDeployment(deployment, quoteConfig, baseTokens, syntheticTokens);

        console.log("=== PHASE 2 CONFIGURATION COMPLETED ===");
        console.log("[SUCCESS] Full deployment completed successfully!");
    }

    function _writeFinalDeployment(
        DeploymentAddresses memory deployment,
        QuoteCurrencyConfig memory quoteConfig,
        BaseTokenAddresses memory baseTokens,
        SyntheticTokens memory syntheticTokens
    ) internal {
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory path = string.concat(root, "/deployments/", chainIdStr, ".json");

        // Build pool keys dynamically
        string memory wethPoolKey = string.concat("WETH_", quoteConfig.symbol, "_Pool");
        string memory wbtcPoolKey = string.concat("WBTC_", quoteConfig.symbol, "_Pool");
        string memory goldPoolKey = string.concat("GOLD_", quoteConfig.symbol, "_Pool");
        string memory silverPoolKey = string.concat("SILVER_", quoteConfig.symbol, "_Pool");
        string memory googlePoolKey = string.concat("GOOGLE_", quoteConfig.symbol, "_Pool");
        string memory nvidiaPoolKey = string.concat("NVIDIA_", quoteConfig.symbol, "_Pool");
        string memory mntPoolKey = string.concat("MNT_", quoteConfig.symbol, "_Pool");
        string memory applePoolKey = string.concat("APPLE_", quoteConfig.symbol, "_Pool");

        string memory json = string.concat(
            "{\n",
            "  \"networkName\": \"localhost\",\n",
            "  \"TokenRegistry\": \"", vm.toString(deployment.tokenRegistry), "\",\n",
            "  \"Oracle\": \"", vm.toString(deployment.oracle), "\",\n",
            "  \"LendingManager\": \"", vm.toString(deployment.lendingManager), "\",\n",
            "  \"BalanceManager\": \"", vm.toString(deployment.balanceManager), "\",\n",
            "  \"PoolManager\": \"", vm.toString(deployment.poolManager), "\",\n",
            "  \"ScaleXRouter\": \"", vm.toString(deployment.scaleXRouter), "\",\n",
            "  \"SyntheticTokenFactory\": \"", vm.toString(deployment.syntheticTokenFactory), "\",\n",
            "  \"", quoteConfig.symbol, "\": \"", vm.toString(quoteConfig.tokenAddress), "\",\n",
            "  \"WETH\": \"", vm.toString(baseTokens.weth), "\",\n",
            "  \"WBTC\": \"", vm.toString(baseTokens.wbtc), "\",\n",
            "  \"GOLD\": \"", vm.toString(baseTokens.gold), "\",\n",
            "  \"SILVER\": \"", vm.toString(baseTokens.silver), "\",\n",
            "  \"GOOGLE\": \"", vm.toString(baseTokens.google), "\",\n",
            "  \"NVIDIA\": \"", vm.toString(baseTokens.nvidia), "\",\n",
            "  \"MNT\": \"", vm.toString(baseTokens.mnt), "\",\n",
            "  \"APPLE\": \"", vm.toString(baseTokens.apple), "\",\n",
            "  \"", quoteConfig.syntheticSymbol, "\": \"", vm.toString(syntheticTokens.sxQuote), "\",\n",
            "  \"sxWETH\": \"", vm.toString(syntheticTokens.sxWETH), "\",\n",
            "  \"sxWBTC\": \"", vm.toString(syntheticTokens.sxWBTC), "\",\n",
            "  \"sxGOLD\": \"", vm.toString(syntheticTokens.sxGOLD), "\",\n",
            "  \"sxSILVER\": \"", vm.toString(syntheticTokens.sxSILVER), "\",\n",
            "  \"sxGOOGLE\": \"", vm.toString(syntheticTokens.sxGOOGLE), "\",\n",
            "  \"sxNVIDIA\": \"", vm.toString(syntheticTokens.sxNVIDIA), "\",\n",
            "  \"sxMNT\": \"", vm.toString(syntheticTokens.sxMNT), "\",\n",
            "  \"sxAPPLE\": \"", vm.toString(syntheticTokens.sxAPPLE), "\",\n",
            "  \"", wethPoolKey, "\": \"0x0000000000000000000000000000000000000000\",\n",
            "  \"", wbtcPoolKey, "\": \"0x0000000000000000000000000000000000000000\",\n",
            "  \"", goldPoolKey, "\": \"0x0000000000000000000000000000000000000000\",\n",
            "  \"", silverPoolKey, "\": \"0x0000000000000000000000000000000000000000\",\n",
            "  \"", googlePoolKey, "\": \"0x0000000000000000000000000000000000000000\",\n",
            "  \"", nvidiaPoolKey, "\": \"0x0000000000000000000000000000000000000000\",\n",
            "  \"", mntPoolKey, "\": \"0x0000000000000000000000000000000000000000\",\n",
            "  \"", applePoolKey, "\": \"0x0000000000000000000000000000000000000000\",\n",
            "  \"deployer\": \"", vm.toString(vm.addr(vm.envUint("PRIVATE_KEY"))), "\",\n",
            "  \"timestamp\": \"", vm.toString(block.timestamp), "\",\n",
            "  \"blockNumber\": \"", vm.toString(block.number), "\",\n",
            "  \"deploymentComplete\": true\n",
            "}"
        );

        vm.writeFile(path, json);
        console.log("Final deployment data written to:", path);
    }
}