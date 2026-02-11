// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {RangeLiquidityManager} from "@scalexcore/RangeLiquidityManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/**
 * @title DeployAndConfigureRangeLiquidity
 * @notice All-in-one deployment script for RangeLiquidityManager
 * @dev Deploys implementation, beacon, proxy, and configures permissions
 */
contract DeployAndConfigureRangeLiquidity is Script {
    struct DeploymentAddresses {
        address implementation;
        address beacon;
        address proxy;
    }

    function run() external returns (DeploymentAddresses memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("   RANGE LIQUIDITY MANAGER - FULL DEPLOYMENT");
        console.log("==========================================================");
        console.log("Deployer:", deployer);
        console.log("");

        // Load configuration
        address poolManager = vm.envAddress("POOL_MANAGER");
        address balanceManager = vm.envAddress("BALANCE_MANAGER");
        address router = vm.envAddress("SCALEX_ROUTER");

        console.log("Configuration:");
        console.log("  PoolManager:", poolManager);
        console.log("  BalanceManager:", balanceManager);
        console.log("  ScaleXRouter:", router);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ============ DEPLOYMENT ============
        console.log("----------------------------------------------------------");
        console.log("PHASE 1: DEPLOYMENT");
        console.log("----------------------------------------------------------");

        console.log("[1/3] Deploying implementation...");
        RangeLiquidityManager implementation = new RangeLiquidityManager();
        console.log("      Implementation:", address(implementation));

        console.log("[2/3] Deploying beacon...");
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), deployer);
        console.log("      Beacon:", address(beacon));

        console.log("[3/3] Deploying proxy...");
        bytes memory initData = abi.encodeCall(
            RangeLiquidityManager.initialize,
            (poolManager, balanceManager, router)
        );
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        console.log("      Proxy:", address(proxy));

        console.log("");

        // ============ CONFIGURATION ============
        console.log("----------------------------------------------------------");
        console.log("PHASE 2: CONFIGURATION");
        console.log("----------------------------------------------------------");

        console.log("[1/1] Authorizing RangeLiquidityManager in BalanceManager...");
        IBalanceManager(balanceManager).setAuthorizedOperator(address(proxy), true);
        console.log("      Authorized!");

        vm.stopBroadcast();

        console.log("");

        // ============ VERIFICATION ============
        console.log("----------------------------------------------------------");
        console.log("PHASE 3: VERIFICATION");
        console.log("----------------------------------------------------------");
        console.log("[OK] Deployment and configuration complete!");
        console.log("");

        // ============ SUMMARY ============
        console.log("==========================================================");
        console.log("   DEPLOYMENT COMPLETE");
        console.log("==========================================================");
        console.log("");
        console.log("Deployed Addresses:");
        console.log("----------------------------------------------------------");
        console.log("Implementation:          ", address(implementation));
        console.log("Beacon:                  ", address(beacon));
        console.log("Proxy (Main Contract):   ", address(proxy));
        console.log("");
        console.log("Save to .env:");
        console.log("----------------------------------------------------------");
        console.log("RANGE_LIQUIDITY_MANAGER=", address(proxy));
        console.log("RANGE_LIQUIDITY_BEACON=", address(beacon));
        console.log("RANGE_LIQUIDITY_IMPL=", address(implementation));
        console.log("");
        console.log("Next Steps:");
        console.log("----------------------------------------------------------");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Update frontend with contract address:", address(proxy));
        console.log("3. Test position creation:");
        console.log("   forge script script/range-liquidity/CreateTestPosition.s.sol \\");
        console.log("       --rpc-url $RPC_URL --broadcast");
        console.log("4. Set up keeper bot for auto-rebalancing");
        console.log("");
        console.log("Documentation:");
        console.log("----------------------------------------------------------");
        console.log("- User Guide:       RANGE_LIQUIDITY_README.md");
        console.log("- Deployment Guide: DEPLOYMENT_GUIDE.md");
        console.log("- Contract Source:  src/core/RangeLiquidityManager.sol");
        console.log("==========================================================");

        return DeploymentAddresses({
            implementation: address(implementation),
            beacon: address(beacon),
            proxy: address(proxy)
        });
    }
}
