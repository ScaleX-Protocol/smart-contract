// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./DeployHelpers.s.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/GTXRouter.sol";
import "../src/core/PoolManager.sol";
import "../src/core/resolvers/PoolManagerResolver.sol";

contract SimpleDebugLimitOrder is Script, DeployHelpers {
    string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";

    GTXRouter gtxRouter;

    function setUp() public {
        loadDeployments();
        loadContracts();
    }

    function loadContracts() private {
        gtxRouter = GTXRouter(deployed[GTX_ROUTER_ADDRESS].addr);
    }

    function run() public {
        // Setup pool - same addresses from the error
        Currency baseCurrency = Currency.wrap(0x567a076BEEF17758952B05B1BC639E6cDd1A31EC);
        Currency quoteCurrency = Currency.wrap(0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6);
        
        IPoolManager.Pool memory pool = IPoolManager.Pool({
            baseCurrency: baseCurrency,
            quoteCurrency: quoteCurrency,
            orderBook: IOrderBook(0xC3dE816B9e719Bdc0493520C03279f62eE75ffb8)
        });

        console.log("Debugging limit order with parameters:");
        console.log("GTXRouter address:", address(gtxRouter));
        console.log("Base currency:", Currency.unwrap(baseCurrency));
        console.log("Quote currency:", Currency.unwrap(quoteCurrency));
        console.log("Order book:", address(pool.orderBook));
        console.log("Price: 4000000000");
        console.log("Quantity: 1000000000000000000");
        console.log("Side: BUY (0)");
        console.log("Deposit amount: 4000000000");

        // First let's just try to call the function without broadcast to see what happens
        try gtxRouter.placeLimitOrder(
            pool,
            4000000000,  // _price
            1000000000000000000,  // _quantity  
            IOrderBook.Side.BUY,  // _side (0)
            IOrderBook.TimeInForce.GTC,  // _timeInForce (0)
            4000000000  // depositAmount
        ) returns (uint48 orderId) {
            console.log("Static call succeeded! Order ID would be:", orderId);
        } catch Error(string memory reason) {
            console.log("Revert with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Low level revert data length: %d", lowLevelData.length);
            
            if (lowLevelData.length >= 4) {
                bytes4 errorSig = bytes4(lowLevelData);
                console.log("Error signature found!");
                console.logBytes4(errorSig);
                
                if (errorSig == 0x7939f424) {
                    console.log("This matches the unknown error signature 0x7939f424!");
                    // Try to decode remaining data
                    if (lowLevelData.length > 4) {
                        bytes memory params = new bytes(lowLevelData.length - 4);
                        for (uint i = 4; i < lowLevelData.length; i++) {
                            params[i-4] = lowLevelData[i];
                        }
                        console.log("Error parameters:");
                        console.logBytes(params);
                    }
                }
            }
        }
    }
}
