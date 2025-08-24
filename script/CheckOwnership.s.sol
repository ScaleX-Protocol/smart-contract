// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract CheckOwnership is Script {
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    address constant TOKEN_REGISTRY = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;
    address constant CURRENT_WALLET = 0x77C037fbF42e85dB1487B390b08f58C00f438812;

    function run() external view {
        console.log("=== Contract Ownership Check ===");
        console.log("Current Wallet:", CURRENT_WALLET);
        console.log("");

        IOwnable bm = IOwnable(BALANCE_MANAGER);
        IOwnable tr = IOwnable(TOKEN_REGISTRY);
        
        address bmOwner = bm.owner();
        address trOwner = tr.owner();
        
        console.log("BalanceManager Owner:", bmOwner);
        if (bmOwner == CURRENT_WALLET) {
            console.log("  Status: CURRENT WALLET IS OWNER");
        } else {
            console.log("  Status: DIFFERENT OWNER");
        }
        console.log("");
        
        console.log("TokenRegistry Owner:", trOwner);
        if (trOwner == CURRENT_WALLET) {
            console.log("  Status: CURRENT WALLET IS OWNER");
        } else {
            console.log("  Status: DIFFERENT OWNER - Cannot register tokens");
        }
        console.log("");
        
        console.log("=== REQUIRED ACTIONS ===");
        if (bmOwner != CURRENT_WALLET) {
            console.log("1. BalanceManager owner needs to call setTokenRegistry()");
        }
        if (trOwner != CURRENT_WALLET) {
            console.log("2. TokenRegistry owner needs to register Rise/Arbitrum mappings");
        }
        
        console.log("Or transfer ownership to current wallet to perform operations");
    }
}