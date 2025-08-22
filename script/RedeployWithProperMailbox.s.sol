// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/ChainBalanceManager.sol";

contract RedeployWithProperMailbox is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== REDEPLOYING WITH PROPER MAILBOX ==========");
        console.log("Deployer:", deployer);
        
        // Step 1: Deploy new BalanceManager with mailbox initialization
        console.log("=== STEP 1: Deploy new BalanceManager on Rari ===");
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address rariMailbox = 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358;
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new BalanceManager with proper initialization including mailbox
        BalanceManager newBalanceManager = new BalanceManager();
        console.log("New BalanceManager implementation deployed:", address(newBalanceManager));
        
        // For now, let's just update the existing BalanceManager to include mailbox setup
        BalanceManager existingBM = BalanceManager(0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5);
        
        try existingBM.setMailbox(rariMailbox) {
            console.log("SUCCESS: Set mailbox on existing BalanceManager");
        } catch Error(string memory reason) {
            console.log("Failed to set mailbox:", reason);
        }
        
        vm.stopBroadcast();
        
        // Step 2: Deploy new ChainBalanceManager with proper destination
        console.log("=== STEP 2: Deploy new ChainBalanceManager on Appchain ===");
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address appchainMailbox = 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1;
        uint32 rariDomain = 1918988905;
        address rariBalanceManager = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new ChainBalanceManager with proper configuration
        ChainBalanceManager newCBM = new ChainBalanceManager();
        console.log("New ChainBalanceManager implementation deployed:", address(newCBM));
        
        // For testing, let's create a completely new ChainBalanceManager
        // Deploy beacon
        UpgradeableBeacon cbmBeacon = new UpgradeableBeacon(address(newCBM), deployer);
        console.log("ChainBalanceManager beacon deployed:", address(cbmBeacon));
        
        // Deploy proxy
        BeaconProxy cbmProxy = new BeaconProxy(address(cbmBeacon), 
            abi.encodeWithSelector(ChainBalanceManager.initialize.selector,
                deployer,
                appchainMailbox, 
                rariDomain,
                rariBalanceManager
            )
        );
        console.log("ChainBalanceManager proxy deployed:", address(cbmProxy));
        
        ChainBalanceManager cbm = ChainBalanceManager(address(cbmProxy));
        
        // Verify configuration
        (address mailbox, uint32 localDomain) = cbm.getMailboxConfig();
        (uint32 destDomain, address destBalanceManager) = cbm.getDestinationConfig();
        
        console.log("Mailbox:", mailbox);
        console.log("Local domain:", localDomain);
        console.log("Destination domain:", destDomain);
        console.log("Destination BalanceManager:", destBalanceManager);
        
        vm.stopBroadcast();
        
        console.log("========== REDEPLOYMENT COMPLETE ==========");
        console.log("New ChainBalanceManager proxy:", address(cbmProxy));
        console.log("Updated BalanceManager:", address(existingBM));
        console.log("");
        console.log("Next steps:");
        console.log("1. Update deployments.json with new ChainBalanceManager address");
        console.log("2. Set up token mappings and whitelisting");
        console.log("3. Test cross-chain deposit flow");
    }
}