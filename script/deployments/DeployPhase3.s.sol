// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {IPoolManager} from "../src/core/interfaces/IPoolManager.sol";
import {ScaleXRouter} from "../src/core/ScaleXRouter.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";
import {PoolKey, PoolId} from "../src/core/libraries/Pool.sol";

contract DeployPhase3 is Script {
    struct Phase3Deployment {
        address WETH_USDC_Pool;
        address WBTC_USDC_Pool;
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
        
        string memory json = vm.readFile(deploymentPath);
        address poolManager = _extractAddress(json, "PoolManager");
        address scaleXRouter = _extractAddress(json, "ScaleXRouter");
        address gsUSDC = _extractAddress(json, "gsUSDC");
        address gsWETH = _extractAddress(json, "gsWETH");
        address gsWBTC = _extractAddress(json, "gsWBTC");
        
        console.log("Loaded addresses:");
        console.log("  PoolManager:", poolManager);
        console.log("  ScaleXRouter:", scaleXRouter);
        console.log("  gsUSDC:", gsUSDC);
        console.log("  gsWETH:", gsWETH);
        console.log("  gsWBTC:", gsWBTC);
        
        // Validate addresses
        require(poolManager != address(0), "PoolManager address is zero");
        require(gsUSDC != address(0), "gsUSDC address is zero");
        require(gsWETH != address(0), "gsWETH address is zero");
        require(gsWBTC != address(0), "gsWBTC address is zero");
        
        // Check if pools already exist before broadcasting
        PoolManager pm = PoolManager(poolManager);
        console.log("Step 1: Checking existing pools...");
        
        // Check WETH/USDC pool
        IPoolManager.Pool memory wethUsdcPool = pm.getPool(
            pm.createPoolKey(Currency.wrap(gsWETH), Currency.wrap(gsUSDC))
        );
        address wethUsdcOrderBook = address(wethUsdcPool.orderBook);
        
        // Check WBTC/USDC pool
        IPoolManager.Pool memory wbtcUsdcPool = pm.getPool(
            pm.createPoolKey(Currency.wrap(gsWBTC), Currency.wrap(gsUSDC))
        );
        address wbtcUsdcOrderBook = address(wbtcUsdcPool.orderBook);
        
        bool wethUsdcExists = wethUsdcOrderBook != address(0);
        bool wbtcUsdcExists = wbtcUsdcOrderBook != address(0);
        
        if (wethUsdcExists) {
            console.log("[OK] WETH/USDC pool already exists:", wethUsdcOrderBook);
        } else {
            console.log("WETH/USDC pool needs to be created");
        }
        
        if (wbtcUsdcExists) {
            console.log("[OK] WBTC/USDC pool already exists:", wbtcUsdcOrderBook);
        } else {
            console.log("WBTC/USDC pool needs to be created");
        }
        
        // Only broadcast if we need to create pools
        if (!wethUsdcExists || !wbtcUsdcExists) {
            console.log("Starting broadcast to create missing pools...");
            vm.startBroadcast(deployerPrivateKey);
            
            // Step 2: Create trading rules
            IOrderBook.TradingRules memory tradingRules = IOrderBook.TradingRules({
                minTradeAmount: 1000000,    // 1 USDC minimum
                minAmountMovement: 1000000,  // 1 USDC minimum price movement
                minPriceMovement: 1000000,   // 1 USDC minimum price movement  
                minOrderSize: 5000000        // 5 USDC minimum order size
            });
            
            if (!wethUsdcExists) {
                console.log("Creating new WETH/USDC pool...");
                PoolId wethUsdcPoolId = pm.createPool(
                    Currency.wrap(gsWETH),      // base currency (WETH)
                    Currency.wrap(gsUSDC),      // quote currency (USDC)
                    tradingRules
                );
                
                // Get the OrderBook address from the newly created pool
                wethUsdcPool = pm.getPool(
                    pm.createPoolKey(Currency.wrap(gsWETH), Currency.wrap(gsUSDC))
                );
                wethUsdcOrderBook = address(wethUsdcPool.orderBook);
                
                console.log("[OK] WETH/USDC pool created with OrderBook:", wethUsdcOrderBook);
            }
            
            if (!wbtcUsdcExists) {
                console.log("Creating new WBTC/USDC pool...");
                PoolId wbtcUsdcPoolId = pm.createPool(
                    Currency.wrap(gsWBTC),      // base currency (WBTC)
                    Currency.wrap(gsUSDC),      // quote currency (USDC)
                    tradingRules
                );
                
                // Get the OrderBook address from the newly created pool
                wbtcUsdcPool = pm.getPool(
                    pm.createPoolKey(Currency.wrap(gsWBTC), Currency.wrap(gsUSDC))
                );
                wbtcUsdcOrderBook = address(wbtcUsdcPool.orderBook);
                
                console.log("[OK] WBTC/USDC pool created with OrderBook:", wbtcUsdcOrderBook);
            }
            
            vm.stopBroadcast();
        }
        
        // Update deployment file with pool addresses
        _updateDeploymentFile(
            deploymentPath,
            wethUsdcOrderBook,
            wbtcUsdcOrderBook,
            deployer
        );
        
        deployment = Phase3Deployment({
            WETH_USDC_Pool: wethUsdcOrderBook,
            WBTC_USDC_Pool: wbtcUsdcOrderBook,
            deployer: deployer,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
        
        console.log("=== PHASE 3 COMPLETED ===");
        console.log("Trading pools created successfully!");
        
        return deployment;
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
        address wethUsdcPool,
        address wbtcUsdcPool,
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
        address usdc = _extractAddress(json, "USDC");
        address weth = _extractAddress(json, "WETH");
        address wbtc = _extractAddress(json, "WBTC");
        address gsUSDC = _extractAddress(json, "gsUSDC");
        address gsWETH = _extractAddress(json, "gsWETH");
        address gsWBTC = _extractAddress(json, "gsWBTC");
        
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
            '  "USDC": "', vm.toString(usdc), '",\n',
            '  "WETH": "', vm.toString(weth), '",\n',
            '  "WBTC": "', vm.toString(wbtc), '",\n',
            '  "gsUSDC": "', vm.toString(gsUSDC), '",\n',
            '  "gsWETH": "', vm.toString(gsWETH), '",\n',
            '  "gsWBTC": "', vm.toString(gsWBTC), '",\n',
            '  "WETH_USDC_Pool": "', vm.toString(wethUsdcPool), '",\n',
            '  "WBTC_USDC_Pool": "', vm.toString(wbtcUsdcPool), '",\n',
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