// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/ChainBalanceManager.sol";
import "../src/core/BalanceManager.sol";
import "../src/core/TokenRegistry.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
// IERC20 imported via Currency library

contract TestCrossChainDeposits is Script {
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========== TEST CROSS-CHAIN DEPOSITS ==========");
        console.log("Test all token mappings and deposit flows");
        console.log("Deployer:", deployer);
        console.log("Network:", vm.toString(block.chainid));
        
        // Test recipient address
        address testRecipient = 0x742d35Cc6235c0532C7EAc72c09371B0B4c9f3c5;
        
        if (block.chainid == 4661) {
            // APPCHAIN - Test deposits to Rari
            testAppchainDeposits(deployer, testRecipient);
        } else if (block.chainid == 1918988905) {
            // RARI - Check received deposits and balances
            testRariBalances(testRecipient);
        } else if (block.chainid == 421614) {
            // ARBITRUM SEPOLIA - Test deposits to Rari
            testArbitrumDeposits(deployer, testRecipient);
        } else if (block.chainid == 11155931) {
            // RISE SEPOLIA - Test deposits to Rari
            testRiseDeposits(deployer, testRecipient);
        } else {
            console.log("Unsupported network for cross-chain deposit testing");
            return;
        }
        
        console.log("========== CROSS-CHAIN DEPOSIT TEST COMPLETE ==========");
    }
    
    function testAppchainDeposits(address deployer, address recipient) internal {
        console.log("=== TESTING APPCHAIN DEPOSITS ===");
        
        // Read deployment data
        string memory appchainData = vm.readFile("deployments/appchain.json");
        
        address chainBalanceManager = vm.parseJsonAddress(appchainData, ".contracts.ChainBalanceManager");
        address usdt = vm.parseJsonAddress(appchainData, ".contracts.USDT");
        address wbtc = vm.parseJsonAddress(appchainData, ".contracts.WBTC");
        address weth = vm.parseJsonAddress(appchainData, ".contracts.WETH");
        
        console.log("ChainBalanceManager:", chainBalanceManager);
        console.log("Test recipient:", recipient);
        console.log("");
        console.log("Source tokens:");
        console.log("USDT:", usdt);
        console.log("WBTC:", wbtc);
        console.log("WETH:", weth);
        console.log("");
        
        vm.startBroadcast(deployer);
        
        ChainBalanceManager cbm = ChainBalanceManager(chainBalanceManager);
        
        // Check token mappings first
        console.log("=== VERIFY TOKEN MAPPINGS ===");
        address usdtMapping = cbm.getTokenMapping(usdt);
        address wbtcMapping = cbm.getTokenMapping(wbtc);
        address wethMapping = cbm.getTokenMapping(weth);
        
        console.log("USDT -> Synthetic:", usdtMapping);
        console.log("WBTC -> Synthetic:", wbtcMapping);
        console.log("WETH -> Synthetic:", wethMapping);
        console.log("");
        
        // Test small deposits of each token
        console.log("=== TEST DEPOSITS ===");
        
        // Check balances using low-level calls
        (bool success1, bytes memory data1) = usdt.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
        (bool success2, bytes memory data2) = wbtc.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
        (bool success3, bytes memory data3) = weth.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
        
        uint256 usdtBalance = success1 ? abi.decode(data1, (uint256)) : 0;
        uint256 wbtcBalance = success2 ? abi.decode(data2, (uint256)) : 0;
        uint256 wethBalance = success3 ? abi.decode(data3, (uint256)) : 0;
        
        console.log("Deployer balances:");
        console.log("USDT:", usdtBalance, "(6 decimals)");
        console.log("WBTC:", wbtcBalance, "(8 decimals)");
        console.log("WETH:", wethBalance, "(18 decimals)");
        console.log("");
        
        // Deposit amounts (small test amounts)
        uint256 usdtAmount = 10 * 10**6;    // 10 USDT (6 decimals)
        uint256 wbtcAmount = 1 * 10**6;     // 0.01 WBTC (8 decimals)  
        uint256 wethAmount = 1 * 10**16;    // 0.01 WETH (18 decimals)
        
        console.log("=== MINT TOKENS IF NEEDED ===");
        
        // Mint USDT if balance insufficient
        if (usdtBalance < usdtAmount) {
            console.log("Minting USDT...");
            (bool mintSuccess,) = usdt.call(abi.encodeWithSignature("mint(address,uint256)", deployer, usdtAmount * 10));
            if (mintSuccess) {
                console.log("USDT minted successfully");
                // Update balance
                (bool success, bytes memory data) = usdt.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
                usdtBalance = success ? abi.decode(data, (uint256)) : 0;
                console.log("New USDT balance:", usdtBalance);
            } else {
                console.log("USDT minting failed - might not have mint function");
            }
        }
        
        // Mint WBTC if balance insufficient
        if (wbtcBalance < wbtcAmount) {
            console.log("Minting WBTC...");
            (bool mintSuccess,) = wbtc.call(abi.encodeWithSignature("mint(address,uint256)", deployer, wbtcAmount * 10));
            if (mintSuccess) {
                console.log("WBTC minted successfully");
                // Update balance
                (bool success, bytes memory data) = wbtc.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
                wbtcBalance = success ? abi.decode(data, (uint256)) : 0;
                console.log("New WBTC balance:", wbtcBalance);
            } else {
                console.log("WBTC minting failed - might not have mint function");
            }
        }
        
        // Mint WETH if balance insufficient
        if (wethBalance < wethAmount) {
            console.log("Minting WETH...");
            (bool mintSuccess,) = weth.call(abi.encodeWithSignature("mint(address,uint256)", deployer, wethAmount * 10));
            if (mintSuccess) {
                console.log("WETH minted successfully");
                // Update balance
                (bool success, bytes memory data) = weth.staticcall(abi.encodeWithSignature("balanceOf(address)", deployer));
                wethBalance = success ? abi.decode(data, (uint256)) : 0;
                console.log("New WETH balance:", wethBalance);
            } else {
                console.log("WETH minting failed - might not have mint function");
            }
        }
        
        console.log("");
        
        // Test USDT deposit
        if (usdtBalance >= usdtAmount && usdtMapping != address(0)) {
            console.log("Testing USDT deposit (10 USDT)...");
            
            (bool approveSuccess,) = usdt.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, usdtAmount));
            if (approveSuccess) {
                console.log("USDT approval successful");
            } else {
                console.log("USDT approval failed");
            }
            
            try cbm.deposit(usdt, usdtAmount, recipient) {
                console.log("SUCCESS: USDT deposit completed");
            } catch Error(string memory reason) {
                console.log("FAILED: USDT deposit -", reason);
            }
        } else {
            console.log("SKIP: USDT deposit (insufficient balance or no mapping)");
        }
        
        // Test WBTC deposit
        if (wbtcBalance >= wbtcAmount && wbtcMapping != address(0)) {
            console.log("Testing WBTC deposit (0.01 WBTC)...");
            
            (bool approveSuccess2,) = wbtc.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, wbtcAmount));
            if (approveSuccess2) {
                console.log("WBTC approval successful");
            } else {
                console.log("WBTC approval failed");
            }
            
            try cbm.deposit(wbtc, wbtcAmount, recipient) {
                console.log("SUCCESS: WBTC deposit completed");
            } catch Error(string memory reason) {
                console.log("FAILED: WBTC deposit -", reason);
            }
        } else {
            console.log("SKIP: WBTC deposit (insufficient balance or no mapping)");
        }
        
        // Test WETH deposit
        if (wethBalance >= wethAmount && wethMapping != address(0)) {
            console.log("Testing WETH deposit (0.01 WETH)...");
            
            (bool approveSuccess3,) = weth.call(abi.encodeWithSignature("approve(address,uint256)", chainBalanceManager, wethAmount));
            if (approveSuccess3) {
                console.log("WETH approval successful");
            } else {
                console.log("WETH approval failed");
            }
            
            try cbm.deposit(weth, wethAmount, recipient) {
                console.log("SUCCESS: WETH deposit completed");
            } catch Error(string memory reason) {
                console.log("FAILED: WETH deposit -", reason);
            }
        } else {
            console.log("SKIP: WETH deposit (insufficient balance or no mapping)");
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== APPCHAIN DEPOSIT TEST COMPLETE ===");
        console.log("Check Rari BalanceManager for synthetic token balances");
        console.log("Expected synthetic tokens:");
        console.log("- gUSDT (6 decimals):", usdtMapping);
        console.log("- gWBTC (8 decimals):", wbtcMapping);
        console.log("- gWETH (18 decimals):", wethMapping);
    }
    
    function testRariBalances(address recipient) internal {
        console.log("=== CHECKING RARI BALANCES ===");
        
        // Read deployment data
        string memory rariData = vm.readFile("deployments/rari.json");
        
        address balanceManager = vm.parseJsonAddress(rariData, ".contracts.BalanceManager");
        address gUSDT = vm.parseJsonAddress(rariData, ".contracts.gsUSDT");
        address gWBTC = vm.parseJsonAddress(rariData, ".contracts.gsWBTC");
        address gWETH = vm.parseJsonAddress(rariData, ".contracts.gsWETH");
        
        console.log("BalanceManager:", balanceManager);
        console.log("Test recipient:", recipient);
        console.log("");
        console.log("Synthetic tokens:");
        console.log("gUSDT:", gUSDT);
        console.log("gWBTC:", gWBTC);
        console.log("gWETH:", gWETH);
        console.log("");
        
        BalanceManager bm = BalanceManager(balanceManager);
        
        console.log("=== ERC20 TOKEN BALANCES ===");
        
        // Check ERC20 balances using low-level calls (should be 0 for users, > 0 for BalanceManager in V3)
        (bool s1, bytes memory d1) = gUSDT.staticcall(abi.encodeWithSignature("balanceOf(address)", recipient));
        (bool s2, bytes memory d2) = gWBTC.staticcall(abi.encodeWithSignature("balanceOf(address)", recipient));
        (bool s3, bytes memory d3) = gWETH.staticcall(abi.encodeWithSignature("balanceOf(address)", recipient));
        
        (bool s4, bytes memory d4) = gUSDT.staticcall(abi.encodeWithSignature("balanceOf(address)", balanceManager));
        (bool s5, bytes memory d5) = gWBTC.staticcall(abi.encodeWithSignature("balanceOf(address)", balanceManager));
        (bool s6, bytes memory d6) = gWETH.staticcall(abi.encodeWithSignature("balanceOf(address)", balanceManager));
        
        uint256 recipientUSDT = s1 ? abi.decode(d1, (uint256)) : 0;
        uint256 recipientWBTC = s2 ? abi.decode(d2, (uint256)) : 0;
        uint256 recipientWETH = s3 ? abi.decode(d3, (uint256)) : 0;
        
        uint256 bmUSDT = s4 ? abi.decode(d4, (uint256)) : 0;
        uint256 bmWBTC = s5 ? abi.decode(d5, (uint256)) : 0;
        uint256 bmWETH = s6 ? abi.decode(d6, (uint256)) : 0;
        
        console.log("Recipient ERC20 balances:");
        console.log("gUSDT:", recipientUSDT, "(should be 0 in V3)");
        console.log("gWBTC:", recipientWBTC, "(should be 0 in V3)");
        console.log("gWETH:", recipientWETH, "(should be 0 in V3)");
        console.log("");
        console.log("BalanceManager ERC20 balances:");
        console.log("gUSDT:", bmUSDT, "(should be > 0 in V3)");
        console.log("gWBTC:", bmWBTC, "(should be > 0 in V3)");  
        console.log("gWETH:", bmWETH, "(should be > 0 in V3)");
        console.log("");
        
        console.log("=== INTERNAL BALANCES (FOR TRADING) ===");
        
        // Check internal balances (should be > 0 for trading)
        try bm.getBalance(recipient, Currency.wrap(gUSDT)) returns (uint256 internalUSDT) {
            console.log("Internal gUSDT balance:", internalUSDT);
        } catch {
            console.log("Could not get internal gUSDT balance");
        }
        
        try bm.getBalance(recipient, Currency.wrap(gWBTC)) returns (uint256 internalWBTC) {
            console.log("Internal gWBTC balance:", internalWBTC);
        } catch {
            console.log("Could not get internal gWBTC balance");
        }
        
        try bm.getBalance(recipient, Currency.wrap(gWETH)) returns (uint256 internalWETH) {
            console.log("Internal gWETH balance:", internalWETH);
        } catch {
            console.log("Could not get internal gWETH balance");
        }
        
        console.log("");
        console.log("=== TOKEN DECIMALS VERIFICATION ===");
        
        (bool dec1, bytes memory decData1) = gUSDT.staticcall(abi.encodeWithSignature("decimals()"));
        (bool dec2, bytes memory decData2) = gWBTC.staticcall(abi.encodeWithSignature("decimals()"));
        (bool dec3, bytes memory decData3) = gWETH.staticcall(abi.encodeWithSignature("decimals()"));
        
        if (dec1) console.log("gUSDT decimals:", abi.decode(decData1, (uint8)), "(should be 6)");
        if (dec2) console.log("gWBTC decimals:", abi.decode(decData2, (uint8)), "(should be 8)");
        if (dec3) console.log("gWETH decimals:", abi.decode(decData3, (uint8)), "(should be 18)");
        
        console.log("");
        console.log("=== V3 CUSTODIAL PATTERN VERIFICATION ===");
        if (bmUSDT > 0 && recipientUSDT == 0) {
            console.log("SUCCESS: V3 custodial pattern working for gUSDT");
        }
        if (bmWBTC > 0 && recipientWBTC == 0) {
            console.log("SUCCESS: V3 custodial pattern working for gWBTC");
        }
        if (bmWETH > 0 && recipientWETH == 0) {
            console.log("SUCCESS: V3 custodial pattern working for gWETH");
        }
        
        console.log("=== RARI BALANCE CHECK COMPLETE ===");
    }
    
    function testArbitrumDeposits(address deployer, address recipient) internal {
        console.log("=== TESTING ARBITRUM SEPOLIA DEPOSITS ===");
        console.log("Implementation depends on Arbitrum deployment");
        console.log("Check if ChainBalanceManager exists on Arbitrum Sepolia");
        
        // Read deployment data
        try vm.readFile("deployments/arbitrum-sepolia.json") returns (string memory arbData) {
            try vm.parseJsonAddress(arbData, ".contracts.ChainBalanceManager") returns (address cbm) {
                console.log("ChainBalanceManager found:", cbm);
                console.log("Test deposits similar to Appchain pattern");
            } catch {
                console.log("No ChainBalanceManager deployed on Arbitrum Sepolia yet");
            }
        } catch {
            console.log("No Arbitrum Sepolia deployment file found");
        }
    }
    
    function testRiseDeposits(address deployer, address recipient) internal {
        console.log("=== TESTING RISE SEPOLIA DEPOSITS ===");
        console.log("Implementation depends on Rise deployment");
        console.log("Check if ChainBalanceManager exists on Rise Sepolia");
        
        // Read deployment data
        try vm.readFile("deployments/rise-sepolia.json") returns (string memory riseData) {
            try vm.parseJsonAddress(riseData, ".contracts.ChainBalanceManager") returns (address cbm) {
                console.log("ChainBalanceManager found:", cbm);
                console.log("Test deposits similar to Appchain pattern");
            } catch {
                console.log("No ChainBalanceManager deployed on Rise Sepolia yet");
            }
        } catch {
            console.log("No Rise Sepolia deployment file found");
        }
    }
}