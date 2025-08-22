// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";

/**
 * @title SetupTokenMappings
 * @dev Configure token mappings and whitelist tokens on ChainBalanceManager contracts
 * @notice Reads addresses from deployment JSON files
 */
contract SetupTokenMappings is Script {
    
    function run() public {
        string memory network = vm.envString("NETWORK");
        
        vm.startBroadcast();
        
        // Read ChainBalanceManager address from deployment file
        string memory deploymentPath = string.concat("deployments/", network, ".json");
        string memory json = vm.readFile(deploymentPath);
        address cbmAddress = vm.parseJsonAddress(json, ".contracts.ChainBalanceManager");
        
        // Read source token addresses from same deployment file
        address usdt = vm.parseJsonAddress(json, ".contracts.USDT");
        address weth = vm.parseJsonAddress(json, ".contracts.WETH");
        address wbtc = vm.parseJsonAddress(json, ".contracts.WBTC");
        
        // Read Rari synthetic token addresses
        string memory rariJson = vm.readFile("deployments/rari.json");
        address gsUSDT = vm.parseJsonAddress(rariJson, ".contracts.gsUSDT");
        address gsWETH = vm.parseJsonAddress(rariJson, ".contracts.gsWETH");
        address gsWBTC = vm.parseJsonAddress(rariJson, ".contracts.gsWBTC");
        
        setupChain(cbmAddress, usdt, weth, wbtc, gsUSDT, gsWETH, gsWBTC, network);
        
        vm.stopBroadcast();
    }
    
    function setupChain(
        address cbmAddress, 
        address usdt,
        address weth,
        address wbtc,
        address gsUSDT, 
        address gsWETH, 
        address gsWBTC,
        string memory chainName
    ) internal {
        ChainBalanceManager cbm = ChainBalanceManager(cbmAddress);
        
        console.log("Setting up token mappings on", chainName);
        console.log("ChainBalanceManager:", cbmAddress);
        console.log("Source USDT:", usdt);
        console.log("Source WETH:", weth);
        console.log("Source WBTC:", wbtc);
        console.log("Target gsUSDT:", gsUSDT);
        console.log("Target gsWETH:", gsWETH);
        console.log("Target gsWBTC:", gsWBTC);
        
        // Whitelist tokens with error handling
        console.log("Whitelisting USDT...");
        try cbm.addToken(usdt) {
            console.log("SUCCESS: USDT whitelisted");
        } catch {
            console.log("USDT already whitelisted or failed");
        }
        
        console.log("Whitelisting WETH...");
        try cbm.addToken(weth) {
            console.log("SUCCESS: WETH whitelisted");
        } catch {
            console.log("WETH already whitelisted or failed");
        }
        
        console.log("Whitelisting WBTC...");
        try cbm.addToken(wbtc) {
            console.log("SUCCESS: WBTC whitelisted");
        } catch {
            console.log("WBTC already whitelisted or failed");
        }
        
        // Set token mappings
        console.log("Setting USDT -> gsUSDT mapping...");
        cbm.setTokenMapping(usdt, gsUSDT);
        
        console.log("Setting WETH -> gsWETH mapping...");
        cbm.setTokenMapping(weth, gsWETH);
        
        console.log("Setting WBTC -> gsWBTC mapping...");
        cbm.setTokenMapping(wbtc, gsWBTC);
        
        console.log("Token setup completed for", chainName);
        
        // Verify mappings
        console.log("=== Verification ===");
        console.log("USDT -> gsUSDT:", cbm.getTokenMapping(usdt));
        console.log("WETH -> gsWETH:", cbm.getTokenMapping(weth));
        console.log("WBTC -> gsWBTC:", cbm.getTokenMapping(wbtc));
        console.log("USDT whitelisted:", cbm.isTokenWhitelisted(usdt));
        console.log("WETH whitelisted:", cbm.isTokenWhitelisted(weth));
        console.log("WBTC whitelisted:", cbm.isTokenWhitelisted(wbtc));
    }
}