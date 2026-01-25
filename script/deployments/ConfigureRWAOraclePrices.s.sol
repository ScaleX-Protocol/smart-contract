// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import {IOracle} from "@scalexcore/interfaces/IOracle.sol";
import {Oracle} from "@scalexcore/Oracle.sol";

/**
 * @title ConfigureRWAOraclePrices
 * @notice Configure oracle prices for NVIDIA, MNT, and APPLE tokens
 */
contract ConfigureRWAOraclePrices is Script, DeployHelpers {
    function run() external {
        loadDeployments();

        address oracle = deployed["Oracle"].addr;
        address sxNVIDIA = deployed["sxNVIDIA"].addr;
        address sxMNT = deployed["sxMNT"].addr;
        address sxAPPLE = deployed["sxAPPLE"].addr;
        address nvidiaPool = deployed["NVIDIA_USDC_Pool"].addr;
        address mntPool = deployed["MNT_USDC_Pool"].addr;
        address applePool = deployed["APPLE_USDC_Pool"].addr;

        console.log("=== Configuring RWA Oracle Prices ===");
        console.log("Oracle:", oracle);
        console.log("");

        uint256 deployerKey = getDeployerKey();
        vm.startBroadcast(deployerKey);

        // NVIDIA: $188
        console.log("Configuring NVIDIA...");
        try IOracle(oracle).addToken(sxNVIDIA, 0) {
            console.log("  [OK] Added sxNVIDIA to oracle");
        } catch {
            console.log("  [INFO] sxNVIDIA already added to oracle");
        }

        IOracle(oracle).setTokenOrderBook(sxNVIDIA, nvidiaPool);
        console.log("  [OK] Set NVIDIA orderbook");

        Oracle(oracle).setPrice(sxNVIDIA, 188e6); // $188
        console.log("  [OK] Set NVIDIA price: $188");

        // MNT: $1
        console.log("");
        console.log("Configuring MNT...");
        try IOracle(oracle).addToken(sxMNT, 0) {
            console.log("  [OK] Added sxMNT to oracle");
        } catch {
            console.log("  [INFO] sxMNT already added to oracle");
        }

        IOracle(oracle).setTokenOrderBook(sxMNT, mntPool);
        console.log("  [OK] Set MNT orderbook");

        Oracle(oracle).setPrice(sxMNT, 1e6); // $1
        console.log("  [OK] Set MNT price: $1");

        // APPLE: $265
        console.log("");
        console.log("Configuring APPLE...");
        try IOracle(oracle).addToken(sxAPPLE, 0) {
            console.log("  [OK] Added sxAPPLE to oracle");
        } catch {
            console.log("  [INFO] sxAPPLE already added to oracle");
        }

        IOracle(oracle).setTokenOrderBook(sxAPPLE, applePool);
        console.log("  [OK] Set APPLE orderbook");

        Oracle(oracle).setPrice(sxAPPLE, 265e6); // $265
        console.log("  [OK] Set APPLE price: $265");

        vm.stopBroadcast();

        // Verify
        console.log("");
        console.log("=== Verifying Prices ===");
        uint256 nvidiaPrice = IOracle(oracle).getSpotPrice(sxNVIDIA);
        console.log("NVIDIA price:", nvidiaPrice / 1e6, "USD");

        uint256 mntPrice = IOracle(oracle).getSpotPrice(sxMNT);
        console.log("MNT price:", mntPrice / 1e6, "USD");

        uint256 applePrice = IOracle(oracle).getSpotPrice(sxAPPLE);
        console.log("APPLE price:", applePrice / 1e6, "USD");

        console.log("");
        console.log("=== Configuration Complete ===");
    }
}
