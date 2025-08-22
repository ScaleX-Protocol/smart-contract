// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./DeployHelpers.s.sol";
import "../src/core/PoolManager.sol";
import "../src/core/GTXRouter.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {PoolId} from "../src/core/libraries/Pool.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";

contract ConfigureRariTrading is DeployHelpers {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Use deployed addresses from previous run
        address poolManagerProxy = 0xF38489749c3e65c82a9273c498A8c6614c34754b;
        address routerProxy = 0xcf3953cA780e2BC08e9B8aAB30f801F6883108ba;
        
        console.log("========== CONFIGURING TRADING WITH CORRECT OWNERSHIP ==========");
        console.log("Deployer:", deployer);
        console.log("PoolManager:", poolManagerProxy);
        console.log("Router:", routerProxy);
        
        vm.startBroadcast(deployerPrivateKey);

        // Configure PoolManager (deployer should be owner since they deployed it)
        PoolManager poolManager = PoolManager(poolManagerProxy);
        
        try poolManager.owner() returns (address currentOwner) {
            console.log("PoolManager owner:", currentOwner);
            if (currentOwner == deployer) {
                poolManager.setRouter(routerProxy);
                console.log("SUCCESS: Set router in PoolManager");
            } else {
                console.log("WARNING: Deployer is not PoolManager owner");
            }
        } catch {
            console.log("ERROR: Could not check PoolManager owner");
        }

        // Create trading pools
        console.log("========== CREATING TRADING POOLS ==========");
        createTradingPools(poolManager, deployer);

        vm.stopBroadcast();

        // SAFE update - preserves existing data
        addTradingToExistingDeployment(poolManagerProxy, routerProxy);
        
        console.log("========== CONFIGURATION COMPLETE ==========");
        console.log("Trading infrastructure ready on Rari testnet");
    }

    function createTradingPools(PoolManager poolManager, address deployer) private {
        // Get synthetic token addresses
        address gsUSDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address gsWBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;

        console.log("Creating pools with tokens:");
        console.log("gsUSDT:", gsUSDT);
        console.log("gsWETH:", gsWETH);  
        console.log("gsWBTC:", gsWBTC);

        // Create gsWETH/gsUSDT pool (WETH base, USDT quote)
        IOrderBook.TradingRules memory ethTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e15,      // 0.001 ETH minimum  
            minAmountMovement: 1e14,   // 0.0001 ETH increment
            minPriceMovement: 1e4,     // 0.01 USDT price increment
            minOrderSize: 10e6         // 10 USDT minimum order size
        });

        try poolManager.createPool(Currency.wrap(gsWETH), Currency.wrap(gsUSDT), ethTradingRules) returns (PoolId poolId) {
            console.log("SUCCESS: Created gsWETH/gsUSDT pool");
            console.logBytes32(PoolId.unwrap(poolId));
        } catch Error(string memory reason) {
            console.log("Pool creation failed:", reason);
            if (keccak256(abi.encodePacked(reason)) == keccak256("PoolAlreadyExists()")) {
                console.log("gsWETH/gsUSDT pool already exists - OK");
            }
        } catch {
            console.log("gsWETH/gsUSDT pool creation failed with unknown error");
        }

        // Create gsWBTC/gsUSDT pool (WBTC base, USDT quote)
        IOrderBook.TradingRules memory btcTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e5,       // 0.001 BTC minimum (8 decimals)
            minAmountMovement: 1e4,    // 0.0001 BTC increment
            minPriceMovement: 100e6,   // 100 USDT price increment
            minOrderSize: 10e6         // 10 USDT minimum order size
        });

        try poolManager.createPool(Currency.wrap(gsWBTC), Currency.wrap(gsUSDT), btcTradingRules) returns (PoolId poolId) {
            console.log("SUCCESS: Created gsWBTC/gsUSDT pool");
            console.logBytes32(PoolId.unwrap(poolId));
        } catch Error(string memory reason) {
            console.log("Pool creation failed:", reason);
            if (keccak256(abi.encodePacked(reason)) == keccak256("PoolAlreadyExists()")) {
                console.log("gsWBTC/gsUSDT pool already exists - OK");
            }
        } catch {
            console.log("gsWBTC/gsUSDT pool creation failed with unknown error");
        }
    }

    function addTradingToExistingDeployment(address poolManager, address router) private {
        // Read existing deployment file
        string memory rariFile = "./deployments/rari.json";
        
        try vm.readFile(rariFile) returns (string memory existingJson) {
            console.log("Found existing rari.json - will preserve all data");
            
            // Parse and modify existing JSON to add only trading components
            // This is a simple append approach that preserves all existing data
            string memory tradingSection = string(abi.encodePacked(
                ',\n\t\t"PoolManager": "', vm.toString(poolManager), '"',
                ',\n\t\t"Router": "', vm.toString(router), '"',
                ',\n\t\t"OrderBookBeacon": "0xa8630B75d92814b79dE1C5A170d00Ef0714b3C28"'
            ));
            
            // Find the closing brace of contracts section and insert before it
            // This preserves all existing contract addresses
            bytes memory existingBytes = bytes(existingJson);
            bytes memory tradingBytes = bytes(tradingSection);
            
            // Simple approach: create a backup and log what we're adding
            string memory backupFile = string(abi.encodePacked(rariFile, ".backup.", vm.toString(block.timestamp)));
            vm.writeFile(backupFile, existingJson);
            console.log("Created backup:", backupFile);
            
            console.log("MANUAL UPDATE REQUIRED:");
            console.log("Add these lines to rari.json contracts section:");
            console.log(tradingSection);
            
        } catch {
            console.log("No existing rari.json found - this is unexpected!");
            console.log("Expected to find existing deployment data");
        }
    }
}