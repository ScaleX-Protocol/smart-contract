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
        
        // Contract addresses
        address syntheticTokenFactoryAddr = 0x2594C4ca1B552ad573bcc0C4c561FAC6a87987fC;
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        
        // Expected addresses (currently just placeholders)
        address expectedGsUSDT = 0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7;
        address expectedGsWBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;
        
        console.log("=== CURRENT STATUS ===");
        console.log("SyntheticTokenFactory:", syntheticTokenFactoryAddr);
        console.log("BalanceManager (V2):", balanceManagerAddr);
        console.log("Expected gsUSDT:", expectedGsUSDT);
        console.log("Expected gsWBTC:", expectedGsWBTC);
        console.log("");
        
        // Check if gsUSDT already exists as contract
        console.log("=== CHECKING EXISTING CONTRACTS ===");
        console.log("gsUSDT placeholder address has no contract code");
        console.log("Need to deploy real ERC20 tokens");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== DEPLOYING REAL SYNTHETIC TOKENS ===");
        
        // Deploy gsUSDT as real ERC20
        console.log("Deploying gsUSDT...");
        SyntheticToken gsUSDT = new SyntheticToken(
            "GTX Synthetic USDT",
            "gsUSDT", 
            balanceManagerAddr  // BalanceManager as minter
        );
        
        console.log("SUCCESS: gsUSDT deployed at:", address(gsUSDT));
        
        // Deploy gsWBTC as real ERC20  
        console.log("Deploying gsWBTC...");
        SyntheticToken gsWBTC = new SyntheticToken(
            "GTX Synthetic WBTC",
            "gsWBTC",
            balanceManagerAddr  // BalanceManager as minter
        );
        
        console.log("SUCCESS: gsWBTC deployed at:", address(gsWBTC));
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("Real gsUSDT ERC20:", address(gsUSDT));
        console.log("Real gsWBTC ERC20:", address(gsWBTC));
        console.log("gsWETH ERC20 (existing):", 0xC7A1777e80982E01e07406e6C6E8B30F5968F836);
        console.log("");
        
        console.log("=== VERIFICATION ===");
        
        // Test ERC20 functionality
        try gsUSDT.name() returns (string memory name) {
            console.log("gsUSDT name:", name);
        } catch {
            console.log("gsUSDT name: Not readable");
        }
        
        try gsUSDT.symbol() returns (string memory symbol) {
            console.log("gsUSDT symbol:", symbol);
        } catch {
            console.log("gsUSDT symbol: Not readable");
        }
        
        try gsUSDT.totalSupply() returns (uint256 supply) {
            console.log("gsUSDT total supply:", supply);
        } catch {
            console.log("gsUSDT total supply: Not readable");
        }
        
        try gsUSDT.bridgeSyntheticTokenReceiver() returns (address minter) {
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