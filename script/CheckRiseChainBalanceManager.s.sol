// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IChainBalanceManager {
    function getMailboxConfig() external view returns (address mailbox, uint32 localDomain);
    function getCrossChainInfo() external view returns (
        address mailbox,
        uint32 localDomain, 
        uint32 destinationDomain,
        address destinationBalanceManager
    );
    function getDestinationConfig() external view returns (uint32 destinationDomain, address destinationBalanceManager);
}

contract CheckRiseChainBalanceManager is Script {
    // From deployments/rise-sepolia.json
    address constant RISE_CBM = 0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745;
    address constant RISE_MAILBOX = 0xD377bFbea110cDbc3D31EaFB146AE6fA5b3190E3;
    uint32 constant EXPECTED_LOCAL_DOMAIN = 11155931;   // Rise Chain ID
    uint32 constant EXPECTED_DEST_DOMAIN = 1918988905;  // Rari domain
    address constant EXPECTED_DEST_BM = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5; // Rari BalanceManager

    function run() external view {
        console.log("=== Rise ChainBalanceManager Configuration Check ===");
        console.log("ChainBalanceManager Address:", RISE_CBM);
        console.log("Expected Mailbox:", RISE_MAILBOX);
        console.log("Expected Local Domain:", EXPECTED_LOCAL_DOMAIN);
        console.log("Expected Destination Domain:", EXPECTED_DEST_DOMAIN);
        console.log("");

        IChainBalanceManager cbm = IChainBalanceManager(RISE_CBM);
        
        // Check basic mailbox configuration
        console.log("Basic Mailbox Configuration:");
        try cbm.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
            console.log("  Configured Mailbox:", mailbox);
            console.log("  Configured Local Domain:", localDomain);
            
            if (mailbox == RISE_MAILBOX) {
                console.log("  Mailbox Status: CORRECT");
            } else {
                console.log("  Mailbox Status: INCORRECT");
            }
            
            if (localDomain == EXPECTED_LOCAL_DOMAIN) {
                console.log("  Local Domain Status: CORRECT");
            } else {
                console.log("  Local Domain Status: INCORRECT");
                console.log("  This will cause Hyperlane message origin mismatch!");
            }
        } catch {
            console.log("  ERROR: Failed to get mailbox config");
        }
        console.log("");
        
        // Check full cross-chain configuration
        console.log("Full Cross-Chain Configuration:");
        try cbm.getCrossChainInfo() returns (
            address mailbox,
            uint32 localDomain, 
            uint32 destinationDomain,
            address destinationBalanceManager
        ) {
            console.log("  Mailbox:", mailbox);
            console.log("  Local Domain:", localDomain);
            console.log("  Destination Domain:", destinationDomain);
            console.log("  Destination BalanceManager:", destinationBalanceManager);
            console.log("");
            
            console.log("Configuration Validation:");
            if (localDomain == EXPECTED_LOCAL_DOMAIN) {
                console.log("  OK: Local domain matches Rise Chain ID");
            } else {
                console.log("  ERROR: Local domain MISMATCH - This is likely the issue!");
                console.log("     Expected: %s, Got: %s", EXPECTED_LOCAL_DOMAIN, localDomain);
            }
            
            if (destinationDomain == EXPECTED_DEST_DOMAIN) {
                console.log("  OK: Destination domain matches Rari domain");
            } else {
                console.log("  ERROR: Destination domain MISMATCH");
                console.log("     Expected: %s, Got: %s", EXPECTED_DEST_DOMAIN, destinationDomain);
            }
            
            if (destinationBalanceManager == EXPECTED_DEST_BM) {
                console.log("  OK: Destination BalanceManager is correct");
            } else {
                console.log("  ERROR: Destination BalanceManager MISMATCH");
                console.log("     Expected: %s", EXPECTED_DEST_BM);
                console.log("     Got:      %s", destinationBalanceManager);
            }
            
        } catch {
            console.log("  ERROR: Failed to get cross-chain info");
        }
        console.log("");
        
        // Check destination configuration separately (fallback method)
        console.log("Destination Configuration (Fallback Check):");
        try cbm.getDestinationConfig() returns (uint32 destinationDomain, address destinationBalanceManager) {
            console.log("  Destination Domain:", destinationDomain);
            console.log("  Destination BalanceManager:", destinationBalanceManager);
        } catch {
            console.log("  ERROR: Failed to get destination config");
        }
        
        console.log("");
        console.log("=== Diagnosis Summary ===");
        console.log("If Rise deposits are failing with 'UnknownOriginChain' error:");
        console.log("1. Check if Rise CBM local domain = 11155931");
        console.log("2. Check if Rari BM has chainBalanceManager[11155931] set");
        console.log("3. Verify Hyperlane message _origin matches the local domain");
        console.log("=== Configuration Check Complete ===");
    }
}