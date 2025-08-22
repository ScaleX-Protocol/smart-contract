// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";

contract AddMissingTokens is Script {
    
    function run() public {
        vm.startBroadcast();
        
        ChainBalanceManager cbm = ChainBalanceManager(0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7);
        
        address weth = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
        address wbtc = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address gsWBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;
        
        console.log("Adding WETH...");
        cbm.addToken(weth);
        console.log("Setting WETH mapping...");
        cbm.setTokenMapping(weth, gsWETH);
        
        console.log("Adding WBTC...");
        cbm.addToken(wbtc);
        console.log("Setting WBTC mapping...");
        cbm.setTokenMapping(wbtc, gsWBTC);
        
        vm.stopBroadcast();
        
        console.log("=== Verification ===");
        console.log("WETH whitelisted:", cbm.isTokenWhitelisted(weth));
        console.log("WBTC whitelisted:", cbm.isTokenWhitelisted(wbtc));
        console.log("WETH mapping:", cbm.getTokenMapping(weth));
        console.log("WBTC mapping:", cbm.getTokenMapping(wbtc));
    }
}