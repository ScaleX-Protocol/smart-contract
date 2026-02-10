// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

interface IOracle {
    function setPrice(address token, uint256 price) external;
    function getSpotPrice(address token) external view returns (uint256);
    function setAuthorizedOrderBook(address token, address orderBook, bool authorized) external;
    function tokenOrderBooks(address token) external view returns (address);
}

/**
 * @title FixOraclePricesPermanent
 * @notice Fixes oracle prices and disables automatic updates from OrderBook trades
 * @dev This prevents trades at wrong prices from overwriting manually set correct prices
 */
contract FixOraclePricesPermanent is Script {
    // Base Sepolia addresses
    address constant ORACLE = 0x83187ccD22D4e8DFf2358A09750331775A207E13;
    address constant SXIDRX = 0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624;
    address constant SXWETH = 0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6;

    // Correct prices (8 decimals for USD)
    uint256 constant CORRECT_IDRX_PRICE = 100_000_000; // $1.00
    uint256 constant CORRECT_WETH_PRICE = 300_000_000_000; // $3000.00

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("=== PERMANENT ORACLE PRICE FIX ===");
        console.log("Oracle:", ORACLE);
        console.log("sxIDRX:", SXIDRX);
        console.log("sxWETH:", SXWETH);
        console.log("");

        // Check current prices
        console.log("Current prices:");
        console.log("sxIDRX:", IOracle(ORACLE).getSpotPrice(SXIDRX));
        console.log("sxWETH:", IOracle(ORACLE).getSpotPrice(SXWETH));
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Disable automatic price updates from OrderBook
        console.log("Step 1: Disabling automatic price updates from OrderBook...");
        address sxwethOrderBook = IOracle(ORACLE).tokenOrderBooks(SXWETH);
        console.log("sxWETH OrderBook:", sxwethOrderBook);

        IOracle(ORACLE).setAuthorizedOrderBook(SXWETH, sxwethOrderBook, false);
        console.log("Disabled automatic updates for sxWETH");

        address sxidrxOrderBook = IOracle(ORACLE).tokenOrderBooks(SXIDRX);
        console.log("sxIDRX OrderBook:", sxidrxOrderBook);

        if (sxidrxOrderBook != address(0)) {
            IOracle(ORACLE).setAuthorizedOrderBook(SXIDRX, sxidrxOrderBook, false);
            console.log("Disabled automatic updates for sxIDRX");
        } else {
            console.log("sxIDRX has no OrderBook configured (no auto-updates to disable)");
        }
        console.log("");

        // Step 2: Set correct prices
        console.log("Step 2: Setting correct prices...");
        IOracle(ORACLE).setPrice(SXIDRX, CORRECT_IDRX_PRICE);
        console.log("sxIDRX price set to:", CORRECT_IDRX_PRICE);

        IOracle(ORACLE).setPrice(SXWETH, CORRECT_WETH_PRICE);
        console.log("sxWETH price set to:", CORRECT_WETH_PRICE);

        vm.stopBroadcast();

        // Verify
        console.log("");
        console.log("=== VERIFICATION ===");
        console.log("New prices:");
        console.log("sxIDRX:", IOracle(ORACLE).getSpotPrice(SXIDRX));
        console.log("sxWETH:", IOracle(ORACLE).getSpotPrice(SXWETH));
        console.log("");
        console.log("Oracle prices fixed and locked!");
        console.log("");
        console.log("NOTE: Automatic price updates from trades are now DISABLED.");
        console.log("Prices will remain at these values until manually updated again.");
    }
}
