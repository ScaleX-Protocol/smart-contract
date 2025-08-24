// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/interfaces/IChainBalanceManager.sol";
import "../src/core/libraries/Currency.sol";

contract TestDeposits is Script {
    
    // Test recipient address
    address constant TEST_RECIPIENT = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
    
    // Test amounts (in wei for consistency)
    uint256 constant TEST_AMOUNT_USDT = 100_000000; // 100 USDT (6 decimals)
    uint256 constant TEST_AMOUNT_WBTC = 1_00000000; // 1 WBTC (8 decimals) 
    uint256 constant TEST_AMOUNT_WETH = 1_000000000000000000; // 1 WETH (18 decimals)
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== TESTING DEPOSITS ==========");
        console.log("Deployer:", deployer);
        console.log("Test recipient:", TEST_RECIPIENT);
        console.log("Network:", vm.toString(block.chainid));
        
        // This script works on Appchain to test cross-chain deposits to Rari
        if (block.chainid != 4661) {
            console.log("This script is designed to run on Appchain (4661) for cross-chain deposits");
            console.log("Current chain:", vm.toString(block.chainid));
            return;
        }
        
        console.log("Detected: Appchain Testnet (source chain for deposits)");
        
        // Read Appchain deployment data
        string memory deploymentData;
        try vm.readFile("deployments/appchain.json") returns (string memory data) {
            deploymentData = data;
            console.log("Reading Appchain deployment data");
        } catch {
            console.log("ERROR: Could not read deployments/appchain.json");
            return;
        }
        
        // Get ChainBalanceManager and source token addresses
        address chainBalanceManager;
        address sourceUSDT;
        address sourceWBTC;
        address sourceWETH;
        
        try vm.parseJsonAddress(deploymentData, ".contracts.ChainBalanceManager") returns (address addr) {
            chainBalanceManager = addr;
        } catch {
            try vm.parseJsonAddress(deploymentData, ".PROXY_CHAINBALANCEMANAGER") returns (address addr) {
                chainBalanceManager = addr;
            } catch {
                console.log("ERROR: Could not find ChainBalanceManager");
                return;
            }
        }
        
        try vm.parseJsonAddress(deploymentData, ".contracts.USDT") returns (address addr) {
            sourceUSDT = addr;
        } catch {
            try vm.parseJsonAddress(deploymentData, ".USDT") returns (address addr) {
                sourceUSDT = addr;
            } catch {
                console.log("WARNING: Could not find source USDT");
            }
        }
        
        try vm.parseJsonAddress(deploymentData, ".contracts.WBTC") returns (address addr) {
            sourceWBTC = addr;
        } catch {
            try vm.parseJsonAddress(deploymentData, ".WBTC") returns (address addr) {
                sourceWBTC = addr;
            } catch {
                console.log("WARNING: Could not find source WBTC");
            }
        }
        
        try vm.parseJsonAddress(deploymentData, ".contracts.WETH") returns (address addr) {
            sourceWETH = addr;
        } catch {
            try vm.parseJsonAddress(deploymentData, ".WETH") returns (address addr) {
                sourceWETH = addr;
            } catch {
                console.log("WARNING: Could not find source WETH");
            }
        }
        
        console.log("");
        console.log("=== CONTRACT ADDRESSES ===");
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Source USDT:", sourceUSDT);
        console.log("Source WBTC:", sourceWBTC);
        console.log("Source WETH:", sourceWETH);
        console.log("");
        
        IChainBalanceManager cbm = IChainBalanceManager(chainBalanceManager);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Test deposit USDT (only configured token mapping)
        if (sourceUSDT != address(0)) {
            console.log("=== TESTING USDT DEPOSIT ===");
            console.log("Amount:", TEST_AMOUNT_USDT, "USDT (has token mapping)");
            
            // Check if token is whitelisted first
            try cbm.isTokenWhitelisted(sourceUSDT) returns (bool isWhitelisted) {
                console.log("Token whitelisted:", isWhitelisted);
                if (!isWhitelisted) {
                    console.log("SKIPPING: Token not whitelisted");
                    return;
                }
            } catch {
                console.log("Could not check whitelist status");
            }
            
            try cbm.deposit(sourceUSDT, TEST_AMOUNT_USDT, TEST_RECIPIENT) {
                console.log("SUCCESS: USDT deposit completed");
                console.log("Cross-chain message sent to Rari");
            } catch Error(string memory reason) {
                console.log("FAILED: USDT deposit failed -", reason);
            } catch {
                console.log("FAILED: USDT deposit failed - Unknown error");
            }
            console.log("");
        }
        
        // WBTC and WETH are not configured yet - skip for now
        console.log("=== SKIPPING WBTC and WETH ===");
        console.log("Token mappings not configured yet for WBTC and WETH");
        console.log("Only USDT has proper cross-chain mapping configured");
        console.log("");
        
        vm.stopBroadcast();
        
        console.log("=== DEPOSIT TESTING COMPLETE ===");
        console.log("Cross-chain messages have been sent to Rari");
        console.log("Wait ~30 seconds for Hyperlane message delivery");
        console.log("Then run CheckTokenBalances.s.sol on Rari to verify");
        console.log("");
        console.log("Expected Results on Rari:");
        console.log("- BalanceManager internal balance for", TEST_RECIPIENT, "should increase");
        console.log("- BalanceManager ERC20 balance should hold the minted synthetic tokens");
        console.log("- User ERC20 wallet balance should remain 0 (correct pattern)");
        console.log("- Total supply of synthetic tokens should increase");
        
        console.log("========== DEPOSIT TESTS COMPLETE ==========");
    }
}