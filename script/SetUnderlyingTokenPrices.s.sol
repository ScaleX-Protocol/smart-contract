// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

interface IOracle {
    function setPrice(address token, uint256 price) external;
}

contract SetUnderlyingTokenPrices is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address oracle = 0x83187ccD22D4e8DFf2358A09750331775A207E13;

        // Underlying tokens
        address underlyingWETH = 0x8b732595a59c9a18acA0Aca3221A656Eb38158fC;
        address underlyingIDRX = 0x80FD9a0F8BCA5255692016D67E0733bf5262C142;

        console.log("=== SETTING UNDERLYING TOKEN PRICES ===");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Set WETH price: $3000 with 8 decimals = 300000000000
        console.log("Setting underlying WETH price to $3000...");
        IOracle(oracle).setPrice(underlyingWETH, 300000000000);
        console.log("Underlying WETH price set!");

        // Set IDRX price: $1.00 with 8 decimals = 100000000
        console.log("Setting underlying IDRX price to $1.00...");
        IOracle(oracle).setPrice(underlyingIDRX, 100000000);
        console.log("Underlying IDRX price set!");

        vm.stopBroadcast();

        console.log("");
        console.log("=== PRICES SET ===");
        console.log("Now auto-borrow health factor calculation should work!");
    }
}
