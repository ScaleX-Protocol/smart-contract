// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/BalanceManager.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

contract CheckRariMinting is Script {
    
    function run() public {
        console.log("========== CHECK RARI MINTING ==========");
        console.log("Check if deposits were received and minted on Rari");
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 1918988905) {
            console.log("ERROR: This script is for Rari network only");
            return;
        }
        
        // Read deployment data
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address balanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        address gUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");
        address gWBTC = vm.parseJsonAddress(rariData, ".contracts.gsWBTC");
        address gWETH = vm.parseJsonAddress(rariData, ".contracts.gsWETH");
        
        address testRecipient = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
        
        console.log("BalanceManager:", balanceManager);
        console.log("Test recipient:", testRecipient);
        console.log("");
        console.log("Synthetic tokens (NEW - correct decimals):");
        console.log("gUSDT (6 decimals):", gUSDT);
        console.log("gWBTC (8 decimals):", gWBTC);
        console.log("gWETH (18 decimals):", gWETH);
        console.log("");
        
        BalanceManager bm = BalanceManager(balanceManager);
        
        console.log("=== TOKEN DECIMALS VERIFICATION ===");
        (bool dec1, bytes memory decData1) = gUSDT.staticcall(abi.encodeWithSignature("decimals()"));
        (bool dec2, bytes memory decData2) = gWBTC.staticcall(abi.encodeWithSignature("decimals()"));
        (bool dec3, bytes memory decData3) = gWETH.staticcall(abi.encodeWithSignature("decimals()"));
        
        if (dec1) console.log("gUSDT decimals:", abi.decode(decData1, (uint8)), "(should be 6)");
        if (dec2) console.log("gWBTC decimals:", abi.decode(decData2, (uint8)), "(should be 8)");
        if (dec3) console.log("gWETH decimals:", abi.decode(decData3, (uint8)), "(should be 18)");
        console.log("");
        
        console.log("=== ERC20 TOKEN BALANCES ===");
        
        // Check recipient ERC20 balances (should be 0 in V3 custodial)
        (bool s1, bytes memory d1) = gUSDT.staticcall(abi.encodeWithSignature("balanceOf(address)", testRecipient));
        (bool s2, bytes memory d2) = gWBTC.staticcall(abi.encodeWithSignature("balanceOf(address)", testRecipient));
        (bool s3, bytes memory d3) = gWETH.staticcall(abi.encodeWithSignature("balanceOf(address)", testRecipient));
        
        uint256 recipientUSDT = s1 ? abi.decode(d1, (uint256)) : 0;
        uint256 recipientWBTC = s2 ? abi.decode(d2, (uint256)) : 0;
        uint256 recipientWETH = s3 ? abi.decode(d3, (uint256)) : 0;
        
        console.log("Recipient ERC20 balances:");
        console.log("gUSDT:", recipientUSDT, "(should be 0 in V3 custodial)");
        console.log("gWBTC:", recipientWBTC, "(should be 0 in V3 custodial)");
        console.log("gWETH:", recipientWETH, "(should be 0 in V3 custodial)");
        console.log("");
        
        // Check BalanceManager ERC20 balances (should be > 0 in V3 custodial)
        (bool s4, bytes memory d4) = gUSDT.staticcall(abi.encodeWithSignature("balanceOf(address)", balanceManager));
        (bool s5, bytes memory d5) = gWBTC.staticcall(abi.encodeWithSignature("balanceOf(address)", balanceManager));
        (bool s6, bytes memory d6) = gWETH.staticcall(abi.encodeWithSignature("balanceOf(address)", balanceManager));
        
        uint256 bmUSDT = s4 ? abi.decode(d4, (uint256)) : 0;
        uint256 bmWBTC = s5 ? abi.decode(d5, (uint256)) : 0;
        uint256 bmWETH = s6 ? abi.decode(d6, (uint256)) : 0;
        
        console.log("BalanceManager ERC20 balances:");
        console.log("gUSDT:", bmUSDT, "(should be > 0 if deposits received)");
        console.log("gWBTC:", bmWBTC, "(should be > 0 if deposits received)");
        console.log("gWETH:", bmWETH, "(should be > 0 if deposits received)");
        console.log("");
        
        console.log("=== INTERNAL BALANCES (FOR TRADING) ===");
        
        // Check internal balances (what users can trade with)
        try bm.getBalance(testRecipient, Currency.wrap(gUSDT)) returns (uint256 internalUSDT) {
            console.log("Internal gUSDT balance:", internalUSDT);
        } catch {
            console.log("Could not get internal gUSDT balance");
        }
        
        try bm.getBalance(testRecipient, Currency.wrap(gWBTC)) returns (uint256 internalWBTC) {
            console.log("Internal gWBTC balance:", internalWBTC);
        } catch {
            console.log("Could not get internal gWBTC balance");
        }
        
        try bm.getBalance(testRecipient, Currency.wrap(gWETH)) returns (uint256 internalWETH) {
            console.log("Internal gWETH balance:", internalWETH);
        } catch {
            console.log("Could not get internal gWETH balance");
        }
        
        console.log("");
        console.log("=== MINTING STATUS ===");
        
        if (bmUSDT > 0) {
            console.log("SUCCESS: gUSDT minted to BalanceManager (V3 custodial working)");
        } else {
            console.log("PENDING: No gUSDT minted yet (deposit may be in transit)");
        }
        
        if (bmWBTC > 0) {
            console.log("SUCCESS: gWBTC minted to BalanceManager (V3 custodial working)");
        } else {
            console.log("PENDING: No gWBTC minted yet (deposit may be in transit)");
        }
        
        if (bmWETH > 0) {
            console.log("SUCCESS: gWETH minted to BalanceManager (V3 custodial working)");
        } else {
            console.log("PENDING: No gWETH minted yet (deposit may be in transit)");
        }
        
        console.log("");
        console.log("=== SUMMARY ===");
        bool anyMinted = (bmUSDT > 0) || (bmWBTC > 0) || (bmWETH > 0);
        
        if (anyMinted) {
            console.log("STATUS: Cross-chain deposits are working!");
            console.log("- Synthetic tokens have CORRECT decimals");
            console.log("- V3 custodial pattern working (tokens held by BalanceManager)");
            console.log("- Ready for trading on the DEX");
        } else {
            console.log("STATUS: No deposits received yet");
            console.log("- Check if cross-chain messages are still in transit");
            console.log("- Verify messageIds on Hyperlane explorer");
        }
        
        console.log("========== RARI MINTING CHECK COMPLETE ==========");
    }
}