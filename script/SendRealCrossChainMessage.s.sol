// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

interface MockERC20 {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract SendRealCrossChainMessage is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== SENDING REAL CROSS-CHAIN MESSAGE =========");
        console.log("User:", deployer);
        
        // Switch to Appchain
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        address usdtAddr = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        MockERC20 usdt = MockERC20(usdtAddr);
        
        console.log("ChainBalanceManager:", chainBalanceManagerAddr);
        console.log("USDT:", usdtAddr);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Check current USDT balance
        uint256 currentBalance = usdt.balanceOf(deployer);
        console.log("Current USDT balance:", currentBalance);
        
        // Step 2: Mint more USDT if needed
        if (currentBalance < 200e6) {
            uint256 mintAmount = 1000e6; // 1000 USDT
            console.log("Minting", mintAmount, "USDT...");
            
            try usdt.mint(deployer, mintAmount) {
                console.log("SUCCESS: Minted USDT");
            } catch Error(string memory reason) {
                console.log("Failed to mint USDT:", reason);
            }
        }
        
        // Check balance after minting
        uint256 newBalance = usdt.balanceOf(deployer);
        console.log("USDT balance after minting:", newBalance);
        
        // Step 3: Approve ChainBalanceManager
        uint256 depositAmount = 100e6; // 100 USDT
        console.log("Approving", depositAmount, "USDT for ChainBalanceManager...");
        
        try usdt.approve(chainBalanceManagerAddr, depositAmount) {
            console.log("SUCCESS: Approved USDT");
        } catch Error(string memory reason) {
            console.log("Failed to approve USDT:", reason);
            vm.stopBroadcast();
            return;
        }
        
        // Step 4: Send the actual cross-chain deposit
        console.log("=== SENDING CROSS-CHAIN DEPOSIT ===");
        console.log("Amount:", depositAmount);
        console.log("Recipient:", deployer);
        
        try cbm.deposit(usdtAddr, depositAmount, deployer) {
            console.log("SUCCESS: Cross-chain deposit sent!");
            console.log("Message dispatched to Rari BalanceManager");
            console.log("Check Hyperlane explorer in a few minutes");
        } catch Error(string memory reason) {
            console.log("Cross-chain deposit failed:", reason);
        } catch {
            console.log("Cross-chain deposit failed with unknown error");
        }
        
        vm.stopBroadcast();
        
        console.log("========== CROSS-CHAIN MESSAGE SENT =========");
        console.log("Now wait 2-5 minutes for Hyperlane relayers to process");
        console.log("Then run SimpleSystemCheck.s.sol to verify tokens arrived");
    }
}