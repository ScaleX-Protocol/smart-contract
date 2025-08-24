// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface ISyntheticTokenFactory {
    function owner() external view returns (address);
    function getTokenRegistry() external view returns (address);
    
    // Use the existing updateTokenMapping function if available
    function updateTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address newSyntheticToken,
        uint8 newSyntheticDecimals
    ) external;
}

interface ITokenRegistry {
    function owner() external view returns (address);
    function registerTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address syntheticToken,
        string memory symbol,
        uint8 sourceDecimals,
        uint8 syntheticDecimals
    ) external;
    function getSyntheticToken(uint32 sourceChainId, address sourceToken, uint32 targetChainId) external view returns (address);
}

contract RegisterTokenMappingsViaSyntheticFactory is Script {
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
    
    // Current synthetic tokens on Rari
    address constant RARI_gUSDT = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d;
    address constant RARI_gWETH = 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8;
    address constant RARI_gWBTC = 0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Register Token Mappings via SyntheticTokenFactory ===");
        console.log("SyntheticTokenFactory:", SYNTHETIC_TOKEN_FACTORY);
        console.log("TokenRegistry:", TOKEN_REGISTRY);
        console.log("");

        ISyntheticTokenFactory stf = ISyntheticTokenFactory(SYNTHETIC_TOKEN_FACTORY);
        ITokenRegistry tr = ITokenRegistry(TOKEN_REGISTRY);
        
        // Verify ownership
        address stfOwner = stf.owner();
        address trOwner = tr.owner();
        console.log("SyntheticTokenFactory owner:", stfOwner);
        console.log("TokenRegistry owner:", trOwner);
        console.log("Current caller (msg.sender):", msg.sender);
        console.log("Current caller (tx.origin):", tx.origin);
        console.log("");
        
        // Check if we need to call from SyntheticTokenFactory owner
        if (stfOwner == tx.origin) {
            console.log("SUCCESS: Current caller is SyntheticTokenFactory owner!");
            console.log("Proceeding with token mapping registration...");
            console.log("");
            
            // Register Rise mappings directly through TokenRegistry
            console.log("=== Registering Rise Sepolia Mappings ===");
            
            // Rise USDT -> gUSDT
            console.log("Registering Rise USDT -> gUSDT...");
            tr.registerTokenMapping(
                RISE_CHAIN_ID, RISE_USDT, RARI_CHAIN_ID, RARI_gUSDT, "gUSDT", 6, 6
            );
            console.log("  SUCCESS: Rise USDT mapping registered");
            
            // Rise WETH -> gWETH
            console.log("Registering Rise WETH -> gWETH...");
            tr.registerTokenMapping(
                RISE_CHAIN_ID, RISE_WETH, RARI_CHAIN_ID, RARI_gWETH, "gWETH", 18, 18
            );
            console.log("  SUCCESS: Rise WETH mapping registered");
            
            // Rise WBTC -> gWBTC
            console.log("Registering Rise WBTC -> gWBTC...");
            tr.registerTokenMapping(
                RISE_CHAIN_ID, RISE_WBTC, RARI_CHAIN_ID, RARI_gWBTC, "gWBTC", 8, 8
            );
            console.log("  SUCCESS: Rise WBTC mapping registered");
            console.log("");
            
            // Register Arbitrum mappings
            console.log("=== Registering Arbitrum Sepolia Mappings ===");
            
            // Arbitrum USDT -> gUSDT
            console.log("Registering Arbitrum USDT -> gUSDT...");
            tr.registerTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID, RARI_gUSDT, "gUSDT", 6, 6
            );
            console.log("  SUCCESS: Arbitrum USDT mapping registered");
            
            // Arbitrum WETH -> gWETH
            console.log("Registering Arbitrum WETH -> gWETH...");
            tr.registerTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID, RARI_gWETH, "gWETH", 18, 18
            );
            console.log("  SUCCESS: Arbitrum WETH mapping registered");
            
            // Arbitrum WBTC -> gWBTC
            console.log("Registering Arbitrum WBTC -> gWBTC...");
            tr.registerTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID, RARI_gWBTC, "gWBTC", 8, 8
            );
            console.log("  SUCCESS: Arbitrum WBTC mapping registered");
            
        } else {
            console.log("ERROR: Current caller is not SyntheticTokenFactory owner!");
            console.log("Expected owner:", stfOwner);
            console.log("Current caller:", tx.origin);
            console.log("");
            console.log("SOLUTION: Use the SyntheticTokenFactory owner private key");
            console.log("Or transfer ownership to current caller temporarily");
        }

        vm.stopBroadcast();
        
        console.log("");
        console.log("=== Verification ===");
        
        // Verify the mappings were created
        address riseUSDTMapping = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_USDT, RARI_CHAIN_ID);
        address arbUSDTMapping = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID);
        
        console.log("Rise USDT mapping result:", riseUSDTMapping);
        console.log("Arbitrum USDT mapping result:", arbUSDTMapping);
        
        if (riseUSDTMapping == RARI_gUSDT && arbUSDTMapping == RARI_gUSDT) {
            console.log("SUCCESS: Token mappings registered correctly!");
            console.log("Cross-chain deposits should now relay successfully!");
        } else {
            console.log("WARNING: Mappings may not have been registered properly");
        }
    }
}