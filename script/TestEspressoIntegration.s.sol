// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script, console} from "forge-std/Script.sol";

import "../src/core/BalanceManager.sol";
import "../src/core/ChainBalanceManager.sol";
import {Currency, CurrencyLibrary} from "../src/core/libraries/Currency.sol";

/**
 * @title Test Espresso Integration
 * @dev Test the complete cross-chain flow with upgraded contracts
 */
contract TestEspressoIntegration is Script {
    function run() external {
        uint256 userPrivateKey = vm.envUint("PRIVATE_KEY");
        address userAddress = vm.addr(userPrivateKey);
        string memory testType = vm.envString("TEST_TYPE"); // "deposit", "withdraw", "complete"

        console.log("=== Testing Espresso Cross-Chain Integration ===");
        console.log("User:", userAddress);
        console.log("Test Type:", testType);
        console.log("");

        if (keccak256(bytes(testType)) == keccak256(bytes("deposit"))) {
            _testCrossChainDeposit(userPrivateKey, userAddress);
        } else if (keccak256(bytes(testType)) == keccak256(bytes("withdraw"))) {
            _testCrossChainWithdraw(userPrivateKey, userAddress);
        } else if (keccak256(bytes(testType)) == keccak256(bytes("complete"))) {
            _testCompleteFlow(userPrivateKey, userAddress);
        } else {
            revert("Invalid TEST_TYPE. Use: deposit, withdraw, complete");
        }
    }

    function _testCrossChainDeposit(uint256 privateKey, address user) internal {
        console.log("=== Testing Cross-Chain Deposit (Appchain to Rari) ===");

        // Connect to Appchain testnet
        vm.createSelectFork("https://appchain.caff.testnet.espresso.network");
        vm.startBroadcast(privateKey);

        // Use deployed addresses or env vars as fallback
        address chainBMProxy;
        try vm.envAddress("APPCHAIN_CHAIN_BM_PROXY") returns (address addr) {
            chainBMProxy = addr;
            console.log("Using env APPCHAIN_CHAIN_BM_PROXY:", chainBMProxy);
        } catch {
            // Use hardcoded working address from Espresso example
            chainBMProxy = 0xDf997311A013F15Df5264172f3a448B14917CFE8;
            console.log("Using fallback ChainBalanceManager address:", chainBMProxy);
        }
        
        ChainBalanceManager chainBM = ChainBalanceManager(chainBMProxy);

        // Test token addresses
        address USDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        IERC20 usdt = IERC20(USDT);

        uint256 depositAmount = 5_000_000; // 5 USDT (6 decimals)

        // Check user token balance
        uint256 userBalance = usdt.balanceOf(user);
        console.log("User USDT balance on Appchain:", userBalance);

        if (userBalance >= depositAmount) {
            console.log("Step 1: Depositing", depositAmount, "USDT to vault...");

            // Approve and deposit
            usdt.approve(chainBMProxy, depositAmount);
            chainBM.deposit(USDT, depositAmount);

            uint256 vaultBalance = chainBM.getBalance(user, USDT);
            console.log("[SUCCESS] Vault balance:", vaultBalance);

            console.log("Step 2: Bridging to synthetic tokens on Rari...");

            // Bridge to synthetic (triggers cross-chain message)
            chainBM.bridgeToSynthetic(USDT, depositAmount);

            console.log("[SUCCESS] Cross-chain message sent!");
            console.log("[WAIT] Wait 2-3 minutes for Hyperlane delivery");
            console.log("[INFO] Check Rari balance with: make test-rari-balance");

            // Show user nonce
            uint256 userNonce = chainBM.getUserNonce(user);
            console.log("User nonce:", userNonce);
        } else {
            console.log("[ERROR] Insufficient USDT balance");
            console.log("[TIP] Get tokens with: make faucet-tokens network=appchain_testnet");
        }

        vm.stopBroadcast();
    }

    function _testCrossChainWithdraw(uint256 privateKey, address user) internal {
        console.log("=== Testing Cross-Chain Withdraw (Rari to Appchain) ===");

        // Connect to Rari testnet
        vm.createSelectFork("https://rari.caff.testnet.espresso.network");
        vm.startBroadcast(privateKey);

        // Use deployed addresses or env vars as fallback
        address balanceManagerProxy;
        try vm.envAddress("RARI_BALANCE_MANAGER_PROXY") returns (address addr) {
            balanceManagerProxy = addr;
            console.log("Using env RARI_BALANCE_MANAGER_PROXY:", balanceManagerProxy);
        } catch {
            // Use hardcoded working address from Espresso example
            balanceManagerProxy = 0xDf997311A013F15Df5264172f3a448B14917CFE8;
            console.log("Using fallback BalanceManager address:", balanceManagerProxy);
        }
        
        BalanceManager balanceManager = BalanceManager(balanceManagerProxy);

        // Synthetic token addresses
        address GS_USDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;

        // Check user synthetic balance
        uint256 gsBalance = balanceManager.getBalance(user, Currency.wrap(GS_USDT));
        console.log("User gsUSDT balance on Rari:", gsBalance);

        if (gsBalance >= 1_000_000) {
            // 1 USDT minimum
            uint256 withdrawAmount = 1_000_000; // 1 USDT
            uint32 targetChainId = 4661; // Appchain

            console.log("Withdrawing", withdrawAmount, "gsUSDT to Appchain...");

            // Request withdrawal (triggers cross-chain message)
            balanceManager.requestWithdraw(Currency.wrap(GS_USDT), withdrawAmount, targetChainId, user);

            console.log("[SUCCESS] Withdrawal request sent!");
            console.log("[WAIT] Wait 2-3 minutes for cross-chain unlock");
            console.log("[INFO] Check unlocked balance with: make test-appchain-unlocked");
        } else {
            console.log("[ERROR] Insufficient gsUSDT balance");
            console.log("[TIP] Do cross-chain deposit first");
        }

        vm.stopBroadcast();
    }

    function _testCompleteFlow(uint256 privateKey, address user) internal {
        console.log("=== Testing Complete Cross-Chain Flow ===");
        console.log("This will test: Deposit -> Bridge -> Wait -> Withdraw -> Unlock");
        console.log("");

        // Step 1: Deposit and bridge
        _testCrossChainDeposit(privateKey, user);

        console.log("");
        console.log("[MANUAL STEP REQUIRED]");
        console.log("1. Wait 2-3 minutes for cross-chain message delivery");
        console.log("2. Verify synthetic tokens on Rari");
        console.log("3. Run: TEST_TYPE=withdraw forge script script/TestEspressoIntegration.s.sol");
        console.log("");
        console.log("Complete flow commands:");
        console.log("  make test-deposit    # Test deposit flow");
        console.log("  make test-withdraw   # Test withdrawal flow");
        console.log("  make test-balances   # Check all balances");
    }

    function _testRariBalance(
        address user
    ) internal {
        console.log("=== Checking Rari Synthetic Balances ===");

        vm.createSelectFork("https://rari.caff.testnet.espresso.network");

        address balanceManagerProxy;
        try vm.envAddress("RARI_BALANCE_MANAGER_PROXY") returns (address addr) {
            balanceManagerProxy = addr;
        } catch {
            balanceManagerProxy = 0xDf997311A013F15Df5264172f3a448B14917CFE8;
        }
        BalanceManager balanceManager = BalanceManager(balanceManagerProxy);

        // Check all synthetic token balances
        address GS_USDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
        address GS_WETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
        address GS_WBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;

        uint256 gsUsdtBalance = balanceManager.getBalance(user, Currency.wrap(GS_USDT));
        uint256 gsWethBalance = balanceManager.getBalance(user, Currency.wrap(GS_WETH));
        uint256 gsWbtcBalance = balanceManager.getBalance(user, Currency.wrap(GS_WBTC));

        console.log("Synthetic token balances on Rari:");
        console.log("  gsUSDT:", gsUsdtBalance);
        console.log("  gsWETH:", gsWethBalance);
        console.log("  gsWBTC:", gsWbtcBalance);

        if (gsUsdtBalance > 0 || gsWethBalance > 0 || gsWbtcBalance > 0) {
            console.log("[SUCCESS] Cross-chain deposit successful!");
            console.log("[READY] Ready for CLOB trading");
        } else {
            console.log("[WAIT] Cross-chain messages still processing");
            console.log("[TIP] Check again in a few minutes");
        }
    }

    function _testAppchainUnlocked(
        address user
    ) internal {
        console.log("=== Checking Appchain Unlocked Balances ===");

        vm.createSelectFork("https://appchain.caff.testnet.espresso.network");

        address chainBMProxy;
        try vm.envAddress("APPCHAIN_CHAIN_BM_PROXY") returns (address addr) {
            chainBMProxy = addr;
        } catch {
            chainBMProxy = 0xDf997311A013F15Df5264172f3a448B14917CFE8;
        }
        ChainBalanceManager chainBM = ChainBalanceManager(chainBMProxy);

        address USDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        address WETH = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;

        uint256 unlockedUsdt = chainBM.getUnlockedBalance(user, USDT);
        uint256 unlockedWeth = chainBM.getUnlockedBalance(user, WETH);

        console.log("Unlocked balances on Appchain:");
        console.log("  USDT:", unlockedUsdt);
        console.log("  WETH:", unlockedWeth);

        if (unlockedUsdt > 0 || unlockedWeth > 0) {
            console.log("[SUCCESS] Cross-chain withdrawal successful!");
            console.log("[READY] Ready to claim tokens");
            console.log("[ACTION] Run: chainBM.claim(token, amount)");
        } else {
            console.log("[WAIT] Cross-chain unlock still processing");
        }
    }
}
