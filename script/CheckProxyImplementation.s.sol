// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckProxyImplementation is Script {
    
    function run() public view {
        console.log("========== CHECK PROXY IMPLEMENTATION ==========");
        console.log("Network:", vm.toString(block.chainid));
        
        address proxyAddress;
        string memory networkName;
        
        if (block.chainid == 421614) {
            proxyAddress = 0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A;
            networkName = "ARBITRUM SEPOLIA";
        } else if (block.chainid == 11155931) {
            proxyAddress = 0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745;
            networkName = "RISE SEPOLIA";
        } else {
            console.log("ERROR: Unsupported network");
            return;
        }
        
        console.log("Network:", networkName);
        console.log("Proxy address:", proxyAddress);
        console.log("");
        
        // Check if it's a beacon proxy by calling beacon()
        console.log("=== CHECK BEACON PROXY ===");
        try this.getBeacon(proxyAddress) returns (address beacon) {
            console.log("Beacon address:", beacon);
            
            // Check what the beacon points to
            try this.getBeaconImplementation(beacon) returns (address impl) {
                console.log("Beacon implementation:", impl);
            } catch {
                console.log("Failed to get beacon implementation");
            }
        } catch {
            console.log("Not a beacon proxy or beacon() call failed");
        }
        
        // Check if it's a standard upgradeable proxy
        console.log("");
        console.log("=== CHECK STANDARD PROXY ===");
        try this.getImplementation(proxyAddress) returns (address impl) {
            console.log("Direct implementation:", impl);
        } catch {
            console.log("Failed to get direct implementation");
        }
        
        console.log("");
        console.log("=== CHECK PROXY TYPE ===");
        
        // Check storage at implementation slot (EIP-1967)
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
        
        address implFromSlot = address(uint160(uint256(vm.load(proxyAddress, IMPLEMENTATION_SLOT))));
        address beaconFromSlot = address(uint160(uint256(vm.load(proxyAddress, BEACON_SLOT))));
        
        console.log("Implementation from storage slot:", implFromSlot);
        console.log("Beacon from storage slot:", beaconFromSlot);
        
        if (beaconFromSlot != address(0)) {
            console.log("Proxy type: Beacon Proxy");
        } else if (implFromSlot != address(0)) {
            console.log("Proxy type: Standard Upgradeable Proxy");
        } else {
            console.log("Proxy type: Unknown or not a proxy");
        }
        
        console.log("========== PROXY CHECK COMPLETE ==========");
    }
    
    function getBeacon(address proxy) external view returns (address) {
        // Call beacon() function on proxy
        (bool success, bytes memory data) = proxy.staticcall(abi.encodeWithSignature("beacon()"));
        require(success, "beacon() call failed");
        return abi.decode(data, (address));
    }
    
    function getBeaconImplementation(address beacon) external view returns (address) {
        (bool success, bytes memory data) = beacon.staticcall(abi.encodeWithSignature("implementation()"));
        require(success, "implementation() call failed");
        return abi.decode(data, (address));
    }
    
    function getImplementation(address proxy) external view returns (address) {
        (bool success, bytes memory data) = proxy.staticcall(abi.encodeWithSignature("implementation()"));
        require(success, "implementation() call failed");
        return abi.decode(data, (address));
    }
}