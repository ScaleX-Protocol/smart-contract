// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/SyntheticTokenFactory.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeFactoryBeaconAndUpdateMappings is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPGRADE FACTORY BEACON + UPDATE MAPPINGS ==========");
        console.log("Step 1: Upgrade SyntheticTokenFactory beacon");
        console.log("Step 2: Update TokenRegistry mappings via upgraded factory");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/rari.json");
        
        address factoryProxy = vm.parseJsonAddress(deploymentData, ".contracts.SyntheticTokenFactory");
        address factoryBeacon = 0x122e4C08f927AD85534Fc19FD5f3BC607b00C731; // From storage check
        
        console.log("SyntheticTokenFactory Proxy:", factoryProxy);
        console.log("SyntheticTokenFactory Beacon:", factoryBeacon);
        
        // New tokens with correct decimals
        address newUSDT = 0x85961935a95690860A5Fb5E4bE09099049c19AD9; // 6 decimals
        address newWBTC = 0x89F26f075284Af73922caB248877F279ac890A36; // 8 decimals  
        address newWETH = 0xc4b6647c4c0Db93b47996b6aa8E309bE29dC6d04; // 18 decimals
        
        console.log("");
        console.log("=== NEW TOKENS WITH CORRECT DECIMALS ===");
        console.log("gsUSDT3 (6 decimals): ", newUSDT);
        console.log("gsWBTC3 (8 decimals): ", newWBTC);
        console.log("gsWETH3 (18 decimals):", newWETH);
        console.log("");
        
        // Read source tokens from Appchain
        string memory appchainData = vm.readFile("deployments/appchain.json");
        address sourceUSDT = vm.parseJsonAddress(appchainData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(appchainData, ".contracts.WBTC");
        address sourceWETH = vm.parseJsonAddress(appchainData, ".contracts.WETH");
        
        console.log("=== SOURCE TOKENS (Appchain 4661) ===");
        console.log("USDT:", sourceUSDT);
        console.log("WBTC:", sourceWBTC);
        console.log("WETH:", sourceWETH);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== STEP 1: DEPLOY NEW FACTORY IMPLEMENTATION ===");
        
        // Deploy new SyntheticTokenFactory implementation with updateTokenMapping
        SyntheticTokenFactory newFactoryImpl = new SyntheticTokenFactory();
        console.log("New implementation deployed:", address(newFactoryImpl));
        
        console.log("");
        console.log("=== STEP 2: UPGRADE BEACON ===");
        
        UpgradeableBeacon beacon = UpgradeableBeacon(factoryBeacon);
        
        // Check beacon owner
        address beaconOwner = beacon.owner();
        console.log("Beacon owner:", beaconOwner);
        
        if (beaconOwner != deployer) {
            console.log("ERROR: Cannot upgrade beacon - deployer is not owner");
            return;
        }
        
        // Upgrade the beacon to new implementation
        console.log("Upgrading beacon to new implementation...");
        beacon.upgradeTo(address(newFactoryImpl));
        console.log("SUCCESS: Beacon upgraded");
        
        console.log("");
        console.log("=== STEP 3: VERIFY UPGRADE ===");
        
        address currentImpl = beacon.implementation();
        console.log("Current implementation:", currentImpl);
        console.log("Expected implementation:", address(newFactoryImpl));
        
        if (currentImpl == address(newFactoryImpl)) {
            console.log("SUCCESS: Upgrade verified");
        } else {
            console.log("ERROR: Upgrade failed - implementation mismatch");
            return;
        }
        
        console.log("");
        console.log("=== STEP 4: UPDATE TOKEN MAPPINGS ===");
        
        SyntheticTokenFactory factory = SyntheticTokenFactory(factoryProxy);
        
        // Update USDT mapping
        console.log("Updating USDT mapping to 6 decimals...");
        try factory.updateTokenMapping(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceUSDT,              // sourceToken
            1918988905,              // targetChainId (Rari)
            newUSDT,                 // newSyntheticToken
            6                        // newSyntheticDecimals
        ) {
            console.log("SUCCESS: USDT mapping updated");
        } catch Error(string memory reason) {
            console.log("FAILED: USDT mapping -", reason);
        }
        
        // Update WBTC mapping
        console.log("Updating WBTC mapping to 8 decimals...");
        try factory.updateTokenMapping(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceWBTC,              // sourceToken
            1918988905,              // targetChainId (Rari)
            newWBTC,                 // newSyntheticToken
            8                        // newSyntheticDecimals
        ) {
            console.log("SUCCESS: WBTC mapping updated");
        } catch Error(string memory reason) {
            console.log("FAILED: WBTC mapping -", reason);
        }
        
        // Update WETH mapping
        console.log("Updating WETH mapping to 18 decimals...");
        try factory.updateTokenMapping(
            4661,                    // sourceChainId (CORRECT: Appchain)
            sourceWETH,              // sourceToken
            1918988905,              // targetChainId (Rari)
            newWETH,                 // newSyntheticToken
            18                       // newSyntheticDecimals
        ) {
            console.log("SUCCESS: WETH mapping updated");
        } catch Error(string memory reason) {
            console.log("FAILED: WETH mapping -", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== VERIFICATION ===");
        console.log("Verify new mappings point to correct decimal tokens:");
        console.log("USDT -> gsUSDT3 (6 dec):", newUSDT);
        console.log("WBTC -> gsWBTC3 (8 dec):", newWBTC);
        console.log("WETH -> gsWETH3 (18 dec):", newWETH);
        console.log("");
        
        console.log("=== NEXT STEPS ===");
        console.log("1. Test cross-chain deposits with new tokens");
        console.log("2. Update ChainBalanceManager mappings on other chains");
        console.log("3. Create new trading pools");
        console.log("4. Update deployments/rari.json");
        
        console.log("========== FACTORY UPGRADED + MAPPINGS UPDATED ==========");
    }
}