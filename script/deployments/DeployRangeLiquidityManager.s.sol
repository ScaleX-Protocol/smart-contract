// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {RangeLiquidityManager} from "@scalexcore/RangeLiquidityManager.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract DeployRangeLiquidityManager is Script {
    struct DeploymentConfig {
        address poolManager;
        address balanceManager;
        address router;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== DEPLOYING RANGE LIQUIDITY MANAGER ===");
        console.log("Deployer address:", deployer);
        console.log("");

        // Load configuration from environment or use defaults
        DeploymentConfig memory config = _loadConfig();

        console.log("Configuration:");
        console.log("  PoolManager:", config.poolManager);
        console.log("  BalanceManager:", config.balanceManager);
        console.log("  Router:", config.router);
        console.log("");

        // Validate configuration
        require(config.poolManager != address(0), "PoolManager address not set");
        require(config.balanceManager != address(0), "BalanceManager address not set");
        require(config.router != address(0), "Router address not set");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy implementation
        console.log("Step 1: Deploying RangeLiquidityManager implementation...");
        RangeLiquidityManager implementation = new RangeLiquidityManager();
        console.log("[OK] Implementation deployed at:", address(implementation));

        // Step 2: Deploy beacon
        console.log("Step 2: Deploying UpgradeableBeacon...");
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), deployer);
        console.log("[OK] Beacon deployed at:", address(beacon));

        // Step 3: Deploy proxy
        console.log("Step 3: Deploying BeaconProxy...");
        bytes memory initData = abi.encodeCall(
            RangeLiquidityManager.initialize,
            (config.poolManager, config.balanceManager, config.router)
        );

        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        console.log("[OK] Proxy deployed at:", address(proxy));

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("");
        console.log("Deployed Addresses:");
        console.log("  Implementation:", address(implementation));
        console.log("  Beacon:", address(beacon));
        console.log("  Proxy (RangeLiquidityManager):", address(proxy));
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Test position creation:");
        console.log("   - Approve tokens to BalanceManager");
        console.log("   - Call createPosition() on", address(proxy));
        console.log("3. Set up keeper bot for auto-rebalancing");
        console.log("");
        console.log("Save these addresses to your .env file:");
        console.log("RANGE_LIQUIDITY_MANAGER=", address(proxy));
        console.log("RANGE_LIQUIDITY_BEACON=", address(beacon));
    }

    function _loadConfig() internal view returns (DeploymentConfig memory) {
        // Try to load from environment variables
        address poolManager = vm.envOr("POOL_MANAGER", address(0));
        address balanceManager = vm.envOr("BALANCE_MANAGER", address(0));
        address router = vm.envOr("SCALEX_ROUTER", address(0));

        return DeploymentConfig({
            poolManager: poolManager,
            balanceManager: balanceManager,
            router: router
        });
    }
}
