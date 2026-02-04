// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

import {UnifiedLiquidityBridge} from "@scalexcore/UnifiedLiquidityBridge.sol";
import {MantleSideChainManager} from "@scalexcore/MantleSideChainManager.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/**
 * @title DeployUnifiedLiquidity
 * @dev Deploys the Arc <-> Mantle unified liquidity bridge contracts.
 *
 * This script is designed to be run TWICE -- once on each chain.  The
 * environment variables below control which deployment path is taken.
 *
 * ---------------------------------------------------------------------------
 * ARC TESTNET DEPLOYMENT (run first)
 * ---------------------------------------------------------------------------
 *   export PRIVATE_KEY=...
 *   export DEPLOY_TARGET=arc
 *   export ARC_USDC=0x3600000000000000000000000000000000000000
 *   export ARC_MAILBOX=<hyperlane mailbox on Arc>
 *   export MANTLE_DOMAIN=5003
 *   # Leave MANTLE_MANAGER empty on first run; patch with setMantleManager later
 *
 *   forge script script/deployments/DeployUnifiedLiquidity.s.sol \
 *       --rpc-url https://rpc.testnet.arc.network \
 *       --broadcast --slow
 *
 * ---------------------------------------------------------------------------
 * MANTLE TESTNET DEPLOYMENT (run second, after Arc is deployed)
 * ---------------------------------------------------------------------------
 *   export PRIVATE_KEY=...
 *   export DEPLOY_TARGET=mantle
 *   export MANTLE_USDC=<bridged USDC address on Mantle Sepolia>
 *   export MANTLE_MAILBOX=<hyperlane mailbox on Mantle>
 *   export ARC_DOMAIN=5042002
 *   export ARC_BRIDGE=<UnifiedLiquidityBridge proxy address from Arc deployment>
 *
 *   forge script script/deployments/DeployUnifiedLiquidity.s.sol \
 *       --rpc-url https://rpc.sepolia.mantle.xyz \
 *       --broadcast --slow
 *
 * ---------------------------------------------------------------------------
 * POST-DEPLOYMENT WIRING
 * ---------------------------------------------------------------------------
 *   After both deployments succeed:
 *     1. Call UnifiedLiquidityBridge.setMantleManager(mantleManagerProxy, 5003) on Arc.
 *     2. Call UnifiedLiquidityBridge.setAuthorisedDepositor(GATEWAY_MINTER, true) on Arc.
 *        Gateway Minter on Arc testnet: 0x0022222ABE238Cc2C7Bb1f21003F0a260052475B
 *     3. (Optional) Call MantleSideChainManager.setArcBridge(...) on Mantle if the
 *        Arc proxy address was not available at Mantle deploy time.
 *
 * ---------------------------------------------------------------------------
 * DEPLOYMENT JSON
 * ---------------------------------------------------------------------------
 *   Each run appends to  deployments/{chainId}.json  with these keys:
 *     Arc side:    UnifiedLiquidityBridge_Impl, UnifiedLiquidityBridge_Beacon, UnifiedLiquidityBridge
 *     Mantle side: MantleSideChainManager_Impl, MantleSideChainManager_Beacon, MantleSideChainManager
 */
