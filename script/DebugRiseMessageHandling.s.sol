// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IBalanceManager {
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _messageBody) external payable;
    function getChainBalanceManager(uint32 chainId) external view returns (address);
    function isMessageProcessed(bytes32 messageId) external view returns (bool);
}

contract DebugRiseMessageHandling is Script {
    // From deployments
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    address constant RISE_CBM = 0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745;
    uint32 constant RISE_DOMAIN = 11155931;
    address constant RARI_MAILBOX = 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358;

    function run() external view {
        console.log("=== Debugging Rise Message Handling ===");
        console.log("BalanceManager:", BALANCE_MANAGER);
        console.log("Rise CBM:", RISE_CBM);
        console.log("Rise Domain:", RISE_DOMAIN);
        console.log("Rari Mailbox:", RARI_MAILBOX);
        console.log("");

        IBalanceManager bm = IBalanceManager(BALANCE_MANAGER);
        
        // Check Rise registration
        console.log("Rise Registration Check:");
        address registeredCBM = bm.getChainBalanceManager(RISE_DOMAIN);
        console.log("  Registered ChainBalanceManager:", registeredCBM);
        console.log("  Expected ChainBalanceManager:", RISE_CBM);
        
        if (registeredCBM == RISE_CBM) {
            console.log("  Status: REGISTRATION OK");
        } else {
            console.log("  Status: REGISTRATION FAILED");
            return;
        }
        console.log("");
        
        // Check if specific messages were processed
        console.log("Message Processing Status:");
        
        // Create a test message to see what messageId would be generated
        bytes memory testMessageBody = abi.encode(
            uint8(1), // DEPOSIT_MESSAGE
            address(0xf2dc96d3e25f06e7458ff670cf1c9218bbb71d9d), // gUSDT synthetic
            address(0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74), // recipient
            uint256(100000000000), // 100k USDT
            uint32(RISE_DOMAIN), // source chain
            uint256(7) // nonce from logs
        );
        
        // Calculate expected message ID (simplified version)
        bytes32 expectedSender = bytes32(uint256(uint160(RISE_CBM)));
        bytes32 testMessageId = keccak256(abi.encodePacked(RISE_DOMAIN, expectedSender, testMessageBody));
        
        console.log("  Test message ID:", vm.toString(testMessageId));
        console.log("  Is processed:", bm.isMessageProcessed(testMessageId));
        console.log("");
        
        console.log("=== Possible Issues ===");
        console.log("1. Rise relayer may not have sufficient gas/ETH on Rari");
        console.log("2. Message format mismatch between Rise CBM and Rari BM");
        console.log("3. Replay protection triggering incorrectly");
        console.log("4. Mailbox permission issues");
        console.log("");
        console.log("Next: Check relayer wallet balance and gas settings");
    }
}