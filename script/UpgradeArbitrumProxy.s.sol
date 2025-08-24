// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IUpgradeableProxy {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
    function admin() external view returns (address);
    function implementation() external view returns (address);
}

contract UpgradeArbitrumProxy is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== UPGRADE ARBITRUM PROXY ==========");
        console.log("Upgrade standard proxy to new implementation");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 421614) {
            console.log("ERROR: This script is for Arbitrum Sepolia only");
            return;
        }
        
        address proxyAddress = 0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A;
        address newImplementation = 0xf70BF960B4546faF96d24afddbB627F5130A6C10;
        
        console.log("Proxy address:", proxyAddress);
        console.log("New implementation:", newImplementation);
        console.log("");
        
        // Check current implementation
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address currentImpl = address(uint160(uint256(vm.load(proxyAddress, IMPLEMENTATION_SLOT))));
        
        console.log("=== CURRENT STATE ===");
        console.log("Current implementation:", currentImpl);
        console.log("Target implementation:", newImplementation);
        console.log("");
        
        if (currentImpl == newImplementation) {
            console.log("Already using target implementation");
            return;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== ATTEMPTING UPGRADE ===");
        
        // Try different upgrade methods
        bool upgraded = false;
        
        // Method 1: Direct upgradeTo call
        try this.tryUpgradeTo(proxyAddress, newImplementation) {
            console.log("SUCCESS: Direct upgradeTo worked");
            upgraded = true;
        } catch Error(string memory reason) {
            console.log("Direct upgradeTo failed:", reason);
        } catch {
            console.log("Direct upgradeTo failed: unknown error");
        }
        
        // Method 2: Try calling on the proxy directly (if it's Ownable)
        if (!upgraded) {
            try this.tryDirectCall(proxyAddress, newImplementation) {
                console.log("SUCCESS: Direct proxy call worked");
                upgraded = true;
            } catch Error(string memory reason) {
                console.log("Direct proxy call failed:", reason);
            } catch {
                console.log("Direct proxy call failed: unknown error");
            }
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== VERIFY FINAL STATE ===");
        
        address finalImpl = address(uint160(uint256(vm.load(proxyAddress, IMPLEMENTATION_SLOT))));
        console.log("Final implementation:", finalImpl);
        
        if (finalImpl == newImplementation) {
            console.log("SUCCESS: Proxy upgraded successfully!");
        } else if (upgraded) {
            console.log("WARNING: Upgrade reported success but implementation unchanged");
        } else {
            console.log("FAILED: Could not upgrade proxy");
            console.log("This proxy may require admin rights or different upgrade method");
        }
        
        console.log("========== ARBITRUM PROXY UPGRADE COMPLETE ==========");
    }
    
    function tryUpgradeTo(address proxy, address newImpl) external {
        IUpgradeableProxy(proxy).upgradeTo(newImpl);
    }
    
    function tryDirectCall(address proxy, address newImpl) external {
        bytes memory data = abi.encodeWithSignature("upgradeTo(address)", newImpl);
        (bool success, bytes memory returnData) = proxy.call(data);
        require(success, string(returnData));
    }
}