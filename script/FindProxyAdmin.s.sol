// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract FindProxyAdmin is Script {
    
    function run() public view {
        console.log("========== FIND PROXY ADMIN ==========");
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 421614) {
            console.log("ERROR: This script is for Arbitrum Sepolia only");
            return;
        }
        
        address proxyAddress = 0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A;
        console.log("Proxy address:", proxyAddress);
        console.log("");
        
        // Check EIP-1967 admin slot
        bytes32 ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        address adminFromSlot = address(uint160(uint256(vm.load(proxyAddress, ADMIN_SLOT))));
        
        console.log("=== PROXY ADMIN DETECTION ===");
        console.log("Admin from storage slot:", adminFromSlot);
        
        if (adminFromSlot != address(0)) {
            console.log("Found ProxyAdmin at:", adminFromSlot);
            
            // Check if admin has owner
            try this.getOwner(adminFromSlot) returns (address owner) {
                console.log("ProxyAdmin owner:", owner);
            } catch {
                console.log("Could not get ProxyAdmin owner");
            }
            
        } else {
            console.log("No ProxyAdmin found in storage slot");
        }
        
        // Try calling admin() function directly on proxy
        console.log("");
        console.log("=== DIRECT ADMIN CALL ===");
        try this.callAdmin(proxyAddress) returns (address admin) {
            console.log("Admin from admin() call:", admin);
        } catch {
            console.log("admin() call failed");
        }
        
        // Try calling getProxyAdmin()
        console.log("");
        console.log("=== GET PROXY ADMIN CALL ===");
        try this.callGetProxyAdmin(proxyAddress) returns (address admin) {
            console.log("Admin from getProxyAdmin() call:", admin);
        } catch {
            console.log("getProxyAdmin() call failed");
        }
        
        console.log("");
        console.log("=== RECOMMENDATIONS ===");
        if (adminFromSlot != address(0)) {
            console.log("Use ProxyAdmin at", adminFromSlot, "to upgrade");
            console.log("Call: ProxyAdmin(", adminFromSlot, ").upgrade(proxy, newImpl)");
        } else {
            console.log("This may be an Ownable proxy - check if deployer is owner");
            console.log("Or it may use a different admin pattern");
        }
        
        console.log("========== PROXY ADMIN SEARCH COMPLETE ==========");
    }
    
    function callAdmin(address proxy) external view returns (address) {
        (bool success, bytes memory data) = proxy.staticcall(abi.encodeWithSignature("admin()"));
        require(success, "admin() call failed");
        return abi.decode(data, (address));
    }
    
    function callGetProxyAdmin(address proxy) external view returns (address) {
        (bool success, bytes memory data) = proxy.staticcall(abi.encodeWithSignature("getProxyAdmin()"));
        require(success, "getProxyAdmin() call failed");
        return abi.decode(data, (address));
    }
    
    function getOwner(address admin) external view returns (address) {
        (bool success, bytes memory data) = admin.staticcall(abi.encodeWithSignature("owner()"));
        require(success, "owner() call failed");
        return abi.decode(data, (address));
    }
}