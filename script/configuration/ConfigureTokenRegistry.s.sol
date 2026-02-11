// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {TokenRegistry} from "@scalexcore/TokenRegistry.sol";

/**
 * @title ConfigureTokenRegistry
 * @dev Configure token mappings in TokenRegistry for local deposits
 * @notice This script sets up token mappings for same-chain deposits (sourceChain == targetChain)
 */
contract ConfigureTokenRegistry is Script {

    function run() external {
        console.log("=== CONFIGURE TOKEN REGISTRY ===");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);

        // Load addresses from deployment file
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deploymentPath = string.concat(root, "/deployments/", chainIdStr, ".json");

        if (!vm.exists(deploymentPath)) {
            revert("Deployment file not found. Run deployment first.");
        }

        string memory json = vm.readFile(deploymentPath);
        address tokenRegistry = _extractAddress(json, "TokenRegistry");

        // Read quote currency from environment
        string memory quoteSymbol = vm.envOr("QUOTE_SYMBOL", string("USDC"));
        string memory syntheticQuoteSymbol = string.concat("sx", quoteSymbol);

        // Load quote token addresses dynamically
        address quoteToken = _extractAddress(json, quoteSymbol);
        address sxQuoteToken = _extractAddress(json, syntheticQuoteSymbol);

        // Real tokens (other assets)
        address weth = _extractAddress(json, "WETH");
        address wbtc = _extractAddress(json, "WBTC");
        address gold = _extractAddress(json, "GOLD");
        address silver = _extractAddress(json, "SILVER");
        address google = _extractAddress(json, "GOOGLE");
        address nvidia = _extractAddress(json, "NVIDIA");
        address mnt = _extractAddress(json, "MNT");
        address apple = _extractAddress(json, "APPLE");

        // Synthetic tokens (other assets)
        address sxWETH = _extractAddress(json, "sxWETH");
        address sxWBTC = _extractAddress(json, "sxWBTC");
        address sxGOLD = _extractAddress(json, "sxGOLD");
        address sxSILVER = _extractAddress(json, "sxSILVER");
        address sxGOOGLE = _extractAddress(json, "sxGOOGLE");
        address sxNVIDIA = _extractAddress(json, "sxNVIDIA");
        address sxMNT = _extractAddress(json, "sxMNT");
        address sxAPPLE = _extractAddress(json, "sxAPPLE");

        console.log("Loaded addresses:");
        console.log("  TokenRegistry:", tokenRegistry);
        console.log("  Chain ID:", chainId);
        console.log("  Quote Token:", quoteSymbol, "->", syntheticQuoteSymbol);
        console.log("    ", quoteToken, "->", sxQuoteToken);
        console.log("  WETH:", weth, "-> sxWETH:", sxWETH);
        console.log("  WBTC:", wbtc, "-> sxWBTC:", sxWBTC);
        console.log("  GOLD:", gold, "-> sxGOLD:", sxGOLD);
        console.log("  SILVER:", silver, "-> sxSILVER:", sxSILVER);
        console.log("  GOOGLE:", google, "-> sxGOOGLE:", sxGOOGLE);
        console.log("  NVIDIA:", nvidia, "-> sxNVIDIA:", sxNVIDIA);
        console.log("  MNT:", mnt, "-> sxMNT:", sxMNT);
        console.log("  APPLE:", apple, "-> sxAPPLE:", sxAPPLE);

        TokenRegistry registry = TokenRegistry(tokenRegistry);
        uint32 currentChainId = uint32(chainId);

        vm.startBroadcast(deployerPrivateKey);

        console.log("\nStep 1: Registering token mappings (auto-activated)...");

        // Register token mappings (same chain for local deposits)
        // Note: mappings are automatically set to isActive=true upon registration

        // Register quote token dynamically
        // Get quote decimals from environment (IDRX = 2, USDC = 6, etc.)
        uint8 quoteDecimals = uint8(vm.envOr("QUOTE_DECIMALS", uint256(6)));
        console.log(string.concat("  Registering ", quoteSymbol, " -> ", syntheticQuoteSymbol, " mapping..."));
        console.log("  Source decimals:", quoteDecimals);
        console.log("  Synthetic decimals: 18");
        registry.registerTokenMapping(currentChainId, quoteToken, currentChainId, sxQuoteToken, quoteSymbol, quoteDecimals, 18);

        console.log("  Registering WETH -> sxWETH mapping...");
        registry.registerTokenMapping(currentChainId, weth, currentChainId, sxWETH, "WETH", 18, 18);

        console.log("  Registering WBTC -> sxWBTC mapping...");
        registry.registerTokenMapping(currentChainId, wbtc, currentChainId, sxWBTC, "WBTC", 8, 18);

        console.log("  Registering GOLD -> sxGOLD mapping...");
        registry.registerTokenMapping(currentChainId, gold, currentChainId, sxGOLD, "GOLD", 18, 18);

        console.log("  Registering SILVER -> sxSILVER mapping...");
        registry.registerTokenMapping(currentChainId, silver, currentChainId, sxSILVER, "SILVER", 18, 18);

        console.log("  Registering GOOGLE -> sxGOOGLE mapping...");
        registry.registerTokenMapping(currentChainId, google, currentChainId, sxGOOGLE, "GOOGLE", 18, 18);

        console.log("  Registering NVIDIA -> sxNVIDIA mapping...");
        registry.registerTokenMapping(currentChainId, nvidia, currentChainId, sxNVIDIA, "NVIDIA", 18, 18);

        console.log("  Registering MNT -> sxMNT mapping...");
        registry.registerTokenMapping(currentChainId, mnt, currentChainId, sxMNT, "MNT", 18, 18);

        console.log("  Registering APPLE -> sxAPPLE mapping...");
        registry.registerTokenMapping(currentChainId, apple, currentChainId, sxAPPLE, "APPLE", 18, 18);

        console.log("[OK] All token mappings registered and activated");

        vm.stopBroadcast();

        console.log("\nStep 2: Verifying mappings...");

        // Verify all mappings
        console.log(" ", quoteSymbol, "mapping active:", registry.isTokenMappingActive(currentChainId, quoteToken, currentChainId));
        console.log("  WETH mapping active:", registry.isTokenMappingActive(currentChainId, weth, currentChainId));
        console.log("  WBTC mapping active:", registry.isTokenMappingActive(currentChainId, wbtc, currentChainId));
        console.log("  GOLD mapping active:", registry.isTokenMappingActive(currentChainId, gold, currentChainId));
        console.log("  SILVER mapping active:", registry.isTokenMappingActive(currentChainId, silver, currentChainId));
        console.log("  GOOGLE mapping active:", registry.isTokenMappingActive(currentChainId, google, currentChainId));
        console.log("  NVIDIA mapping active:", registry.isTokenMappingActive(currentChainId, nvidia, currentChainId));
        console.log("  MNT mapping active:", registry.isTokenMappingActive(currentChainId, mnt, currentChainId));
        console.log("  APPLE mapping active:", registry.isTokenMappingActive(currentChainId, apple, currentChainId));

        console.log("\n=== TOKEN REGISTRY CONFIGURATION COMPLETE ===");
    }

    function _extractAddress(string memory json, string memory key) internal view returns (address) {
        string memory fullKey = string.concat(".", key);
        return vm.parseJsonAddress(json, fullKey);
    }
}
