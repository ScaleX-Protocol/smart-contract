// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPoolManager {
    function execute(address target, bytes calldata data) external payable returns (bytes memory);
}

interface IOrderBook {
    function setRouter(address router) external;
    function owner() external view returns (address);
}

contract AuthorizeAgentRouter is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== AUTHORIZE AGENT ROUTER IN ORDERBOOK ===");
        console.log("Deployer:", deployer);
        console.log("");

        // Load addresses
        string memory root = vm.projectRoot();
        string memory deploymentPath = string.concat(root, "/deployments/84532.json");
        string memory json = vm.readFile(deploymentPath);

        address poolManager = _extractAddress(json, "PoolManager");
        address agentRouter = _extractAddress(json, "AgentRouter");
        address wethIDRXPool = _extractAddress(json, "WETH_IDRX_Pool");

        console.log("PoolManager:", poolManager);
        console.log("AgentRouter:", agentRouter);
        console.log("WETH/IDRX OrderBook:", wethIDRXPool);
        console.log("");

        // Check OrderBook owner
        address orderBookOwner = IOrderBook(wethIDRXPool).owner();
        console.log("OrderBook owner:", orderBookOwner);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Use vm.prank to call as PoolManager
        console.log("Setting AgentRouter as authorized router on OrderBook...");

        // Since OrderBook.setRouter is onlyOwner and owner is PoolManager,
        // we need PoolManager to call it. But PoolManager doesn't have such a function.
        // The workaround: we'll have to accept that agent orders won't work through OrderBook
        // OR we need to update the system architecture.

        // For now, let's just verify the situation
        console.log("");
        console.log("ISSUE: OrderBook only accepts calls from its $.router, owner(), or self");
        console.log("OrderBook owner is PoolManager, not us");
        console.log("PoolManager doesn't have a function to set router on OrderBooks");
        console.log("");
        console.log("SOLUTIONS:");
        console.log("1. Add a function to PoolManager to call setRouter on OrderBooks");
        console.log("2. Have AgentRouter inherit from or wrap the existing router");
        console.log("3. Deploy new OrderBooks with AgentRouter as the router");
        console.log("4. Check if RouterV1 exists and authorize AgentRouter there");

        vm.stopBroadcast();
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(string.concat('"', key, '": "'));

        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) {
            return address(0);
        }

        uint256 addressStart = keyPos + keyBytes.length;
        bytes memory addressBytes = new bytes(42);
        for (uint256 i = 0; i < 42; i++) {
            addressBytes[i] = jsonBytes[addressStart + i];
        }

        return _bytesToAddress(addressBytes);
    }

    function _indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        if (needle.length == 0 || haystack.length < needle.length) {
            return type(uint256).max;
        }

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

    function _bytesToAddress(bytes memory data) internal pure returns (address) {
        return address(uint160(uint256(_hexToUint(data))));
    }

    function _hexToUint(bytes memory data) internal pure returns (uint256) {
        uint256 result = 0;
        for (uint256 i = 0; i < data.length; i++) {
            uint8 byteValue = uint8(data[i]);
            uint256 digit;
            if (byteValue >= 48 && byteValue <= 57) {
                digit = uint256(byteValue) - 48;
            } else if (byteValue >= 97 && byteValue <= 102) {
                digit = uint256(byteValue) - 87;
            } else if (byteValue >= 65 && byteValue <= 70) {
                digit = uint256(byteValue) - 55;
            } else {
                continue;
            }
            result = result * 16 + digit;
        }
        return result;
    }
}
