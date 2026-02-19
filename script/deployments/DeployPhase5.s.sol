// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {IdentityRegistryUpgradeable} from "@scalexagents/registries/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "@scalexagents/registries/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "@scalexagents/registries/ValidationRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {LendingManager} from "@scalex/yield/LendingManager.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {PoolManager} from "@scalexcore/PoolManager.sol";
import {IOracle} from "@scalexcore/interfaces/IOracle.sol";
import {Oracle} from "@scalexcore/Oracle.sol";

/**
 * @title DeployPhase5
 * @notice Deploys and configures AI Agent Infrastructure using ERC-8004 contracts
 * @dev Uses upgradeable ERC-8004 registries with UUPS proxy pattern.
 *      PolicyFactory and AgentRouter use Beacon Proxy + Diamond Storage (ERC-7201),
 *      consistent with BalanceManager and ScaleXRouter.
 */
contract DeployPhase5 is Script {
    struct Phase5Deployment {
        address identityRegistry;
        address identityImplementation;
        address reputationRegistry;
        address reputationImplementation;
        address validationRegistry;
        address validationImplementation;
        address policyFactory;
        address policyFactoryImplementation;
        address policyFactoryBeacon;
        address agentRouter;
        address agentRouterImplementation;
        address agentRouterBeacon;
        address deployer;
        uint256 timestamp;
        uint256 blockNumber;
    }

    function run() external returns (Phase5Deployment memory deployment) {
        console.log("=== PHASE 5: AI AGENT INFRASTRUCTURE DEPLOYMENT (ERC-8004 UPGRADEABLE) ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("");

        // Load addresses from deployment file
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deploymentPath = string.concat(root, "/deployments/", chainIdStr, ".json");

        if (!vm.exists(deploymentPath)) {
            revert("Deployment file not found. Run phases 1-4 first.");
        }

        string memory json = vm.readFile(deploymentPath);
        address poolManager = _extractAddress(json, "PoolManager");
        address balanceManager = _extractAddress(json, "BalanceManager");
        address lendingManager = _extractAddress(json, "LendingManager");
        address oracle = _extractAddress(json, "Oracle");
        address IDRX = _extractAddress(json, "IDRX");
        address sxIDRX = _extractAddress(json, "sxIDRX");

        console.log("Loaded addresses:");
        console.log("  PoolManager:", poolManager);
        console.log("  BalanceManager:", balanceManager);
        console.log("  LendingManager:", lendingManager);
        console.log("  Oracle:", oracle);
        console.log("  IDRX:", IDRX);
        console.log("  sxIDRX:", sxIDRX);
        console.log("");

        // Validate addresses
        require(poolManager != address(0), "PoolManager address is zero");
        require(balanceManager != address(0), "BalanceManager address is zero");
        require(lendingManager != address(0), "LendingManager address is zero");
        require(oracle != address(0), "Oracle address is zero");
        require(IDRX != address(0), "IDRX address is zero");
        require(sxIDRX != address(0), "sxIDRX address is zero");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy IdentityRegistry (Upgradeable via UUPS + ERC1967Proxy)
        console.log("Step 1: Deploying IdentityRegistry (ERC-8004 Upgradeable)...");

        IdentityRegistryUpgradeable identityImpl = new IdentityRegistryUpgradeable();
        console.log("[OK] IdentityRegistry Implementation:", address(identityImpl));

        ERC1967Proxy identityProxy = new ERC1967Proxy(address(identityImpl), "");
        console.log("[OK] IdentityRegistry Proxy:", address(identityProxy));

        IdentityRegistryUpgradeable identityRegistry = IdentityRegistryUpgradeable(address(identityProxy));
        identityRegistry.initialize();
        console.log("[OK] IdentityRegistry initialized");
        console.log("");

        // Step 2: Deploy ReputationRegistry (Upgradeable via UUPS + ERC1967Proxy)
        console.log("Step 2: Deploying ReputationRegistry (ERC-8004 Upgradeable)...");

        ReputationRegistryUpgradeable reputationImpl = new ReputationRegistryUpgradeable();
        console.log("[OK] ReputationRegistry Implementation:", address(reputationImpl));

        ERC1967Proxy reputationProxy = new ERC1967Proxy(address(reputationImpl), "");
        console.log("[OK] ReputationRegistry Proxy:", address(reputationProxy));

        ReputationRegistryUpgradeable reputationRegistry = ReputationRegistryUpgradeable(address(reputationProxy));
        reputationRegistry.initialize(address(identityRegistry));
        console.log("[OK] ReputationRegistry initialized");
        console.log("");

        // Step 3: Deploy ValidationRegistry (Upgradeable via UUPS + ERC1967Proxy)
        console.log("Step 3: Deploying ValidationRegistry (ERC-8004 Upgradeable)...");

        ValidationRegistryUpgradeable validationImpl = new ValidationRegistryUpgradeable();
        console.log("[OK] ValidationRegistry Implementation:", address(validationImpl));

        ERC1967Proxy validationProxy = new ERC1967Proxy(address(validationImpl), "");
        console.log("[OK] ValidationRegistry Proxy:", address(validationProxy));

        ValidationRegistryUpgradeable validationRegistry = ValidationRegistryUpgradeable(address(validationProxy));
        validationRegistry.initialize(address(identityRegistry));
        console.log("[OK] ValidationRegistry initialized");
        console.log("");

        // Step 4: Deploy PolicyFactory (Beacon Proxy + Diamond Storage)
        console.log("Step 4: Deploying PolicyFactory (Beacon Proxy)...");

        PolicyFactory policyFactoryImpl = new PolicyFactory();
        console.log("[OK] PolicyFactory Implementation:", address(policyFactoryImpl));

        UpgradeableBeacon policyFactoryBeacon = new UpgradeableBeacon(address(policyFactoryImpl), deployer);
        console.log("[OK] PolicyFactory Beacon:", address(policyFactoryBeacon));

        BeaconProxy policyFactoryProxy = new BeaconProxy(
            address(policyFactoryBeacon),
            abi.encodeCall(PolicyFactory.initialize, (deployer, address(identityRegistry)))
        );
        PolicyFactory policyFactory = PolicyFactory(address(policyFactoryProxy));
        console.log("[OK] PolicyFactory Proxy:", address(policyFactory));
        console.log("");

        // Step 5: Deploy AgentRouter (Beacon Proxy + Diamond Storage)
        console.log("Step 5: Deploying AgentRouter (Beacon Proxy)...");

        AgentRouter agentRouterImpl = new AgentRouter();
        console.log("[OK] AgentRouter Implementation:", address(agentRouterImpl));

        UpgradeableBeacon agentRouterBeacon = new UpgradeableBeacon(address(agentRouterImpl), deployer);
        console.log("[OK] AgentRouter Beacon:", address(agentRouterBeacon));

        BeaconProxy agentRouterProxy = new BeaconProxy(
            address(agentRouterBeacon),
            abi.encodeCall(AgentRouter.initialize, (
                deployer,
                address(identityRegistry),
                address(reputationRegistry),
                address(validationRegistry),
                address(policyFactory),
                poolManager,
                balanceManager,
                lendingManager
            ))
        );
        AgentRouter agentRouter = AgentRouter(address(agentRouterProxy));
        console.log("[OK] AgentRouter Proxy:", address(agentRouter));
        console.log("");

        // Step 6: Authorize AgentRouter in PolicyFactory
        console.log("Step 6: Authorizing AgentRouter in PolicyFactory...");
        policyFactory.setAuthorizedRouter(address(agentRouter), true);
        console.log("[OK] AgentRouter authorized in PolicyFactory");
        console.log("");

        // Step 7: Authorize AgentRouter in BalanceManager
        console.log("Step 7: Authorizing AgentRouter in BalanceManager...");
        BalanceManager(balanceManager).addAuthorizedOperator(address(agentRouter));
        console.log("[OK] AgentRouter authorized in BalanceManager");
        console.log("");

        // Step 8: Authorize AgentRouter in all OrderBooks (via PoolManager.addAuthorizedRouterToOrderBook)
        console.log("Step 8: Authorizing AgentRouter in all OrderBooks...");
        {
            string[8] memory poolKeys = ["WETH_IDRX_Pool", "WBTC_IDRX_Pool", "GOLD_IDRX_Pool", "SILVER_IDRX_Pool", "GOOGLE_IDRX_Pool", "NVIDIA_IDRX_Pool", "MNT_IDRX_Pool", "APPLE_IDRX_Pool"];
            for (uint256 i = 0; i < poolKeys.length; i++) {
                address orderBook = _extractAddress(json, poolKeys[i]);
                if (orderBook != address(0)) {
                    PoolManager(poolManager).addAuthorizedRouterToOrderBook(orderBook, address(agentRouter));
                    console.log("[OK] AgentRouter authorized in OrderBook:", orderBook);
                }
            }
        }
        console.log("[OK] AgentRouter authorized in all OrderBooks");
        console.log("");

        // Step 9: Configure Oracle prices for IDRX and sxIDRX
        console.log("Step 9: Configuring Oracle prices for IDRX and sxIDRX...");

        try Oracle(oracle).addToken(IDRX, 0) {
            console.log("[OK] IDRX registered in Oracle");
        } catch {
            console.log("[SKIP] IDRX already registered in Oracle");
        }
        try Oracle(oracle).addToken(sxIDRX, 0) {
            console.log("[OK] sxIDRX registered in Oracle");
        } catch {
            console.log("[SKIP] sxIDRX already registered in Oracle");
        }

        // IDRX: $1 -> 1e2 = 100 (IDRX has 2 decimals, so 1e2 represents $1)
        Oracle(oracle).setPrice(IDRX, 1e2);
        console.log("[OK] Set IDRX price: 100 (raw) = $1.00");

        // sxIDRX: $1 -> 1e2 = 100 (same as IDRX, 1:1 peg)
        Oracle(oracle).setPrice(sxIDRX, 1e2);
        console.log("[OK] Set sxIDRX price: 100 (raw) = $1.00");
        console.log("");

        // Verify oracle prices
        uint256 idrxPrice = IOracle(oracle).getSpotPrice(IDRX);
        uint256 sxIdrxPrice = IOracle(oracle).getSpotPrice(sxIDRX);
        console.log("Verified oracle prices:");
        console.log("  IDRX raw price:", idrxPrice, "= $", idrxPrice / 100);
        console.log("  sxIDRX raw price:", sxIdrxPrice, "= $", sxIdrxPrice / 100);
        console.log("");

        vm.stopBroadcast();

        console.log("[SUCCESS] Phase 5 completed with official ERC-8004 contracts!");
        console.log("");
        console.log("Agent Infrastructure addresses:");
        console.log("  IdentityRegistry (Proxy):", address(identityRegistry));
        console.log("  IdentityRegistry (Impl):", address(identityImpl));
        console.log("  ReputationRegistry (Proxy):", address(reputationRegistry));
        console.log("  ReputationRegistry (Impl):", address(reputationImpl));
        console.log("  ValidationRegistry (Proxy):", address(validationRegistry));
        console.log("  ValidationRegistry (Impl):", address(validationImpl));
        console.log("  PolicyFactory (Proxy):", address(policyFactory));
        console.log("  PolicyFactory (Impl):", address(policyFactoryImpl));
        console.log("  PolicyFactory (Beacon):", address(policyFactoryBeacon));
        console.log("  AgentRouter (Proxy):", address(agentRouter));
        console.log("  AgentRouter (Impl):", address(agentRouterImpl));
        console.log("  AgentRouter (Beacon):", address(agentRouterBeacon));
        console.log("");
        console.log("Authorizations completed:");
        console.log("  [OK] AgentRouter authorized in PolicyFactory");
        console.log("  [OK] AgentRouter authorized in BalanceManager");
        console.log("  [OK] AgentRouter authorized in PoolManager");
        console.log("");
        console.log("Oracle configuration completed:");
        console.log("  [OK] IDRX price set to $1.00");
        console.log("  [OK] sxIDRX price set to $1.00");
        console.log("");
        console.log("Ready for marketplace deployment!");

        deployment = Phase5Deployment({
            identityRegistry: address(identityRegistry),
            identityImplementation: address(identityImpl),
            reputationRegistry: address(reputationRegistry),
            reputationImplementation: address(reputationImpl),
            validationRegistry: address(validationRegistry),
            validationImplementation: address(validationImpl),
            policyFactory: address(policyFactory),
            policyFactoryImplementation: address(policyFactoryImpl),
            policyFactoryBeacon: address(policyFactoryBeacon),
            agentRouter: address(agentRouter),
            agentRouterImplementation: address(agentRouterImpl),
            agentRouterBeacon: address(agentRouterBeacon),
            deployer: deployer,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(string.concat('"', key, '": "'));

        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) {
            return address(0);
        }

        uint256 addressStart = keyPos + keyBytes.length;
        bytes memory addressBytes = new bytes(42);
        for (uint256 i = 0; i < 42; i++) {
            addressBytes[i] = jsonBytes[addressStart + i];
        }

        return _bytesToAddress(addressBytes);
    }

    function _indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        if (needle.length == 0 || haystack.length < needle.length) {
            return type(uint256).max;
        }

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

        return type(uint256).max;
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
                digit = uint256(byteValue) - 87;
            } else if (byteValue >= 65 && byteValue <= 70) {
                digit = uint256(byteValue) - 55;
            } else {
                continue;
            }
            result = result * 16 + digit;
        }
        return result;
    }
}
