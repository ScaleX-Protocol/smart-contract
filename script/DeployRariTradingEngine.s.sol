// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/core/BalanceManager.sol";
import "../src/core/GTXRouter.sol";
import "../src/core/PoolManager.sol";
import "../src/core/OrderBook.sol";
import "./DeployHelpers.s.sol";

import {PoolManagerResolver} from "../src/core/resolvers/PoolManagerResolver.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {PoolKey} from "../src/core/libraries/Pool.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";

contract DeployRariTradingEngine is DeployHelpers {
    
    struct DeploymentConfig {
        address balanceManager;
        address owner;
        address feeReceiver;
        bool useExistingBalanceManager;
    }

    function run() public {
        loadDeployments();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Dynamic configuration - check what exists
        DeploymentConfig memory config = detectExistingDeployments(deployer);
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("========== DYNAMIC DEPLOYMENT ANALYSIS ==========");
        console.log("Existing BalanceManager:", config.balanceManager);
        console.log("Use existing:", config.useExistingBalanceManager);
        console.log("Owner:", config.owner);

        address balanceManagerBeacon;
        address balanceManagerProxy = config.balanceManager;

        // Deploy BalanceManager only if needed
        if (!config.useExistingBalanceManager) {
            console.log("========== DEPLOYING NEW BALANCE MANAGER ==========");
            balanceManagerBeacon = Upgrades.deployBeacon("BalanceManager.sol", config.owner);
            balanceManagerProxy = Upgrades.deployBeaconProxy(
                balanceManagerBeacon,
                abi.encodeCall(
                    BalanceManager.initialize,
                    (config.owner, config.feeReceiver, 1, 2) // 0.1% maker, 0.2% taker
                )
            );
            console.log("Deployed new BalanceManager:", balanceManagerProxy);
        } else {
            console.log("Using existing BalanceManager:", balanceManagerProxy);
        }

        // Always deploy trading infrastructure
        console.log("========== DEPLOYING TRADING COMPONENTS ==========");
        address poolManagerBeacon = Upgrades.deployBeacon("PoolManager.sol", config.owner);
        address routerBeacon = Upgrades.deployBeacon("GTXRouter.sol", config.owner);
        address orderBookBeacon = Upgrades.deployBeacon("OrderBook.sol", config.owner);

        console.log("PoolManager Beacon:", poolManagerBeacon);
        console.log("Router Beacon:", routerBeacon);
        console.log("OrderBook Beacon:", orderBookBeacon);

        address poolManagerResolver = address(new PoolManagerResolver());
        console.log("PoolManagerResolver:", poolManagerResolver);

        // Deploy trading proxies
        address poolManagerProxy = Upgrades.deployBeaconProxy(
            poolManagerBeacon,
            abi.encodeCall(PoolManager.initialize, (config.owner, balanceManagerProxy, orderBookBeacon))
        );
        
        address routerProxy = Upgrades.deployBeaconProxy(
            routerBeacon, 
            abi.encodeCall(GTXRouter.initialize, (poolManagerProxy, balanceManagerProxy))
        );

        console.log("PoolManager Proxy:", poolManagerProxy);
        console.log("Router Proxy:", routerProxy);

        // Configure BalanceManager authorization
        console.log("========== CONFIGURING AUTHORIZATIONS ==========");
        configureBalanceManager(balanceManagerProxy, poolManagerProxy, routerProxy, config.owner, deployer);

        // Configure PoolManager
        PoolManager poolManager = PoolManager(poolManagerProxy);
        poolManager.setRouter(routerProxy);
        console.log("Set router in PoolManager");

        // Create trading pools dynamically
        console.log("========== CREATING TRADING POOLS ==========");
        createTradingPools(poolManager);

        console.log("========== DEPLOYMENT COMPLETE ==========");
        console.log("PoolManager:", poolManagerProxy);
        console.log("Router:", routerProxy);
        console.log("OrderBook Beacon:", orderBookBeacon);

        vm.stopBroadcast();

        // Update deployment file
        updateRariDeployment(balanceManagerProxy, poolManagerProxy, routerProxy, orderBookBeacon, config.useExistingBalanceManager);
    }

    function detectExistingDeployments(address deployer) private view returns (DeploymentConfig memory) {
        // Check for existing BalanceManager on Rari
        address existingBalanceManager = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        
        // Try to call a function to verify it exists
        bool balanceManagerExists = false;
        try BalanceManager(existingBalanceManager).owner() returns (address) {
            balanceManagerExists = true;
        } catch {
            balanceManagerExists = false;
        }

        address owner = vm.envOr("OWNER_ADDRESS", deployer);
        address feeReceiver = vm.envOr("FEE_RECEIVER_ADDRESS", deployer);

        return DeploymentConfig({
            balanceManager: balanceManagerExists ? existingBalanceManager : address(0),
            owner: owner,
            feeReceiver: feeReceiver,
            useExistingBalanceManager: balanceManagerExists
        });
    }

    function configureBalanceManager(
        address balanceManagerProxy, 
        address poolManagerProxy, 
        address routerProxy,
        address owner,
        address deployer
    ) private {
        BalanceManager balanceManager = BalanceManager(balanceManagerProxy);
        
        // Check if we have owner permissions
        address currentOwner = balanceManager.owner();
        bool hasOwnerPermissions = (currentOwner == deployer) || (currentOwner == owner);
        
        if (hasOwnerPermissions) {
            balanceManager.setPoolManager(poolManagerProxy);
            console.log("Set PoolManager in BalanceManager");

            balanceManager.setAuthorizedOperator(poolManagerProxy, true);
            console.log("Authorized PoolManager as operator");

            balanceManager.setAuthorizedOperator(routerProxy, true);
            console.log("Authorized Router as operator");
        } else {
            console.log("WARNING: No owner permissions for BalanceManager");
            console.log("Current owner:", currentOwner);
            console.log("Deployer:", deployer);
            console.log("Manual configuration required");
        }
    }

    function createTradingPools(PoolManager poolManager) private {
        // Get synthetic token addresses dynamically
        address gsUSDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address gsWBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;

        // Verify tokens exist
        require(gsUSDT != address(0), "gsUSDT not found");
        require(gsWETH != address(0), "gsWETH not found");
        require(gsWBTC != address(0), "gsWBTC not found");

        // Create gsUSDT/gsWETH pool
        IOrderBook.TradingRules memory ethTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e15,      // 0.001 ETH minimum  
            minAmountMovement: 1e14,   // 0.0001 ETH increment
            minPriceMovement: 1e4,     // 0.01 USDT price increment
            minOrderSize: 10e6         // 10 USDT minimum
        });

        try poolManager.createPool(Currency.wrap(gsWETH), Currency.wrap(gsUSDT), ethTradingRules) {
            console.log("Created gsUSDT/gsWETH trading pool");
        } catch {
            console.log("Failed to create gsUSDT/gsWETH pool (may already exist)");
        }

        // Create gsUSDT/gsWBTC pool
        IOrderBook.TradingRules memory btcTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e5,       // 0.001 BTC minimum (8 decimals)
            minAmountMovement: 1e4,    // 0.0001 BTC increment
            minPriceMovement: 100e6,   // 100 USDT price increment
            minOrderSize: 10e6         // 10 USDT minimum
        });

        try poolManager.createPool(Currency.wrap(gsWBTC), Currency.wrap(gsUSDT), btcTradingRules) {
            console.log("Created gsUSDT/gsWBTC trading pool");
        } catch {
            console.log("Failed to create gsUSDT/gsWBTC pool (may already exist)");
        }
    }

    function updateRariDeployment(
        address balanceManager,
        address poolManager, 
        address router, 
        address orderBookBeacon,
        bool usedExistingBalanceManager
    ) private {
        string memory rariFile = "./deployments/rari.json";
        
        string memory tradingStatus = usedExistingBalanceManager ? "ENABLED - Using existing BalanceManager" : "ENABLED - Full deployment";
        
        string memory updatedJson = string(abi.encodePacked(
            '{\n',
            '\t"chainId": 1918988905,\n',
            '\t"contracts": {\n',
            '\t\t"BalanceManager": "', vm.toString(balanceManager), '",\n',
            '\t\t"ChainRegistry": "0x0a1Ced1539C9FB81aBdDF870588A4fEfBf461bBB",\n',
            '\t\t"SyntheticTokenFactory": "0x2594C4ca1B552ad573bcc0C4c561FAC6a87987fC",\n',
            '\t\t"TokenRegistry": "0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E",\n',
            '\t\t"PoolManager": "', vm.toString(poolManager), '",\n',
            '\t\t"Router": "', vm.toString(router), '",\n',
            '\t\t"OrderBookBeacon": "', vm.toString(orderBookBeacon), '",\n',
            '\t\t"gsUSDT": "0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68",\n',
            '\t\t"gsWBTC": "0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF",\n',
            '\t\t"gsWETH": "0xC7A1777e80982E01e07406e6C6E8B30F5968F836"\n',
            '\t},\n',
            '\t"deployedAt": "', vm.toString(block.timestamp), '",\n',
            '\t"domainId": 1918988905,\n',
            '\t"mailbox": "0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358",\n',
            '\t"network": "rari",\n',
            '\t"rpc": "${RARI_ENDPOINT}",\n',
            '\t"trading": {\n',
            '\t\t"status": "', tradingStatus, '",\n',
            '\t\t"pools": {\n',
            '\t\t\t"gsUSDT_gsWETH": {\n',
            '\t\t\t\t"base": "0xC7A1777e80982E01e07406e6C6E8B30F5968F836",\n',
            '\t\t\t\t"quote": "0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68",\n',
            '\t\t\t\t"fee": 30,\n',
            '\t\t\t\t"minOrderSize": "10000000",\n',
            '\t\t\t\t"minTradeAmount": "1000000000000000"\n',
            '\t\t\t},\n',
            '\t\t\t"gsUSDT_gsWBTC": {\n',
            '\t\t\t\t"base": "0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF",\n',
            '\t\t\t\t"quote": "0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68",\n',
            '\t\t\t\t"fee": 30,\n',
            '\t\t\t\t"minOrderSize": "10000000",\n',
            '\t\t\t\t"minTradeAmount": "100000"\n',
            '\t\t\t}\n',
            '\t\t}\n',
            '\t}\n',
            '}'
        ));

        vm.writeFile(rariFile, updatedJson);
        console.log("Updated rari.json with trading infrastructure");
    }
}