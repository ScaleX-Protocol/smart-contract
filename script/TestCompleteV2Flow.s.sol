// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/GTXRouter.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

interface IERC20Extended {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract TestCompleteV2Flow is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== TESTING COMPLETE V2 FLOW ==========");
        console.log("User:", deployer);
        console.log("Testing: Deposit -> Mint -> Balance Sync -> Trade");
        console.log("");
        
        // Switch to Rari
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        // Contract addresses
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address routerAddr = 0xF38489749c3e65c82a9273c498A8c6614c34754b;
        address gsUSDT = 0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7;
        address gsWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        
        BalanceManager balanceManager = BalanceManager(balanceManagerAddr);
        GTXRouter router = GTXRouter(routerAddr);
        
        Currency usdtCurrency = Currency.wrap(gsUSDT);
        Currency wethCurrency = Currency.wrap(gsWETH);
        
        console.log("=== LATEST CROSS-CHAIN MESSAGE ===");
        console.log("Message ID: 0xe8b4ee6b7ccf3401080241ea2d3527707d312b4e0daac88d45dfba6c9713b21c");
        console.log("Amount: 100 USDT (100,000,000 units)");
        console.log("Expected: Real ERC20 token minting with V2 system");
        console.log("");
        
        // Check user balances
        console.log("=== STEP 1: CHECK CURRENT BALANCES ===");
        
        uint256 internalUsdtBalance = balanceManager.getBalance(deployer, usdtCurrency);
        uint256 internalWethBalance = balanceManager.getBalance(deployer, wethCurrency);
        uint256 userNonce = balanceManager.getUserNonce(deployer);
        
        console.log("User nonce (messages processed):", userNonce);
        console.log("Internal BalanceManager balances:");
        console.log("- gsUSDT:", internalUsdtBalance);
        console.log("- gsWETH:", internalWethBalance);
        console.log("");
        
        // Try to check ERC20 balances
        console.log("=== STEP 2: CHECK ERC20 TOKEN BALANCES ===");
        
        uint256 erc20UsdtBalance = 0;
        uint256 erc20WethBalance = 0;
        uint256 usdtTotalSupply = 0;
        uint256 wethTotalSupply = 0;
        
        // Check gsUSDT ERC20 
        try IERC20Extended(gsUSDT).balanceOf(deployer) returns (uint256 bal) {
            erc20UsdtBalance = bal;
            console.log("gsUSDT ERC20 balance:", bal);
            
            try IERC20Extended(gsUSDT).totalSupply() returns (uint256 supply) {
                usdtTotalSupply = supply;
                console.log("gsUSDT total supply:", supply);
            } catch {
                console.log("gsUSDT total supply: Not readable");
            }
        } catch {
            console.log("gsUSDT: Not accessible as ERC20 (not deployed yet)");
        }
        
        // Check gsWETH ERC20
        try IERC20Extended(gsWETH).balanceOf(deployer) returns (uint256 bal) {
            erc20WethBalance = bal;
            console.log("gsWETH ERC20 balance:", bal);
            
            try IERC20Extended(gsWETH).totalSupply() returns (uint256 supply) {
                wethTotalSupply = supply;
                console.log("gsWETH total supply:", supply);
            } catch {
                console.log("gsWETH total supply: Not readable");
            }
            
            try IERC20Extended(gsWETH).name() returns (string memory name) {
                console.log("gsWETH name:", name);
            } catch {
                console.log("gsWETH name: Not readable");
            }
        } catch {
            console.log("gsWETH: Not accessible as ERC20");
        }
        
        console.log("");
        
        // Check balance synchronization
        console.log("=== STEP 3: VERIFY BALANCE SYNCHRONIZATION ===");
        
