// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";

contract DebugChainBalanceManagerConfig is Script {
    
    function run() public {
        console.log("========== DEBUGGING CHAINBALANCEMANAGER CONFIG ==========");
        
        // Connect to Appchain where ChainBalanceManager is deployed
        vm.createSelectFork(vm.envString("APPCHAIN_ENDPOINT"));
        
        address chainBalanceManagerAddr = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
        console.log("ChainBalanceManager address:", chainBalanceManagerAddr);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManagerAddr);
        
        console.log("=== 1. BASIC CONTRACT CHECKS ===");
        
        // Check if contract exists and has code
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(chainBalanceManagerAddr)
        }
        console.log("Contract code size:", codeSize);
        
        if (codeSize == 0) {
            console.log("ERROR: No contract at this address!");
            return;
        }
        
        console.log("=== 2. STORAGE SLOT EXAMINATION ===");
        
        // ChainBalanceManagerStorage uses a specific storage slot
        // bytes32 private constant STORAGE_SLOT = bytes32(uint256(keccak256("gtx.clob.storage.chainbalancemanager")) - 1);
        bytes32 storageSlot = bytes32(uint256(keccak256("gtx.clob.storage.chainbalancemanager")) - 1);
        console.log("Expected storage slot:");
        console.logBytes32(storageSlot);
        
        // Try to read storage directly for key fields
        // Storage struct layout:
        // mapping(address => mapping(address => uint256)) balanceOf;           // slot 0 in struct
        // mapping(address => mapping(address => uint256)) unlockedBalanceOf;   // slot 1 in struct  
        // mapping(address => bool) whitelistedTokens;                          // slot 2 in struct
        // address[] tokenList;                                                 // slot 3 in struct
        // mapping(address => address) sourceToSynthetic;                      // slot 4 in struct
        // mapping(address => address) syntheticToSource;                      // slot 5 in struct
        // address mailbox;                                                     // slot 6 in struct
        // uint32 localDomain;                                                  // slot 7 in struct (packed)
        // uint32 destinationDomain;                                            // slot 8 in struct
        // address destinationBalanceManager;                                   // slot 9 in struct
        
        bytes32 mailboxSlot = bytes32(uint256(storageSlot) + 6);
        bytes32 localDomainSlot = bytes32(uint256(storageSlot) + 7);
        bytes32 destinationDomainSlot = bytes32(uint256(storageSlot) + 8);
        bytes32 destinationBalanceManagerSlot = bytes32(uint256(storageSlot) + 9);
        
        bytes32 mailboxData = vm.load(chainBalanceManagerAddr, mailboxSlot);
        bytes32 localDomainData = vm.load(chainBalanceManagerAddr, localDomainSlot);
        bytes32 destinationDomainData = vm.load(chainBalanceManagerAddr, destinationDomainSlot);
        bytes32 destinationBalanceManagerData = vm.load(chainBalanceManagerAddr, destinationBalanceManagerSlot);
        
        console.log("=== 3. RAW STORAGE DATA ===");
        console.log("Mailbox slot data:");
        console.logBytes32(mailboxData);
        console.log("Local domain slot data:");
        console.logBytes32(localDomainData);
        console.log("Destination domain slot data:");
        console.logBytes32(destinationDomainData);
        console.log("Destination balance manager slot data:");
        console.logBytes32(destinationBalanceManagerData);
        
        // Convert raw data
        address mailboxFromStorage = address(uint160(uint256(mailboxData)));
        uint32 localDomainFromStorage = uint32(uint256(localDomainData));
        uint32 destinationDomainFromStorage = uint32(uint256(destinationDomainData));
        address destinationBalanceManagerFromStorage = address(uint160(uint256(destinationBalanceManagerData)));
        
        console.log("=== 4. PARSED STORAGE VALUES ===");
        console.log("Mailbox from storage:", mailboxFromStorage);
        console.log("Local domain from storage:", localDomainFromStorage);
        console.log("Destination domain from storage:", destinationDomainFromStorage);
        console.log("Destination balance manager from storage:", destinationBalanceManagerFromStorage);
        
        console.log("=== 5. FUNCTION CALL TESTS ===");
        
        // Test getMailboxConfig() - this should work according to fix script
        try cbm.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
            console.log("SUCCESS: getMailboxConfig() returned:");
            console.log("  Mailbox:", mailbox);
            console.log("  Local domain:", localDomain);
        } catch Error(string memory reason) {
            console.log("FAILED: getMailboxConfig() error:", reason);
        } catch (bytes memory data) {
            console.log("FAILED: getMailboxConfig() with low-level error:");
            console.logBytes(data);
        }
        
        // Test getCrossChainConfig() - legacy function
        try cbm.getCrossChainConfig() returns (uint32 destinationDomain, address destinationBalanceManager) {
            console.log("SUCCESS: getCrossChainConfig() returned:");
            console.log("  Destination domain:", destinationDomain);
            console.log("  Destination balance manager:", destinationBalanceManager);
        } catch Error(string memory reason) {
            console.log("FAILED: getCrossChainConfig() error:", reason);
        } catch (bytes memory data) {
            console.log("FAILED: getCrossChainConfig() with low-level error:");
            console.logBytes(data);
        }
        
        // Test getDestinationConfig() - this is the problematic function
        try cbm.getDestinationConfig() returns (uint32 destinationDomain, address destinationBalanceManager) {
            console.log("SUCCESS: getDestinationConfig() returned:");
            console.log("  Destination domain:", destinationDomain);
            console.log("  Destination balance manager:", destinationBalanceManager);
        } catch Error(string memory reason) {
            console.log("FAILED: getDestinationConfig() error:", reason);
        } catch (bytes memory data) {
            console.log("FAILED: getDestinationConfig() with low-level error:");
            console.logBytes(data);
        }
        
        console.log("=== 6. PROXY DETECTION ===");
        
        // Check if this is a proxy contract
        // ERC1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 implData = vm.load(chainBalanceManagerAddr, implSlot);
        address implementation = address(uint160(uint256(implData)));
        
        console.log("ERC1967 implementation slot:");
        console.logBytes32(implData);
        console.log("Implementation address:", implementation);
        
        if (implementation != address(0)) {
            console.log("This is a proxy contract!");
            console.log("Implementation:", implementation);
            
            // Check implementation code size
            uint256 implCodeSize;
            assembly {
                implCodeSize := extcodesize(implementation)
            }
            console.log("Implementation code size:", implCodeSize);
        } else {
            console.log("This is not a proxy contract (or using different proxy pattern)");
        }
        
        console.log("=== 7. OWNERSHIP AND ACCESS ===");
        
        // Check ownership
        try cbm.owner() returns (address owner) {
            console.log("Contract owner:", owner);
        } catch Error(string memory reason) {
            console.log("FAILED to get owner:", reason);
        } catch {
            console.log("FAILED to get owner with unknown error");
        }
        
        console.log("=== 8. EXPECTED VS ACTUAL VALUES ===");
        
        uint32 expectedDestinationDomain = 1918988905; // Rari
        address expectedDestinationBalanceManager = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        
        console.log("Expected destination domain:", expectedDestinationDomain);
        console.log("Actual destination domain:", destinationDomainFromStorage);
        console.log("Domain match:", expectedDestinationDomain == destinationDomainFromStorage);
        
        console.log("Expected destination balance manager:", expectedDestinationBalanceManager);
        console.log("Actual destination balance manager:", destinationBalanceManagerFromStorage);
        console.log("Balance manager match:", expectedDestinationBalanceManager == destinationBalanceManagerFromStorage);
        
        console.log("========== DEBUG COMPLETE ==========");
    }
}