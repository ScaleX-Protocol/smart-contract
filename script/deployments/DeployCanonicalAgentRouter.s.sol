// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {PoolManager} from "@scalexcore/PoolManager.sol";

interface IOrderBookAdmin {
    function removeAuthorizedRouter(address _router) external;
}

/**
 * @title DeployCanonicalAgentRouter
 * @notice Fresh deployment of AgentRouter + PolicyFactory pointing to canonical ERC-8004 registries.
 * @dev Canonical registries are already deployed at vanity 0x8004... addresses on Base Sepolia.
 *      This script does NOT deploy registries - it uses the canonical ones so agents appear on 8004scan.
 *
 *      Also deauthorizes the old AgentRouter from BalanceManager and all OrderBooks.
 */
contract DeployCanonicalAgentRouter is Script {
    // Canonical ERC-8004 registries on Base Sepolia (indexed by 8004scan)
    address constant CANONICAL_IDENTITY   = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address constant CANONICAL_REPUTATION = 0x8004B663056A597Dffe9eCcC1965A193B7388713;
    address constant CANONICAL_VALIDATION = 0x8004Cb1BF31DAf7788923b405b754f57acEB4272;

    // Old AgentRouter to deauthorize
    address constant OLD_AGENT_ROUTER = 0xE9c1a6665364294194aa3B1CE89654926b338493;

    struct CanonicalDeployment {
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

    function run() external returns (CanonicalDeployment memory deployment) {
        console.log("=== DEPLOY CANONICAL AGENT ROUTER (ERC-8004 Migration) ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("");

        // Load existing addresses from deployment file
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deploymentPath = string.concat(root, "/deployments/", chainIdStr, ".json");

        require(vm.exists(deploymentPath), "Deployment file not found");

        string memory json = vm.readFile(deploymentPath);
        address poolManager = _extractAddress(json, "PoolManager");
        address balanceManager = _extractAddress(json, "BalanceManager");
        address lendingManager = _extractAddress(json, "LendingManager");

        console.log("Loaded addresses:");
        console.log("  PoolManager:", poolManager);
        console.log("  BalanceManager:", balanceManager);
        console.log("  LendingManager:", lendingManager);
        console.log("");
        console.log("Canonical registries:");
        console.log("  IdentityRegistry:", CANONICAL_IDENTITY);
        console.log("  ReputationRegistry:", CANONICAL_REPUTATION);
        console.log("  ValidationRegistry:", CANONICAL_VALIDATION);
        console.log("");

        require(poolManager != address(0), "PoolManager address is zero");
        require(balanceManager != address(0), "BalanceManager address is zero");
        require(lendingManager != address(0), "LendingManager address is zero");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy PolicyFactory (Beacon Proxy)
        console.log("Step 1: Deploying PolicyFactory...");

        PolicyFactory policyFactoryImpl = new PolicyFactory();
        console.log("[OK] PolicyFactory Implementation:", address(policyFactoryImpl));

        UpgradeableBeacon policyFactoryBeacon = new UpgradeableBeacon(address(policyFactoryImpl), deployer);
        console.log("[OK] PolicyFactory Beacon:", address(policyFactoryBeacon));

        BeaconProxy policyFactoryProxy = new BeaconProxy(
            address(policyFactoryBeacon),
            abi.encodeCall(PolicyFactory.initialize, (deployer, CANONICAL_IDENTITY))
        );
        PolicyFactory policyFactory = PolicyFactory(address(policyFactoryProxy));
        console.log("[OK] PolicyFactory Proxy:", address(policyFactory));
        console.log("");

        // Step 2: Deploy AgentRouter (Beacon Proxy)
        console.log("Step 2: Deploying AgentRouter...");

        AgentRouter agentRouterImpl = new AgentRouter();
        console.log("[OK] AgentRouter Implementation:", address(agentRouterImpl));

        UpgradeableBeacon agentRouterBeacon = new UpgradeableBeacon(address(agentRouterImpl), deployer);
        console.log("[OK] AgentRouter Beacon:", address(agentRouterBeacon));

        BeaconProxy agentRouterProxy = new BeaconProxy(
            address(agentRouterBeacon),
            abi.encodeCall(AgentRouter.initialize, (
                deployer,
                CANONICAL_IDENTITY,
                CANONICAL_REPUTATION,
                CANONICAL_VALIDATION,
                address(policyFactory),
                poolManager,
                balanceManager,
                lendingManager
            ))
        );
        AgentRouter agentRouter = AgentRouter(address(agentRouterProxy));
        console.log("[OK] AgentRouter Proxy:", address(agentRouter));
        console.log("");

        // Step 3: Authorize new AgentRouter in PolicyFactory
        console.log("Step 3: Authorizing new AgentRouter in PolicyFactory...");
        policyFactory.setAuthorizedRouter(address(agentRouter), true);
        console.log("[OK] AgentRouter authorized in PolicyFactory");
        console.log("");

        // Step 4: Authorize new AgentRouter in BalanceManager
        console.log("Step 4: Authorizing new AgentRouter in BalanceManager...");
        BalanceManager(balanceManager).addAuthorizedOperator(address(agentRouter));
        console.log("[OK] AgentRouter authorized in BalanceManager");
        console.log("");

        // Step 5: Authorize new AgentRouter in all OrderBooks
        console.log("Step 5: Authorizing new AgentRouter in all OrderBooks...");
        {
            string[8] memory poolKeys = [
                "WETH_IDRX_Pool", "WBTC_IDRX_Pool", "GOLD_IDRX_Pool", "SILVER_IDRX_Pool",
                "GOOGLE_IDRX_Pool", "NVIDIA_IDRX_Pool", "MNT_IDRX_Pool", "APPLE_IDRX_Pool"
            ];
            for (uint256 i = 0; i < poolKeys.length; i++) {
                address orderBook = _extractAddress(json, poolKeys[i]);
                if (orderBook != address(0)) {
                    PoolManager(poolManager).addAuthorizedRouterToOrderBook(orderBook, address(agentRouter));
                    console.log("[OK] Authorized in OrderBook:", orderBook);
                }
            }
        }
        console.log("");

        // Step 6: Deauthorize OLD AgentRouter from BalanceManager + OrderBooks
        console.log("Step 6: Deauthorizing old AgentRouter (", OLD_AGENT_ROUTER, ")...");
        try BalanceManager(balanceManager).setAuthorizedOperator(OLD_AGENT_ROUTER, false) {
            console.log("[OK] Old AgentRouter removed from BalanceManager");
        } catch {
            console.log("[SKIP] Old AgentRouter not in BalanceManager (already removed or never added)");
        }
        {
            string[8] memory poolKeys = [
                "WETH_IDRX_Pool", "WBTC_IDRX_Pool", "GOLD_IDRX_Pool", "SILVER_IDRX_Pool",
                "GOOGLE_IDRX_Pool", "NVIDIA_IDRX_Pool", "MNT_IDRX_Pool", "APPLE_IDRX_Pool"
            ];
            for (uint256 i = 0; i < poolKeys.length; i++) {
                address orderBook = _extractAddress(json, poolKeys[i]);
                if (orderBook != address(0)) {
                    try IOrderBookAdmin(orderBook).removeAuthorizedRouter(OLD_AGENT_ROUTER) {
                        console.log("[OK] Old router removed from OrderBook:", orderBook);
                    } catch {
                        console.log("[SKIP] Old router not in OrderBook:", orderBook);
                    }
                }
            }
        }
        console.log("");

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("");
        console.log("New addresses:");
        console.log("  PolicyFactory (Proxy):", address(policyFactory));
        console.log("  PolicyFactory (Impl):", address(policyFactoryImpl));
        console.log("  PolicyFactory (Beacon):", address(policyFactoryBeacon));
        console.log("  AgentRouter (Proxy):", address(agentRouter));
        console.log("  AgentRouter (Impl):", address(agentRouterImpl));
        console.log("  AgentRouter (Beacon):", address(agentRouterBeacon));
        console.log("");
        console.log("Canonical registries (not deployed, existing):");
        console.log("  IdentityRegistry:", CANONICAL_IDENTITY);
        console.log("  ReputationRegistry:", CANONICAL_REPUTATION);
        console.log("  ValidationRegistry:", CANONICAL_VALIDATION);
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Update deployments/<chainId>.json with new addresses");
        console.log("2. Register agents on canonical IdentityRegistry (0x8004A...)");
        console.log("3. Update metadata on R2 (agents.scalex.money)");
        console.log("4. Update indexer to watch canonical registries");
        console.log("5. Update frontend contract addresses");
        console.log("6. Verify agents appear on testnet.8004scan.io");

        deployment = CanonicalDeployment({
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

        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }

        return type(uint256).max;
    }

    function _bytesToAddress(bytes memory b) internal pure returns (address) {
        require(b.length >= 42, "Invalid address length");
        uint160 result = 0;
        for (uint256 i = 2; i < 42; i++) {
            uint8 c = uint8(b[i]);
            uint8 nibble;
            if (c >= 48 && c <= 57) {
                nibble = c - 48;
            } else if (c >= 65 && c <= 70) {
                nibble = c - 55;
            } else if (c >= 97 && c <= 102) {
                nibble = c - 87;
            } else {
                revert("Invalid hex character");
            }
            result = result * 16 + nibble;
        }
        return address(result);
    }
}
