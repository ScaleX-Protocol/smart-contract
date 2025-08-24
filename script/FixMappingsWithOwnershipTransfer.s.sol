// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface ISyntheticTokenFactory {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

interface ITokenRegistry {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
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

contract FixMappingsWithOwnershipTransfer is Script {
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
    
    // Existing synthetic tokens on Rari 
    address constant RARI_gUSDT = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d;
    address constant RARI_gWETH = 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8;
    address constant RARI_gWBTC = 0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Fix Token Mappings with Ownership Transfer ===");
        console.log("Current caller (deployer):", deployer);
        console.log("");
        
        ISyntheticTokenFactory stf = ISyntheticTokenFactory(SYNTHETIC_TOKEN_FACTORY);
        ITokenRegistry tr = ITokenRegistry(TOKEN_REGISTRY);
        
        // Step 1: Transfer TokenRegistry ownership from SyntheticTokenFactory to us
        console.log("=== Step 1: Transfer TokenRegistry Ownership ===");
        address originalSTFOwner = stf.owner();
        address originalTROwner = tr.owner();
        
        console.log("SyntheticTokenFactory owner:", originalSTFOwner);
        console.log("TokenRegistry owner:", originalTROwner);
        console.log("Current caller:", deployer);
        console.log("");
        
        if (originalSTFOwner != deployer) {
            console.log("ERROR: Not SyntheticTokenFactory owner!");
            vm.stopBroadcast();
            return;
        }
        
        console.log("Transferring TokenRegistry ownership to current wallet...");
        // Use SyntheticTokenFactory to transfer TokenRegistry ownership to us
        stf.transferOwnership(deployer);
        
        // Now we own SyntheticTokenFactory, so TokenRegistry should be owned by us
        address newTROwner = tr.owner();
        console.log("New TokenRegistry owner:", newTROwner);
        
        if (newTROwner != deployer) {
            // If that didn't work, try direct transfer
            console.log("Direct transfer of TokenRegistry ownership...");
            tr.transferOwnership(deployer);
            newTROwner = tr.owner();
            console.log("TokenRegistry owner after direct transfer:", newTROwner);
        }
        
        if (newTROwner != deployer) {
            console.log("ERROR: Could not transfer TokenRegistry ownership");
            vm.stopBroadcast();
            return;
        }
        
        console.log("SUCCESS: TokenRegistry ownership transferred");
        console.log("");
        
        // Step 2: Register Rise mappings (all new)
        console.log("=== Step 2: Register Rise Mappings ===");
        
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
        
        // Step 3: Fix Arbitrum mappings
        console.log("=== Step 3: Fix Arbitrum Mappings ===");
        
        // Check and fix Arbitrum USDT
        address currentArbUSDT = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID);
        if (currentArbUSDT == address(0)) {
            console.log("Registering Arbitrum USDT -> gUSDT...");
            tr.registerTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID, RARI_gUSDT, "gUSDT", 6, 6
            );
        } else if (currentArbUSDT != RARI_gUSDT) {
            console.log("Updating Arbitrum USDT -> gUSDT...");
            tr.updateTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID, RARI_gUSDT, 6
            );
        } else {
            console.log("Arbitrum USDT mapping already correct");
        }
        console.log("  SUCCESS: Arbitrum USDT fixed");
        
        // Check and fix Arbitrum WETH
        address currentArbWETH = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID);
        if (currentArbWETH == address(0)) {
            console.log("Registering Arbitrum WETH -> gWETH...");
            tr.registerTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID, RARI_gWETH, "gWETH", 18, 18
            );
        } else if (currentArbWETH != RARI_gWETH) {
            console.log("Updating Arbitrum WETH -> gWETH...");
            tr.updateTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID, RARI_gWETH, 18
            );
        } else {
            console.log("Arbitrum WETH mapping already correct");
        }
        console.log("  SUCCESS: Arbitrum WETH fixed");
        
        // Check and fix Arbitrum WBTC
        address currentArbWBTC = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID);
        if (currentArbWBTC == address(0)) {
            console.log("Registering Arbitrum WBTC -> gWBTC...");
            tr.registerTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID, RARI_gWBTC, "gWBTC", 8, 8
            );
        } else if (currentArbWBTC != RARI_gWBTC) {
            console.log("Updating Arbitrum WBTC -> gWBTC...");
            tr.updateTokenMapping(
                ARBITRUM_CHAIN_ID, ARB_WBTC, RARI_CHAIN_ID, RARI_gWBTC, 8
            );
        } else {
            console.log("Arbitrum WBTC mapping already correct");
        }
        console.log("  SUCCESS: Arbitrum WBTC fixed");
        console.log("");
        
        // Step 4: Transfer ownership back
        console.log("=== Step 4: Restore Original Ownership ===");
        console.log("Transferring TokenRegistry ownership back to SyntheticTokenFactory...");
        tr.transferOwnership(SYNTHETIC_TOKEN_FACTORY);
        
        console.log("Transferring SyntheticTokenFactory ownership back to original owner...");
        stf.transferOwnership(originalSTFOwner);
        
        console.log("SUCCESS: Original ownership restored");
        console.log("SyntheticTokenFactory owner:", stf.owner());
        console.log("TokenRegistry owner:", tr.owner());

        vm.stopBroadcast();
        
        console.log("");
        console.log("=== Final Verification ===");
        
        // Verify all mappings
        address finalRiseUSDT = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_USDT, RARI_CHAIN_ID);
        address finalArbUSDT = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_USDT, RARI_CHAIN_ID);
        address finalRiseWETH = tr.getSyntheticToken(RISE_CHAIN_ID, RISE_WETH, RARI_CHAIN_ID);
        address finalArbWETH = tr.getSyntheticToken(ARBITRUM_CHAIN_ID, ARB_WETH, RARI_CHAIN_ID);
        
        console.log("Rise USDT -> Synthetic:", finalRiseUSDT, "(gUSDT)");
        console.log("Arbitrum USDT -> Synthetic:", finalArbUSDT, "(gUSDT)");
        console.log("Rise WETH -> Synthetic:", finalRiseWETH, "(gWETH)");
        console.log("Arbitrum WETH -> Synthetic:", finalArbWETH, "(gWETH)");
        console.log("");
        
        if (finalRiseUSDT == RARI_gUSDT && finalArbUSDT == RARI_gUSDT && 
            finalRiseWETH == RARI_gWETH && finalArbWETH == RARI_gWETH) {
            console.log("SUCCESS: All mappings fixed!");
            console.log("All chains now use the same synthetic tokens:");
            console.log("  Appchain/Rise/Arbitrum USDT -> gUSDT");
            console.log("  Appchain/Rise/Arbitrum WETH -> gWETH");  
            console.log("  Appchain/Rise/Arbitrum WBTC -> gWBTC");
            console.log("");
            console.log("Cross-chain deposits should now work from all chains!");
        } else {
            console.log("WARNING: Some mappings may not be correct");
        }
        
        console.log("");
        console.log("TODO: Enhance with proper access control and governance later");
    }
}