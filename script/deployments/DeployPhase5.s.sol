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
import {PricePrediction} from "@scalexcore/PricePrediction.sol";

/**
 * @title DeployPhase5
 * @notice Deploys and configures AI Agent Infrastructure using ERC-8004 contracts
 * @dev On Base Sepolia (84532), uses canonical ERC-8004 registries at 0x8004... addresses
 *      so agents appear on testnet.8004scan.io. On other chains, deploys fresh registries.
 *      PolicyFactory and AgentRouter use Beacon Proxy + Diamond Storage (ERC-7201),
 *      consistent with BalanceManager and ScaleXRouter.
 */
contract DeployPhase5 is Script {
    // Canonical ERC-8004 registries on Base Sepolia (indexed by 8004scan)
    address constant CANONICAL_IDENTITY   = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address constant CANONICAL_REPUTATION = 0x8004B663056A597Dffe9eCcC1965A193B7388713;
    address constant CANONICAL_VALIDATION = 0x8004Cb1BF31DAf7788923b405b754f57acEB4272;
    uint256 constant BASE_SEPOLIA_CHAIN_ID = 84532;

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

        // Steps 1-3: ERC-8004 Registries
        // On Base Sepolia, use canonical 0x8004... registries (indexed by 8004scan)
        // On other chains, deploy fresh registries
        address identityAddr;
        address identityImplAddr;
        address reputationAddr;
        address reputationImplAddr;
        address validationAddr;
        address validationImplAddr;

        if (block.chainid == BASE_SEPOLIA_CHAIN_ID) {
            console.log("Steps 1-3: Using CANONICAL ERC-8004 registries (Base Sepolia)...");
            console.log("  IdentityRegistry:", CANONICAL_IDENTITY);
            console.log("  ReputationRegistry:", CANONICAL_REPUTATION);
            console.log("  ValidationRegistry:", CANONICAL_VALIDATION);
            console.log("  Agents will appear on testnet.8004scan.io");
            console.log("");

            identityAddr = CANONICAL_IDENTITY;
            identityImplAddr = CANONICAL_IDENTITY; // canonical, no separate impl
            reputationAddr = CANONICAL_REPUTATION;
            reputationImplAddr = CANONICAL_REPUTATION;
            validationAddr = CANONICAL_VALIDATION;
            validationImplAddr = CANONICAL_VALIDATION;
        } else {
            console.log("Step 1: Deploying IdentityRegistry (ERC-8004 Upgradeable)...");

            IdentityRegistryUpgradeable identityImpl = new IdentityRegistryUpgradeable();
            console.log("[OK] IdentityRegistry Implementation:", address(identityImpl));

            ERC1967Proxy identityProxy = new ERC1967Proxy(address(identityImpl), "");
            IdentityRegistryUpgradeable(address(identityProxy)).initialize();
            console.log("[OK] IdentityRegistry Proxy:", address(identityProxy));
            console.log("");

            console.log("Step 2: Deploying ReputationRegistry (ERC-8004 Upgradeable)...");

            ReputationRegistryUpgradeable reputationImpl = new ReputationRegistryUpgradeable();
            ERC1967Proxy reputationProxy = new ERC1967Proxy(address(reputationImpl), "");
            ReputationRegistryUpgradeable(address(reputationProxy)).initialize(address(identityProxy));
            console.log("[OK] ReputationRegistry Proxy:", address(reputationProxy));
            console.log("");

            console.log("Step 3: Deploying ValidationRegistry (ERC-8004 Upgradeable)...");

            ValidationRegistryUpgradeable validationImpl = new ValidationRegistryUpgradeable();
            ERC1967Proxy validationProxy = new ERC1967Proxy(address(validationImpl), "");
            ValidationRegistryUpgradeable(address(validationProxy)).initialize(address(identityProxy));
            console.log("[OK] ValidationRegistry Proxy:", address(validationProxy));
            console.log("");

            identityAddr = address(identityProxy);
            identityImplAddr = address(identityImpl);
            reputationAddr = address(reputationProxy);
            reputationImplAddr = address(reputationImpl);
            validationAddr = address(validationProxy);
            validationImplAddr = address(validationImpl);
        }

        // Step 4: Deploy PolicyFactory (Beacon Proxy + Diamond Storage)
        console.log("Step 4: Deploying PolicyFactory (Beacon Proxy)...");

        PolicyFactory policyFactoryImpl = new PolicyFactory();
        console.log("[OK] PolicyFactory Implementation:", address(policyFactoryImpl));

        UpgradeableBeacon policyFactoryBeacon = new UpgradeableBeacon(address(policyFactoryImpl), deployer);
        console.log("[OK] PolicyFactory Beacon:", address(policyFactoryBeacon));

        BeaconProxy policyFactoryProxy = new BeaconProxy(
            address(policyFactoryBeacon),
            abi.encodeCall(PolicyFactory.initialize, (deployer, identityAddr))
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
                identityAddr,
                reputationAddr,
                validationAddr,
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

        // Step 6b: Configure PricePrediction <-> AgentRouter (if PricePrediction deployed)
        address pricePredictionAddr = _extractAddress(json, "PricePrediction");
        if (pricePredictionAddr != address(0)) {
            console.log("Step 6b: Configuring PricePrediction <-> AgentRouter...");
            agentRouter.setPricePrediction(pricePredictionAddr);
            PricePrediction(pricePredictionAddr).setAuthorizedRouter(address(agentRouter), true);
            console.log("[OK] AgentRouter.setPricePrediction:", pricePredictionAddr);
            console.log("[OK] PricePrediction.setAuthorizedRouter:", address(agentRouter));
            console.log("");
        }

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
        console.log("  IdentityRegistry (Proxy):", identityAddr);
        console.log("  IdentityRegistry (Impl):", identityImplAddr);
        console.log("  ReputationRegistry (Proxy):", reputationAddr);
        console.log("  ReputationRegistry (Impl):", reputationImplAddr);
        console.log("  ValidationRegistry (Proxy):", validationAddr);
        console.log("  ValidationRegistry (Impl):", validationImplAddr);
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

        // Write Phase 5 addresses to deployment JSON
        _updateDeploymentJson(
            deploymentPath, json,
            identityAddr, identityImplAddr,
            reputationAddr, reputationImplAddr,
            validationAddr, validationImplAddr,
            address(policyFactory), address(policyFactoryImpl), address(policyFactoryBeacon),
            address(agentRouter), address(agentRouterImpl), address(agentRouterBeacon)
        );
        console.log("[OK] Updated deployment JSON with Phase 5 addresses");

        deployment = Phase5Deployment({
            identityRegistry: identityAddr,
            identityImplementation: identityImplAddr,
            reputationRegistry: reputationAddr,
            reputationImplementation: reputationImplAddr,
            validationRegistry: validationAddr,
            validationImplementation: validationImplAddr,
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

    function _updateDeploymentJson(
        string memory deploymentPath,
        string memory json,
        address identityAddr, address identityImplAddr,
        address reputationAddr, address reputationImplAddr,
        address validationAddr, address validationImplAddr,
        address policyFactory_, address policyFactoryImpl_, address policyFactoryBeacon_,
        address agentRouter_, address agentRouterImpl_, address agentRouterBeacon_
    ) internal {
        string memory newJson = _buildJsonPart1(json);
        newJson = string.concat(newJson, _buildJsonPart2(json));
        newJson = string.concat(newJson, _buildJsonPart3(json));
        newJson = string.concat(newJson, _buildJsonPart4(json));
        newJson = string.concat(newJson, _buildJsonPhase5(
            identityAddr, identityImplAddr,
            reputationAddr, reputationImplAddr,
            validationAddr, validationImplAddr,
            policyFactory_, agentRouter_,
            policyFactoryImpl_, policyFactoryBeacon_
        ));
        newJson = string.concat(newJson, _buildJsonTail(json, agentRouterImpl_, agentRouterBeacon_));
        vm.writeFile(deploymentPath, newJson);
    }

    function _buildJsonPart1(string memory json) internal pure returns (string memory) {
        return string.concat(
            "{\n",
            '  "networkName": "localhost",\n',
            '  "TokenRegistry": "', vm.toString(_extractAddress(json, "TokenRegistry")), '",\n',
            '  "Oracle": "', vm.toString(_extractAddress(json, "Oracle")), '",\n',
            '  "LendingManager": "', vm.toString(_extractAddress(json, "LendingManager")), '",\n',
            '  "BalanceManager": "', vm.toString(_extractAddress(json, "BalanceManager")), '",\n',
            '  "PoolManager": "', vm.toString(_extractAddress(json, "PoolManager")), '",\n',
            '  "ScaleXRouter": "', vm.toString(_extractAddress(json, "ScaleXRouter")), '",\n',
            '  "SyntheticTokenFactory": "', vm.toString(_extractAddress(json, "SyntheticTokenFactory")), '",\n',
            '  "AutoBorrowHelper": "', vm.toString(_extractAddress(json, "AutoBorrowHelper")), '",\n'
        );
    }

    function _buildJsonPart2(string memory json) internal pure returns (string memory) {
        return string.concat(
            '  "IDRX": "', vm.toString(_extractAddress(json, "IDRX")), '",\n',
            '  "WETH": "', vm.toString(_extractAddress(json, "WETH")), '",\n',
            '  "WBTC": "', vm.toString(_extractAddress(json, "WBTC")), '",\n',
            '  "GOLD": "', vm.toString(_extractAddress(json, "GOLD")), '",\n',
            '  "SILVER": "', vm.toString(_extractAddress(json, "SILVER")), '",\n',
            '  "GOOGLE": "', vm.toString(_extractAddress(json, "GOOGLE")), '",\n',
            '  "NVIDIA": "', vm.toString(_extractAddress(json, "NVIDIA")), '",\n',
            '  "MNT": "', vm.toString(_extractAddress(json, "MNT")), '",\n',
            '  "APPLE": "', vm.toString(_extractAddress(json, "APPLE")), '",\n'
        );
    }

    function _buildJsonPart3(string memory json) internal pure returns (string memory) {
        return string.concat(
            '  "sxIDRX": "', vm.toString(_extractAddress(json, "sxIDRX")), '",\n',
            '  "sxWETH": "', vm.toString(_extractAddress(json, "sxWETH")), '",\n',
            '  "sxWBTC": "', vm.toString(_extractAddress(json, "sxWBTC")), '",\n',
            '  "sxGOLD": "', vm.toString(_extractAddress(json, "sxGOLD")), '",\n',
            '  "sxSILVER": "', vm.toString(_extractAddress(json, "sxSILVER")), '",\n',
            '  "sxGOOGLE": "', vm.toString(_extractAddress(json, "sxGOOGLE")), '",\n',
            '  "sxNVIDIA": "', vm.toString(_extractAddress(json, "sxNVIDIA")), '",\n',
            '  "sxMNT": "', vm.toString(_extractAddress(json, "sxMNT")), '",\n',
            '  "sxAPPLE": "', vm.toString(_extractAddress(json, "sxAPPLE")), '",\n'
        );
    }

    function _buildJsonPart4(string memory json) internal pure returns (string memory) {
        return string.concat(
            '  "WETH_IDRX_Pool": "', vm.toString(_extractAddress(json, "WETH_IDRX_Pool")), '",\n',
            '  "WBTC_IDRX_Pool": "', vm.toString(_extractAddress(json, "WBTC_IDRX_Pool")), '",\n',
            '  "GOLD_IDRX_Pool": "', vm.toString(_extractAddress(json, "GOLD_IDRX_Pool")), '",\n',
            '  "SILVER_IDRX_Pool": "', vm.toString(_extractAddress(json, "SILVER_IDRX_Pool")), '",\n',
            '  "GOOGLE_IDRX_Pool": "', vm.toString(_extractAddress(json, "GOOGLE_IDRX_Pool")), '",\n',
            '  "NVIDIA_IDRX_Pool": "', vm.toString(_extractAddress(json, "NVIDIA_IDRX_Pool")), '",\n',
            '  "MNT_IDRX_Pool": "', vm.toString(_extractAddress(json, "MNT_IDRX_Pool")), '",\n',
            '  "APPLE_IDRX_Pool": "', vm.toString(_extractAddress(json, "APPLE_IDRX_Pool")), '",\n'
        );
    }

    function _buildJsonPhase5(
        address identityAddr, address identityImplAddr,
        address reputationAddr, address reputationImplAddr,
        address validationAddr, address validationImplAddr,
        address policyFactory_, address agentRouter_,
        address policyFactoryImpl_, address policyFactoryBeacon_
    ) internal pure returns (string memory) {
        return string.concat(
            '  "IdentityRegistry": "', vm.toString(identityAddr), '",\n',
            '  "IdentityRegistryImpl": "', vm.toString(identityImplAddr), '",\n',
            '  "ReputationRegistry": "', vm.toString(reputationAddr), '",\n',
            '  "ReputationRegistryImpl": "', vm.toString(reputationImplAddr), '",\n',
            '  "ValidationRegistry": "', vm.toString(validationAddr), '",\n',
            '  "ValidationRegistryImpl": "', vm.toString(validationImplAddr), '",\n',
            '  "PolicyFactory": "', vm.toString(policyFactory_), '",\n',
            '  "AgentRouter": "', vm.toString(agentRouter_), '",\n',
            '  "PolicyFactoryImpl": "', vm.toString(policyFactoryImpl_), '",\n',
            '  "PolicyFactoryBeacon": "', vm.toString(policyFactoryBeacon_), '",\n'
        );
    }

    function _buildJsonTail(
        string memory json,
        address agentRouterImpl_,
        address agentRouterBeacon_
    ) internal view returns (string memory) {
        string memory part1 = string.concat(
            '  "AgentRouterImpl": "', vm.toString(agentRouterImpl_), '",\n',
            '  "AgentRouterBeacon": "', vm.toString(agentRouterBeacon_), '",\n',
            '  "deployer": "', vm.toString(_extractAddress(json, "deployer")), '",\n'
        );
        return string.concat(part1,
            '  "timestamp": "', vm.toString(block.timestamp), '",\n',
            '  "blockNumber": "', vm.toString(block.number), '",\n',
            '  "deploymentComplete": true\n',
            "}"
        );
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
