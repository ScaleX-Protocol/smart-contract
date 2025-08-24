// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IBalanceManager {
    function setTokenRegistry(address _tokenRegistry) external;
    function getTokenRegistry() external view returns (address);
}

contract FixBalanceManagerTokenRegistry is Script {
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    address constant TOKEN_REGISTRY = 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Fix BalanceManager TokenRegistry ===");
        
        IBalanceManager bm = IBalanceManager(BALANCE_MANAGER);
        
        address current = bm.getTokenRegistry();
        console.log("Current TokenRegistry:", current);
        console.log("Setting to:", TOKEN_REGISTRY);
        
        bm.setTokenRegistry(TOKEN_REGISTRY);
        
        address updated = bm.getTokenRegistry();
        console.log("Updated TokenRegistry:", updated);
        
        if (updated == TOKEN_REGISTRY) {
            console.log("SUCCESS: BalanceManager TokenRegistry fixed!");
        } else {
            console.log("ERROR: Update failed");
        }

        vm.stopBroadcast();
    }
}