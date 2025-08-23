// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/SyntheticTokenFactory.sol";
import "../src/token/SyntheticToken.sol";
import "../src/core/BalanceManager.sol";

contract DeployActualSyntheticTokens is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== DEPLOYING ACTUAL SYNTHETIC TOKENS ==========");
        console.log("Deployer:", deployer);
        
        // Switch to Rari
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        // Read deployment addresses from rari.json (dynamically)
        string memory deploymentFile = vm.readFile("deployments/rari.json");
        
        // Parse JSON to get deployed contract addresses
        address syntheticTokenFactoryAddr = vm.parseJsonAddress(deploymentFile, ".contracts.SyntheticTokenFactory");
        address balanceManagerAddr = vm.parseJsonAddress(deploymentFile, ".contracts.BalanceManager");
        
        // Get current synthetic token addresses from deployment file
        address currentGsUSDT = vm.parseJsonAddress(deploymentFile, ".contracts.gsUSDT");
        address currentGsWBTC = vm.parseJsonAddress(deploymentFile, ".contracts.gsWBTC");
        address currentGsWETH = vm.parseJsonAddress(deploymentFile, ".contracts.gsWETH");
        
        console.log("=== CURRENT STATUS ===");
        console.log("SyntheticTokenFactory:", syntheticTokenFactoryAddr);
        console.log("BalanceManager (V2):", balanceManagerAddr);
        console.log("Current gsUSDT (from rari.json):", currentGsUSDT);
        console.log("Current gsWBTC (from rari.json):", currentGsWBTC);
        console.log("Current gsWETH (from rari.json):", currentGsWETH);
        console.log("");
        
        // Check if synthetic tokens already exist as real contracts
        console.log("=== CHECKING EXISTING CONTRACTS ===");
        
        // Check if gsUSDT has contract code
        bool gsUSDTExists = currentGsUSDT.code.length > 0;
        bool gsWBTCExists = currentGsWBTC.code.length > 0;
        bool gsWETHExists = currentGsWETH.code.length > 0;
        
        console.log("gsUSDT contract exists:", gsUSDTExists);
        console.log("gsWBTC contract exists:", gsWBTCExists);  
        console.log("gsWETH contract exists:", gsWETHExists);
        
        if (gsUSDTExists && gsWBTCExists && gsWETHExists) {
            console.log("All synthetic tokens already deployed as real contracts!");
            console.log("No need to redeploy.");
            return;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== DEPLOYING REAL SYNTHETIC TOKENS ===");
        
        address newGsUSDT = currentGsUSDT;
        address newGsWBTC = currentGsWBTC;
        
        // Deploy gsUSDT only if it doesn't exist
        if (!gsUSDTExists) {
            console.log("Deploying gsUSDT...");
            SyntheticToken gsUSDT = new SyntheticToken(
                "GTX Synthetic USDT",
                "gsUSDT", 
                balanceManagerAddr  // BalanceManager as minter
            );
            newGsUSDT = address(gsUSDT);
            console.log("SUCCESS: gsUSDT deployed at:", newGsUSDT);
        } else {
            console.log("gsUSDT already exists at:", currentGsUSDT);
        }
        
        // Deploy gsWBTC only if it doesn't exist  
        if (!gsWBTCExists) {
            console.log("Deploying gsWBTC...");
            SyntheticToken gsWBTC = new SyntheticToken(
                "GTX Synthetic WBTC",
                "gsWBTC",
                balanceManagerAddr  // BalanceManager as minter
            );
            newGsWBTC = address(gsWBTC);
            console.log("SUCCESS: gsWBTC deployed at:", newGsWBTC);
        } else {
            console.log("gsWBTC already exists at:", currentGsWBTC);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("Real gsUSDT ERC20:", newGsUSDT);
        console.log("Real gsWBTC ERC20:", newGsWBTC);
        console.log("gsWETH ERC20 (existing):", currentGsWETH);
        console.log("");
        
        console.log("=== VERIFICATION ===");
        
        // Verify gsUSDT functionality
        SyntheticToken gsUSDTToken = SyntheticToken(newGsUSDT);
        try gsUSDTToken.name() returns (string memory name) {
            console.log("gsUSDT name:", name);
        } catch {
            console.log("gsUSDT name: Not readable");
        }
        
        try gsUSDTToken.symbol() returns (string memory symbol) {
            console.log("gsUSDT symbol:", symbol);
        } catch {
            console.log("gsUSDT symbol: Not readable");
        }
        
        try gsUSDTToken.totalSupply() returns (uint256 supply) {
            console.log("gsUSDT total supply:", supply);
        } catch {
            console.log("gsUSDT total supply: Not readable");
        }
        
        try gsUSDTToken.bridgeSyntheticTokenReceiver() returns (address minter) {
            console.log("gsUSDT minter (BalanceManager):", minter);
            if (minter == balanceManagerAddr) {
                console.log("SUCCESS: BalanceManager is authorized minter");
            } else {
                console.log("WARNING: BalanceManager not set as minter");
            }
        } catch {
            console.log("gsUSDT minter: Not readable");
        }
        
        console.log("");
        console.log("=== IMPORTANT NOTES ===");
        console.log("1. These are NEW token contracts at different addresses");
        console.log("2. Old placeholder addresses won't work");
        console.log("3. Need to update system to use new addresses:");
        console.log("   - Update cross-chain message handling");
        console.log("   - Update trading pool configurations");
        console.log("   - Update frontend/client references");
        console.log("");
        
        console.log("=== NEXT STEPS ===");
        console.log("1. Update BalanceManager cross-chain message handling to use new addresses");
        console.log("2. Configure TokenRegistry with new mappings");
        console.log("3. Update trading pools to use new token addresses");
        console.log("4. Test cross-chain deposit -> mint flow with real tokens");
        
        console.log("========== REAL SYNTHETIC TOKENS DEPLOYED ==========");
        console.log("V2 system can now mint actual ERC20 tokens!");
    }
}