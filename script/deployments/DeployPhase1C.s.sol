// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {OrderBook} from "../src/core/OrderBook.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {ScaleXRouter} from "../src/core/ScaleXRouter.sol";
import {SyntheticTokenFactory} from "../src/core/SyntheticTokenFactory.sol";

contract DeployPhase1C is Script {
    struct Phase1CDeployment {
        address PoolManager;
        address ScaleXRouter;
        address SyntheticTokenFactory;
        address deployer;
        uint256 timestamp;
        uint256 blockNumber;
    }

    function run() external returns (Phase1CDeployment memory deployment) {
        console.log("=== PHASE 1C: FINAL INFRASTRUCTURE ===");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Load Phase 1B data to get contract addresses
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory phase1bPath = string.concat(root, "/deployments/", chainIdStr, "-phase1b.json");
        string memory phase1bJson = vm.readFile(phase1bPath);
        
        // Parse Phase 1B addresses
        address tokenRegistry = _extractAddress(phase1bJson, "TokenRegistry");
        address balanceManager = _extractAddress(phase1bJson, "BalanceManager");
        address lendingManager = _extractAddress(phase1bJson, "LendingManager");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Step 1: Deploying OrderBook beacon...");
        OrderBook orderBookImpl = new OrderBook();
        UpgradeableBeacon orderBookBeacon = new UpgradeableBeacon(address(orderBookImpl), deployer);
        console.log("[OK] OrderBook beacon deployed:", address(orderBookBeacon));
        
        vm.warp(block.timestamp + 10);
        
        console.log("Step 2: Deploying PoolManager...");
        PoolManager poolManagerImpl = new PoolManager();
        UpgradeableBeacon poolManagerBeacon = new UpgradeableBeacon(address(poolManagerImpl), deployer);
        BeaconProxy poolManagerProxy = new BeaconProxy(
            address(poolManagerBeacon),
            abi.encodeCall(PoolManager.initialize, (deployer, balanceManager, address(orderBookBeacon)))
        );
        console.log("[OK] PoolManager proxy deployed:", address(poolManagerProxy));
        
        vm.warp(block.timestamp + 10);
        
        console.log("Step 3: Deploying ScaleXRouter...");
        ScaleXRouter scaleXRouterImpl = new ScaleXRouter();
        UpgradeableBeacon scaleXRouterBeacon = new UpgradeableBeacon(address(scaleXRouterImpl), deployer);
        BeaconProxy scaleXRouterProxy = new BeaconProxy(
            address(scaleXRouterBeacon),
            abi.encodeCall(ScaleXRouter.initialize, (address(poolManagerProxy), balanceManager))
        );
        console.log("[OK] ScaleXRouter proxy deployed:", address(scaleXRouterProxy));
        
        vm.warp(block.timestamp + 10);
        
        console.log("Step 4: Deploying SyntheticTokenFactory...");
        SyntheticTokenFactory factoryImpl = new SyntheticTokenFactory();
        UpgradeableBeacon factoryBeacon = new UpgradeableBeacon(address(factoryImpl), deployer);
        BeaconProxy factoryProxy = new BeaconProxy(
            address(factoryBeacon),
            abi.encodeCall(SyntheticTokenFactory.initialize, (deployer, tokenRegistry, deployer))
        );
        console.log("[OK] SyntheticTokenFactory proxy deployed:", address(factoryProxy));
        
        vm.stopBroadcast();
        
        // Merge all phase data into single deployment file
        _mergeAndSaveDeployment(
            address(poolManagerProxy),
            address(scaleXRouterProxy),
            address(factoryProxy),
            deployer
        );
        
        deployment = Phase1CDeployment({
            PoolManager: address(poolManagerProxy),
            ScaleXRouter: address(scaleXRouterProxy),
            SyntheticTokenFactory: address(factoryProxy),
            deployer: deployer,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
        
        console.log("=== PHASE 1C COMPLETED ===");
        console.log("=== ALL PHASE 1 SUB-DEPLOYMENTS COMPLETED ===");
        return deployment;
    }
    
    function _mergeAndSaveDeployment(
        address poolManager,
        address scaleXRouter,
        address syntheticTokenFactory,
        address deployer
    ) internal {
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        
        // Read previous phase data
        string memory phase1aPath = string.concat(root, "/deployments/", chainIdStr, "-phase1a.json");
        string memory phase1bPath = string.concat(root, "/deployments/", chainIdStr, "-phase1b.json");
        
        string memory phase1aJson = vm.readFile(phase1aPath);
        string memory phase1bJson = vm.readFile(phase1bPath);
        
        // Extract addresses from previous phases
        address usdc = _extractAddress(phase1aJson, "USDC");
        address weth = _extractAddress(phase1aJson, "WETH");
        address wbtc = _extractAddress(phase1aJson, "WBTC");
        address tokenRegistryFrom1B = _extractAddress(phase1bJson, "TokenRegistry");
        address oracle = _extractAddress(phase1bJson, "Oracle");
        address lendingManager = _extractAddress(phase1bJson, "LendingManager");
        address balanceManager = _extractAddress(phase1bJson, "BalanceManager");
        
        // Create final merged deployment file
        string memory finalPath = string.concat(root, "/deployments/", chainIdStr, ".json");
        string memory json = string.concat(
            "{\n",
            "  \"networkName\": \"localhost\",\n",
            "  \"USDC\": \"", vm.toString(usdc), "\",\n",
            "  \"WETH\": \"", vm.toString(weth), "\",\n",
            "  \"WBTC\": \"", vm.toString(wbtc), "\",\n",
            "  \"TokenRegistry\": \"", vm.toString(tokenRegistryFrom1B), "\",\n",
            "  \"Oracle\": \"", vm.toString(oracle), "\",\n",
            "  \"LendingManager\": \"", vm.toString(lendingManager), "\",\n",
            "  \"BalanceManager\": \"", vm.toString(balanceManager), "\",\n",
            "  \"PoolManager\": \"", vm.toString(poolManager), "\",\n",
            "  \"ScaleXRouter\": \"", vm.toString(scaleXRouter), "\",\n",
            "  \"SyntheticTokenFactory\": \"", vm.toString(syntheticTokenFactory), "\",\n",
            "  \"deployer\": \"", vm.toString(deployer), "\",\n",
            "  \"timestamp\": \"", vm.toString(block.timestamp), "\",\n",
            "  \"blockNumber\": \"", vm.toString(block.number), "\",\n",
            "  \"deploymentComplete\": true\n",
            "}"
        );
        
        vm.writeFile(finalPath, json);
        console.log("Final merged deployment data written to:", finalPath);
        
        // Clean up intermediate files
        vm.removeFile(phase1aPath);
        vm.removeFile(phase1bPath);
    }
    
    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        // Simple JSON parsing to extract address value
        // Looking for pattern: "key": "0x1234567890abcdef..."
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
}