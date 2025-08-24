// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract CheckMessageIds is Script {
    
    function run() public {
        console.log("========== CHECK MESSAGE IDS ==========");
        console.log("Getting recent cross-chain deposit message IDs");
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 4661) {
            console.log("ERROR: This script is for Appchain Testnet only");
            return;
        }
        
        address deployer = 0x77C037fbF42e85dB1487B390b08f58C00f438812;
        address chainBalanceManager = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        address mailbox = 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1;
        
        console.log("Deployer:", deployer);
        console.log("ChainBalanceManager:", chainBalanceManager);  
        console.log("Mailbox:", mailbox);
        console.log("");
        
        // The deposit transactions should have emitted MessageDispatched events from the mailbox
        console.log("=== RECENT MESSAGE IDS ===");
        console.log("Check these transaction hashes on block explorer:");
        console.log("");
        
        // Get the recent block range to search for events
        uint256 currentBlock = block.number;
        uint256 fromBlock = currentBlock - 100; // Look back 100 blocks
        
        console.log("Searching from block", fromBlock, "to", currentBlock);
        console.log("");
        
        // The best way is to look at the actual transaction logs from the explorer
        console.log("=== HOW TO FIND MESSAGE IDS ===");
        console.log("1. Go to Appchain block explorer");
        console.log("2. Search for deployer address:", deployer);
        console.log("3. Look for recent 'deposit' transactions to ChainBalanceManager");
        console.log("4. In each transaction, look for 'MessageDispatched' event from mailbox:", mailbox);
        console.log("5. The 'messageId' parameter is what you need");
        console.log("");
        
        // Try to get recent transaction count
        uint256 currentNonce = vm.getNonce(deployer);
        console.log("Current nonce:", currentNonce);
        console.log("Recent deposit transactions should be at nonces:");
        console.log("- USDT deposit: nonce", currentNonce - 5, "to", currentNonce - 4);
        console.log("- WBTC deposit: nonce", currentNonce - 3, "to", currentNonce - 2); 
        console.log("- WETH deposit: nonce", currentNonce - 1, "to", currentNonce);
        console.log("");
        
        console.log("=== HYPERLANE EXPLORER LINKS ===");
        console.log("Once you have the messageId, track it here:");
        console.log("https://hyperlane-explorer.gtxdex.xyz/message/{messageId}");
        console.log("");
        console.log("Expected destination:");
        console.log("- Chain: Rari (domain 1918988905)");
        console.log("- Recipient: BalanceManager at 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5");
        console.log("- Synthetic tokens:");
        console.log("  - gUSDT: 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d (6 decimals)");
        console.log("  - gWBTC: 0xd99813A6152dBB2026b2Cd4298CF88fAC1bCf748 (8 decimals)");
        console.log("  - gWETH: 0x3ffE82D34548b9561530AFB0593d52b9E9446fC8 (18 decimals)");
        
        console.log("========== MESSAGE ID CHECK COMPLETE ==========");
    }
}