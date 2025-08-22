// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/core/BalanceManager.sol";
import "../src/core/GTXRouter.sol";
import "../src/core/PoolManager.sol";
import "./DeployHelpers.s.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract SimpleRariTradingDeploy is DeployHelpers {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Existing BalanceManager
        address existingBalanceManager = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        
        console.log("========== SIMPLE RARI TRADING DEPLOYMENT ==========");
        console.log("Deployer:", deployer);
        console.log("Existing BalanceManager:", existingBalanceManager);
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy beacons with deployer as owner
        console.log("Deploying PoolManager beacon...");
        address poolManagerBeacon = Upgrades.deployBeacon("PoolManager.sol", deployer);
        console.log("PoolManager Beacon:", poolManagerBeacon);

        console.log("Deploying Router beacon...");
        address routerBeacon = Upgrades.deployBeacon("GTXRouter.sol", deployer);
        console.log("Router Beacon:", routerBeacon);

        console.log("Deploying OrderBook beacon...");
        address orderBookBeacon = Upgrades.deployBeacon("OrderBook.sol", deployer);
        console.log("OrderBook Beacon:", orderBookBeacon);

        // Deploy proxies
        console.log("Deploying PoolManager proxy...");
        address poolManagerProxy = Upgrades.deployBeaconProxy(
            poolManagerBeacon,
            abi.encodeCall(PoolManager.initialize, (deployer, existingBalanceManager, orderBookBeacon))
        );
        console.log("PoolManager Proxy:", poolManagerProxy);

        console.log("Deploying Router proxy...");
        address routerProxy = Upgrades.deployBeaconProxy(
            routerBeacon, 
            abi.encodeCall(GTXRouter.initialize, (poolManagerProxy, existingBalanceManager))
        );
        console.log("Router Proxy:", routerProxy);

        // Configure PoolManager
        console.log("Setting router in PoolManager...");
        PoolManager(poolManagerProxy).setRouter(routerProxy);
        console.log("Router set successfully!");

        // Configure BalanceManager authorization
        console.log("Authorizing operators in BalanceManager...");
        BalanceManager balanceManager = BalanceManager(existingBalanceManager);
        
        balanceManager.setPoolManager(poolManagerProxy);
        console.log("PoolManager set in BalanceManager");

        balanceManager.setAuthorizedOperator(poolManagerProxy, true);
        console.log("PoolManager authorized as operator");

        balanceManager.setAuthorizedOperator(routerProxy, true);
        console.log("Router authorized as operator");

        vm.stopBroadcast();

        console.log("========== DEPLOYMENT COMPLETE ==========");
        console.log("PoolManager:", poolManagerProxy);
        console.log("Router:", routerProxy);
        console.log("OrderBook Beacon:", orderBookBeacon);
        console.log("Ready to create trading pools!");
    }
}