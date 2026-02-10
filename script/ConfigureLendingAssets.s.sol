// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

interface ILendingManager {
    function configureAsset(
        address token,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor
    ) external;
}

contract ConfigureLendingAssets is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address lendingManager = 0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c;
        address sxIDRX = 0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624;
        address sxWETH = 0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6;

        console.log("=== CONFIGURING LENDING ASSETS ===");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Configure IDRX as collateral
        // - 80% collateral factor
        // - 85% liquidation threshold
        // - 5% liquidation bonus
        // - 10% reserve factor
        console.log("Configuring sxIDRX...");
        ILendingManager(lendingManager).configureAsset(
            sxIDRX,
            8000,  // 80% collateral factor
            8500,  // 85% liquidation threshold
            500,   // 5% liquidation bonus
            1000   // 10% reserve factor
        );
        console.log("sxIDRX configured!");

        // Configure WETH for borrowing
        // - 70% collateral factor (lower for volatile asset)
        // - 75% liquidation threshold
        // - 5% liquidation bonus
        // - 10% reserve factor
        console.log("Configuring sxWETH...");
        ILendingManager(lendingManager).configureAsset(
            sxWETH,
            7000,  // 70% collateral factor
            7500,  // 75% liquidation threshold
            500,   // 5% liquidation bonus
            1000   // 10% reserve factor
        );
        console.log("sxWETH configured!");

        vm.stopBroadcast();

        console.log("");
        console.log("=== CONFIGURATION COMPLETE ===");
        console.log("");
        console.log("You can now test auto-borrow!");
        console.log("With 100 IDRX collateral at 80% factor:");
        console.log("- Max borrow: ~$80 worth");
        console.log("- Your order (~$63 WETH) should work!");
    }
}
