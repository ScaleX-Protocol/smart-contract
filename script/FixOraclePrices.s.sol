// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

interface IOracle {
    function setPrice(address token, uint256 price) external;
    function getSpotPrice(address token) external view returns (uint256);
}

contract FixOraclePrices is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address oracle = 0x83187ccD22D4e8DFf2358A09750331775A207E13;
        address sxIDRX = 0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624;
        address sxWETH = 0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6;

        // Correct prices (8 decimals for USD)
        // 1 IDRX = 1/15000 USD = $0.0000666... ≈ 6666 (8 decimals)
        // But if treating as $1 per IDRX: 100000000 (8 decimals)
        uint256 correctIDRXPrice = 100000000; // $1.00 per sxIDRX
        uint256 correctWETHPrice = 300000000000; // $3000.00 per sxWETH

        console.log("=== FIXING ORACLE PRICES ===");
        console.log("Oracle:", oracle);
        console.log("");

        console.log("Current prices:");
        console.log("sxIDRX:", IOracle(oracle).getSpotPrice(sxIDRX));
        console.log("sxWETH:", IOracle(oracle).getSpotPrice(sxWETH));
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Set correct prices
        console.log("Setting correct prices...");
        IOracle(oracle).setPrice(sxIDRX, correctIDRXPrice);
        console.log("sxIDRX price set to:", correctIDRXPrice);

        IOracle(oracle).setPrice(sxWETH, correctWETHPrice);
        console.log("sxWETH price set to:", correctWETHPrice);

        vm.stopBroadcast();

        console.log("");
        console.log("New prices:");
        console.log("sxIDRX:", IOracle(oracle).getSpotPrice(sxIDRX));
        console.log("sxWETH:", IOracle(oracle).getSpotPrice(sxWETH));
        console.log("");
        console.log("Oracle prices fixed!");
    }
}
