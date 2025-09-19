// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface ITokenRegistry {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function registerTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address syntheticToken,
        string memory symbol,
        uint8 sourceDecimals,
        uint8 syntheticDecimals
    ) external;
}

contract FixTokenMappingsWithOwnership is Script {
    address constant TOKEN_REGISTRY = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;
    address constant SYNTHETIC_TOKEN_FACTORY = 0x2594C4ca1B552ad573bcc0C4c561FAC6a87987fC;
    
    // Chain IDs
    uint32 constant RARI_CHAIN_ID = 1918988905;
    uint32 constant RISE_CHAIN_ID = 11155931;
    uint32 constant ARBITRUM_CHAIN_ID = 421614;
    
    // Rise source tokens -> Rari synthetic tokens
    address constant RISE_USDT = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;
    address constant RISE_WETH = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
    address constant RISE_WBTC = 0xc6b3109e45F7A479Ac324e014b6a272e4a25bF0E;
    
    // Arbitrum source tokens -> Rari synthetic tokens  
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

        console.log("=== Fixing Token Mappings with Ownership Transfer ===");
        console.log("TokenRegistry:", TOKEN_REGISTRY);
        console.log("");

        ITokenRegistry tr = ITokenRegistry(TOKEN_REGISTRY);
        
        // Step 1: Transfer ownership to deployer temporarily
        address currentOwner = tr.owner();
        console.log("Current TokenRegistry owner:", currentOwner);
        console.log("Transferring ownership to deployer temporarily...");
        
        tr.transferOwnership(msg.sender);
        console.log("TokenRegistry ownership transferred to:", msg.sender);
        console.log("");
        
        // Step 2: Register Rise token mappings
        console.log("Registering Rise Sepolia token mappings...");
        
        tr.registerTokenMapping(
            RISE_CHAIN_ID, RISE_USDT, RARI_CHAIN_ID, RARI_gUSDT, "gUSDT", 6, 6
        );
        console.log("  Rise USDT -> gUSDT mapping registered");
        
        tr.registerTokenMapping(
            RISE_CHAIN_ID, RISE_WETH, RARI_CHAIN_ID, RARI_gWETH, "gWETH", 18, 18
        );
        console.log("  Rise WETH -> gWETH mapping registered");
        
        tr.registerTokenMapping(
            RISE_CHAIN_ID, RISE_WBTC, RARI_CHAIN_ID, RARI_gWBTC, "gWBTC", 8, 8
        );
        console.log("  Rise WBTC -> gWBTC mapping registered");
        console.log("");
        
        // Step 3: Register Arbitrum token mappings
        console.log("Registering Arbitrum Sepolia token mappings...");
        
        tr.registerTokenMapping(
            ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID, RARI_gUSDT, "gUSDT", 6, 6
        );
        console.log("  Arbitrum USDT -> gUSDT mapping registered");
        
        tr.registerTokenMapping(
            ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID, RARI_gWETH, "gWETH", 18, 18
        );
        console.log("  Arbitrum WETH -> gWETH mapping registered");
        
        tr.registerTokenMapping(
            ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID, RARI_gWBTC, "gWBTC", 8, 8
        );
        console.log("  Arbitrum WBTC -> gWBTC mapping registered");
        console.log("");
        
        // Step 4: Transfer ownership back to original owner
        console.log("Transferring TokenRegistry ownership back to:", currentOwner);
        tr.transferOwnership(currentOwner);
        console.log("TokenRegistry ownership restored");

        vm.stopBroadcast();
        
        console.log("");
        console.log("=== Token Mapping Fix Complete ===");
        console.log("Rise and Arbitrum token mappings registered!");
        console.log("Cross-chain deposits should now relay successfully!");
    }
}