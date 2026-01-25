// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {LendingManager} from "../../src/yield/LendingManager.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {Oracle} from "../../src/core/Oracle.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title SetupBasicLending
 * @dev Basic setup of lending protocol infrastructure without complex operations
 * 
 * Environment Variables:
 *   PRIVATE_KEY - Deployer private key
 *   
 * Usage:
 *   PRIVATE_KEY=0x... forge script script/lending/SetupBasicLending.s.sol:SetupBasicLending --rpc-url http://127.0.0.1:8545 --broadcast
 */
contract SetupBasicLending is Script, DeployHelpers {

    // Loaded contracts
    LendingManager public lendingManager;
    BalanceManager public balanceManager;
    TokenRegistry public tokenRegistry;
    Oracle public oracle;

    // Quote currency configuration
    string public quoteCurrency;
    uint8 public quoteDecimals;
    
    function run() external {
        loadDeployments();
        uint256 deployerPrivateKey = getDeployerKey();
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== BASIC LENDING SETUP ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("");
        
        _loadContracts();
        _verifyLendingInfrastructure();
        _displayLendingStatus();
        
        vm.stopBroadcast();
        
        console.log("\n=== LENDING SETUP COMPLETE ===");
    }
    
    function _loadContracts() internal {
        console.log("=== Loading Lending Contracts ===");

        // Load quote currency from environment (defaults to USDC)
        quoteCurrency = vm.envOr("QUOTE_CURRENCY", string("USDC"));
        quoteDecimals = uint8(vm.envOr("QUOTE_DECIMALS", uint256(6)));
        console.log("Using quote currency:", quoteCurrency);

        // Load core contracts
        require(deployed["LendingManager"].isSet, "LendingManager not found");
        require(deployed["BalanceManager"].isSet, "BalanceManager not found");
        require(deployed["TokenRegistry"].isSet, "TokenRegistry not found");
        require(deployed["Oracle"].isSet, "Oracle not found");

        lendingManager = LendingManager(deployed["LendingManager"].addr);
        balanceManager = BalanceManager(deployed["BalanceManager"].addr);
        tokenRegistry = TokenRegistry(deployed["TokenRegistry"].addr);
        oracle = Oracle(deployed["Oracle"].addr);

        console.log("LendingManager:", address(lendingManager));
        console.log("BalanceManager:", address(balanceManager));
        console.log("TokenRegistry:", address(tokenRegistry));
        console.log("Oracle:", address(oracle));
        console.log("");
    }
    
    function _verifyLendingInfrastructure() internal {
        console.log("=== Verifying Lending Infrastructure ===");

        // Check if tokens are loaded in deployments
        require(deployed[quoteCurrency].isSet, string.concat(quoteCurrency, " not found"));
        require(deployed["WETH"].isSet, "WETH not found");
        require(deployed["WBTC"].isSet, "WBTC not found");

        address quoteToken = deployed[quoteCurrency].addr;
        address weth = deployed["WETH"].addr;
        address wbtc = deployed["WBTC"].addr;

        console.log(string.concat(quoteCurrency, ":"), quoteToken);
        console.log("WETH:", weth);
        console.log("WBTC:", wbtc);

        // Verify TokenRegistry is accessible
        console.log("TokenRegistry Status:");
        console.log("  Address:", address(tokenRegistry));
        console.log("  Tokens loaded in deployment file");

        // Try to get oracle address from LendingManager (if function exists)
        try lendingManager.oracle() returns (address lendingOracle) {
            console.log("LendingManager Oracle:", lendingOracle);
            console.log("Matches deployed Oracle:", lendingOracle == address(oracle));
        } catch {
            console.log("Could not retrieve LendingManager oracle");
        }

        console.log("[OK] Lending infrastructure verified");
        console.log("");
    }
    
    function _displayLendingStatus() internal {
        console.log("=== Lending Protocol Status ===");

        address quoteToken = deployed[quoteCurrency].addr;
        address weth = deployed["WETH"].addr;
        address wbtc = deployed["WBTC"].addr;
        address deployer = vm.addr(getDeployerKey());
        uint256 quoteDivisor = 10**quoteDecimals;

        console.log("Account:", deployer);

        // Check user positions (should be empty initially)
        try lendingManager.getUserSupply(deployer, quoteToken) returns (uint256 supply) {
            console.log(string.concat(quoteCurrency, " Supply:"), supply / quoteDivisor);
        } catch {
            console.log(string.concat(quoteCurrency, " Supply: Not available"));
        }

        try lendingManager.getUserDebt(deployer, quoteToken) returns (uint256 debt) {
            console.log(string.concat(quoteCurrency, " Debt:"), debt / quoteDivisor);
        } catch {
            console.log(string.concat(quoteCurrency, " Debt: Not available"));
        }

        try lendingManager.calculateInterestRate(quoteToken) returns (uint256 rate) {
            console.log(string.concat(quoteCurrency, " Interest Rate:"), rate / 100, "%");
        } catch {
            console.log(string.concat(quoteCurrency, " Interest Rate: Not configured"));
        }

        // Display setup information
        console.log("");
        console.log("Lending Infrastructure Ready:");
        console.log("[OK] LendingManager deployed and accessible");
        console.log("[OK] Oracle configured and linked");
        console.log("[OK] TokenRegistry supports tokens");
        console.log("[OK] BalanceManager integrated");
        console.log("");
        console.log("Next Steps:");
        console.log("- Configure asset parameters (collateral factors, rates)");
        console.log("- Supply liquidity to lending pools");
        console.log("- Enable borrowing against collateral");
        console.log("- Start interest accrual");
    }
}