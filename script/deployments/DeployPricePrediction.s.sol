// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {PricePrediction} from "@scalexcore/PricePrediction.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";

/**
 * @title DeployPricePrediction
 * @notice Phase 6: Deploy PricePrediction contract (Beacon Proxy) and authorize it in BalanceManager.
 * @dev Requires prior phases to have run (deployments/<chainId>.json must exist).
 *
 * Required env vars:
 *   PRIVATE_KEY              — Deployer private key
 *   KEYSTONE_FORWARDER       — Chainlink CRE KeystoneForwarder address
 *
 * Optional env vars (with defaults):
 *   PROTOCOL_FEE_BPS         — Protocol fee in BPS (default: 200 = 2%)
 *   MIN_STAKE_AMOUNT         — Min stake in raw IDRX units (default: 10_000_000 = 10 IDRX, 6 decimals)
 *   MAX_MARKET_TVL           — Max TVL per market, 0 = no cap (default: 0)
 */
contract DeployPricePrediction is Script {
    struct Phase6Deployment {
        address pricePrediction;
        address pricePredictionImpl;
        address pricePredictionBeacon;
        address deployer;
        uint256 timestamp;
        uint256 blockNumber;
    }

    function run() external returns (Phase6Deployment memory deployment) {
        console.log("=== PHASE 6: PRICE PREDICTION MARKETS DEPLOYMENT ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);

        // Load existing deployment JSON
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");

        if (!vm.exists(deploymentPath)) {
            revert("Deployment file not found. Run phases 1-5 first.");
        }

        string memory json = vm.readFile(deploymentPath);

        address balanceManager = _extractAddress(json, "BalanceManager");
        address oracle = _extractAddress(json, "Oracle");
        address sxIDRX = _extractAddress(json, "sxIDRX");

        require(balanceManager != address(0), "BalanceManager address is zero");
        require(oracle != address(0), "Oracle address is zero");
        require(sxIDRX != address(0), "sxIDRX address is zero");

        console.log("Loaded addresses:");
        console.log("  BalanceManager:", balanceManager);
        console.log("  Oracle:", oracle);
        console.log("  sxIDRX (collateral):", sxIDRX);
        console.log("");

        // Read env config
        address keystoneForwarder = vm.envAddress("KEYSTONE_FORWARDER");
        uint256 protocolFeeBps = vm.envOr("PROTOCOL_FEE_BPS", uint256(200));       // 2%
        uint256 minStakeAmount = vm.envOr("MIN_STAKE_AMOUNT", uint256(10_000_000)); // 10 IDRX (6 decimals)
        uint256 maxMarketTvl = vm.envOr("MAX_MARKET_TVL", uint256(0));              // no cap

        require(keystoneForwarder != address(0), "KEYSTONE_FORWARDER env var required");
        require(protocolFeeBps <= 1000, "Protocol fee too high (max 10%)");

        console.log("Configuration:");
        console.log("  KeystoneForwarder:", keystoneForwarder);
        console.log("  Protocol fee (bps):", protocolFeeBps);
        console.log("  Min stake amount:", minStakeAmount);
        console.log("  Max market TVL (0=no cap):", maxMarketTvl);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy PricePrediction implementation
        console.log("Step 1: Deploying PricePrediction implementation...");
        PricePrediction impl = new PricePrediction();
        console.log("[OK] PricePrediction Implementation:", address(impl));

        // Step 2: Deploy UpgradeableBeacon
        console.log("Step 2: Deploying UpgradeableBeacon...");
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), deployer);
        console.log("[OK] PricePrediction Beacon:", address(beacon));

        // Step 3: Deploy BeaconProxy with initializer
        console.log("Step 3: Deploying BeaconProxy and initializing...");
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeCall(
                PricePrediction.initialize,
                (
                    deployer,
                    balanceManager,
                    oracle,
                    keystoneForwarder,
                    Currency.wrap(sxIDRX),
                    protocolFeeBps,
                    minStakeAmount
                )
            )
        );
        PricePrediction pricePrediction = PricePrediction(address(proxy));
        console.log("[OK] PricePrediction Proxy:", address(pricePrediction));

        // Optional: set max TVL if non-zero
        if (maxMarketTvl > 0) {
            pricePrediction.setMaxMarketTvl(maxMarketTvl);
            console.log("[OK] Max market TVL set:", maxMarketTvl);
        }

        // Step 4: Authorize PricePrediction in BalanceManager
        console.log("Step 4: Authorizing PricePrediction in BalanceManager...");
        BalanceManager(balanceManager).addAuthorizedOperator(address(pricePrediction));
        console.log("[OK] PricePrediction authorized as BalanceManager operator");

        vm.stopBroadcast();

        // Step 5: Update deployment JSON
        console.log("Step 5: Updating deployment JSON...");
        _updateDeploymentJson(deploymentPath, json, address(pricePrediction), address(impl), address(beacon), deployer);
        console.log("[OK] Deployment JSON updated at:", deploymentPath);

        console.log("");
        console.log("[SUCCESS] Phase 6: PricePrediction deployed and configured!");
        console.log("  PricePrediction (Proxy):", address(pricePrediction));
        console.log("  PricePrediction (Impl):", address(impl));
        console.log("  PricePrediction (Beacon):", address(beacon));
        console.log("");
        console.log("Next steps:");
        console.log("  1. Configure Chainlink CRE workflow to trigger on SettlementRequested events");
        console.log("  2. Create prediction markets using create-prediction-markets.sh");

        deployment = Phase6Deployment({
            pricePrediction: address(pricePrediction),
            pricePredictionImpl: address(impl),
            pricePredictionBeacon: address(beacon),
            deployer: deployer,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
    }

    function _updateDeploymentJson(
        string memory deploymentPath,
        string memory existingJson,
        address pricePrediction,
        address pricePredictionImpl,
        address pricePredictionBeacon,
        address deployer
    ) internal {
        // Read all existing keys to preserve them
        string memory networkName = _extractString(existingJson, "networkName");
        address tokenRegistry = _extractAddress(existingJson, "TokenRegistry");
        address oracle = _extractAddress(existingJson, "Oracle");
        address lendingManager = _extractAddress(existingJson, "LendingManager");
        address balanceManager = _extractAddress(existingJson, "BalanceManager");
        address poolManager = _extractAddress(existingJson, "PoolManager");
        address scaleXRouter = _extractAddress(existingJson, "ScaleXRouter");
        address syntheticTokenFactory = _extractAddress(existingJson, "SyntheticTokenFactory");
        address autoBorrowHelper = _extractAddress(existingJson, "AutoBorrowHelper");
        address IDRX = _extractAddress(existingJson, "IDRX");
        address WETH = _extractAddress(existingJson, "WETH");
        address WBTC = _extractAddress(existingJson, "WBTC");
        address GOLD = _extractAddress(existingJson, "GOLD");
        address SILVER = _extractAddress(existingJson, "SILVER");
        address GOOGLE = _extractAddress(existingJson, "GOOGLE");
        address NVIDIA = _extractAddress(existingJson, "NVIDIA");
        address MNT = _extractAddress(existingJson, "MNT");
        address APPLE = _extractAddress(existingJson, "APPLE");
        address sxIDRX = _extractAddress(existingJson, "sxIDRX");
        address sxWETH = _extractAddress(existingJson, "sxWETH");
        address sxWBTC = _extractAddress(existingJson, "sxWBTC");
        address sxGOLD = _extractAddress(existingJson, "sxGOLD");
        address sxSILVER = _extractAddress(existingJson, "sxSILVER");
        address sxGOOGLE = _extractAddress(existingJson, "sxGOOGLE");
        address sxNVIDIA = _extractAddress(existingJson, "sxNVIDIA");
        address sxMNT = _extractAddress(existingJson, "sxMNT");
        address sxAPPLE = _extractAddress(existingJson, "sxAPPLE");
        address wethPool = _extractAddress(existingJson, "WETH_IDRX_Pool");
        address wbtcPool = _extractAddress(existingJson, "WBTC_IDRX_Pool");
        address goldPool = _extractAddress(existingJson, "GOLD_IDRX_Pool");
        address silverPool = _extractAddress(existingJson, "SILVER_IDRX_Pool");
        address googlePool = _extractAddress(existingJson, "GOOGLE_IDRX_Pool");
        address nvidiaPool = _extractAddress(existingJson, "NVIDIA_IDRX_Pool");
        address mntPool = _extractAddress(existingJson, "MNT_IDRX_Pool");
        address applePool = _extractAddress(existingJson, "APPLE_IDRX_Pool");
        address identityRegistry = _extractAddress(existingJson, "IdentityRegistry");
        address identityRegistryImpl = _extractAddress(existingJson, "IdentityRegistryImpl");
        address reputationRegistry = _extractAddress(existingJson, "ReputationRegistry");
        address reputationRegistryImpl = _extractAddress(existingJson, "ReputationRegistryImpl");
        address validationRegistry = _extractAddress(existingJson, "ValidationRegistry");
        address validationRegistryImpl = _extractAddress(existingJson, "ValidationRegistryImpl");
        address policyFactory = _extractAddress(existingJson, "PolicyFactory");
        address agentRouter = _extractAddress(existingJson, "AgentRouter");
        address policyFactoryImpl = _extractAddress(existingJson, "PolicyFactoryImpl");
        address policyFactoryBeacon = _extractAddress(existingJson, "PolicyFactoryBeacon");
        address agentRouterImpl = _extractAddress(existingJson, "AgentRouterImpl");
        address agentRouterBeacon = _extractAddress(existingJson, "AgentRouterBeacon");

        string memory newJson = string.concat(
            "{\n",
            '  "networkName": "', networkName, '",\n',
            '  "TokenRegistry": "', vm.toString(tokenRegistry), '",\n',
            '  "Oracle": "', vm.toString(oracle), '",\n',
            '  "LendingManager": "', vm.toString(lendingManager), '",\n',
            '  "BalanceManager": "', vm.toString(balanceManager), '",\n',
            '  "PoolManager": "', vm.toString(poolManager), '",\n',
            '  "ScaleXRouter": "', vm.toString(scaleXRouter), '",\n',
            '  "SyntheticTokenFactory": "', vm.toString(syntheticTokenFactory), '",\n',
            '  "AutoBorrowHelper": "', vm.toString(autoBorrowHelper), '",\n',
            '  "IDRX": "', vm.toString(IDRX), '",\n',
            '  "WETH": "', vm.toString(WETH), '",\n',
            '  "WBTC": "', vm.toString(WBTC), '",\n',
            '  "GOLD": "', vm.toString(GOLD), '",\n',
            '  "SILVER": "', vm.toString(SILVER), '",\n',
            '  "GOOGLE": "', vm.toString(GOOGLE), '",\n',
            '  "NVIDIA": "', vm.toString(NVIDIA), '",\n',
            '  "MNT": "', vm.toString(MNT), '",\n',
            '  "APPLE": "', vm.toString(APPLE), '",\n',
            '  "sxIDRX": "', vm.toString(sxIDRX), '",\n',
            '  "sxWETH": "', vm.toString(sxWETH), '",\n',
            '  "sxWBTC": "', vm.toString(sxWBTC), '",\n',
            '  "sxGOLD": "', vm.toString(sxGOLD), '",\n',
            '  "sxSILVER": "', vm.toString(sxSILVER), '",\n',
            '  "sxGOOGLE": "', vm.toString(sxGOOGLE), '",\n',
            '  "sxNVIDIA": "', vm.toString(sxNVIDIA), '",\n',
            '  "sxMNT": "', vm.toString(sxMNT), '",\n',
            '  "sxAPPLE": "', vm.toString(sxAPPLE), '",\n',
            '  "WETH_IDRX_Pool": "', vm.toString(wethPool), '",\n',
            '  "WBTC_IDRX_Pool": "', vm.toString(wbtcPool), '",\n',
            '  "GOLD_IDRX_Pool": "', vm.toString(goldPool), '",\n',
            '  "SILVER_IDRX_Pool": "', vm.toString(silverPool), '",\n',
            '  "GOOGLE_IDRX_Pool": "', vm.toString(googlePool), '",\n',
            '  "NVIDIA_IDRX_Pool": "', vm.toString(nvidiaPool), '",\n',
            '  "MNT_IDRX_Pool": "', vm.toString(mntPool), '",\n',
            '  "APPLE_IDRX_Pool": "', vm.toString(applePool), '",\n',
            '  "IdentityRegistry": "', vm.toString(identityRegistry), '",\n',
            '  "IdentityRegistryImpl": "', vm.toString(identityRegistryImpl), '",\n',
            '  "ReputationRegistry": "', vm.toString(reputationRegistry), '",\n',
            '  "ReputationRegistryImpl": "', vm.toString(reputationRegistryImpl), '",\n',
            '  "ValidationRegistry": "', vm.toString(validationRegistry), '",\n',
            '  "ValidationRegistryImpl": "', vm.toString(validationRegistryImpl), '",\n',
            '  "PolicyFactory": "', vm.toString(policyFactory), '",\n',
            '  "AgentRouter": "', vm.toString(agentRouter), '",\n',
            '  "PolicyFactoryImpl": "', vm.toString(policyFactoryImpl), '",\n',
            '  "PolicyFactoryBeacon": "', vm.toString(policyFactoryBeacon), '",\n',
            '  "AgentRouterImpl": "', vm.toString(agentRouterImpl), '",\n',
            '  "AgentRouterBeacon": "', vm.toString(agentRouterBeacon), '",\n',
            '  "PricePrediction": "', vm.toString(pricePrediction), '",\n',
            '  "PricePredictionImpl": "', vm.toString(pricePredictionImpl), '",\n',
            '  "PricePredictionBeacon": "', vm.toString(pricePredictionBeacon), '",\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "timestamp": "', vm.toString(block.timestamp), '",\n',
            '  "blockNumber": "', vm.toString(block.number), '",\n',
            '  "deploymentComplete": true\n',
            "}"
        );

        vm.writeFile(deploymentPath, newJson);
    }

    // =============================================================
    //                    JSON HELPERS
    // =============================================================

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

    function _extractString(string memory json, string memory key) internal pure returns (string memory) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(string.concat('"', key, '": "'));

        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) {
            return "";
        }

        uint256 valueStart = keyPos + keyBytes.length;
        uint256 valueEnd = valueStart;
        while (valueEnd < jsonBytes.length && jsonBytes[valueEnd] != '"') {
            valueEnd++;
        }

        bytes memory valueBytes = new bytes(valueEnd - valueStart);
        for (uint256 i = 0; i < valueEnd - valueStart; i++) {
            valueBytes[i] = jsonBytes[valueStart + i];
        }

        return string(valueBytes);
    }

    function _indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        if (needle.length == 0 || haystack.length < needle.length) {
            return type(uint256).max;
        }

        uint256 needleLength = needle.length;
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