        if (userNonce > 0) {
            console.log("Cross-chain messages processed:", userNonce);
            
            if (internalUsdtBalance > 0) {
                console.log("Internal balance exists:", internalUsdtBalance);
                
                if (erc20UsdtBalance > 0) {
                    console.log("ERC20 balance exists:", erc20UsdtBalance);
                    
                    if (internalUsdtBalance == erc20UsdtBalance) {
                        console.log("SUCCESS: Balances are synchronized!");
                        console.log("V2 token minting working correctly");
                    } else {
                        console.log("WARNING: Balance mismatch");
                        console.log("Internal:", internalUsdtBalance, "vs ERC20:", erc20UsdtBalance);
                    }
                } else {
                    console.log("INFO: Internal balance exists but no ERC20 tokens");
                    console.log("This suggests V1 processing or gsUSDT not deployed as ERC20");
                }
            } else {
                console.log("No internal balance - messages may still be processing");
            }
        } else {
            console.log("Cross-chain messages still processing...");
            console.log("Expected: User nonce should become 5");
        }
        
        console.log("");
        
        // Test trading if tokens are available
        console.log("=== STEP 4: TEST TRADING FUNCTIONALITY ===");
        
        if (internalUsdtBalance >= 10000000) { // At least 10 USDT for trading
            console.log("Sufficient balance for trading test");
            console.log("Attempting small swap: 5 USDT -> WETH");
            
            vm.startBroadcast(deployerPrivateKey);
            
            uint256 swapAmount = 5000000; // 5 USDT
            
            try router.swap(
                usdtCurrency,
                wethCurrency,
                swapAmount,
                0, // minOut - accept any amount
                1, // fee tier
                deployer
            ) {
                console.log("SUCCESS: Swap executed!");
                
                // Check new balances
                uint256 newUsdtBalance = balanceManager.getBalance(deployer, usdtCurrency);
                uint256 newWethBalance = balanceManager.getBalance(deployer, wethCurrency);
                
                console.log("New gsUSDT balance:", newUsdtBalance);
                console.log("New gsWETH balance:", newWethBalance);
                console.log("gsWETH received:", newWethBalance - internalWethBalance);
                
                console.log("TRADING SYSTEM FULLY OPERATIONAL!");
                
            } catch Error(string memory reason) {
                console.log("Swap failed:", reason);
                console.log("This may be due to insufficient liquidity or pool configuration");
            } catch {
                console.log("Swap failed with unknown error");
            }
            
            vm.stopBroadcast();
        } else {
            console.log("Insufficient balance for trading test");
            console.log("Need at least 10 USDT, have:", internalUsdtBalance);
        }
        
        console.log("");
        
        // Summary
        console.log("=== TEST SUMMARY ===");
        console.log("1. Cross-chain deposit: SENT (message 4)");
        console.log("2. Message processing:", userNonce > 0 ? "PROCESSED" : "PENDING");
        console.log("3. Token minting:", erc20UsdtBalance > 0 ? "SUCCESS" : "PENDING/NOT_DEPLOYED");
        console.log("4. Balance sync:", (internalUsdtBalance > 0 && erc20UsdtBalance == internalUsdtBalance) ? "SYNCHRONIZED" : "PENDING");
        console.log("5. Trading ready:", internalUsdtBalance >= 10000000 ? "YES" : "WAITING_FOR_TOKENS");
        
        console.log("");
        console.log("=== NEXT STEPS ===");
        if (userNonce == 0) {
            console.log("1. Wait for Hyperlane relayers to process message (2-5 minutes)");
            console.log("2. Message should mint real ERC20 tokens with V2 system");
        } else if (erc20UsdtBalance == 0 && internalUsdtBalance > 0) {
            console.log("1. Deploy actual gsUSDT ERC20 contract");
            console.log("2. Configure BalanceManager as minter");
            console.log("3. Re-test token minting flow");
        } else if (internalUsdtBalance >= 10000000) {
            console.log("1. System ready for full trading");
            console.log("2. Can test limit orders, market orders");
            console.log("3. Can test cross-chain withdrawals");
        }
        
        console.log("========== V2 FLOW TEST COMPLETE ==========");
    }
}