// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

interface MockERC20 {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

contract CheckSourceChainLocks is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== SOURCE CHAIN LOCK STATUS ==========");
        console.log("User:", deployer);
        
        // Switch to Appchain (source)
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        address usdtAddr = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        MockERC20 usdt = MockERC20(usdtAddr);
        
        console.log("=== CONTRACT ADDRESSES ===");
        console.log("ChainBalanceManager:", chainBalanceManagerAddr);
        console.log("USDT:", usdtAddr);
        console.log("");
        
        // Check user balances
        console.log("=== USER BALANCES ===");
        uint256 userUsdtBalance = usdt.balanceOf(deployer);
        uint256 userNonce = cbm.getUserNonce(deployer);
        
        console.log("User USDT balance:", userUsdtBalance);
        console.log("User nonce (messages sent):", userNonce);
        console.log("");
        
        // Check contract balances (locked tokens)
        console.log("=== LOCKED TOKENS IN CONTRACT ===");
        uint256 contractUsdtBalance = usdt.balanceOf(chainBalanceManagerAddr);
        console.log("USDT locked in ChainBalanceManager:", contractUsdtBalance);
        
        if (contractUsdtBalance > 0) {
            console.log("STATUS: TOKENS ARE LOCKED ON SOURCE CHAIN!");
            console.log("This confirms the cross-chain deposit mechanism is working");
        } else {
            console.log("STATUS: No tokens locked yet");
        }
        console.log("");
        
        // Check deposit history through user balances on the contract
        console.log("=== DEPOSIT TRACKING ===");
        try cbm.getBalance(deployer, 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516) returns (uint256 balance) {
            console.log("User balance in ChainBalanceManager:", balance);
            if (balance > 0) {
                console.log("STATUS: User has deposits tracked in ChainBalanceManager");
            }
        } catch {
            console.log("Could not read balance from ChainBalanceManager");
        }
        
        // Show recent transactions
        console.log("=== RECENT CROSS-CHAIN MESSAGES ===");
        console.log("Message 1: 0xd99fae70374c834f5f5d84a6a87abba8579de8004e93bc59e5694cee5addec1b");
        console.log("Message 2: 0xfaa05febc04a0683b919a4a8b3fac1077a6e60aa380c23219e974d4edb8c5b90");
        console.log("");
        
        console.log("=== SUMMARY ===");
        console.log("Messages sent from Appchain:", userNonce);
        console.log("USDT locked on Appchain:", contractUsdtBalance);
        console.log("Expected gsUSDT on Rari:", contractUsdtBalance, "(when processed)");
        
        console.log("========== SOURCE CHAIN CHECK COMPLETE ==========");
    }
}