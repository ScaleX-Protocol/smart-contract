// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IBalanceManager {
    function setChainBalanceManager(uint32 chainId, address chainBalanceManager) external;
    function getChainBalanceManager(uint32 chainId) external view returns (address);
}

contract FixChainRegistrations is Script {
    // From deployments/rari.json
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    
    // Chain IDs and correct ChainBalanceManager addresses
    uint32 constant RISE_SEPOLIA_CHAIN_ID = 11155931;
    uint32 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
    
    address constant RISE_CBM_CORRECT = 0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745;
    address constant ARBITRUM_CBM_CORRECT = 0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Fixing Chain Registrations on Rari BalanceManager ===");
        console.log("BalanceManager Address:", BALANCE_MANAGER);
        console.log("");

        IBalanceManager balanceManager = IBalanceManager(BALANCE_MANAGER);
        
        // Check current registrations first
        console.log("Current Registrations:");
        address currentRise = balanceManager.getChainBalanceManager(RISE_SEPOLIA_CHAIN_ID);
        address currentArbitrum = balanceManager.getChainBalanceManager(ARBITRUM_SEPOLIA_CHAIN_ID);
        console.log("  Rise Sepolia (%s): %s", RISE_SEPOLIA_CHAIN_ID, currentRise);
        console.log("  Arbitrum Sepolia (%s): %s", ARBITRUM_SEPOLIA_CHAIN_ID, currentArbitrum);
        console.log("");
        
        // Fix Rise Sepolia registration
        console.log("Fixing Rise Sepolia registration...");
        console.log("  Setting chainBalanceManager[%s] = %s", RISE_SEPOLIA_CHAIN_ID, RISE_CBM_CORRECT);
        balanceManager.setChainBalanceManager(RISE_SEPOLIA_CHAIN_ID, RISE_CBM_CORRECT);
        console.log("  Rise Sepolia registration updated!");
        console.log("");
        
        // Fix Arbitrum Sepolia registration  
        console.log("Fixing Arbitrum Sepolia registration...");
        console.log("  Setting chainBalanceManager[%s] = %s", ARBITRUM_SEPOLIA_CHAIN_ID, ARBITRUM_CBM_CORRECT);
        balanceManager.setChainBalanceManager(ARBITRUM_SEPOLIA_CHAIN_ID, ARBITRUM_CBM_CORRECT);
        console.log("  Arbitrum Sepolia registration updated!");
        console.log("");
        
        // Verify the fixes
        console.log("Verifying fixes:");
        address newRise = balanceManager.getChainBalanceManager(RISE_SEPOLIA_CHAIN_ID);
        address newArbitrum = balanceManager.getChainBalanceManager(ARBITRUM_SEPOLIA_CHAIN_ID);
        
        console.log("  Rise Sepolia (%s): %s", RISE_SEPOLIA_CHAIN_ID, newRise);
        if (newRise == RISE_CBM_CORRECT) {
            console.log("    Status: FIXED CORRECTLY");
        } else {
            console.log("    Status: STILL INCORRECT");
        }
        
        console.log("  Arbitrum Sepolia (%s): %s", ARBITRUM_SEPOLIA_CHAIN_ID, newArbitrum);
        if (newArbitrum == ARBITRUM_CBM_CORRECT) {
            console.log("    Status: FIXED CORRECTLY");
        } else {
            console.log("    Status: STILL INCORRECT");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== Chain Registration Fix Complete ===");
        console.log("Rise and Arbitrum deposits should now work!");
    }
}