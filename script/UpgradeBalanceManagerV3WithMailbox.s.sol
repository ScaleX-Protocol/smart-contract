// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeBalanceManagerV3WithMailbox is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPGRADE BALANCE MANAGER TO V3 (WITH MAILBOX FIXES) ==========");
        console.log("Deploy new implementation with mailbox reinit hell fixes");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address balanceManager = vm.parseJsonAddress(deploymentData, ".contracts.BalanceManager");
        address balanceManagerBeacon = vm.parseJsonAddress(deploymentData, ".contracts.BalanceManagerBeacon");
        address currentImpl = vm.parseJsonAddress(deploymentData, ".contracts.BalanceManagerImplV2");
        address mailbox = vm.parseJsonAddress(deploymentData, ".mailbox");
        uint32 domainId = uint32(vm.parseJsonUint(deploymentData, ".domainId"));
        
        console.log("BalanceManager (proxy):", balanceManager);
        console.log("BalanceManagerBeacon:", balanceManagerBeacon);
        console.log("Current Implementation V2:", currentImpl);
        console.log("Mailbox:", mailbox);
        console.log("Domain ID:", domainId);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== STEP 1: DEPLOY NEW V3 IMPLEMENTATION ===");
        
        // Deploy new BalanceManager V3 implementation with mailbox fixes
        console.log("Deploying BalanceManager V3 with mailbox fixes...");
        BalanceManager newImpl = new BalanceManager();
        
        console.log("New BalanceManager V3 Implementation:", address(newImpl));
        console.log("");
        
        console.log("=== STEP 2: UPGRADE BEACON TO V3 ===");
        
        UpgradeableBeacon beacon = UpgradeableBeacon(balanceManagerBeacon);
        
        console.log("Current beacon implementation:", beacon.implementation());
        console.log("Upgrading to V3...");
        
        try beacon.upgradeTo(address(newImpl)) {
            console.log("SUCCESS: Beacon upgraded to V3!");
            console.log("New implementation:", beacon.implementation());
        } catch Error(string memory reason) {
            console.log("FAILED: Beacon upgrade -", reason);
            vm.stopBroadcast();
            return;
        }
        
        console.log("");
        
        console.log("=== STEP 3: TEST NEW MAILBOX FUNCTIONS ===");
        
        BalanceManager bm = BalanceManager(balanceManager);
        
        // Test the new mailbox functions
        console.log("Testing getCrossChainConfig()...");
        try bm.getCrossChainConfig() returns (address currentMailbox, uint32 currentDomain) {
            console.log("SUCCESS: getCrossChainConfig() works!");
            console.log("Current mailbox:", currentMailbox);
            console.log("Current domain:", currentDomain);
            
            if (currentMailbox == address(0)) {
                console.log("Mailbox not initialized - initializing now...");
                
                try bm.updateCrossChainConfig(mailbox, domainId) {
                    console.log("SUCCESS: Mailbox initialized!");
                } catch Error(string memory reason) {
                    console.log("FAILED: Mailbox init -", reason);
                }
            } else {
                console.log("Mailbox already initialized");
            }
        } catch Error(string memory reason) {
            console.log("FAILED: getCrossChainConfig() -", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== V3 MAILBOX FEATURES ADDED ===");
        console.log("+ getCrossChainConfig() - Get current mailbox config");
        console.log("+ updateCrossChainConfig() - Update mailbox without reinit hell");
        console.log("+ Fixed restrictive initializeCrossChain() requirement");
        console.log("+ CrossChainInitialized event");
        console.log("+ CrossChainConfigUpdated event");
        console.log("");
        
        console.log("=== DEPLOYMENT RECORD UPDATE ===");
        console.log("Add to deployments/rari.json:");
        console.log("");
        console.log("\"BalanceManagerImplV3\":", address(newImpl), ",");
        console.log("");
        console.log("\"upgrades\": {");
        console.log("  \"balanceManagerV3\": {");
        console.log("    \"upgradedAt\":", vm.toString(block.timestamp), ",");
        console.log("    \"previousImpl\":", currentImpl, ",");
        console.log("    \"newImpl\":", address(newImpl), ",");
        console.log("    \"changes\": [");
        console.log("      \"Added getCrossChainConfig() function\",");
        console.log("      \"Added updateCrossChainConfig() function\",");
        console.log("      \"Fixed mailbox reinit hell issue\",");
        console.log("      \"Added CrossChain events\",");
        console.log("      \"Removed restrictive mailbox initialization\"");
        console.log("    ],");
        console.log("    \"status\": \"ACTIVE\"");
        console.log("  }");
        console.log("}");
        
        console.log("");
        console.log("=== WHAT'S FIXED ===");
        console.log("BEFORE V3: require(mailbox == address(0)) - caused reinit hell");
        console.log("AFTER V3:  updateCrossChainConfig() - flexible mailbox updates");
        console.log("");
        console.log("NOW YOU CAN:");
        console.log("- Upgrade BalanceManager without losing mailbox config");
        console.log("- Update mailbox address after deployment");
        console.log("- No more manual re-setup after every upgrade");
        
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Run ComprehensiveSystemCheck.s.sol to verify everything");
        console.log("2. Test cross-chain deposits from all chains");
        console.log("3. Celebrate - no more reinit hell!");
        
        console.log("========== BALANCE MANAGER V3 MAILBOX UPGRADE COMPLETE ==========");
    }
}