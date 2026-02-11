// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";

contract FixSupportedAssets is Script, DeployHelpers {
    function run() external {
        loadDeployments();

        uint256 deployerPrivateKey = getDeployerKey();
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== FIXING SUPPORTED ASSETS IN BALANCEMANAGER ===");
        console.log("Deployer:", deployer);
        console.log("");

        BalanceManager balanceManager = BalanceManager(deployed["BalanceManager"].addr);
        console.log("BalanceManager:", address(balanceManager));
        console.log("");

        // Get all token addresses
        address usdc = deployed["USDC"].addr;
        address weth = deployed["WETH"].addr;
        address wbtc = deployed["WBTC"].addr;
        address gold = deployed["GOLD"].addr;
        address silver = deployed["SILVER"].addr;
        address google = deployed["GOOGLE"].addr;
        address nvidia = deployed["NVIDIA"].addr;
        address mnt = deployed["MNT"].addr;
        address apple = deployed["APPLE"].addr;

        address sxUSDC = deployed["sxUSDC"].addr;
        address sxWETH = deployed["sxWETH"].addr;
        address sxWBTC = deployed["sxWBTC"].addr;
        address sxGOLD = deployed["sxGOLD"].addr;
        address sxSILVER = deployed["sxSILVER"].addr;
        address sxGOOGLE = deployed["sxGOOGLE"].addr;
        address sxNVIDIA = deployed["sxNVIDIA"].addr;
        address sxMNT = deployed["sxMNT"].addr;
        address sxAPPLE = deployed["sxAPPLE"].addr;

        console.log("Step 1: Checking current state...");
        address currentSxWETH = balanceManager.getSyntheticToken(weth);
        console.log("  Current getSyntheticToken(WETH):", currentSxWETH);

        if (currentSxWETH != address(0)) {
            console.log("  [OK] Synthetic tokens already configured!");
            console.log("  No changes needed.");
            return;
        }
        console.log("  [!] Synthetic tokens NOT configured. Fixing...");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Step 2: Adding supported assets...");

        balanceManager.addSupportedAsset(usdc, sxUSDC);
        console.log("  [OK] Added USDC -> sxUSDC");

        balanceManager.addSupportedAsset(weth, sxWETH);
        console.log("  [OK] Added WETH -> sxWETH");

        balanceManager.addSupportedAsset(wbtc, sxWBTC);
        console.log("  [OK] Added WBTC -> sxWBTC");

        balanceManager.addSupportedAsset(gold, sxGOLD);
        console.log("  [OK] Added GOLD -> sxGOLD");

        balanceManager.addSupportedAsset(silver, sxSILVER);
        console.log("  [OK] Added SILVER -> sxSILVER");

        balanceManager.addSupportedAsset(google, sxGOOGLE);
        console.log("  [OK] Added GOOGLE -> sxGOOGLE");

        balanceManager.addSupportedAsset(nvidia, sxNVIDIA);
        console.log("  [OK] Added NVIDIA -> sxNVIDIA");

        balanceManager.addSupportedAsset(mnt, sxMNT);
        console.log("  [OK] Added MNT -> sxMNT");

        balanceManager.addSupportedAsset(apple, sxAPPLE);
        console.log("  [OK] Added APPLE -> sxAPPLE");

        vm.stopBroadcast();

        console.log("");
        console.log("Step 3: Verifying fix...");
        currentSxWETH = balanceManager.getSyntheticToken(weth);
        console.log("  getSyntheticToken(WETH):", currentSxWETH);
        console.log("  Expected:", sxWETH);

        if (currentSxWETH == sxWETH) {
            console.log("  [SUCCESS] VERIFICATION PASSED!");
        } else {
            console.log("  [FAILED] VERIFICATION FAILED!");
        }

        console.log("");
        console.log("=== FIX COMPLETE ===");
    }
}
