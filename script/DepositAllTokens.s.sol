// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/interfaces/IChainBalanceManager.sol";

contract DepositAllTokens is Script {
    
    // Test recipient address
    address constant RECIPIENT = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
    
    // Test amounts
    uint256 constant AMOUNT_USDT = 50_000000; // 50 USDT (6 decimals)
    uint256 constant AMOUNT_WBTC = 50_000000; // 0.5 WBTC (8 decimals)
    uint256 constant AMOUNT_WETH = 500000000000000000; // 0.5 WETH (18 decimals)
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== DEPOSITING ALL 3 TOKENS ==========");
        console.log("Deployer:", deployer);
        console.log("Recipient:", RECIPIENT);
        console.log("Network:", vm.toString(block.chainid));
        
        if (block.chainid != 4661) {
            console.log("ERROR: Must run on Appchain (4661)");
            return;
        }
        
        // Read deployment data
        string memory deploymentData = vm.readFile("deployments/appchain.json");
        
        address cbm = vm.parseJsonAddress(deploymentData, ".contracts.ChainBalanceManager");
        address usdt = vm.parseJsonAddress(deploymentData, ".contracts.USDT");
        address wbtc = vm.parseJsonAddress(deploymentData, ".contracts.WBTC");
        address weth = vm.parseJsonAddress(deploymentData, ".contracts.WETH");
        
        console.log("");
        console.log("ChainBalanceManager:", cbm);
        console.log("USDT:", usdt);
        console.log("WBTC:", wbtc);
        console.log("WETH:", weth);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Approve and deposit USDT
        console.log("=== DEPOSITING USDT ===");
        console.log("Amount:", AMOUNT_USDT);
        
        (bool success1,) = usdt.call(abi.encodeWithSignature("approve(address,uint256)", cbm, AMOUNT_USDT));
        require(success1, "USDT approve failed");
        console.log("USDT approved");
        
        try IChainBalanceManager(cbm).deposit(usdt, AMOUNT_USDT, RECIPIENT) {
            console.log("SUCCESS: USDT deposit completed");
        } catch Error(string memory reason) {
            console.log("FAILED: USDT deposit -", reason);
        }
        
        // Approve and deposit WBTC
        console.log("");
        console.log("=== DEPOSITING WBTC ===");
        console.log("Amount:", AMOUNT_WBTC);
        
        (bool success2,) = wbtc.call(abi.encodeWithSignature("approve(address,uint256)", cbm, AMOUNT_WBTC));
        require(success2, "WBTC approve failed");
        console.log("WBTC approved");
        
        try IChainBalanceManager(cbm).deposit(wbtc, AMOUNT_WBTC, RECIPIENT) {
            console.log("SUCCESS: WBTC deposit completed");
        } catch Error(string memory reason) {
            console.log("FAILED: WBTC deposit -", reason);
        }
        
        // Approve and deposit WETH
        console.log("");
        console.log("=== DEPOSITING WETH ===");
        console.log("Amount:", AMOUNT_WETH);
        
        (bool success3,) = weth.call(abi.encodeWithSignature("approve(address,uint256)", cbm, AMOUNT_WETH));
        require(success3, "WETH approve failed");
        console.log("WETH approved");
        
        try IChainBalanceManager(cbm).deposit(weth, AMOUNT_WETH, RECIPIENT) {
            console.log("SUCCESS: WETH deposit completed");
        } catch Error(string memory reason) {
            console.log("FAILED: WETH deposit -", reason);
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== DEPOSITS COMPLETE ===");
        console.log("Cross-chain messages sent to Rari");
        console.log("Wait ~30 seconds then check balances on Rari");
        console.log("Expected V3 pattern: BalanceManager holds tokens, user has internal balance");
        
        console.log("========== ALL DEPOSITS SENT ==========");
    }
}