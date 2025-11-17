// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {LendingManagerV2} from "@scalex/yield/LendingManagerV2.sol";
import {BalanceManagerV2} from "@scalex/core/upgrade/BalanceManagerV2.sol";
import {ScaleXRouterV2} from "@scalex/core/upgrade/ScaleXRouterV2.sol";
import {PoolManagerV2} from "@scalex/core/upgrade/PoolManagerV2.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title UpdateCoreContracts
 * @dev Fully automated upgrade script - no manual steps required
 */
contract UpdateCoreContracts is Script {
    
    // EIP1967 beacon storage slot
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
    
    // Read deployment addresses dynamically from JSON using vm.parseJson
    function _getDeploymentAddresses() internal view returns (address[4] memory) {
        // Use vm.parseJson to get deployment addresses
        // This reads the deployment JSON and extracts addresses dynamically
        string memory deploymentJson = vm.readFile("deployments/31337.json");
        
        // Parse the JSON using vm.parseJson (supported in newer foundry versions)
        // Fallback to string manipulation if parseJson is not available
        
        // Try to extract addresses using simple string manipulation
        address lendingManager = _extractAddressFromJson(deploymentJson, "LendingManager");
        address balanceManager = _extractAddressFromJson(deploymentJson, "BalanceManager");
        address scaleXRouter = _extractAddressFromJson(deploymentJson, "ScaleXRouter");
        address poolManager = _extractAddressFromJson(deploymentJson, "PoolManager");
        
        return [lendingManager, balanceManager, scaleXRouter, poolManager];
    }
    
    // Simple address extraction using string manipulation
    function _extractAddressFromJson(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory searchPattern = bytes(string(abi.encodePacked('"', key, '":')));
        
        uint256 keyIndex = _findSubstring(jsonBytes, searchPattern);
        require(keyIndex != type(uint256).max, string(abi.encodePacked("Key not found: ", key)));
        
        // Skip to the opening quote after colon
        uint256 addressStart = keyIndex + searchPattern.length;
        while (addressStart < jsonBytes.length && jsonBytes[addressStart] != '"') {
            addressStart++;
        }
        addressStart++; // Skip opening quote
        
        // Find the closing quote
        uint256 addressEnd = addressStart;
        while (addressEnd < jsonBytes.length && jsonBytes[addressEnd] != '"') {
            addressEnd++;
        }
        
        // Extract and parse the address
        string memory addressStr = string(_subBytes(jsonBytes, addressStart, addressEnd - addressStart));
        
        // Convert hex string to address
        return stringToAddress(addressStr);
    }
    
    // Convert hex string to address
    function stringToAddress(string memory s) internal pure returns (address) {
        bytes memory b = bytes(s);
        
        // Remove 0x prefix if present
        uint256 start = 0;
        if (b.length >= 2 && b[0] == '0' && (b[1] == 'x' || b[1] == 'X')) {
            start = 2;
        }
        
        uint256 result = 0;
        for (uint256 i = start; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 48 && c <= 57) { // '0'-'9'
                result = result * 16 + (c - 48);
            } else if (c >= 97 && c <= 102) { // 'a'-'f'
                result = result * 16 + (c - 87);
            } else if (c >= 65 && c <= 70) { // 'A'-'F'
                result = result * 16 + (c - 55);
            }
        }
        return address(uint160(result));
    }
    
        
    // Find substring in bytes
    function _findSubstring(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        if (needle.length > haystack.length) return type(uint256).max;
        
        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }
        return type(uint256).max;
    }
    
    // Extract sub-bytes
    function _subBytes(bytes memory source, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = source[start + i];
        }
        return result;
    }
    
    struct ContractInfo {
        address proxyAddress;
        string name;
        address currentBeacon;
        address v2Implementation;
    }
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== AUTOMATED CORE CONTRACTS UPGRADE ===");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("\n=== Step 1: Deploy V2 Implementations ===");
        
        // Deploy V2 implementations
        LendingManagerV2 lendingV2 = new LendingManagerV2();
        console.log("LendingManager V2:", address(lendingV2));
        
        BalanceManagerV2 balanceV2 = new BalanceManagerV2();
        console.log("BalanceManager V2:", address(balanceV2));
        
        ScaleXRouterV2 routerV2 = new ScaleXRouterV2();
        console.log("ScaleXRouter V2:", address(routerV2));
        
        PoolManagerV2 poolV2 = new PoolManagerV2();
        console.log("PoolManager V2:", address(poolV2));
        
        console.log("\n=== Step 2: Discover Current Beacons ===");
        
        // Get dynamic deployment addresses
        address[4] memory addresses = _getDeploymentAddresses();
        
        // Setup contract info
        ContractInfo[4] memory contracts;
        
        contracts[0] = ContractInfo({
            proxyAddress: addresses[0],
            name: "LendingManager",
            currentBeacon: address(0),
            v2Implementation: address(lendingV2)
        });
        
        contracts[1] = ContractInfo({
            proxyAddress: addresses[1],
            name: "BalanceManager",
            currentBeacon: address(0),
            v2Implementation: address(balanceV2)
        });
        
        contracts[2] = ContractInfo({
            proxyAddress: addresses[2],
            name: "ScaleXRouter",
            currentBeacon: address(0),
            v2Implementation: address(routerV2)
        });
        
        contracts[3] = ContractInfo({
            proxyAddress: addresses[3],
            name: "PoolManager",
            currentBeacon: address(0),
            v2Implementation: address(poolV2)
        });
        
        // Discover current beacons
        for (uint i = 0; i < 4; i++) {
            contracts[i].currentBeacon = _getBeacon(contracts[i].proxyAddress);
            console.log(contracts[i].name, "current beacon:", contracts[i].currentBeacon);
        }
        
        console.log("\n=== Step 3: Perform Upgrades ===");
        
        // Upgrade beacons directly
        for (uint i = 0; i < 4; i++) {
            console.log("Upgrading", contracts[i].name, "...");
            
            // Verify we own the beacon
            address beaconOwner = UpgradeableBeacon(contracts[i].currentBeacon).owner();
            require(beaconOwner == deployer, string(abi.encodePacked("Not owner of ", contracts[i].name, " beacon")));
            
            // Perform the upgrade
            UpgradeableBeacon(contracts[i].currentBeacon).upgradeTo(contracts[i].v2Implementation);
            console.log("[SUCCESS]", contracts[i].name, "upgraded to", contracts[i].v2Implementation);
        }
        
        console.log("\n=== Step 4: Verification ===");
        
        // Verify all upgrades before stopping broadcast
        bool allSuccess = true;
        for (uint i = 0; i < 4; i++) {
            // Direct static call to verify getVersion works
            (bool success, bytes memory data) = contracts[i].proxyAddress.staticcall(
                abi.encodeWithSignature("getVersion()")
            );
            
            if (success) {
                string memory version = abi.decode(data, (string));
                console.log("[SUCCESS]", contracts[i].name, "version:", version);
            } else {
                console.log("[ERROR]", contracts[i].name, "verification failed");
                allSuccess = false;
            }
        }
        
        if (!allSuccess) {
            revert("Some upgrades failed verification");
        }
        
        vm.stopBroadcast();
        
        if (allSuccess) {
            console.log("\n[SUCCESS] ALL UPGRADES COMPLETED SUCCESSFULLY!");
        } else {
            console.log("\n[WARNING] Some upgrades failed verification");
        }
        
        console.log("\n=== Upgrade Summary ===");
        for (uint i = 0; i < 4; i++) {
            console.log(contracts[i].name, ":", contracts[i].proxyAddress);
            console.log("  - Beacon:", contracts[i].currentBeacon, "-> V2:", contracts[i].v2Implementation);
        }
    }
    
    /**
     * @dev Get beacon address from proxy storage slot
     */
    function _getBeacon(address proxy) internal view returns (address) {
        bytes32 data = vm.load(proxy, BEACON_SLOT);
        return address(uint160(uint256(data)));
    }
    
    /**
     * @dev Verify upgrade worked correctly (internal function)
     */
    function _verifyUpgradeInternal(address contractAddr) internal view returns (string memory version) {
        (bool success, bytes memory data) = contractAddr.staticcall(
            abi.encodeWithSignature("getVersion()")
        );
        if (!success) {
            revert("getVersion call failed");
        }
        return abi.decode(data, (string));
    }
    
    /**
     * @dev Verify upgrade worked correctly (external function for testing)
     */
    function _verifyUpgrade(address contractAddr) external view returns (string memory version) {
        return _verifyUpgradeInternal(contractAddr);
    }
}