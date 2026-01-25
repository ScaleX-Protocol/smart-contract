// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainBalanceManager} from "../../src/core/ChainBalanceManager.sol";

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
        address usdt = vm.parseJsonAddress(json, ".contracts.USDC");
        address weth = vm.parseJsonAddress(json, ".contracts.WETH");
        address wbtc = vm.parseJsonAddress(json, ".contracts.WBTC");
        
        // Read Rari synthetic token addresses
        string memory rariJson = vm.readFile("deployments/rari.json");
        address sxUSDC = vm.parseJsonAddress(rariJson, ".contracts.gsUSDC");
        address sxWETH = vm.parseJsonAddress(rariJson, ".contracts.gsWETH");
        address sxWBTC = vm.parseJsonAddress(rariJson, ".contracts.gsWBTC");
        
        setupChain(cbmAddress, usdt, weth, wbtc, sxUSDC, sxWETH, sxWBTC, network);
        
        vm.stopBroadcast();
    }
    
    function setupChain(
        address cbmAddress, 
        address usdt,
        address weth,
        address wbtc,
        address sxUSDC, 
        address sxWETH, 
        address sxWBTC,
        string memory chainName
    ) internal {
        ChainBalanceManager cbm = ChainBalanceManager(cbmAddress);
        
        console.log("Setting up token mappings on", chainName);
        console.log("ChainBalanceManager:", cbmAddress);
        console.log("Source USDC:", usdt);
        console.log("Source WETH:", weth);
        console.log("Source WBTC:", wbtc);
        console.log("Target sxUSDC:", sxUSDC);
        console.log("Target sxWETH:", sxWETH);
        console.log("Target sxWBTC:", sxWBTC);
        
        // Whitelist tokens with error handling
        console.log("Whitelisting USDC...");
        try cbm.addToken(usdt) {
            console.log("SUCCESS: USDC whitelisted");
        } catch {
            console.log("USDC already whitelisted or failed");
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
        console.log("Setting USDC -> sxUSDC mapping...");
        cbm.setTokenMapping(usdt, sxUSDC);
        
        console.log("Setting WETH -> sxWETH mapping...");
        cbm.setTokenMapping(weth, sxWETH);
        
        console.log("Setting WBTC -> sxWBTC mapping...");
        cbm.setTokenMapping(wbtc, sxWBTC);
        
        console.log("Token setup completed for", chainName);
        
        // Verify mappings
        console.log("=== Verification ===");
        console.log("USDC -> sxUSDC:", cbm.getTokenMapping(usdt));
        console.log("WETH -> sxWETH:", cbm.getTokenMapping(weth));
        console.log("WBTC -> sxWBTC:", cbm.getTokenMapping(wbtc));
        console.log("USDC whitelisted:", cbm.isTokenWhitelisted(usdt));
        console.log("WETH whitelisted:", cbm.isTokenWhitelisted(weth));
        console.log("WBTC whitelisted:", cbm.isTokenWhitelisted(wbtc));
    }
}