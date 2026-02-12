// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {IdentityRegistryUpgradeable} from "@scalexagents/registries/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "@scalexagents/registries/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "@scalexagents/registries/ValidationRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {LendingManager} from "@scalex/yield/LendingManager.sol";

/**
 * @title DeployPhase5Official
 * @notice Deploys and configures AI Agent Infrastructure using ERC-8004 contracts
 * @dev Uses forked ERC-8004 registries (99.9% official, minimal changes for Foundry compatibility)
 *      with UUPS proxy pattern. Changes: Added __Ownable_init() to initialize() functions.
 */
contract DeployPhase5Official is Script {
    struct Phase5Deployment {
        address identityRegistry;
        address identityImplementation;
        address reputationRegistry;
        address reputationImplementation;
        address validationRegistry;
        address validationImplementation;
        address policyFactory;
        address agentRouter;
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

        console.log("Loaded addresses:");
        console.log("  PoolManager:", poolManager);
        console.log("  BalanceManager:", balanceManager);
        console.log("  LendingManager:", lendingManager);
        console.log("");

        // Validate addresses
        require(poolManager != address(0), "PoolManager address is zero");
        require(balanceManager != address(0), "BalanceManager address is zero");
        require(lendingManager != address(0), "LendingManager address is zero");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy IdentityRegistry (Upgradeable)
        console.log("Step 1: Deploying IdentityRegistry (ERC-8004 Upgradeable)...");

        IdentityRegistryUpgradeable identityImpl = new IdentityRegistryUpgradeable();
        console.log("[OK] IdentityRegistry Implementation:", address(identityImpl));

        // Deploy proxy WITHOUT initialization (initialize manually after)
        ERC1967Proxy identityProxy = new ERC1967Proxy(
            address(identityImpl),
            ""  // Empty init data
        );
        console.log("[OK] IdentityRegistry Proxy:", address(identityProxy));

        IdentityRegistryUpgradeable identityRegistry = IdentityRegistryUpgradeable(address(identityProxy));

        // Initialize through the proxy
        identityRegistry.initialize();
        console.log("[OK] IdentityRegistry initialized");
        console.log("");

        // Step 2: Deploy ReputationRegistry (Upgradeable)
        console.log("Step 2: Deploying ReputationRegistry (ERC-8004 Upgradeable)...");

        ReputationRegistryUpgradeable reputationImpl = new ReputationRegistryUpgradeable();
        console.log("[OK] ReputationRegistry Implementation:", address(reputationImpl));

        ERC1967Proxy reputationProxy = new ERC1967Proxy(
            address(reputationImpl),
            ""  // Empty init data
        );
        console.log("[OK] ReputationRegistry Proxy:", address(reputationProxy));

        ReputationRegistryUpgradeable reputationRegistry = ReputationRegistryUpgradeable(address(reputationProxy));
        reputationRegistry.initialize(address(identityRegistry));
        console.log("[OK] ReputationRegistry initialized");
        console.log("");

        // Step 3: Deploy ValidationRegistry (Upgradeable)
        console.log("Step 3: Deploying ValidationRegistry (ERC-8004 Upgradeable)...");

        ValidationRegistryUpgradeable validationImpl = new ValidationRegistryUpgradeable();
        console.log("[OK] ValidationRegistry Implementation:", address(validationImpl));

        ERC1967Proxy validationProxy = new ERC1967Proxy(
            address(validationImpl),
            ""  // Empty init data
        );
        console.log("[OK] ValidationRegistry Proxy:", address(validationProxy));

        ValidationRegistryUpgradeable validationRegistry = ValidationRegistryUpgradeable(address(validationProxy));
        validationRegistry.initialize(address(identityRegistry));
        console.log("[OK] ValidationRegistry initialized");
        console.log("");

        // Step 4: Deploy PolicyFactory
        console.log("Step 4: Deploying PolicyFactory...");
        PolicyFactory policyFactory = new PolicyFactory(address(identityRegistry));
        console.log("[OK] PolicyFactory deployed:", address(policyFactory));
        console.log("");

        // Step 5: Deploy AgentRouter
        console.log("Step 5: Deploying AgentRouter...");
        AgentRouter agentRouter = new AgentRouter(
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry),
            address(policyFactory),
            poolManager,
            balanceManager,
            lendingManager
        );
        console.log("[OK] AgentRouter deployed:", address(agentRouter));
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

        vm.stopBroadcast();

        console.log("");

        console.log("[SUCCESS] Phase 5 completed with official ERC-8004 contracts!");
        console.log("Agent Infrastructure addresses:");
        console.log("  IdentityRegistry (Proxy):", address(identityRegistry));
        console.log("  IdentityRegistry (Impl):", address(identityImpl));
        console.log("  ReputationRegistry (Proxy):", address(reputationRegistry));
        console.log("  ReputationRegistry (Impl):", address(reputationImpl));
        console.log("  ValidationRegistry (Proxy):", address(validationRegistry));
        console.log("  ValidationRegistry (Impl):", address(validationImpl));
        console.log("  PolicyFactory:", address(policyFactory));
        console.log("  AgentRouter:", address(agentRouter));

        // Return deployment info
        deployment = Phase5Deployment({
            identityRegistry: address(identityRegistry),
            identityImplementation: address(identityImpl),
            reputationRegistry: address(reputationRegistry),
            reputationImplementation: address(reputationImpl),
            validationRegistry: address(validationRegistry),
            validationImplementation: address(validationImpl),
            policyFactory: address(policyFactory),
            agentRouter: address(agentRouter),
            deployer: deployer,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        // Find the key in the JSON
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(string.concat('"', key, '": "'));

        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) {
            return address(0);
        }

        // Extract address (42 characters: 0x + 40 hex digits)
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
        address identityRegistry,
        address identityImplementation,
        address reputationRegistry,
        address reputationImplementation,
        address validationRegistry,
        address validationImplementation,
        address policyFactory,
        address agentRouter
    ) internal {
        string memory json = vm.readFile(deploymentPath);

        // Read all existing addresses
        address tokenRegistry = _extractAddress(json, "TokenRegistry");
        address oracle = _extractAddress(json, "Oracle");
        address lendingManager = _extractAddress(json, "LendingManager");
        address balanceManager = _extractAddress(json, "BalanceManager");
        address poolManager = _extractAddress(json, "PoolManager");
        address scaleXRouter = _extractAddress(json, "ScaleXRouter");
        address syntheticTokenFactory = _extractAddress(json, "SyntheticTokenFactory");
        address autoBorrowHelper = _extractAddress(json, "AutoBorrowHelper");

        // Load quote currency config
        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        string memory syntheticQuoteSymbol = string.concat("sx", quoteSymbol);

        address quoteToken = _extractAddress(json, quoteSymbol);
        address sxQuote = _extractAddress(json, syntheticQuoteSymbol);

        address weth = _extractAddress(json, "WETH");
        address wbtc = _extractAddress(json, "WBTC");
        address gold = _extractAddress(json, "GOLD");
        address silver = _extractAddress(json, "SILVER");
        address google = _extractAddress(json, "GOOGLE");
        address nvidia = _extractAddress(json, "NVIDIA");
        address mnt = _extractAddress(json, "MNT");
        address apple = _extractAddress(json, "APPLE");
        address sxWETH = _extractAddress(json, "sxWETH");
        address sxWBTC = _extractAddress(json, "sxWBTC");
        address sxGOLD = _extractAddress(json, "sxGOLD");
        address sxSILVER = _extractAddress(json, "sxSILVER");
        address sxGOOGLE = _extractAddress(json, "sxGOOGLE");
        address sxNVIDIA = _extractAddress(json, "sxNVIDIA");
        address sxMNT = _extractAddress(json, "sxMNT");
        address sxAPPLE = _extractAddress(json, "sxAPPLE");

        // Build pool keys
        string memory wethPoolKey = string.concat("WETH_", quoteSymbol, "_Pool");
        string memory wbtcPoolKey = string.concat("WBTC_", quoteSymbol, "_Pool");
        string memory goldPoolKey = string.concat("GOLD_", quoteSymbol, "_Pool");
        string memory silverPoolKey = string.concat("SILVER_", quoteSymbol, "_Pool");
        string memory googlePoolKey = string.concat("GOOGLE_", quoteSymbol, "_Pool");
        string memory nvidiaPoolKey = string.concat("NVIDIA_", quoteSymbol, "_Pool");
        string memory mntPoolKey = string.concat("MNT_", quoteSymbol, "_Pool");
        string memory applePoolKey = string.concat("APPLE_", quoteSymbol, "_Pool");

        address wethPool = _extractAddress(json, wethPoolKey);
        address wbtcPool = _extractAddress(json, wbtcPoolKey);
        address goldPool = _extractAddress(json, goldPoolKey);
        address silverPool = _extractAddress(json, silverPoolKey);
        address googlePool = _extractAddress(json, googlePoolKey);
        address nvidiaPool = _extractAddress(json, nvidiaPoolKey);
        address mntPool = _extractAddress(json, mntPoolKey);
        address applePool = _extractAddress(json, applePoolKey);

        address deployer = _extractAddress(json, "deployer");

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
            '  "AutoBorrowHelper": "', vm.toString(autoBorrowHelper), '",\n',
            '  "IdentityRegistry": "', vm.toString(identityRegistry), '",\n',
            '  "IdentityRegistryImplementation": "', vm.toString(identityImplementation), '",\n',
            '  "ReputationRegistry": "', vm.toString(reputationRegistry), '",\n',
            '  "ReputationRegistryImplementation": "', vm.toString(reputationImplementation), '",\n',
            '  "ValidationRegistry": "', vm.toString(validationRegistry), '",\n',
            '  "ValidationRegistryImplementation": "', vm.toString(validationImplementation), '",\n',
            '  "PolicyFactory": "', vm.toString(policyFactory), '",\n',
            '  "AgentRouter": "', vm.toString(agentRouter), '",\n',
            '  "', quoteSymbol, '": "', vm.toString(quoteToken), '",\n',
            '  "WETH": "', vm.toString(weth), '",\n',
            '  "WBTC": "', vm.toString(wbtc), '",\n',
            '  "GOLD": "', vm.toString(gold), '",\n',
            '  "SILVER": "', vm.toString(silver), '",\n',
            '  "GOOGLE": "', vm.toString(google), '",\n',
            '  "NVIDIA": "', vm.toString(nvidia), '",\n',
            '  "MNT": "', vm.toString(mnt), '",\n',
            '  "APPLE": "', vm.toString(apple), '",\n',
            '  "', syntheticQuoteSymbol, '": "', vm.toString(sxQuote), '",\n',
            '  "sxWETH": "', vm.toString(sxWETH), '",\n',
            '  "sxWBTC": "', vm.toString(sxWBTC), '",\n',
            '  "sxGOLD": "', vm.toString(sxGOLD), '",\n',
            '  "sxSILVER": "', vm.toString(sxSILVER), '",\n',
            '  "sxGOOGLE": "', vm.toString(sxGOOGLE), '",\n',
            '  "sxNVIDIA": "', vm.toString(sxNVIDIA), '",\n',
            '  "sxMNT": "', vm.toString(sxMNT), '",\n',
            '  "sxAPPLE": "', vm.toString(sxAPPLE), '",\n',
            '  "', wethPoolKey, '": "', vm.toString(wethPool), '",\n',
            '  "', wbtcPoolKey, '": "', vm.toString(wbtcPool), '",\n',
            '  "', goldPoolKey, '": "', vm.toString(goldPool), '",\n',
            '  "', silverPoolKey, '": "', vm.toString(silverPool), '",\n',
            '  "', googlePoolKey, '": "', vm.toString(googlePool), '",\n',
            '  "', nvidiaPoolKey, '": "', vm.toString(nvidiaPool), '",\n',
            '  "', mntPoolKey, '": "', vm.toString(mntPool), '",\n',
            '  "', applePoolKey, '": "', vm.toString(applePool), '",\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "timestamp": "', vm.toString(block.timestamp), '",\n',
            '  "blockNumber": "', vm.toString(block.number), '",\n',
            '  "deploymentComplete": true\n',
            "}"
        );

        vm.writeFile(deploymentPath, newJson);
    }
}
