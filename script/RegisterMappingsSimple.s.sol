// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface ISyntheticTokenFactory {
    function owner() external view returns (address);
    
    function createSyntheticToken(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        string memory name,
        string memory symbol,
        uint8 sourceDecimals,
        uint8 syntheticDecimals
    ) external returns (address syntheticToken);
    
    function updateTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address newSyntheticToken,
        uint8 newSyntheticDecimals
    ) external;
}

interface ITokenRegistry {
    function getSyntheticToken(uint32 sourceChainId, address sourceToken, uint32 targetChainId) external view returns (address);
}

contract RegisterMappingsSimple is Script {
    address constant SYNTHETIC_TOKEN_FACTORY = 0x2594C4ca1B552ad573bcc0C4c561FAC6a87987fC;
    address constant TOKEN_REGISTRY = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;
    
    // Chain IDs
    uint32 constant RARI_CHAIN_ID = 1918988905;
    uint32 constant RISE_CHAIN_ID = 11155931;
    uint32 constant ARBITRUM_CHAIN_ID = 421614;
    
    // Rise source tokens
    address constant RISE_USDT = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;
    address constant RISE_WETH = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
    address constant RISE_WBTC = 0xc6b3109e45F7A479Ac324e014b6a272e4a25bF0E;
    
    // Arbitrum source tokens  
    address constant ARB_USDT = 0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a;
    address constant ARB_WETH = 0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7;
    address constant ARB_WBTC = 0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A;
    
    // Existing synthetic tokens we want to reuse
    address constant RARI_gUSDT = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d;
    address constant RARI_gWETH = 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8;
    address constant RARI_gWBTC = 0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Register Token Mappings (Simple Approach) ===");
        console.log("Strategy: Create temporary synthetic tokens, then update to existing ones");
        console.log("Deployer:", deployer);
        console.log("");
        
        ISyntheticTokenFactory stf = ISyntheticTokenFactory(SYNTHETIC_TOKEN_FACTORY);
        ITokenRegistry tr = ITokenRegistry(TOKEN_REGISTRY);
        
        // Verify ownership
        address stfOwner = stf.owner();
        if (stfOwner != deployer) {
            console.log("ERROR: Not SyntheticTokenFactory owner!");
            console.log("Expected:", deployer);
            console.log("Actual:", stfOwner);
            vm.stopBroadcast();
            return;
        }
        
        console.log("SUCCESS: We own SyntheticTokenFactory");
        console.log("");
        
        // Step 1: Handle Rise mappings
        console.log("=== Step 1: Rise Token Mappings ===");
        
        // Rise USDT
        address existingRiseUSDT = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_USDT, RARI_CHAIN_ID);
        if (existingRiseUSDT == address(0)) {
            console.log("Creating Rise USDT mapping...");
            address tempSynthetic = stf.createSyntheticToken(
                RISE_CHAIN_ID, RISE_USDT, RARI_CHAIN_ID, 
                "Temp Rise USDT", "tUSDT", 6, 6
            );
            console.log("  Temp synthetic created:", tempSynthetic);
            
            console.log("Updating to point to existing gUSDT...");
            stf.updateTokenMapping(RISE_CHAIN_ID, RISE_USDT, RARI_CHAIN_ID, RARI_gUSDT, 6);
            console.log("  SUCCESS: Rise USDT -> gUSDT");
        } else {
            console.log("Rise USDT mapping already exists:", existingRiseUSDT);
        }
        
        // Rise WETH
        address existingRiseWETH = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_WETH, RARI_CHAIN_ID);
        if (existingRiseWETH == address(0)) {
            console.log("Creating Rise WETH mapping...");
            address tempSynthetic = stf.createSyntheticToken(
                RISE_CHAIN_ID, RISE_WETH, RARI_CHAIN_ID,
                "Temp Rise WETH", "tWETH", 18, 18
            );
            console.log("  Temp synthetic created:", tempSynthetic);
            
            console.log("Updating to point to existing gWETH...");
            stf.updateTokenMapping(RISE_CHAIN_ID, RISE_WETH, RARI_CHAIN_ID, RARI_gWETH, 18);
            console.log("  SUCCESS: Rise WETH -> gWETH");
        } else {
            console.log("Rise WETH mapping already exists:", existingRiseWETH);
        }
        
        // Rise WBTC
        address existingRiseWBTC = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_WBTC, RARI_CHAIN_ID);
        if (existingRiseWBTC == address(0)) {
            console.log("Creating Rise WBTC mapping...");
            address tempSynthetic = stf.createSyntheticToken(
                RISE_CHAIN_ID, RISE_WBTC, RARI_CHAIN_ID,
                "Temp Rise WBTC", "tWBTC", 8, 8
            );
            console.log("  Temp synthetic created:", tempSynthetic);
            
            console.log("Updating to point to existing gWBTC...");
            stf.updateTokenMapping(RISE_CHAIN_ID, RISE_WBTC, RARI_CHAIN_ID, RARI_gWBTC, 8);
            console.log("  SUCCESS: Rise WBTC -> gWBTC");
        } else {
            console.log("Rise WBTC mapping already exists:", existingRiseWBTC);
        }
        console.log("");
        
        // Step 2: Handle Arbitrum mappings
        console.log("=== Step 2: Arbitrum Token Mappings ===");
        
        // Arbitrum USDT
        address existingArbUSDT = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID);
        if (existingArbUSDT == address(0)) {
            console.log("Creating Arbitrum USDT mapping...");
            address tempSynthetic = stf.createSyntheticToken(
                ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID,
                "Temp Arbitrum USDT", "tUSDT", 6, 6
            );
            console.log("  Temp synthetic created:", tempSynthetic);
            
            console.log("Updating to point to existing gUSDT...");
            stf.updateTokenMapping(ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID, RARI_gUSDT, 6);
            console.log("  SUCCESS: Arbitrum USDT -> gUSDT");
        } else if (existingArbUSDT != RARI_gUSDT) {
            console.log("Updating existing Arbitrum USDT mapping to gUSDT...");
            stf.updateTokenMapping(ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID, RARI_gUSDT, 6);
            console.log("  SUCCESS: Arbitrum USDT -> gUSDT");
        } else {
            console.log("Arbitrum USDT already points to gUSDT");
        }
        
        // Arbitrum WETH
        address existingArbWETH = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID);
        if (existingArbWETH == address(0)) {
            console.log("Creating Arbitrum WETH mapping...");
            address tempSynthetic = stf.createSyntheticToken(
                ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID,
                "Temp Arbitrum WETH", "tWETH", 18, 18
            );
            console.log("  Temp synthetic created:", tempSynthetic);
            
            console.log("Updating to point to existing gWETH...");
            stf.updateTokenMapping(ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID, RARI_gWETH, 18);
            console.log("  SUCCESS: Arbitrum WETH -> gWETH");
        } else if (existingArbWETH != RARI_gWETH) {
            console.log("Updating existing Arbitrum WETH mapping to gWETH...");
            stf.updateTokenMapping(ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID, RARI_gWETH, 18);
            console.log("  SUCCESS: Arbitrum WETH -> gWETH");
        } else {
            console.log("Arbitrum WETH already points to gWETH");
        }
        
        // Arbitrum WBTC
        address existingArbWBTC = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID);
        if (existingArbWBTC == address(0)) {
            console.log("Creating Arbitrum WBTC mapping...");
            address tempSynthetic = stf.createSyntheticToken(
                ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID,
                "Temp Arbitrum WBTC", "tWBTC", 8, 8
            );
            console.log("  Temp synthetic created:", tempSynthetic);
            
            console.log("Updating to point to existing gWBTC...");
            stf.updateTokenMapping(ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID, RARI_gWBTC, 8);
            console.log("  SUCCESS: Arbitrum WBTC -> gWBTC");
        } else if (existingArbWBTC != RARI_gWBTC) {
            console.log("Updating existing Arbitrum WBTC mapping to gWBTC...");
            stf.updateTokenMapping(ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID, RARI_gWBTC, 8);
            console.log("  SUCCESS: Arbitrum WBTC -> gWBTC");
        } else {
            console.log("Arbitrum WBTC already points to gWBTC");
        }

        vm.stopBroadcast();
        
        console.log("");
        console.log("=== Final Verification ===");
        
        // Verify all mappings
        address finalRiseUSDT = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_USDT, RARI_CHAIN_ID);
        address finalArbUSDT = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID);
        address finalRiseWETH = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_WETH, RARI_CHAIN_ID);
        address finalArbWETH = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID);
        
        console.log("Rise USDT -> gUSDT:", finalRiseUSDT == RARI_gUSDT ? "YES" : "NO");
        console.log("Arbitrum USDT -> gUSDT:", finalArbUSDT == RARI_gUSDT ? "YES" : "NO");
        console.log("Rise WETH -> gWETH:", finalRiseWETH == RARI_gWETH ? "YES" : "NO");
        console.log("Arbitrum WETH -> gWETH:", finalArbWETH == RARI_gWETH ? "YES" : "NO");
        console.log("");
        
        if (finalRiseUSDT == RARI_gUSDT && finalArbUSDT == RARI_gUSDT && 
            finalRiseWETH == RARI_gWETH && finalArbWETH == RARI_gWETH) {
            console.log("SUCCESS: All mappings configured correctly!");
            console.log("Cross-chain deposits will now mint existing gUSDT/gWETH/gWBTC!");
            console.log("Rise and Arbitrum deposits should relay successfully!");
        } else {
            console.log("WARNING: Some mappings may not be correct");
        }
    }
}