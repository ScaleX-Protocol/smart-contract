// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {BalanceManager} from "../src/core/BalanceManager.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {ScaleXRouter} from "../src/core/ScaleXRouter.sol";
import {OrderBook} from "../src/core/OrderBook.sol";
import {LendingManager} from "../src/yield/LendingManager.sol";
import {Oracle} from "../src/core/Oracle.sol";
import {TokenRegistry} from "../src/core/TokenRegistry.sol";
import {SyntheticTokenFactory} from "../src/core/SyntheticTokenFactory.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract DeployPhase1 is Script {
    struct Phase1Deployment {
        address USDC;
        address WETH;
        address WBTC;
        address TokenRegistry;
        address Oracle;
        address LendingManager;
        address BalanceManager;
        address PoolManager;
        address ScaleXRouter;
        address SyntheticTokenFactory;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("=== PHASE 1: CORE CONTRACT DEPLOYMENT ===");
        console.log("Deployer address:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy Mock Tokens
        console.log("Step 1: Deploying Mock Tokens...");
        MockToken usdc = new MockToken("USDC Coin", "USDC", 6);
        MockToken weth = new MockToken("Wrapped Ether", "WETH", 18);
        MockToken wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);
        
        // Mint initial tokens to deployer
        usdc.mint(deployer, 1_000_000 * 1e6); // 1M USDC
        weth.mint(deployer, 1_000 * 1e18); // 1K WETH
        wbtc.mint(deployer, 50 * 1e8); // 50 WBTC
        
        console.log("[OK] USDC deployed:", address(usdc));
        console.log("[OK] WETH deployed:", address(weth));
        console.log("[OK] WBTC deployed:", address(wbtc));
        
        // Step 2: Deploy TokenRegistry
        console.log("Step 2: Deploying TokenRegistry...");
        TokenRegistry tokenRegistryImpl = new TokenRegistry();
        UpgradeableBeacon tokenRegistryBeacon = new UpgradeableBeacon(address(tokenRegistryImpl), deployer);
        
        BeaconProxy tokenRegistryProxy = new BeaconProxy(
            address(tokenRegistryBeacon),
            abi.encodeCall(TokenRegistry.initialize, (deployer))
        );
        console.log("[OK] TokenRegistry proxy deployed:", address(tokenRegistryProxy));
        
        // Step 3: Deploy Oracle
        console.log("Step 3: Deploying Oracle...");
        Oracle oracleImpl = new Oracle();
        UpgradeableBeacon oracleBeacon = new UpgradeableBeacon(address(oracleImpl), deployer);
        BeaconProxy oracleProxy = new BeaconProxy(
            address(oracleBeacon),
            abi.encodeCall(Oracle.initialize, (deployer, address(tokenRegistryProxy)))
        );
        console.log("[OK] Oracle proxy deployed:", address(oracleProxy));
        
        // Step 4: Deploy LendingManager
        console.log("Step 4: Deploying LendingManager...");
        LendingManager lendingManagerImpl = new LendingManager();
        UpgradeableBeacon lendingManagerBeacon = new UpgradeableBeacon(address(lendingManagerImpl), deployer);
        BeaconProxy lendingManagerProxy = new BeaconProxy(
            address(lendingManagerBeacon),
            abi.encodeCall(LendingManager.initialize, (deployer, address(oracleProxy)))
        );
        console.log("[OK] LendingManager proxy deployed:", address(lendingManagerProxy));
        
        // Step 5: Deploy BalanceManager
        console.log("Step 5: Deploying BalanceManager...");
        BalanceManager balanceManagerImpl = new BalanceManager();
        UpgradeableBeacon balanceManagerBeacon = new UpgradeableBeacon(address(balanceManagerImpl), deployer);
        BeaconProxy balanceManagerProxy = new BeaconProxy(
            address(balanceManagerBeacon),
            abi.encodeCall(BalanceManager.initialize, (deployer, deployer, 0, 0))
        );
        console.log("[OK] BalanceManager proxy deployed:", address(balanceManagerProxy));
        
        // Step 6: Deploy OrderBook for PoolManager
        console.log("Step 6: Deploying OrderBook beacon...");
        OrderBook orderBookImpl = new OrderBook();
        UpgradeableBeacon orderBookBeacon = new UpgradeableBeacon(address(orderBookImpl), deployer);
        console.log("[OK] OrderBook beacon deployed:", address(orderBookBeacon));
        
        // Step 7: Deploy PoolManager
        console.log("Step 7: Deploying PoolManager...");
        PoolManager poolManagerImpl = new PoolManager();
        UpgradeableBeacon poolManagerBeacon = new UpgradeableBeacon(address(poolManagerImpl), deployer);
        BeaconProxy poolManagerProxy = new BeaconProxy(
            address(poolManagerBeacon),
            abi.encodeCall(PoolManager.initialize, (deployer, address(balanceManagerProxy), address(orderBookBeacon)))
        );
        console.log("[OK] PoolManager proxy deployed:", address(poolManagerProxy));
        
        // Step 8: Deploy ScaleXRouter
        console.log("Step 8: Deploying ScaleXRouter...");
        ScaleXRouter routerImpl = new ScaleXRouter();
        UpgradeableBeacon routerBeacon = new UpgradeableBeacon(address(routerImpl), deployer);
        BeaconProxy routerProxy = new BeaconProxy(
            address(routerBeacon),
            abi.encodeCall(ScaleXRouter.initialize, (address(poolManagerProxy), address(balanceManagerProxy)))
        );
        console.log("[OK] ScaleXRouter proxy deployed:", address(routerProxy));
        
        // Step 9: Deploy SyntheticTokenFactory
        console.log("Step 9: Deploying SyntheticTokenFactory...");
        SyntheticTokenFactory syntheticTokenFactoryImpl = new SyntheticTokenFactory();
        UpgradeableBeacon syntheticTokenFactoryBeacon = new UpgradeableBeacon(address(syntheticTokenFactoryImpl), deployer);
        BeaconProxy syntheticTokenFactoryProxy = new BeaconProxy(
            address(syntheticTokenFactoryBeacon),
            abi.encodeCall(SyntheticTokenFactory.initialize, (deployer, address(tokenRegistryProxy), deployer))
        );
        console.log("[OK] SyntheticTokenFactory proxy deployed:", address(syntheticTokenFactoryProxy));
        
        vm.stopBroadcast();
        
        // Step 10: Write Phase 1 deployment data
        console.log("Step 10: Writing Phase 1 deployment data...");
        _writePhase1Deployment(
            address(usdc),
            address(weth),
            address(wbtc),
            address(tokenRegistryProxy),
            address(oracleProxy),
            address(lendingManagerProxy),
            address(balanceManagerProxy),
            address(poolManagerProxy),
            address(routerProxy),
            address(syntheticTokenFactoryProxy)
        );
        
        console.log("=== PHASE 1 DEPLOYMENT COMPLETED ===");
    }
    
    function _writePhase1Deployment(
        address usdc,
        address weth,
        address wbtc,
        address tokenRegistry,
        address oracle,
        address lendingManager,
        address balanceManager,
        address poolManager,
        address router,
        address syntheticTokenFactory
    ) internal {
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory path = string.concat(root, "/deployments/", chainIdStr, ".json");
        
        string memory json = string.concat(
            "{\n",
            "  \"networkName\": \"localhost\",\n",
            "  \"USDC\": \"", vm.toString(usdc), "\",\n",
            "  \"WETH\": \"", vm.toString(weth), "\",\n",
            "  \"WBTC\": \"", vm.toString(wbtc), "\",\n",
            "  \"TokenRegistry\": \"", vm.toString(tokenRegistry), "\",\n",
            "  \"Oracle\": \"", vm.toString(oracle), "\",\n",
            "  \"LendingManager\": \"", vm.toString(lendingManager), "\",\n",
            "  \"BalanceManager\": \"", vm.toString(balanceManager), "\",\n",
            "  \"PoolManager\": \"", vm.toString(poolManager), "\",\n",
            "  \"ScaleXRouter\": \"", vm.toString(router), "\",\n",
            "  \"SyntheticTokenFactory\": \"", vm.toString(syntheticTokenFactory), "\",\n",
            "  \"deployer\": \"", vm.toString(vm.addr(vm.envUint("PRIVATE_KEY"))), "\",\n",
            "  \"timestamp\": \"", vm.toString(block.timestamp), "\",\n",
            "  \"blockNumber\": \"", vm.toString(block.number), "\",\n",
            "  \"deploymentComplete\": true\n",
            "}"
        );
        
        vm.writeFile(path, json);
        console.log("Phase 1 deployment data written to:", path);
    }
}