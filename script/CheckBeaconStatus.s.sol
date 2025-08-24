// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract CheckBeaconStatus is Script {
    
    function run() public view {
        console.log("========== CHECK BEACON STATUS ==========");
        console.log("Network:", vm.toString(block.chainid));
        
        address beaconAddress;
        address expectedImpl;
        string memory networkName;
        
        if (block.chainid == 421614) {
            beaconAddress = 0xB7b9994Cba82150b874828bEdA2871E9d189b04c;
            expectedImpl = 0xf70BF960B4546faF96d24afddbB627F5130A6C10;
            networkName = "ARBITRUM SEPOLIA";
        } else if (block.chainid == 11155931) {
            beaconAddress = 0x7D1457070Ee64d008053bB7A5EA354e11622BFB9;
            expectedImpl = 0xcA4dFb2A848b551Baee6410fB75270B2815BFDA8;
            networkName = "RISE SEPOLIA";
        } else {
            console.log("ERROR: Unsupported network");
            return;
        }
        
        console.log("Network:", networkName);
        console.log("Beacon address:", beaconAddress);
        console.log("Expected implementation:", expectedImpl);
        console.log("");
        
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);
        
        address currentImpl = beacon.implementation();
        address owner = beacon.owner();
        
        console.log("=== BEACON STATUS ===");
        console.log("Current implementation:", currentImpl);
        console.log("Expected implementation:", expectedImpl);
        console.log("Implementation correct:", currentImpl == expectedImpl);
        console.log("Beacon owner:", owner);
        console.log("");
        
        if (currentImpl == expectedImpl) {
            console.log("SUCCESS: Beacon upgrade confirmed");
        } else {
            console.log("ERROR: Beacon still points to old implementation");
        }
        
        console.log("========== BEACON STATUS CHECK COMPLETE ==========");
    }
}