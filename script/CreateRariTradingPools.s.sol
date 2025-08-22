// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./DeployHelpers.s.sol";
import "../src/core/PoolManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {PoolId} from "../src/core/libraries/Pool.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";

contract CreateRariTradingPools is DeployHelpers {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Deployed trading infrastructure
        address poolManagerProxy = 0xA3B22cA94Cc3Eb8f6Bd8F4108D88d085e12d886b;
        
        // Synthetic tokens
        address gsUSDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address gsWBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;
        
        console.log("========== CREATING RARI TRADING POOLS ==========");
        console.log("PoolManager:", poolManagerProxy);
        console.log("gsUSDT:", gsUSDT);
        console.log("gsWETH:", gsWETH);  
        console.log("gsWBTC:", gsWBTC);
        
        vm.startBroadcast(deployerPrivateKey);
        
        PoolManager poolManager = PoolManager(poolManagerProxy);

        // Create gsWETH/gsUSDT pool (1 WETH = X USDT)
        console.log("Creating gsWETH/gsUSDT trading pool...");
        IOrderBook.TradingRules memory ethTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e15,      // 0.001 ETH minimum  
            minAmountMovement: 1e14,   // 0.0001 ETH increment
            minPriceMovement: 1e4,     // 0.01 USDT price increment
            minOrderSize: 10e6         // 10 USDT minimum order size
        });

        try poolManager.createPool(Currency.wrap(gsWETH), Currency.wrap(gsUSDT), ethTradingRules) returns (PoolId poolId) {
            console.log("SUCCESS: Created gsWETH/gsUSDT pool");
            console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        } catch Error(string memory reason) {
            console.log("gsWETH/gsUSDT pool creation failed:", reason);
        } catch {
            console.log("gsWETH/gsUSDT pool creation failed with unknown error");
        }

        // Create gsWBTC/gsUSDT pool (1 WBTC = X USDT)
        console.log("Creating gsWBTC/gsUSDT trading pool...");
        IOrderBook.TradingRules memory btcTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e5,       // 0.001 BTC minimum (8 decimals)
            minAmountMovement: 1e4,    // 0.0001 BTC increment
            minPriceMovement: 100e6,   // 100 USDT price increment
            minOrderSize: 10e6         // 10 USDT minimum order size
        });

        try poolManager.createPool(Currency.wrap(gsWBTC), Currency.wrap(gsUSDT), btcTradingRules) returns (PoolId poolId) {
            console.log("SUCCESS: Created gsWBTC/gsUSDT pool");
            console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        } catch Error(string memory reason) {
            console.log("gsWBTC/gsUSDT pool creation failed:", reason);
        } catch {
            console.log("gsWBTC/gsUSDT pool creation failed with unknown error");
        }

        vm.stopBroadcast();

        console.log("========== TRADING POOLS CREATED ==========");
        console.log("CLOB trading infrastructure is now ready!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Test cross-chain deposit to synthetic tokens");
        console.log("2. Test trading: place limit orders, market orders");
        console.log("3. Test cross-chain withdrawal");
    }
}