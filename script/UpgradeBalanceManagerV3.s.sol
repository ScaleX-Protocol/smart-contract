// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeBalanceManagerV3 is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPGRADING BALANCE MANAGER TO V3 ==========");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        // Only run on Rari
        if (block.chainid != 1918988905) {
            console.log("This script is designed for Rari network only");
            return;
        }
        
        console.log("Detected: Rari Testnet");
        
        // Read deployment data
        string memory deploymentData;
        try vm.readFile("deployments/rari.json") returns (string memory data) {
            deploymentData = data;
            console.log("Reading Rari deployment data");
        } catch {
            console.log("ERROR: Could not read deployments/rari.json");
            return;
        }
        
        // Get current contract addresses
        address balanceManagerBeacon;
        address currentImpl;
        address balanceManagerProxy;
        
        try vm.parseJsonAddress(deploymentData, ".contracts.BalanceManagerBeacon") returns (address addr) {
            balanceManagerBeacon = addr;
        } catch {
            console.log("ERROR: Could not find BalanceManagerBeacon");
            return;
        }
        
        try vm.parseJsonAddress(deploymentData, ".contracts.BalanceManagerImplV2") returns (address addr) {
            currentImpl = addr;
        } catch {
            console.log("ERROR: Could not find current implementation");
            return;
        }
        
        try vm.parseJsonAddress(deploymentData, ".contracts.BalanceManager") returns (address addr) {
            balanceManagerProxy = addr;
        } catch {
            console.log("ERROR: Could not find BalanceManager proxy");
            return;
        }
        
        console.log("");
        console.log("=== CURRENT DEPLOYMENT ===");
        console.log("BalanceManager Proxy:", balanceManagerProxy);
        console.log("BalanceManager Beacon:", balanceManagerBeacon);
        console.log("Current Implementation (V2):", currentImpl);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new BalanceManager implementation (V3)
        console.log("=== DEPLOYING BALANCE MANAGER V3 ===");
        console.log("Changes in V3:");
        console.log("- Fixed minting pattern: mint to BalanceManager instead of user");
        console.log("- Fixed burning pattern: burn from BalanceManager instead of user");
        console.log("- Maintains user internal balance accounting");
        console.log("");
        
        BalanceManager newImpl = new BalanceManager();
        address newImplAddress = address(newImpl);
        
        console.log("New implementation (V3) deployed at:", newImplAddress);
        
        // Upgrade the beacon to point to new implementation
        console.log("");
        console.log("=== UPGRADING BEACON ===");
        
        UpgradeableBeacon beacon = UpgradeableBeacon(balanceManagerBeacon);
        beacon.upgradeTo(newImplAddress);
        
        console.log("SUCCESS: Beacon upgraded to V3 implementation");
        
        vm.stopBroadcast();
        
        // Verify upgrade
        console.log("");
        console.log("=== VERIFYING UPGRADE ===");
        
        address implementationAfterUpgrade = beacon.implementation();
        console.log("Beacon now points to:", implementationAfterUpgrade);
        
        if (implementationAfterUpgrade == newImplAddress) {
            console.log("SUCCESS: UPGRADE SUCCESSFUL");
        } else {
            console.log("FAILED: UPGRADE FAILED - Beacon still points to old implementation");
            return;
        }
        
        // Test that proxy still works
        try BalanceManager(balanceManagerProxy).owner() returns (address owner) {
            console.log("Proxy owner:", owner);
            console.log("SUCCESS: PROXY FUNCTIONALITY VERIFIED");
        } catch {
            console.log("FAILED: PROXY TEST FAILED");
        }
        
        console.log("");
        console.log("=== UPGRADE SUMMARY ===");
        console.log("Previous Implementation (V2):", currentImpl);
        console.log("New Implementation (V3):     ", newImplAddress);
        console.log("Beacon Address:              ", balanceManagerBeacon);
        console.log("Proxy Address:               ", balanceManagerProxy);
        console.log("");
        console.log("=== V3 CHANGES ===");
        console.log("+ Mint synthetic tokens TO BalanceManager contract");
        console.log("+ Burn synthetic tokens FROM BalanceManager contract");
        console.log("+ Credit/debit user internal balances for trading");
        console.log("+ Proper custodial pattern for CLOB system");
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Update rari.json with new implementation address");
        console.log("2. Test cross-chain deposit to verify new minting pattern");
        console.log("3. Run CheckTokenBalances.s.sol to verify correct pattern");
        console.log("4. Expected: BalanceManager ERC20 balance > 0, User ERC20 balance = 0");
        
        console.log("========== BALANCE MANAGER V3 UPGRADE COMPLETE ==========");
    }
}