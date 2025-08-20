// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./DeployHelpers.s.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/GTXRouter.sol";
import "../src/core/PoolManager.sol";
import "../src/mocks/MockToken.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";
import "../src/resolvers/PoolManagerResolver.sol";

contract DebugLimitOrder is Script, DeployHelpers {
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
    string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";

    BalanceManager balanceManager;
    PoolManager poolManager;
    GTXRouter gtxRouter;
    PoolManagerResolver poolManagerResolver;
    MockWETH mockWETH;
    MockUSDC mockUSDC;

    function setUp() public {
        loadDeployments();
        loadContracts();
        poolManagerResolver = new PoolManagerResolver();
    }

    function loadContracts() private {
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
        gtxRouter = GTXRouter(deployed[GTX_ROUTER_ADDRESS].addr);
        mockWETH = MockWETH(deployed[WETH_ADDRESS].addr);
        mockUSDC = MockUSDC(deployed[USDC_ADDRESS].addr);
    }

    function run() public {
        uint256 deployerKey = getDeployerKey();
        address deployer = vm.addr(deployerKey);

        // Setup pool - same addresses from the error
        Currency baseCurrency = Currency.wrap(0x567a076BEEF17758952B05B1BC639E6cDd1A31EC);
        Currency quoteCurrency = Currency.wrap(0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6);
        
        IPoolManager.Pool memory pool = IPoolManager.Pool({
            baseCurrency: baseCurrency,
            quoteCurrency: quoteCurrency,
            orderBook: IOrderBook(0xC3dE816B9e719Bdc0493520C03279f62eE75ffb8)
        });

        console.log("Debugging limit order with parameters:");
        console.log("Base currency:", Currency.unwrap(baseCurrency));
        console.log("Quote currency:", Currency.unwrap(quoteCurrency));
        console.log("Order book:", address(pool.orderBook));
        console.log("Price:", 4000000000);
        console.log("Quantity:", 1000000000000000000);
        console.log("Side: BUY (0)");
        console.log("Deposit amount:", 4000000000);

        vm.startBroadcast(deployerKey);
        
        try gtxRouter.placeLimitOrder(
            pool,
            4000000000,  // _price
            1000000000000000000,  // _quantity  
            IOrderBook.Side.BUY,  // _side (0)
            IOrderBook.TimeInForce.GTC,  // _timeInForce (0)
            4000000000  // depositAmount
        ) returns (uint48 orderId) {
            console.log("Order placed successfully! Order ID:", orderId);
        } catch Error(string memory reason) {
            console.log("Revert reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Low level revert data:");
            console.logBytes(lowLevelData);
            
            // Try to decode the error signature
            if (lowLevelData.length >= 4) {
                bytes4 errorSig = bytes4(lowLevelData);
                console.log("Error signature:");
                console.logBytes4(errorSig);
                
                // Check if it matches known error signatures
                if (errorSig == 0x7939f424) {
                    console.log("This is the unknown error signature 0x7939f424");
                }
            }
        }
        
        vm.stopBroadcast();
    }
}
