// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";

/**
 * @title CheckOwnership
 * @dev Check ownership and configuration of ChainBalanceManager
 */
contract CheckOwnership is Script {
    
    address constant APPCHAIN_CBM = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
    
    function run() public view {
        console.log("=== Checking ChainBalanceManager Status ===");
        console.log("ChainBalanceManager Address:", APPCHAIN_CBM);
        console.log("Current caller:", msg.sender);
        
        ChainBalanceManager cbm = ChainBalanceManager(APPCHAIN_CBM);
        
        // Check owner
        try cbm.owner() returns (address owner) {
            console.log("Contract owner:", owner);
            console.log("Is caller owner?", owner == msg.sender);
        } catch {
            console.log("Could not read owner");
        }
        
        // Check cross-chain config
        try cbm.getCrossChainConfig() returns (uint32 domain, address bm) {
            console.log("Current destination domain:", domain);
            console.log("Current destination BalanceManager:", bm);
        } catch {
            console.log("Could not read cross-chain config");
        }
        
        // Check mailbox config
        try cbm.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
            console.log("Mailbox:", mailbox);
            console.log("Local domain:", localDomain);
        } catch {
            console.log("Could not read mailbox config");
        }
    }
}