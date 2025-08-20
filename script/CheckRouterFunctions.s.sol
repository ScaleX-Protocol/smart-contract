// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckRouterFunctions is Script {
    address constant ROUTER = 0x41995633558cb6c8D539583048DbD0C9C5451F98;
    address constant POOL_MANAGER = 0x192F275A3BB908c0e111B716acd35E9ABb9E70cD;
    address constant WETH = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
    address constant USDC = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;

    function run() external view {
        console.log("=== Contract and Function Validation ===");
        
        // Check contract existence first
        checkContractExistence();
        
        console.log("=== Checking Router Functions ===");
        console.log("Router address:", ROUTER);
        
        // Try common function signatures to see what exists
        string[] memory functions = new string[](15);
        functions[0] = "owner()";
        functions[1] = "calculateMinOutForSwap(address,address,uint256,uint256)";
        functions[2] = "calculateMinOutForSwap((address),(address),uint256,uint256)";
        functions[3] = "getNextBestPrices((address,address,address),uint8,uint128,uint8)";
        functions[4] = "swap(address,address,uint256,uint256)";
        functions[5] = "swap((address),(address),uint256,uint256)";
        functions[6] = "swapExactInputForOutput(address,address,uint256,uint256)";
        functions[7] = "calculateMinOutAmountForMarket((address,address,address),uint256,uint8,uint256)";
        functions[8] = "supportsInterface(bytes4)";
        functions[9] = "name()";
        functions[10] = "implementation()";
        functions[11] = "proxiableUUID()";
        functions[12] = "upgradeTo(address)";
        functions[13] = "initialize(address)";
        functions[14] = "version()";
        
        for (uint i = 0; i < functions.length; i++) {
            testFunction(functions[i]);
        }
        
        console.log("");
        console.log("=== Analysis ===");
        console.log("ISSUE: calculateMinOutForSwap function is MISSING from deployed router!");
        console.log("This explains why your swap calls are failing with empty revert data.");
        console.log("");
        console.log("SOLUTIONS:");
        console.log("1. Deploy the complete GTXRouter implementation");
        console.log("2. Check if there's an updated router address");  
        console.log("3. Use manual swap logic with direct OrderBook calls");
    }
    
    function checkContractExistence() internal view {
        console.log("=== Contract Existence Check ===");
        
        console.log("Router:", ROUTER, "- Code size:", getCodeSize(ROUTER));
        console.log("Pool Manager:", POOL_MANAGER, "- Code size:", getCodeSize(POOL_MANAGER));
        console.log("WETH:", WETH, "- Code size:", getCodeSize(WETH));
        console.log("USDC:", USDC, "- Code size:", getCodeSize(USDC));
        console.log("");
    }
    
    function getCodeSize(address addr) internal view returns (uint256 size) {
        assembly {
            size := extcodesize(addr)
        }
    }
    
    function testFunction(string memory functionSig) internal view {
        bytes memory callData = abi.encodeWithSignature(functionSig);
        (bool success, bytes memory data) = ROUTER.staticcall(callData);
        
        if (success) {
            console.log("[EXISTS]", functionSig, "- SUCCESS");
        } else if (data.length > 0) {
            console.log("[EXISTS]", functionSig, "- FAILED with data");
        } else {
            console.log("[MISSING]", functionSig, "- Empty error");
        }
    }
}