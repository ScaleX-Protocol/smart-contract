// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/interfaces/IPoolManager.sol";
import "../src/core/interfaces/IOrderBook.sol";
import "../src/core/libraries/Currency.sol";
import "../src/core/libraries/Pool.sol";

contract CreatePools is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== CREATING NEW POOLS ==========");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        // Detect network and read deployments
        string memory networkFile;
        bool hasDeployments = false;
        
        if (block.chainid == 1918988905) {
            // Rari
            networkFile = "deployments/rari.json";
            hasDeployments = true;
            console.log("Detected: Rari Testnet");
        } else {
            console.log("This script is designed for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData;
        try vm.readFile(networkFile) returns (string memory data) {
            deploymentData = data;
            console.log("Reading deployment data from:", networkFile);
        } catch {
            console.log("ERROR: Could not read deployment file:", networkFile);
            return;
        }
        
        // Get contract addresses
        address poolManager;
        address gsUSDT;
        address gsWBTC;
        address gsWETH;
        
        try vm.parseJsonAddress(deploymentData, ".contracts.PoolManager") returns (address addr) {
            poolManager = addr;
        } catch {
            console.log("ERROR: Could not find PoolManager");
            return;
        }
        
        try vm.parseJsonAddress(deploymentData, ".contracts.gsUSDT") returns (address addr) {
            gsUSDT = addr;
        } catch {
            console.log("ERROR: Could not find gsUSDT");
            return;
        }
        
        try vm.parseJsonAddress(deploymentData, ".contracts.gsWBTC") returns (address addr) {
            gsWBTC = addr;
        } catch {
            console.log("ERROR: Could not find gsWBTC");
            return;
        }
        
        try vm.parseJsonAddress(deploymentData, ".contracts.gsWETH") returns (address addr) {
            gsWETH = addr;
        } catch {
            console.log("ERROR: Could not find gsWETH");
            return;
        }
        
        console.log("");
        console.log("=== CONTRACT ADDRESSES ===");
        console.log("PoolManager:", poolManager);
        console.log("gsUSDT:", gsUSDT);
        console.log("gsWBTC:", gsWBTC);
        console.log("gsWETH:", gsWETH);
        console.log("");
        
        IPoolManager pm = IPoolManager(poolManager);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Create Pool 1: gsWETH / gsUSDT
        console.log("=== CREATING POOL 1: gsWETH / gsUSDT ===");
        
        // Default trading rules - you can customize these
        IOrderBook.TradingRules memory tradingRules1 = IOrderBook.TradingRules({
            minTradeAmount: 1000000000000000, // 0.001 ETH in wei
            minAmountMovement: 1000000000000000, // 0.001 ETH minimum amount step
            minPriceMovement: 10000, // 0.01 USDT price tick
            minOrderSize: 10000000 // 10 USDT in 6 decimals
        });
        
        PoolId pool1Id;
        try pm.createPool(
            Currency.wrap(gsWETH),
            Currency.wrap(gsUSDT),
            tradingRules1
        ) returns (PoolId poolId) {
            pool1Id = poolId;
            console.log("SUCCESS: gsWETH/gsUSDT pool created");
            console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        } catch Error(string memory reason) {
            console.log("FAILED to create gsWETH/gsUSDT pool:", reason);
        } catch {
            console.log("FAILED to create gsWETH/gsUSDT pool: Unknown error");
        }
        
        // Create Pool 2: gsWBTC / gsUSDT  
        console.log("");
        console.log("=== CREATING POOL 2: gsWBTC / gsUSDT ===");
        
        // Different trading rules for BTC (higher minimum amounts)
        IOrderBook.TradingRules memory tradingRules2 = IOrderBook.TradingRules({
            minTradeAmount: 100000, // 0.001 BTC in 8 decimals
            minAmountMovement: 100000, // 0.001 BTC minimum amount step
            minPriceMovement: 100000000, // 1 USDT price tick for BTC
            minOrderSize: 10000000 // 10 USDT in 6 decimals
        });
        
        PoolId pool2Id;
        try pm.createPool(
            Currency.wrap(gsWBTC),
            Currency.wrap(gsUSDT),
            tradingRules2
        ) returns (PoolId poolId) {
            pool2Id = poolId;
            console.log("SUCCESS: gsWBTC/gsUSDT pool created");
            console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        } catch Error(string memory reason) {
            console.log("FAILED to create gsWBTC/gsUSDT pool:", reason);
        } catch {
            console.log("FAILED to create gsWBTC/gsUSDT pool: Unknown error");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== POOL CREATION SUMMARY ===");
        if (PoolId.unwrap(pool1Id) != bytes32(0)) {
            console.log("gsWETH/gsUSDT Pool ID:", vm.toString(PoolId.unwrap(pool1Id)));
        } else {
            console.log("gsWETH/gsUSDT: FAILED TO CREATE");
        }
        
        if (PoolId.unwrap(pool2Id) != bytes32(0)) {
            console.log("gsWBTC/gsUSDT Pool ID:", vm.toString(PoolId.unwrap(pool2Id)));
        } else {
            console.log("gsWBTC/gsUSDT: FAILED TO CREATE");
        }
        
        console.log("");
        console.log("=== VERIFICATION ===");
        
        // Verify pools exist
        if (PoolId.unwrap(pool1Id) != bytes32(0)) {
            console.log("Verifying gsWETH/gsUSDT pool...");
            PoolKey memory key1 = PoolKey({
                baseCurrency: Currency.wrap(gsWETH),
                quoteCurrency: Currency.wrap(gsUSDT)
            });
            try pm.getPool(key1) returns (IPoolManager.Pool memory retrievedPool) {
                console.log("  Base currency:", Currency.unwrap(retrievedPool.baseCurrency));
                console.log("  Quote currency:", Currency.unwrap(retrievedPool.quoteCurrency));
                console.log("  OrderBook:", address(retrievedPool.orderBook));
                console.log("  Status: VERIFIED");
            } catch {
                console.log("  Status: FAILED TO VERIFY");
            }
        }
        
        if (PoolId.unwrap(pool2Id) != bytes32(0)) {
            console.log("Verifying gsWBTC/gsUSDT pool...");
            PoolKey memory key2 = PoolKey({
                baseCurrency: Currency.wrap(gsWBTC),
                quoteCurrency: Currency.wrap(gsUSDT)
            });
            try pm.getPool(key2) returns (IPoolManager.Pool memory retrievedPool) {
                console.log("  Base currency:", Currency.unwrap(retrievedPool.baseCurrency));
                console.log("  Quote currency:", Currency.unwrap(retrievedPool.quoteCurrency));
                console.log("  OrderBook:", address(retrievedPool.orderBook));
                console.log("  Status: VERIFIED");
            } catch {
                console.log("  Status: FAILED TO VERIFY");
            }
        }
        
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Update trading config in rari.json with new pool IDs");
        console.log("2. Configure pool parameters (minTradeAmount, minOrderSize, etc.)");
        console.log("3. Test deposits and trading");
        console.log("4. Add pools to frontend configuration");
        
        console.log("========== POOL CREATION COMPLETE ==========");
    }
}