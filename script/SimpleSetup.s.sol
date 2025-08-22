// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";

/**
 * @title SimpleSetup
 * @dev Just whitelist token and set mapping
 */
contract SimpleSetup is Script {
    
    address constant APPCHAIN_CBM = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
    address constant APPCHAIN_USDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
    address constant RARI_GSUSDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
    
    function run() public {
        vm.startBroadcast();
        
        ChainBalanceManager cbm = ChainBalanceManager(APPCHAIN_CBM);
        
        console.log("Whitelisting USDT...");
        cbm.addToken(APPCHAIN_USDT);
        console.log("USDT whitelisted");
        
        console.log("Setting token mapping...");
        cbm.setTokenMapping(APPCHAIN_USDT, RARI_GSUSDT);
        console.log("Token mapping set");
        
        vm.stopBroadcast();
    }
}