// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract CheckSyntheticFactoryOwner is Script {
    address constant SYNTHETIC_TOKEN_FACTORY = 0x2594C4ca1B552ad573bcc0C4c561FAC6a87987fC;
    address constant TOKEN_REGISTRY = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;
    address constant CURRENT_WALLET = 0x77C037fbF42e85dB1487B390b08f58C00f438812;

    function run() external view {
        console.log("=== SyntheticTokenFactory & TokenRegistry Ownership ===");
        console.log("Current Wallet:", CURRENT_WALLET);
        console.log("");

        IOwnable stf = IOwnable(SYNTHETIC_TOKEN_FACTORY);
        IOwnable tr = IOwnable(TOKEN_REGISTRY);
        
        address stfOwner = stf.owner();
        address trOwner = tr.owner();
        
        console.log("SyntheticTokenFactory:", SYNTHETIC_TOKEN_FACTORY);
        console.log("  Owner:", stfOwner);
        if (stfOwner == CURRENT_WALLET) {
            console.log("  Status: CURRENT WALLET IS OWNER - CAN REGISTER MAPPINGS!");
        } else {
            console.log("  Status: Different owner - cannot register directly");
        }
        console.log("");
        
        console.log("TokenRegistry:", TOKEN_REGISTRY);
        console.log("  Owner:", trOwner);
        if (trOwner == CURRENT_WALLET) {
            console.log("  Status: CURRENT WALLET IS OWNER - CAN REGISTER DIRECTLY!");
        } else if (trOwner == SYNTHETIC_TOKEN_FACTORY) {
            console.log("  Status: Owned by SyntheticTokenFactory - need STF owner");
        } else {
            console.log("  Status: Different owner - cannot register");
        }
        console.log("");
        
        console.log("=== ACTION PLAN ===");
        if (stfOwner == CURRENT_WALLET) {
            console.log("SUCCESS: Use RegisterTokenMappingsViaSyntheticFactory.s.sol script");
            console.log("SUCCESS: Current wallet can register token mappings");
        } else if (trOwner == CURRENT_WALLET) {
            console.log("SUCCESS: Use FixTokenRegistryIssues.s.sol script");
            console.log("SUCCESS: Current wallet owns TokenRegistry directly");
        } else {
            console.log("ERROR: Cannot register token mappings with current wallet");
            console.log("ERROR: Need to use the owner's private key or get ownership");
            console.log("   STF Owner:", stfOwner);
            console.log("   TR Owner:", trOwner);
        }
    }
}