contract DeployUnifiedLiquidity is Script {
    // ----------------------------------------------------------
    // run()
    // ----------------------------------------------------------

    function run() external {
        // Determine deployment target.
        string memory target = vm.envOr("DEPLOY_TARGET", string("arc"));

        if (keccak256(bytes(target)) == keccak256(bytes("arc"))) {
            deployArc();
        } else if (keccak256(bytes(target)) == keccak256(bytes("mantle"))) {
            deployMantle();
        } else {
            revert("DEPLOY_TARGET must be 'arc' or 'mantle'");
        }
    }

    // ----------------------------------------------------------
    // ARC deployment
    // ----------------------------------------------------------

    function deployArc() internal {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        // ---------- Read config ----------
        address arcUsdc = vm.envAddress("ARC_USDC");
        address arcMailbox = vm.envAddress("ARC_MAILBOX");
        uint32 mantleDomain = uint32(vm.envUint("MANTLE_DOMAIN")); // 5003

        // MantleManager may not exist yet; default to zero.
        address mantleManager = vm.envOr("MANTLE_MANAGER", address(0));

        console.log("============================================================");
        console.log("  DeployUnifiedLiquidity -- ARC TESTNET");
        console.log("============================================================");
        console.log("Deployer         =", deployer);
        console.log("ARC_USDC         =", arcUsdc);
        console.log("ARC_MAILBOX      =", arcMailbox);
        console.log("MANTLE_DOMAIN    =", mantleDomain);
        console.log("MANTLE_MANAGER   =", mantleManager);

        vm.startBroadcast(privateKey);

        // 1. Implementation
        UnifiedLiquidityBridge impl = new UnifiedLiquidityBridge();
        console.log("[OK] UnifiedLiquidityBridge impl =", address(impl));

        // 2. Beacon
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), deployer);
        console.log("[OK] UnifiedLiquidityBridge beacon =", address(beacon));

        // 3. Proxy (initialised)
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeCall(
                UnifiedLiquidityBridge.initialize,
                (deployer, arcUsdc, arcMailbox, mantleDomain, mantleManager)
            )
        );
        console.log("[OK] UnifiedLiquidityBridge proxy  =", address(proxy));

        vm.stopBroadcast();

        // ---------- Persist ----------
        _appendToDeploymentJson(
            "UnifiedLiquidityBridge_Impl", address(impl),
            "UnifiedLiquidityBridge_Beacon", address(beacon),
            "UnifiedLiquidityBridge", address(proxy)
        );

        console.log("");
        console.log("============================================================");
        console.log("  ARC DEPLOYMENT COMPLETE");
        console.log("  Next: deploy Mantle side, then call setMantleManager on Arc.");
        console.log("============================================================");
    }

    // ----------------------------------------------------------
    // MANTLE deployment
    // ----------------------------------------------------------

    function deployMantle() internal {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        // ---------- Read config ----------
        address mantleUsdc = vm.envAddress("MANTLE_USDC");
        address mantleMailbox = vm.envAddress("MANTLE_MAILBOX");
        uint32 arcDomain = uint32(vm.envUint("ARC_DOMAIN")); // 5042002
        address arcBridge = vm.envAddress("ARC_BRIDGE");      // from Arc deployment

        console.log("============================================================");
        console.log("  DeployUnifiedLiquidity -- MANTLE SEPOLIA");
        console.log("============================================================");
        console.log("Deployer         =", deployer);
        console.log("MANTLE_USDC      =", mantleUsdc);
        console.log("MANTLE_MAILBOX   =", mantleMailbox);
        console.log("ARC_DOMAIN       =", arcDomain);
        console.log("ARC_BRIDGE       =", arcBridge);

        vm.startBroadcast(privateKey);

        // 1. Implementation
        MantleSideChainManager impl = new MantleSideChainManager();
        console.log("[OK] MantleSideChainManager impl  =", address(impl));

        // 2. Beacon
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), deployer);
        console.log("[OK] MantleSideChainManager beacon =", address(beacon));

        // 3. Proxy (initialised)
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeCall(
                MantleSideChainManager.initialize,
                (deployer, mantleUsdc, mantleMailbox, arcDomain, arcBridge)
            )
        );
        console.log("[OK] MantleSideChainManager proxy  =", address(proxy));

        vm.stopBroadcast();

        // ---------- Persist ----------
        _appendToDeploymentJson(
            "MantleSideChainManager_Impl", address(impl),
            "MantleSideChainManager_Beacon", address(beacon),
            "MantleSideChainManager", address(proxy)
        );

        console.log("");
        console.log("============================================================");
        console.log("  MANTLE DEPLOYMENT COMPLETE");
        console.log("  Next: call UnifiedLiquidityBridge.setMantleManager on Arc.");
        console.log("============================================================");
    }

    // ----------------------------------------------------------
    // JSON persistence (appends 3 key/value pairs to the chain's deployment file)
    // ----------------------------------------------------------

    function _appendToDeploymentJson(
        string memory key1, address val1,
        string memory key2, address val2,
        string memory key3, address val3
    ) internal {
        string memory root = vm.projectRoot();
        string memory chainIdStr = vm.toString(block.chainid);
        string memory path = string.concat(root, "/deployments/", chainIdStr, ".json");

        // Attempt to read existing JSON; if absent start fresh.
        string memory existing;
        try vm.readFile(path) returns (string memory data) {
            existing = data;
        } catch {
            existing = "";
        }

        // Build a new JSON blob that merges existing keys with the three new ones.
        // We use vm.serializeString on a fresh object, then re-serialise existing
        // keys on top.  This is the same approach used by DeployPhase1.
        string memory json;

        // Re-serialise existing keys if the file was non-empty.
        if (bytes(existing).length > 0) {
            string[] memory keys = vm.parseJsonKeys(existing, "$");
            for (uint256 i = 0; i < keys.length; i++) {
                string memory k = keys[i];
                // Skip the three keys we are about to overwrite.
                if (
                    keccak256(bytes(k)) == keccak256(bytes(key1))
                    || keccak256(bytes(k)) == keccak256(bytes(key2))
                    || keccak256(bytes(k)) == keccak256(bytes(key3))
                ) {
                    continue;
                }
                string memory jsonPath = string.concat(".", k);
                // Values in the existing file may be addresses (strings) or booleans.
                // Read as raw bytes and try address first, fall back to raw string.
                try vm.parseJsonAddress(existing, jsonPath) returns (address a) {
                    vm.serializeString(json, k, vm.toString(a));
                } catch {
                    // Could be a bool, number, or other type -- store as-is via
                    // the raw bytes trick is impractical in Forge; just store
                    // the original string representation.
                    bytes memory raw = vm.parseJson(existing, jsonPath);
                    // raw is abi-encoded; for simple strings/bools this works:
                    try vm.parseJsonBool(existing, jsonPath) returns (bool b) {
                        vm.serializeString(json, k, b ? "true" : "false");
                    } catch {
                        // Fallback: treat as string (covers timestamp, blockNumber, etc.)
                        vm.serializeString(json, k, string(raw));
                    }
                }
            }
        }

        // Write the three new entries.
        vm.serializeString(json, key1, vm.toString(val1));
        vm.serializeString(json, key2, vm.toString(val2));
        json = vm.serializeString(json, key3, vm.toString(val3));

        vm.writeJson(json, path);
        console.log("Deployment data appended to:", path);
    }
}
