// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

contract TestCalculateMinOut is Script {
    address constant ROUTER = 0x41995633558cb6c8D539583048DbD0C9C5451F98;
    address constant WETH = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
    address constant USDC = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;
    uint256 constant INPUT_AMOUNT = 100000000000000000; // 0.1 ETH
    uint256 constant SLIPPAGE_BPS = 500; // 5%

    function run() external view {
        console.log("=== Testing calculateMinOutForSwap ===");
        console.log("Router:", ROUTER);
        console.log("WETH:", WETH);
        console.log("USDC:", USDC);
        console.log("Input Amount:", INPUT_AMOUNT);
        console.log("Slippage BPS:", SLIPPAGE_BPS);
        console.log("");
        
        // The function signature is: calculateMinOutForSwap(Currency,Currency,uint256,uint256)
        // Currency is a custom type that wraps an address
        bytes memory callData = abi.encodeWithSignature(
            "calculateMinOutForSwap((address),(address),uint256,uint256)",
            WETH,  // This gets wrapped as Currency
            USDC,  // This gets wrapped as Currency  
            INPUT_AMOUNT,
            SLIPPAGE_BPS
        );
        
        console.log("Calling calculateMinOutForSwap with Currency parameters...");
        (bool success, bytes memory data) = ROUTER.staticcall(callData);
        
        console.log("Call success:", success);
        console.log("Return data length:", data.length);
        
        if (success && data.length >= 32) {
            uint128 minOut = abi.decode(data, (uint128));
            console.log("SUCCESS! Min out amount:", minOut);
        } else if (!success) {
            console.log("Call failed. Error data:");
            if (data.length > 0) {
                console.logBytes(data);
                
                // Try to decode common error types
                if (data.length >= 4) {
                    bytes4 errorSig = bytes4(data);
                    console.log("Error selector:", vm.toString(errorSig));
                    
                    if (errorSig == 0x08c379a0) { // Error(string)
                        // Skip the first 4 bytes (selector) to decode the string
                        bytes memory errorData = new bytes(data.length - 4);
                        for (uint i = 0; i < data.length - 4; i++) {
                            errorData[i] = data[i + 4];
                        }
                        string memory errorMsg = abi.decode(errorData, (string));
                        console.log("Error message:", errorMsg);
                    } else if (errorSig == 0x4e487b71) { // Panic(uint256)
                        // Skip the first 4 bytes (selector) to decode the uint256
                        bytes memory panicData = new bytes(data.length - 4);
                        for (uint i = 0; i < data.length - 4; i++) {
                            panicData[i] = data[i + 4];
                        }
                        uint256 panicCode = abi.decode(panicData, (uint256));
                        console.log("Panic code:", panicCode);
                    }
                }
            } else {
                console.log("Empty error data - function likely doesn't exist or has wrong signature");
            }
        }
    }
}