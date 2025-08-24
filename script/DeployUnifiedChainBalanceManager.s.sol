// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "../src/core/TokenRegistry.sol";

contract DeployUnifiedChainBalanceManager is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== DEPLOYING UNIFIED CHAIN BALANCE MANAGER ==========");
        console.log("Deployer:", deployer);
        
        // Read deployment addresses from rari.json (dynamically)
        string memory deploymentFile = vm.readFile("deployments/rari.json");
        
        // Parse JSON to get deployed contract addresses
        address balanceManagerAddr = vm.parseJsonAddress(deploymentFile, ".contracts.BalanceManager");
        address tokenRegistryAddr = vm.parseJsonAddress(deploymentFile, ".contracts.TokenRegistry");
        
        // Get current synthetic token addresses from deployment file
        address currentGsUSDT = vm.parseJsonAddress(deploymentFile, ".contracts.gsUSDT");
        address currentGsWBTC = vm.parseJsonAddress(deploymentFile, ".contracts.gsWBTC");
        address currentGsWETH = vm.parseJsonAddress(deploymentFile, ".contracts.gsWETH");
        
        console.log("=== CURRENT STATUS ===");
        console.log("BalanceManager (V2):", balanceManagerAddr);
        console.log("TokenRegistry:", tokenRegistryAddr);
        console.log("Synthetic Tokens:");
        console.log("  gsUSDT:", currentGsUSDT);
        console.log("  gsWBTC:", currentGsWBTC);
        console.log("  gsWETH:", currentGsWETH);
        console.log("");
        
        // Switch to Rari
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        // For Rari, we need real token addresses (USDT, WETH, WBTC on Rari)
        // These would be the real tokens that users deposit to get synthetic tokens
        address realUSDT = address(0x123); // TODO: Get real USDT address on Rari
        address realWETH = address(0x456); // TODO: Get real WETH address on Rari  
        address realWBTC = address(0x789); // TODO: Get real WBTC address on Rari
        
        console.log("=== REAL TOKENS ON RARI (for local deposits) ===");
        console.log("Real USDT:", realUSDT);
        console.log("Real WETH:", realWETH);
        console.log("Real WBTC:", realWBTC);
        console.log("NOTE: These addresses need to be updated with actual Rari token addresses");
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== DEPLOYING UNIFIED CHAIN BALANCE MANAGER ON RARI ===");
        
        // Deploy ChainBalanceManager for destination chain (same-chain mode)
        ChainBalanceManager chainBalanceManager = new ChainBalanceManager();
        
        // Initialize for destination chain mode
        chainBalanceManager.initializeDestinationChain(
            deployer,           // owner
            balanceManagerAddr  // balanceManager (our "message handler")
        );
        
        console.log("SUCCESS: ChainBalanceManager deployed at:", address(chainBalanceManager));
        
        // Set up token mappings (real tokens → synthetic tokens)
        console.log("Setting up token mappings...");
        
        // Whitelist real tokens
        chainBalanceManager.addWhitelistedToken(realUSDT);
        chainBalanceManager.addWhitelistedToken(realWETH);
        chainBalanceManager.addWhitelistedToken(realWBTC);
        console.log("Real tokens whitelisted");
        
        // Map real tokens to synthetic tokens
        chainBalanceManager.setTokenMapping(realUSDT, currentGsUSDT); // USDT → gsUSDT
        chainBalanceManager.setTokenMapping(realWETH, currentGsWETH); // WETH → gsWETH
        chainBalanceManager.setTokenMapping(realWBTC, currentGsWBTC); // WBTC → gsWBTC
        console.log("Token mappings configured");
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("ChainBalanceManager (Rari):", address(chainBalanceManager));
        console.log("Mode: Destination Chain (same-chain)");
        console.log("Message Handler: BalanceManager (direct calls)");
        console.log("Target BalanceManager:", balanceManagerAddr);
        console.log("");
        
        // Verify configuration
        console.log("=== CONFIGURATION VERIFICATION ===");
        (
            bool isDestinationChain,
            address messageHandler,
            uint32 localDomain,
            uint32 destinationDomain,
            address destinationBalanceManager
        ) = chainBalanceManager.getUnifiedConfig();
        
        console.log("Is Destination Chain:", isDestinationChain);
        console.log("Message Handler:", messageHandler);
        console.log("Local Domain:", localDomain);
        console.log("Destination Domain:", destinationDomain);
        console.log("Destination BalanceManager:", destinationBalanceManager);
        
        if (isDestinationChain && messageHandler == balanceManagerAddr) {
            console.log("✅ Configuration CORRECT: Destination chain mode with BalanceManager as message handler");
        } else {
            console.log("❌ Configuration ERROR: Unexpected configuration");
        }
        
        console.log("");
        console.log("=== USAGE INSTRUCTIONS ===");
        console.log("1. Users can now deposit real tokens (USDT, WETH, WBTC) on Rari");
        console.log("2. ChainBalanceManager will call BalanceManager directly (no cross-chain messaging)");
        console.log("3. BalanceManager will mint equivalent synthetic tokens (gsUSDT, gsWETH, gsWBTC)");
        console.log("4. Same interface as cross-chain deposits but instant execution");
        console.log("");
        
        console.log("=== NEXT STEPS ===");
        console.log("1. Update real token addresses once known");
        console.log("2. Test local deposit flow: realToken → ChainBalanceManager → BalanceManager → syntheticToken");
        console.log("3. Update frontend to use ChainBalanceManager for Rari deposits");
        console.log("4. Configure BalanceManager to accept calls from ChainBalanceManager");
        
        console.log("========== UNIFIED CHAIN BALANCE MANAGER DEPLOYED ==========");
    }
}