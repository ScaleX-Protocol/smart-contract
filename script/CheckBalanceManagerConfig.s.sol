// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IBalanceManager {
    function getChainBalanceManager(uint32 chainId) external view returns (address);
    function getCrossChainConfig() external view returns (uint32 destinationDomain, address destinationBalanceManager);
    function getMailboxConfig() external view returns (address mailbox, uint32 localDomain);
}

contract CheckBalanceManagerConfig is Script {
    // From deployments/rari.json
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    
    // Expected ChainBalanceManager addresses from deployment files
    uint32 constant RISE_SEPOLIA_CHAIN_ID = 11155931;
    uint32 constant ARBITRUM_SEPOLIA_CHAIN_ID = 421614;
    uint32 constant APPCHAIN_TESTNET_CHAIN_ID = 4661;
    
    address constant RISE_CBM = 0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745;
    address constant ARBITRUM_CBM = 0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A;
    address constant APPCHAIN_CBM = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;

    function run() external view {
        console.log("=== BalanceManager Configuration Check ===");
        console.log("BalanceManager Address:", BALANCE_MANAGER);
        console.log("");

        IBalanceManager bm = IBalanceManager(BALANCE_MANAGER);
        
        // Check mailbox configuration
        try bm.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
            console.log("Mailbox Configuration:");
            console.log("  Mailbox Address:", mailbox);
            console.log("  Local Domain:", localDomain);
            console.log("");
        } catch {
            console.log("ERROR: Failed to get mailbox config");
            console.log("");
        }
        
        // Check chain registrations
        console.log("Chain Balance Manager Registrations:");
        console.log("");
        
        // Rise Sepolia
        console.log("Rise Sepolia (Chain ID: %s)", RISE_SEPOLIA_CHAIN_ID);
        address riseRegistered = bm.getChainBalanceManager(RISE_SEPOLIA_CHAIN_ID);
        console.log("  Registered Address:", riseRegistered);
        console.log("  Expected Address:  ", RISE_CBM);
        if (riseRegistered == address(0)) {
            console.log("  Status: NOT REGISTERED");
        } else if (riseRegistered == RISE_CBM) {
            console.log("  Status: CORRECTLY REGISTERED");
        } else {
            console.log("  Status: WRONG ADDRESS");
        }
        console.log("");
        
        // Arbitrum Sepolia  
        console.log("Arbitrum Sepolia (Chain ID: %s)", ARBITRUM_SEPOLIA_CHAIN_ID);
        address arbitrumRegistered = bm.getChainBalanceManager(ARBITRUM_SEPOLIA_CHAIN_ID);
        console.log("  Registered Address:", arbitrumRegistered);
        console.log("  Expected Address:  ", ARBITRUM_CBM);
        if (arbitrumRegistered == address(0)) {
            console.log("  Status: NOT REGISTERED");
        } else if (arbitrumRegistered == ARBITRUM_CBM) {
            console.log("  Status: CORRECTLY REGISTERED");
        } else {
            console.log("  Status: WRONG ADDRESS");
        }
        console.log("");
        
        // Appchain Testnet
        console.log("Appchain Testnet (Chain ID: %s)", APPCHAIN_TESTNET_CHAIN_ID);
        address appchainRegistered = bm.getChainBalanceManager(APPCHAIN_TESTNET_CHAIN_ID);
        console.log("  Registered Address:", appchainRegistered);
        console.log("  Expected Address:  ", APPCHAIN_CBM);
        if (appchainRegistered == address(0)) {
            console.log("  Status: NOT REGISTERED");
        } else if (appchainRegistered == APPCHAIN_CBM) {
            console.log("  Status: CORRECTLY REGISTERED");
        } else {
            console.log("  Status: WRONG ADDRESS");
        }
        console.log("");
        
        console.log("=== Configuration Check Complete ===");
    }
}