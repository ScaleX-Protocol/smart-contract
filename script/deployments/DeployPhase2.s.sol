// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {TokenRegistry} from "../src/core/TokenRegistry.sol";
import {SyntheticTokenFactory} from "../src/core/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../src/token/SyntheticToken.sol";
import {LendingManager} from "../src/yield/LendingManager.sol";
import {ScaleXRouter} from "../src/core/ScaleXRouter.sol";
import {BalanceManager} from "../src/core/BalanceManager.sol";
import {PoolManager} from "../src/core/PoolManager.sol";

contract DeployPhase2 is Script {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("=== PHASE 2: CONFIGURATION AND SETUP ===");
        console.log("Deployer address:", deployer);
        
        // Read addresses from environment variables (set by deploy.sh)
        address usdc = vm.envAddress("USDC_ADDRESS");
        address weth = vm.envAddress("WETH_ADDRESS");
        address wbtc = vm.envAddress("WBTC_ADDRESS");
        address tokenRegistry = vm.envAddress("TOKEN_REGISTRY_ADDRESS");
        address oracle = vm.envAddress("ORACLE_ADDRESS");
        address lendingManager = vm.envAddress("LENDING_MANAGER_ADDRESS");
        address balanceManager = vm.envAddress("BALANCE_MANAGER_ADDRESS");
        address poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");
        address scaleXRouter = vm.envAddress("SCALEX_ROUTER_ADDRESS");
        address syntheticTokenFactory = vm.envAddress("SYNTHETIC_TOKEN_FACTORY_ADDRESS");
        
        console.log("Loaded Phase 1 deployment:");
        console.log("  TokenRegistry:", tokenRegistry);
        console.log("  LendingManager:", lendingManager);
        console.log("  BalanceManager:", balanceManager);
        console.log("  ScaleXRouter:", scaleXRouter);
        console.log("  SyntheticTokenFactory:", syntheticTokenFactory);
        console.log("  USDC:", usdc);
        console.log("  WETH:", weth);
        console.log("  WBTC:", wbtc);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Configure TokenRegistry factory permissions
        console.log("Step 1: Configuring TokenRegistry...");
        TokenRegistry(tokenRegistry).initializeUpgrade(deployer, syntheticTokenFactory);
        console.log("[OK] SyntheticTokenFactory set as factory in TokenRegistry");
        
        // Step 2: Initialize core contract relationships
        console.log("Step 2: Setting up core contract relationships...");
        BalanceManager bm = BalanceManager(balanceManager);
        PoolManager pm = PoolManager(poolManager);
        ScaleXRouter router = ScaleXRouter(scaleXRouter);
        LendingManager lm = LendingManager(lendingManager);
        
        bm.setPoolManager(address(pm));
        bm.setLendingManager(address(lm));
        bm.setTokenRegistry(address(tokenRegistry));
        bm.setAuthorizedOperator(address(router), true);
        bm.setAuthorizedOperator(address(pm), true);
        
        lm.setBalanceManager(address(bm));
        router.setLendingManager(address(lm));
        
        pm.setRouter(address(router));
        
        console.log("[OK] Core contract relationships configured");
        
        // Step 3: Create Synthetic Tokens
        console.log("Step 3: Creating Synthetic Tokens...");
        SyntheticTokenFactory factory = SyntheticTokenFactory(syntheticTokenFactory);
        
        uint32 chainId = uint32(block.chainid);
        
        address gsUSDC = factory.createSyntheticToken(
            chainId, 
            usdc, 
            chainId, 
            "gsUSDC", 
            "gsUSDC", 
            6, 
            6
        );
        console.log("[OK] gsUSDC created:", gsUSDC);
        
        address gsWETH = factory.createSyntheticToken(
            chainId, 
            weth, 
            chainId, 
            "gsWETH", 
            "gsWETH", 
            18, 
            18
        );
        console.log("[OK] gsWETH created:", gsWETH);
        
        address gsWBTC = factory.createSyntheticToken(
            chainId, 
            wbtc, 
            chainId, 
            "gsWBTC", 
            "gsWBTC", 
            8, 
            8
        );
        console.log("[OK] gsWBTC created:", gsWBTC);
        
        // Step 4: Set BalanceManager as minter for Synthetic Tokens
        console.log("Step 4: Setting BalanceManager as minter...");
        SyntheticToken(gsUSDC).setMinter(address(bm));
        SyntheticToken(gsWETH).setMinter(address(bm));
        SyntheticToken(gsWBTC).setMinter(address(bm));
        console.log("[OK] BalanceManager set as minter for all synthetic tokens");
        
        // Step 5: Add supported assets to BalanceManager
        console.log("Step 5: Adding supported assets...");
        bm.addSupportedAsset(usdc, gsUSDC);
        bm.addSupportedAsset(weth, gsWETH);
        bm.addSupportedAsset(wbtc, gsWBTC);
        console.log("[OK] All synthetic tokens added as supported assets");
        
        // Step 6: Configure lending assets
        console.log("Step 6: Configuring lending assets...");
        
        // USDC: 75% CF, 85% LT, 8% LB, 10% RF
        lm.configureAsset(
            usdc,
            7500,   // 75% collateral factor (7500 basis points)
            8500,   // 85% liquidation threshold (8500 basis points)
            800,    // 8% liquidation bonus (800 basis points)
            1000    // 10% reserve factor (1000 basis points)
        );
        console.log("[OK] USDC lending asset configured");
        
        // WETH: 70% CF, 85% LT, 8% LB, 10% RF
        lm.configureAsset(
            weth,
            7000,   // 70% collateral factor (7000 basis points)
            8500,   // 85% liquidation threshold (8500 basis points)
            800,    // 8% liquidation bonus (800 basis points)
            1000    // 10% reserve factor (1000 basis points)
        );
        console.log("[OK] WETH lending asset configured");
        
        // WBTC: 65% CF, 85% LT, 8% LB, 10% RF
        lm.configureAsset(
            wbtc,
            6500,   // 65% collateral factor (6500 basis points)
            8500,   // 85% liquidation threshold (8500 basis points)
            800,    // 8% liquidation bonus (800 basis points)
            1000    // 10% reserve factor (1000 basis points)
        );
        console.log("[OK] WBTC lending asset configured");
        
        // Step 7: Set ScaleXRouter in LendingManager
        console.log("Step 7: Finalizing ScaleXRouter setup...");
        lm.setBalanceManager(address(bm));
        console.log("[OK] ScaleXRouter linked to LendingManager");
        
        vm.stopBroadcast();
        
        // Step 8: Write final deployment data
        console.log("Step 8: Writing final deployment data...");
        _writeFinalDeployment(
            tokenRegistry,
            oracle,
            lendingManager,
            balanceManager,
            poolManager,
            scaleXRouter,
            syntheticTokenFactory,
            usdc,
            weth,
            wbtc,
            gsUSDC,
            gsWETH,
            gsWBTC
        );
        
        console.log("=== PHASE 2 CONFIGURATION COMPLETED ===");
        console.log("[SUCCESS] Full deployment completed successfully!");
    }
    
    function _writeFinalDeployment(
        address tokenRegistry,
        address oracle,
        address lendingManager,
        address balanceManager,
        address poolManager,
        address scaleXRouter,
        address syntheticTokenFactory,
        address usdc,
        address weth,
        address wbtc,
        address gsUSDC,
        address gsWETH,
        address gsWBTC
    ) internal {
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory path = string.concat(root, "/deployments/", chainIdStr, ".json");
        
        string memory json = string.concat(
            "{\n",
            "  \"networkName\": \"localhost\",\n",
            "  \"TokenRegistry\": \"", vm.toString(tokenRegistry), "\",\n",
            "  \"Oracle\": \"", vm.toString(oracle), "\",\n",
            "  \"LendingManager\": \"", vm.toString(lendingManager), "\",\n",
            "  \"BalanceManager\": \"", vm.toString(balanceManager), "\",\n",
            "  \"PoolManager\": \"", vm.toString(poolManager), "\",\n",
            "  \"ScaleXRouter\": \"", vm.toString(scaleXRouter), "\",\n",
            "  \"SyntheticTokenFactory\": \"", vm.toString(syntheticTokenFactory), "\",\n",
            "  \"USDC\": \"", vm.toString(usdc), "\",\n",
            "  \"WETH\": \"", vm.toString(weth), "\",\n",
            "  \"WBTC\": \"", vm.toString(wbtc), "\",\n",
            "  \"gsUSDC\": \"", vm.toString(gsUSDC), "\",\n",
            "  \"gsWETH\": \"", vm.toString(gsWETH), "\",\n",
            "  \"gsWBTC\": \"", vm.toString(gsWBTC), "\",\n",
            "  \"WETH_USDC_Pool\": \"0x0000000000000000000000000000000000000000\",\n",
            "  \"WBTC_USDC_Pool\": \"0x0000000000000000000000000000000000000000\",\n",
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