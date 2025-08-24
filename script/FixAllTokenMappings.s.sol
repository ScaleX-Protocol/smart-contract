// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IBalanceManager {
    function setTokenRegistry(address _tokenRegistry) external;
    function getTokenRegistry() external view returns (address);
}

interface ITokenRegistry {
    function owner() external view returns (address);
    function getSyntheticToken(uint32 sourceChainId, address sourceToken, uint32 targetChainId) external view returns (address);
    function registerTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address syntheticToken,
        string memory symbol,
        uint8 sourceDecimals,
        uint8 syntheticDecimals
    ) external;
    function updateTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address newSyntheticToken,
        uint8 newSyntheticDecimals
    ) external;
}

contract FixAllTokenMappings is Script {
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    address constant TOKEN_REGISTRY = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;
    
    // Chain IDs
    uint32 constant RARI_CHAIN_ID = 1918988905;
    uint32 constant RISE_CHAIN_ID = 11155931;
    uint32 constant ARBITRUM_CHAIN_ID = 421614;
    uint32 constant APPCHAIN_ID = 4661;
    
    // Rise source tokens
    address constant RISE_USDT = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;
    address constant RISE_WETH = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
    address constant RISE_WBTC = 0xc6b3109e45F7A479Ac324e014b6a272e4a25bF0E;
    
    // Arbitrum source tokens  
    address constant ARB_USDT = 0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a;
    address constant ARB_WETH = 0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7;
    address constant ARB_WBTC = 0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A;
    
    // Existing synthetic tokens on Rari (same as Appchain uses)
    address constant RARI_gUSDT = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d;
    address constant RARI_gWETH = 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8;
    address constant RARI_gWBTC = 0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Fix All Token Mappings (Appchain Comparison) ===");
        console.log("BalanceManager:", BALANCE_MANAGER);
        console.log("TokenRegistry:", TOKEN_REGISTRY);
        console.log("");
        
        IBalanceManager bm = IBalanceManager(BALANCE_MANAGER);
        ITokenRegistry tr = ITokenRegistry(TOKEN_REGISTRY);
        
        // Step 1: Fix BalanceManager TokenRegistry
        console.log("=== Step 1: Fix BalanceManager TokenRegistry ===");
        address currentTokenRegistry = bm.getTokenRegistry();
        console.log("Current TokenRegistry:", currentTokenRegistry);
        
        if (currentTokenRegistry != TOKEN_REGISTRY) {
            console.log("Setting BalanceManager TokenRegistry...");
            bm.setTokenRegistry(TOKEN_REGISTRY);
            console.log("SUCCESS: BalanceManager TokenRegistry updated");
        } else {
            console.log("BalanceManager TokenRegistry already correct");
        }
        console.log("");
        
        // Step 2: Register Rise mappings (all new)
        console.log("=== Step 2: Register Rise Mappings (New) ===");
        console.log("Rise has 0 mappings - registering all new...");
        
        console.log("Registering Rise USDT -> gUSDT...");
        tr.registerTokenMapping(
            RISE_CHAIN_ID, RISE_USDT, RARI_CHAIN_ID, RARI_gUSDT, "gUSDT", 6, 6
        );
        console.log("  SUCCESS: Rise USDT registered");
        
        console.log("Registering Rise WETH -> gWETH...");
        tr.registerTokenMapping(
            RISE_CHAIN_ID, RISE_WETH, RARI_CHAIN_ID, RARI_gWETH, "gWETH", 18, 18
        );
        console.log("  SUCCESS: Rise WETH registered");
        
        console.log("Registering Rise WBTC -> gWBTC...");
        tr.registerTokenMapping(
            RISE_CHAIN_ID, RISE_WBTC, RARI_CHAIN_ID, RARI_gWBTC, "gWBTC", 8, 8
        );
        console.log("  SUCCESS: Rise WBTC registered");
        console.log("");
        
        // Step 3: Check and update Arbitrum mappings
        console.log("=== Step 3: Update Arbitrum Mappings (Fix Existing) ===");
        console.log("Arbitrum has wrong mappings - updating to correct synthetic tokens...");
        
        // Check current Arbitrum USDT mapping
        address currentArbUSDT = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID);
        console.log("Current Arbitrum USDT mapping:", currentArbUSDT);
        console.log("Expected gUSDT:", RARI_gUSDT);
        
        if (currentArbUSDT == address(0)) {
            console.log("No mapping exists - registering new...");
            tr.registerTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID, RARI_gUSDT, "gUSDT", 6, 6
            );
        } else if (currentArbUSDT != RARI_gUSDT) {
            console.log("Wrong mapping - updating...");
            tr.updateTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID, RARI_gUSDT, 6
            );
        } else {
            console.log("Mapping already correct");
        }
        console.log("  SUCCESS: Arbitrum USDT mapping fixed");
        
        // Check current Arbitrum WETH mapping
        address currentArbWETH = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID);
        console.log("Current Arbitrum WETH mapping:", currentArbWETH);
        console.log("Expected gWETH:", RARI_gWETH);
        
        if (currentArbWETH == address(0)) {
            console.log("No mapping exists - registering new...");
            tr.registerTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID, RARI_gWETH, "gWETH", 18, 18
            );
        } else if (currentArbWETH != RARI_gWETH) {
            console.log("Wrong mapping - updating...");
            tr.updateTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID, RARI_gWETH, 18
            );
        } else {
            console.log("Mapping already correct");
        }
        console.log("  SUCCESS: Arbitrum WETH mapping fixed");
        
        // Check current Arbitrum WBTC mapping
        address currentArbWBTC = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID);
        console.log("Current Arbitrum WBTC mapping:", currentArbWBTC);
        console.log("Expected gWBTC:", RARI_gWBTC);
        
        if (currentArbWBTC == address(0)) {
            console.log("No mapping exists - registering new...");
            tr.registerTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID, RARI_gWBTC, "gWBTC", 8, 8
            );
        } else if (currentArbWBTC != RARI_gWBTC) {
            console.log("Wrong mapping - updating...");
            tr.updateTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID, RARI_gWBTC, 8
            );
        } else {
            console.log("Mapping already correct");
        }
        console.log("  SUCCESS: Arbitrum WBTC mapping fixed");

        vm.stopBroadcast();
        
        console.log("");
        console.log("=== Final Verification ===");
        
        // Verify all mappings point to correct synthetic tokens
        address finalRiseUSDT = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_USDT, RARI_CHAIN_ID);
        address finalArbUSDT = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID);
        
        console.log("Rise USDT -> Synthetic:", finalRiseUSDT);
        console.log("Arbitrum USDT -> Synthetic:", finalArbUSDT);
        console.log("Expected gUSDT:", RARI_gUSDT);
        console.log("");
        
        if (finalRiseUSDT == RARI_gUSDT && finalArbUSDT == RARI_gUSDT) {
            console.log("SUCCESS: All token mappings fixed!");
            console.log("All chains now map to same synthetic tokens:");
            console.log("  Appchain USDT -> gUSDT");
            console.log("  Rise USDT -> gUSDT");  
            console.log("  Arbitrum USDT -> gUSDT");
            console.log("");
            console.log("Cross-chain deposits should now relay successfully!");
        } else {
            console.log("WARNING: Some mappings may not be correct");
        }
    }
}