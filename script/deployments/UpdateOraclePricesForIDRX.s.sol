// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import {IOracle} from "@scalexcore/interfaces/IOracle.sol";
import {Oracle} from "@scalexcore/Oracle.sol";

/**
 * @title UpdateOraclePricesForIDRX
 * @notice Update Oracle prices from USDC (6 decimals) to IDRX (2 decimals)
 * @dev Divides all prices by 10,000 to account for 4 decimal places difference
 */
contract UpdateOraclePricesForIDRX is Script, DeployHelpers {
    function run() external {
        loadDeployments();

        address oracle = deployed["Oracle"].addr;
        address sxWBTC = deployed["sxWBTC"].addr;
        address sxGOLD = deployed["sxGOLD"].addr;
        address sxSILVER = deployed["sxSILVER"].addr;
        address sxGOOGLE = deployed["sxGOOGLE"].addr;
        address sxNVIDIA = deployed["sxNVIDIA"].addr;
        address sxMNT = deployed["sxMNT"].addr;
        address sxAPPLE = deployed["sxAPPLE"].addr;

        console.log("=== Updating Oracle Prices for IDRX (2 decimals) ===");
        console.log("Oracle:", oracle);
        console.log("Converting from USDC (1e6) to IDRX (1e2) scaling");
        console.log("");

        uint256 deployerKey = getDeployerKey();
        vm.startBroadcast(deployerKey);

        // WBTC: $95,000 -> 95000e2 = 9,500,000
        console.log("Updating WBTC...");
        Oracle(oracle).setPrice(sxWBTC, 95000e2);
        console.log("  [OK] Set WBTC price: 9,500,000 (raw) = $95,000");

        // GOLD: $4,450 -> 4450e2 = 445,000
        console.log("Updating GOLD...");
        Oracle(oracle).setPrice(sxGOLD, 4450e2);
        console.log("  [OK] Set GOLD price: 445,000 (raw) = $4,450");

        // SILVER: $78 -> 78e2 = 7,800
        console.log("Updating SILVER...");
        Oracle(oracle).setPrice(sxSILVER, 78e2);
        console.log("  [OK] Set SILVER price: 7,800 (raw) = $78");

        // GOOGLE: $314 -> 314e2 = 31,400
        console.log("Updating GOOGLE...");
        Oracle(oracle).setPrice(sxGOOGLE, 314e2);
        console.log("  [OK] Set GOOGLE price: 31,400 (raw) = $314");

        // NVIDIA: $188 -> 188e2 = 18,800
        console.log("Updating NVIDIA...");
        Oracle(oracle).setPrice(sxNVIDIA, 188e2);
        console.log("  [OK] Set NVIDIA price: 18,800 (raw) = $188");

        // MNT: $1 -> 1e2 = 100
        console.log("Updating MNT...");
        Oracle(oracle).setPrice(sxMNT, 1e2);
        console.log("  [OK] Set MNT price: 100 (raw) = $1");

        // APPLE: $265 -> 265e2 = 26,500
        console.log("Updating APPLE...");
        Oracle(oracle).setPrice(sxAPPLE, 265e2);
        console.log("  [OK] Set APPLE price: 26,500 (raw) = $265");

        vm.stopBroadcast();

        // Verify
        console.log("");
        console.log("=== Verifying Updated Prices ===");
        
        uint256 wbtcPrice = IOracle(oracle).getSpotPrice(sxWBTC);
        console.log("WBTC raw price:", wbtcPrice);
        console.log("WBTC USD price:", wbtcPrice / 100);

        uint256 goldPrice = IOracle(oracle).getSpotPrice(sxGOLD);
        console.log("GOLD raw price:", goldPrice);
        console.log("GOLD USD price:", goldPrice / 100);

        uint256 silverPrice = IOracle(oracle).getSpotPrice(sxSILVER);
        console.log("SILVER raw price:", silverPrice);
        console.log("SILVER USD price:", silverPrice / 100);

        uint256 googlePrice = IOracle(oracle).getSpotPrice(sxGOOGLE);
        console.log("GOOGLE raw price:", googlePrice);
        console.log("GOOGLE USD price:", googlePrice / 100);

        uint256 nvidiaPrice = IOracle(oracle).getSpotPrice(sxNVIDIA);
        console.log("NVIDIA raw price:", nvidiaPrice);
        console.log("NVIDIA USD price:", nvidiaPrice / 100);

        uint256 mntPrice = IOracle(oracle).getSpotPrice(sxMNT);
        console.log("MNT raw price:", mntPrice);
        console.log("MNT USD price:", mntPrice / 100);

        uint256 applePrice = IOracle(oracle).getSpotPrice(sxAPPLE);
        console.log("APPLE raw price:", applePrice);
        console.log("APPLE USD price:", applePrice / 100);

        console.log("");
        console.log("=== Update Complete ===");
        console.log("All prices now use IDRX (2 decimals) scaling");
    }
}
