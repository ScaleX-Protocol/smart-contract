// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/ai-agents/AgentRouter.sol";

contract DeployUpdatedAgentRouter is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Load deployment addresses
        string memory json = vm.readFile("deployments/84532.json");
        address identityRegistry = vm.parseJsonAddress(json, ".IdentityRegistry");
        address policyFactory = vm.parseJsonAddress(json, ".PolicyFactory");
        address reputationRegistry = vm.parseJsonAddress(json, ".ReputationRegistry");
        address validationRegistry = vm.parseJsonAddress(json, ".ValidationRegistry");
        address lendingManager = vm.parseJsonAddress(json, ".LendingManager");
        address poolManager = vm.parseJsonAddress(json, ".PoolManager");
        address balanceManager = vm.parseJsonAddress(json, ".BalanceManager");

        console.log("=== Deploy Updated AgentRouter ===");
        console.log("IdentityRegistry:", identityRegistry);
        console.log("PolicyFactory:", policyFactory);
        console.log("ReputationRegistry:", reputationRegistry);
        console.log("ValidationRegistry:", validationRegistry);
        console.log("LendingManager:", lendingManager);
        console.log("PoolManager:", poolManager);
        console.log("BalanceManager:", balanceManager);
        console.log("");

        vm.startBroadcast(deployerKey);

        // Deploy new implementation only (Beacon Proxy pattern)
        // Upgrade by calling: UpgradeableBeacon(agentRouterBeacon).upgradeTo(address(newRouterImpl))
        AgentRouter newRouterImpl = new AgentRouter();

        vm.stopBroadcast();

        console.log("New AgentRouter implementation deployed at:", address(newRouterImpl));
        console.log("");
        console.log("To upgrade: call UpgradeableBeacon.upgradeTo(address(newRouterImpl))");
        console.log("Proxy address and all authorizations are preserved - no re-authorization needed");
    }
}
