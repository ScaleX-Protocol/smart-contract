// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/core/Oracle.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title UpgradeOracleAndLink
 * @notice Upgrades Oracle to new implementation with SyntheticTokenFactory fallback and links it
 */
contract UpgradeOracleAndLink is Script {
    function run() external {
        // Deployment addresses from 84532.json
        address oracleProxy = 0x83187ccD22D4e8DFf2358A09750331775A207E13;
        address syntheticTokenFactory = 0x17D803b6Bb4ECF60e8f8b60f4489afdA1743e021;

        console.log("=== Upgrading Oracle and Linking to Factory ===");
        console.log("Oracle Proxy:", oracleProxy);
        console.log("SyntheticTokenFactory:", syntheticTokenFactory);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy new Oracle implementation
        console.log("1. Deploying new Oracle implementation...");
        Oracle newImplementation = new Oracle();
        console.log("   New implementation:", address(newImplementation));
        console.log("");

        // 2. Get ProxyAdmin to upgrade
        console.log("2. Getting ProxyAdmin...");
        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(oracleProxy));

        // The ProxyAdmin is the admin of the proxy
        // We need to get it from the proxy's admin slot
        bytes32 adminSlot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
        address proxyAdmin = address(uint160(uint256(vm.load(oracleProxy, adminSlot))));
        console.log("   ProxyAdmin:", proxyAdmin);
        console.log("");

        // 3. Upgrade to new implementation
        console.log("3. Upgrading Oracle proxy to new implementation...");
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(oracleProxy),
            address(newImplementation),
            ""
        );
        console.log("   [OK] Upgrade complete");
        console.log("");

        // 4. Link Oracle to SyntheticTokenFactory
        console.log("4. Linking Oracle to SyntheticTokenFactory...");
        Oracle oracle = Oracle(oracleProxy);
        oracle.setSyntheticTokenFactory(syntheticTokenFactory);
        console.log("   [OK] Factory linked");
        console.log("");

        vm.stopBroadcast();

        // 5. Verify configuration
        console.log("=== Verification ===");
        address configuredFactory = address(oracle.syntheticTokenFactory());
        console.log("Oracle.syntheticTokenFactory():", configuredFactory);
        require(configuredFactory == syntheticTokenFactory, "Factory not configured correctly");
        console.log("[OK] All checks passed!");
    }
}
