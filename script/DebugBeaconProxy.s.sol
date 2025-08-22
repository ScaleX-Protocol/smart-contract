// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract DebugBeaconProxy is Script {
    
    function run() public {
        console.log("========== DEBUGGING BEACON PROXY CHAINBALANCEMANAGER ==========");
        
        // Connect to Appchain where ChainBalanceManager is deployed
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        console.log("ChainBalanceManager proxy address:", chainBalanceManagerAddr);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        console.log("=== 1. BEACON PROXY DETECTION ===");
        
        // Check for beacon proxy pattern
        // BeaconProxy stores beacon address at a specific slot
        // bytes32 private constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
        bytes32 beaconSlot = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
        bytes32 beaconData = vm.load(chainBalanceManagerAddr, beaconSlot);
        address beaconAddress = address(uint160(uint256(beaconData)));
        
        console.log("Beacon slot data:");
        console.logBytes32(beaconData);
        console.log("Beacon address:", beaconAddress);
        
        if (beaconAddress != address(0)) {
            console.log("This is a BeaconProxy!");
            
            // Get implementation from beacon
            UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);
            
            try beacon.implementation() returns (address implementation) {
                console.log("Implementation address:", implementation);
                
                // Check implementation code size
                uint256 implCodeSize;
                assembly {
                    implCodeSize := extcodesize(implementation)
                }
                console.log("Implementation code size:", implCodeSize);
                
                // Test functions on the implementation directly
                console.log("=== 2. DIRECT IMPLEMENTATION TESTS ===");
                
                ChainBalanceManager implContract = ChainBalanceManager(implementation);
                
                try implContract.getCrossChainConfig() returns (uint32 destDomain, address destBM) {
                    console.log("Direct implementation getCrossChainConfig():");
                    console.log("  Domain:", destDomain);
                    console.log("  Balance Manager:", destBM);
                } catch Error(string memory reason) {
                    console.log("Direct implementation getCrossChainConfig() failed:", reason);
                } catch {
                    console.log("Direct implementation getCrossChainConfig() failed with unknown error");
                }
                
                try implContract.getDestinationConfig() returns (uint32 destDomain, address destBM) {
                    console.log("Direct implementation getDestinationConfig():");
                    console.log("  Domain:", destDomain);
                    console.log("  Balance Manager:", destBM);
                } catch Error(string memory reason) {
                    console.log("Direct implementation getDestinationConfig() failed:", reason);
                } catch {
                    console.log("Direct implementation getDestinationConfig() failed with unknown error");
                }
                
            } catch Error(string memory reason) {
                console.log("Failed to get implementation from beacon:", reason);
            } catch {
                console.log("Failed to get implementation from beacon with unknown error");
            }
        } else {
            console.log("Not a standard BeaconProxy");
        }
        
        console.log("=== 3. FUNCTION SELECTOR ANALYSIS ===");
        
        // Calculate function selectors to check for collisions
        bytes4 getCrossChainConfigSelector = bytes4(keccak256("getCrossChainConfig()"));
        bytes4 getDestinationConfigSelector = bytes4(keccak256("getDestinationConfig()"));
        bytes4 getMailboxConfigSelector = bytes4(keccak256("getMailboxConfig()"));
        
        console.log("getCrossChainConfig() selector:");
        console.logBytes4(getCrossChainConfigSelector);
        console.log("getDestinationConfig() selector:");
        console.logBytes4(getDestinationConfigSelector);
        console.log("getMailboxConfig() selector:");
        console.logBytes4(getMailboxConfigSelector);
        
        console.log("=== 4. LOW-LEVEL FUNCTION CALLS ===");
        
        // Try low-level calls to see what's happening
        (bool success1, bytes memory result1) = address(cbm).staticcall(
            abi.encodeWithSelector(getCrossChainConfigSelector)
        );
        console.log("Low-level getCrossChainConfig() success:", success1);
        if (success1) {
            console.log("Result length:", result1.length);
            if (result1.length >= 64) {
                (uint32 domain, address manager) = abi.decode(result1, (uint32, address));
                console.log("Decoded domain:", domain);
                console.log("Decoded manager:", manager);
            }
        } else {
            console.log("Low-level getCrossChainConfig() failed");
            console.logBytes(result1);
        }
        
        (bool success2, bytes memory result2) = address(cbm).staticcall(
            abi.encodeWithSelector(getDestinationConfigSelector)
        );
        console.log("Low-level getDestinationConfig() success:", success2);
        if (success2) {
            console.log("Result length:", result2.length);
            if (result2.length >= 64) {
                (uint32 domain, address manager) = abi.decode(result2, (uint32, address));
                console.log("Decoded domain:", domain);
                console.log("Decoded manager:", manager);
            }
        } else {
            console.log("Low-level getDestinationConfig() failed");
            console.logBytes(result2);
        }
        
        console.log("=== 5. PROXY STATE VS IMPLEMENTATION STATE ===");
        
        // The issue might be that the proxy and implementation have different storage
        // For upgradeable contracts, storage should be in the proxy, not implementation
        console.log("Testing proxy vs implementation storage...");
        
        // Check if initialization was called correctly
        try cbm.owner() returns (address owner) {
            console.log("Proxy owner (should be set if initialized):", owner);
        } catch {
            console.log("Proxy owner not accessible");
        }
        
        console.log("========== BEACON PROXY DEBUG COMPLETE ==========");
    }
}