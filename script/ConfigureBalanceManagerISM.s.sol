// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IISMConfigurable {
    function setInterchainSecurityModule(address _module) external;
    function interchainSecurityModule() external view returns (address);
}

contract ConfigureBalanceManagerISM is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Switch to Rari RPC  
        vm.createSelectFork(vm.envString("RARI_ENDPOINT"));
        
        address balanceManagerAddr = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
        address workingISM = 0xb5208A993B99ddAFa33Eb7C3c9855Af4A715c135; // From testRecipient
        
        console.log("========== CONFIGURING BALANCE MANAGER ISM ==========");
        console.log("BalanceManager:", balanceManagerAddr);
        console.log("Using ISM from testRecipient:", workingISM);
        
        // Check current ISM
        IISMConfigurable balanceManager = IISMConfigurable(balanceManagerAddr);
        
        try balanceManager.interchainSecurityModule() returns (address currentISM) {
            console.log("Current ISM:", currentISM);
            if (currentISM == workingISM) {
                console.log("ISM already configured correctly!");
                return;
            }
        } catch {
            console.log("BalanceManager doesn't support ISM configuration");
            console.log("This might be why messages aren't being processed");
            return;
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        try balanceManager.setInterchainSecurityModule(workingISM) {
            console.log("SUCCESS: ISM configured for BalanceManager");
        } catch Error(string memory reason) {
            console.log("FAILED to set ISM:", reason);
        } catch {
            console.log("FAILED to set ISM - function might not exist");
        }
        
        vm.stopBroadcast();
        
        // Verify the ISM
        try balanceManager.interchainSecurityModule() returns (address newISM) {
            console.log("New ISM:", newISM);
            if (newISM == workingISM) {
                console.log("SUCCESS: ISM configuration complete!");
                console.log("BalanceManager should now receive cross-chain messages");
            } else {
                console.log("ERROR: ISM not set correctly");
            }
        } catch {
            console.log("Cannot verify ISM configuration");
        }
        
        console.log("========== ISM CONFIGURATION COMPLETE ==========");
    }
}