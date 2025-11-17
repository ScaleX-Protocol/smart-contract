// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {TokenRegistry} from "@scalexcore/TokenRegistry.sol";
import {Oracle} from "@scalexcore/Oracle.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {LendingManager} from "@scalex/yield/LendingManager.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {OrderBook} from "@scalexcore/OrderBook.sol";
import {PoolManager} from "@scalexcore/PoolManager.sol";

contract DeployPhase1B is Script {
    struct Phase1BDeployment {
        address TokenRegistry;
        address Oracle;
        address LendingManager;
        address BalanceManager;
        address PoolManager;
        address ScaleXRouter;
        address SyntheticTokenFactory;
        address deployer;
        uint256 timestamp;
        uint256 blockNumber;
    }

    function run() external returns (Phase1BDeployment memory deployment) {
        console.log("=== PHASE 1B: CORE INFRASTRUCTURE ===");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Load Phase 1A data to verify file exists
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory path = string.concat(root, "/deployments/", chainIdStr, "-phase1a.json");
        string memory json = vm.readFile(path);
        
        // Parse Phase 1A addresses (we just need to verify it exists)
        address usdc;
        address weth;
        address wbtc;
        (usdc, weth, wbtc) = _parsePhase1A(json);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Step 1: Deploying TokenRegistry...");
        TokenRegistry tokenRegistryImpl = new TokenRegistry();
        console.log("[OK] TokenRegistry implementation deployed:", address(tokenRegistryImpl));
        
        UpgradeableBeacon tokenRegistryBeacon = new UpgradeableBeacon(address(tokenRegistryImpl), deployer);
        console.log("[OK] TokenRegistry beacon deployed:", address(tokenRegistryBeacon));
        
        BeaconProxy tokenRegistryProxy = new BeaconProxy(
            address(tokenRegistryBeacon),
            abi.encodeCall(TokenRegistry.initialize, (deployer))
        );
        console.log("[OK] TokenRegistry proxy deployed:", address(tokenRegistryProxy));
        
        vm.warp(block.timestamp + 10); // Longer delay between major contracts
        
        console.log("Step 2: Deploying Oracle...");
        Oracle oracleImpl = new Oracle();
        UpgradeableBeacon oracleBeacon = new UpgradeableBeacon(address(oracleImpl), deployer);
        BeaconProxy oracleProxy = new BeaconProxy(
            address(oracleBeacon),
            abi.encodeCall(Oracle.initialize, (deployer, address(tokenRegistryProxy)))
        );
        console.log("[OK] Oracle proxy deployed:", address(oracleProxy));
        
        vm.warp(block.timestamp + 10);
        
        console.log("Step 3: Deploying LendingManager...");
        LendingManager lendingManagerImpl = new LendingManager();
        UpgradeableBeacon lendingManagerBeacon = new UpgradeableBeacon(address(lendingManagerImpl), deployer);
        BeaconProxy lendingManagerProxy = new BeaconProxy(
            address(lendingManagerBeacon),
            abi.encodeCall(LendingManager.initialize, (deployer, deployer, address(oracleProxy)))
        );
        console.log("[OK] LendingManager proxy deployed:", address(lendingManagerProxy));
        
        vm.warp(block.timestamp + 10);
        
        console.log("Step 4: Deploying BalanceManager...");
        BalanceManager balanceManagerImpl = new BalanceManager();
        UpgradeableBeacon balanceManagerBeacon = new UpgradeableBeacon(address(balanceManagerImpl), deployer);
        BeaconProxy balanceManagerProxy = new BeaconProxy(
            address(balanceManagerBeacon),
            abi.encodeCall(BalanceManager.initialize, (deployer, deployer, 0, 0))
        );
        console.log("[OK] BalanceManager proxy deployed:", address(balanceManagerProxy));
        
        vm.stopBroadcast();
        
        // Save deployment data
        _saveDeployment(
            address(tokenRegistryProxy),
            address(oracleProxy),
            address(lendingManagerProxy),
            address(balanceManagerProxy),
            deployer
        );
        
        deployment = Phase1BDeployment({
            TokenRegistry: address(tokenRegistryProxy),
            Oracle: address(oracleProxy),
            LendingManager: address(lendingManagerProxy),
            BalanceManager: address(balanceManagerProxy),
            PoolManager: address(0), // Will be deployed in 1C
            ScaleXRouter: address(0), // Will be deployed in 1C
            SyntheticTokenFactory: address(0), // Will be deployed in 1C
            deployer: deployer,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
        
        console.log("=== PHASE 1B COMPLETED ===");
        return deployment;
    }
    
    function _parsePhase1A(string memory json) internal pure returns (address usdc, address weth, address wbtc) {
        // Simplified parsing - just return zero addresses since we only need to verify file exists
        return (address(0), address(0), address(0));
    }
    
    function _saveDeployment(
        address tokenRegistry,
        address oracle,
        address lendingManager,
        address balanceManager,
        address deployer
    ) internal {
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory path = string.concat(root, "/deployments/", chainIdStr, "-phase1b.json");
        
        string memory json = string.concat(
            "{\n",
            "  \"phase\": \"1b\",\n",
            "  \"TokenRegistry\": \"", vm.toString(tokenRegistry), "\",\n",
            "  \"Oracle\": \"", vm.toString(oracle), "\",\n",
            "  \"LendingManager\": \"", vm.toString(lendingManager), "\",\n",
            "  \"BalanceManager\": \"", vm.toString(balanceManager), "\",\n",
            "  \"deployer\": \"", vm.toString(deployer), "\",\n",
            "  \"timestamp\": \"", vm.toString(block.timestamp), "\",\n",
            "  \"blockNumber\": \"", vm.toString(block.number), "\"\n",
            "}"
        );
        
        vm.writeFile(path, json);
        console.log("Phase 1B deployment data written to:", path);
    }
}