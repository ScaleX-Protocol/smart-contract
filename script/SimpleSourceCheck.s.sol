// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface MockERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IChainBalanceManager {
    function getUserNonce(address user) external view returns (uint256);
}

contract SimpleSourceCheck is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== SOURCE CHAIN QUICK CHECK ==========");
        
        // Switch to Appchain
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        address usdtAddr = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        
        MockERC20 usdt = MockERC20(usdtAddr);
        IChainBalanceManager cbm = IChainBalanceManager(chainBalanceManagerAddr);
        
        // Check balances
        uint256 userBalance = usdt.balanceOf(deployer);
        uint256 contractBalance = usdt.balanceOf(chainBalanceManagerAddr);
        uint256 userNonce = cbm.getUserNonce(deployer);
        
        console.log("User USDT balance:", userBalance);
        console.log("Contract locked USDT:", contractBalance);
        console.log("Messages sent:", userNonce);
        
        if (contractBalance > 0) {
            console.log("SUCCESS: Tokens are locked on source chain!");
        } else {
            console.log("No tokens locked yet");
        }
        
        console.log("========== SOURCE CHECK COMPLETE ==========");
    }
}