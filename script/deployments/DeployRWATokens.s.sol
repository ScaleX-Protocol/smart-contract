// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";

contract DeployRWATokens is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("=== DEPLOYING RWA MOCK TOKENS ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        MockToken gold = new MockToken("Gold Token", "GOLD", 18);
        MockToken silver = new MockToken("Silver Token", "SILVER", 18);
        MockToken google = new MockToken("Google Stock", "GOOGLE", 18);
        MockToken nvidia = new MockToken("NVIDIA Stock", "NVIDIA", 18);
        MockToken mnt = new MockToken("Mantle Token", "MNT", 18);
        MockToken apple = new MockToken("Apple Stock", "APPLE", 18);

        // Mint initial supply
        gold.mint(deployer, 1000 * 1e18);
        silver.mint(deployer, 10000 * 1e18);
        google.mint(deployer, 100 * 1e18);
        nvidia.mint(deployer, 100 * 1e18);
        mnt.mint(deployer, 100000 * 1e18);
        apple.mint(deployer, 100 * 1e18);

        vm.stopBroadcast();

        console.log("[OK] GOLD deployed:", address(gold));
        console.log("[OK] SILVER deployed:", address(silver));
        console.log("[OK] GOOGLE deployed:", address(google));
        console.log("[OK] NVIDIA deployed:", address(nvidia));
        console.log("[OK] MNT deployed:", address(mnt));
        console.log("[OK] APPLE deployed:", address(apple));
        console.log("=== RWA TOKENS DEPLOYMENT COMPLETE ===");
    }
}
