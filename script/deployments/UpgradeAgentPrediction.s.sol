// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {PricePrediction} from "@scalexcore/PricePrediction.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title UpgradeAgentPrediction
 * @notice Upgrades PolicyFactory, AgentRouter, and PricePrediction beacon implementations
 *         to add agent prediction support, then cross-authorizes AgentRouter <-> PricePrediction.
 */
contract UpgradeAgentPrediction is Script {
    function run() external {
        console.log("=== UPGRADE: Agent Prediction Integration ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);

        // Load deployment addresses
        string memory root = vm.projectRoot();
        string memory chainIdStr = vm.toString(block.chainid);
        string memory deploymentPath = string.concat(root, "/deployments/", chainIdStr, ".json");
        string memory json = vm.readFile(deploymentPath);

        address policyFactoryBeacon = _extractAddress(json, "PolicyFactoryBeacon");
        address agentRouterBeacon = _extractAddress(json, "AgentRouterBeacon");
        address pricePredictionBeacon = _extractAddress(json, "PricePredictionBeacon");
        address agentRouterProxy = _extractAddress(json, "AgentRouter");
        address pricePredictionProxy = _extractAddress(json, "PricePrediction");

        console.log("PolicyFactory Beacon:", policyFactoryBeacon);
        console.log("AgentRouter Beacon:", agentRouterBeacon);
        console.log("PricePrediction Beacon:", pricePredictionBeacon);
        console.log("AgentRouter Proxy:", agentRouterProxy);
        console.log("PricePrediction Proxy:", pricePredictionProxy);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new PolicyFactory implementation & upgrade beacon
        console.log("Step 1: Upgrading PolicyFactory...");
        PolicyFactory newPolicyFactory = new PolicyFactory();
        UpgradeableBeacon(policyFactoryBeacon).upgradeTo(address(newPolicyFactory));
        console.log("[OK] PolicyFactory upgraded to:", address(newPolicyFactory));

        // Step 2: Deploy new AgentRouter implementation & upgrade beacon
        console.log("Step 2: Upgrading AgentRouter...");
        AgentRouter newAgentRouter = new AgentRouter();
        UpgradeableBeacon(agentRouterBeacon).upgradeTo(address(newAgentRouter));
        console.log("[OK] AgentRouter upgraded to:", address(newAgentRouter));

        // Step 3: Deploy new PricePrediction implementation & upgrade beacon
        console.log("Step 3: Upgrading PricePrediction...");
        PricePrediction newPricePrediction = new PricePrediction();
        UpgradeableBeacon(pricePredictionBeacon).upgradeTo(address(newPricePrediction));
        console.log("[OK] PricePrediction upgraded to:", address(newPricePrediction));

        // Step 4: Cross-authorize AgentRouter <-> PricePrediction
        console.log("Step 4: Cross-authorizing AgentRouter <-> PricePrediction...");
        AgentRouter(agentRouterProxy).setPricePrediction(pricePredictionProxy);
        console.log("[OK] AgentRouter.setPricePrediction:", pricePredictionProxy);

        PricePrediction(pricePredictionProxy).setAuthorizedRouter(agentRouterProxy, true);
        console.log("[OK] PricePrediction.setAuthorizedRouter:", agentRouterProxy);

        vm.stopBroadcast();

        console.log("");
        console.log("[SUCCESS] Agent Prediction upgrade complete!");
        console.log("  New PolicyFactory Impl:", address(newPolicyFactory));
        console.log("  New AgentRouter Impl:", address(newAgentRouter));
        console.log("  New PricePrediction Impl:", address(newPricePrediction));
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(string.concat('"', key, '": "'));
        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) return address(0);
        uint256 addressStart = keyPos + keyBytes.length;
        bytes memory addressBytes = new bytes(42);
        for (uint256 i = 0; i < 42; i++) {
            addressBytes[i] = jsonBytes[addressStart + i];
        }
        return address(uint160(uint256(_hexToUint(addressBytes))));
    }

    function _indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        if (needle.length == 0 || haystack.length < needle.length) return type(uint256).max;
        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) { found = false; break; }
            }
            if (found) return i;
        }
        return type(uint256).max;
    }

    function _hexToUint(bytes memory data) internal pure returns (uint256) {
        uint256 result = 0;
        for (uint256 i = 0; i < data.length; i++) {
            uint8 b = uint8(data[i]);
            uint256 d;
            if (b >= 48 && b <= 57) d = uint256(b) - 48;
            else if (b >= 97 && b <= 102) d = uint256(b) - 87;
            else if (b >= 65 && b <= 70) d = uint256(b) - 55;
            else continue;
            result = result * 16 + d;
        }
        return result;
    }
}
