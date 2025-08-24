// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract RedeployArbitrumChainBalanceManager is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== REDEPLOY ARBITRUM CHAIN BALANCE MANAGER ==========");
        console.log("Deploy new ChainBalanceManager with correct beacon proxy pattern");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 421614) {
            console.log("ERROR: This script is for Arbitrum Sepolia only");
            return;
        }
        
        // Read deployment data
        string memory arbitrumData = vm.readFile("deployments/arbitrum-sepolia.json");
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address oldChainBalanceManager = vm.parseJsonAddress(arbitrumData, ".contracts.ChainBalanceManager");
        address mailbox = vm.parseJsonAddress(arbitrumData, ".mailbox");
        uint32 rariDomain = uint32(vm.parseJsonUint(rariData, ".domainId"));
        address rariBalanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        
        console.log("");
        console.log("OLD ChainBalanceManager:", oldChainBalanceManager);
        console.log("Mailbox:", mailbox);
        console.log("Rari domain:", rariDomain);
        console.log("Rari BalanceManager:", rariBalanceManager);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== DEPLOY NEW BEACON PROXY PATTERN ===");
        
        // 1. Deploy new implementation
        ChainBalanceManager implementation = new ChainBalanceManager();
        console.log("New implementation:", address(implementation));
        
        // 2. Deploy beacon
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), deployer);
        console.log("New beacon:", address(beacon));
        
        // 3. Deploy beacon proxy with initialization
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,uint32,address)",
            deployer,           // owner
            mailbox,           // mailbox (correct for Arbitrum)
            rariDomain,        // destination domain (Rari)
            rariBalanceManager // destination BalanceManager (Rari V3)
        );
        
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        address newChainBalanceManager = address(proxy);
        
        console.log("New ChainBalanceManager (proxy):", newChainBalanceManager);
        console.log("");
        
        // 4. Verify initialization
        ChainBalanceManager cbm = ChainBalanceManager(newChainBalanceManager);
        
        console.log("=== VERIFY INITIALIZATION ===");
        
        try cbm.getMailboxConfig() returns (address verifyMailbox, uint32 localDomain) {
            console.log("Mailbox:", verifyMailbox);
            console.log("Local domain:", localDomain);
            console.log("Local domain correct:", localDomain == block.chainid);
        } catch Error(string memory reason) {
            console.log("FAILED to verify mailbox config:", reason);
        }
        
        try cbm.getCrossChainConfig() returns (uint32 destDomain, address destManager) {
            console.log("Destination domain:", destDomain);
            console.log("Destination manager:", destManager);
            console.log("Destination correct:", destManager == rariBalanceManager);
        } catch Error(string memory reason) {
            console.log("FAILED to verify cross-chain config:", reason);
        }
        
        console.log("");
        console.log("=== RECONFIGURE TOKENS ===");
        
        // Token addresses from current deployment
        address sourceUSDT = vm.parseJsonAddress(arbitrumData, ".contracts.USDT");
        address sourceWBTC = vm.parseJsonAddress(arbitrumData, ".contracts.WBTC");
        address sourceWETH = vm.parseJsonAddress(arbitrumData, ".contracts.WETH");
        
        // NEW synthetic tokens (correct decimals)
        address gsUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");
        address gsWBTC = vm.parseJsonAddress(rariData, ".contracts.gsWBTC");
        address gsWETH = vm.parseJsonAddress(rariData, ".contracts.gsWETH");
        
        console.log("Configuring tokens...");
        
        // Whitelist tokens
        try cbm.addToken(sourceUSDT) {
            console.log("USDT whitelisted");
        } catch Error(string memory reason) {
            console.log("USDT whitelist failed:", reason);
        }
        
        try cbm.addToken(sourceWBTC) {
            console.log("WBTC whitelisted");
        } catch Error(string memory reason) {
            console.log("WBTC whitelist failed:", reason);
        }
        
        try cbm.addToken(sourceWETH) {
            console.log("WETH whitelisted");
        } catch Error(string memory reason) {
            console.log("WETH whitelist failed:", reason);
        }
        
        // Set token mappings (to NEW synthetic tokens)
        try cbm.setTokenMapping(sourceUSDT, gsUSDT) {
            console.log("USDT -> gsUSDT mapping set");
        } catch Error(string memory reason) {
            console.log("USDT mapping failed:", reason);
        }
        
        try cbm.setTokenMapping(sourceWBTC, gsWBTC) {
            console.log("WBTC -> gsWBTC mapping set");
        } catch Error(string memory reason) {
            console.log("WBTC mapping failed:", reason);
        }
        
        try cbm.setTokenMapping(sourceWETH, gsWETH) {
            console.log("WETH -> gsWETH mapping set");
        } catch Error(string memory reason) {
            console.log("WETH mapping failed:", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("OLD ChainBalanceManager:", oldChainBalanceManager);
        console.log("NEW ChainBalanceManager:", newChainBalanceManager);
        console.log("Implementation:", address(implementation));
        console.log("Beacon:", address(beacon));
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Update Rari BalanceManager registry:");
        console.log("   setChainBalanceManager(421614,", newChainBalanceManager, ")");
        console.log("2. Update deployment files with new address");
        console.log("3. Test deposits from new Arbitrum ChainBalanceManager");
        
        console.log("========== ARBITRUM REDEPLOYMENT COMPLETE ==========");
    }
}