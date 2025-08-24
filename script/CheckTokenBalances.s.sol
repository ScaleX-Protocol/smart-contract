// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/interfaces/IBalanceManager.sol";
import "../src/core/libraries/Currency.sol";

contract CheckTokenBalances is Script {
    
    // Set this to the user address you want to check
    address constant RECIPIENT_TO_CHECK = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
    
    function run() public {
        console.log("========== TOKEN BALANCE CHECKER ==========");
        console.log("Checking balances for recipient:", RECIPIENT_TO_CHECK);
        console.log("Network:", vm.toString(block.chainid));
        
        // Detect network and read deployments
        string memory networkFile;
        bool hasDeployments = false;
        
        if (block.chainid == 1918988905) {
            // Rari
            networkFile = "deployments/rari.json";
            hasDeployments = true;
            console.log("Detected: Rari Testnet");
        } else if (block.chainid == 11155931) {
            // Rise Sepolia
            networkFile = "deployments/11155931.json";  
            hasDeployments = true;
            console.log("Detected: Rise Sepolia");
        } else if (block.chainid == 4661) {
            // Appchain
            networkFile = "deployments/appchain.json";
            hasDeployments = true;
            console.log("Detected: Appchain Testnet");
        } else if (block.chainid == 421614) {
            // Arbitrum Sepolia
            networkFile = "deployments/arbitrum-sepolia.json";
            hasDeployments = true;
            console.log("Detected: Arbitrum Sepolia");
        } else {
            console.log("Unknown network - cannot proceed without deployment info");
            return;
        }
        
        if (!hasDeployments) {
            console.log("No deployment file available for this network");
            return;
        }
        
        // Read deployment data
        string memory deploymentData;
        try vm.readFile(networkFile) returns (string memory data) {
            deploymentData = data;
            console.log("Reading deployment data from:", networkFile);
        } catch {
            console.log("ERROR: Could not read deployment file:", networkFile);
            return;
        }
        
        // Get BalanceManager address
        address balanceManager;
        try vm.parseJsonAddress(deploymentData, ".contracts.BalanceManager") returns (address addr) {
            balanceManager = addr;
        } catch {
            console.log("ERROR: Could not find BalanceManager in deployment file");
            return;
        }
        
        console.log("BalanceManager address:", balanceManager);
        console.log("");
        
        // Get synthetic token addresses
        address[] memory syntheticTokens = new address[](3);
        string[] memory tokenNames = new string[](3);
        
        try vm.parseJsonAddress(deploymentData, ".contracts.gsUSDT") returns (address addr) {
            syntheticTokens[0] = addr;
            tokenNames[0] = "gsUSDT";
        } catch {
            console.log("WARNING: gsUSDT not found in deployments");
        }
        
        try vm.parseJsonAddress(deploymentData, ".contracts.gsWBTC") returns (address addr) {
            syntheticTokens[1] = addr;
            tokenNames[1] = "gsWBTC";
        } catch {
            console.log("WARNING: gsWBTC not found in deployments");
        }
        
        try vm.parseJsonAddress(deploymentData, ".contracts.gsWETH") returns (address addr) {
            syntheticTokens[2] = addr;
            tokenNames[2] = "gsWETH";
        } catch {
            console.log("WARNING: gsWETH not found in deployments");
        }
        
        // Check balances
        console.log("=== BALANCE MANAGER BALANCES ===");
        IBalanceManager bm = IBalanceManager(balanceManager);
        
        for (uint i = 0; i < syntheticTokens.length; i++) {
            if (syntheticTokens[i] == address(0)) continue;
            
            address token = syntheticTokens[i];
            string memory name = tokenNames[i];
            
            console.log("");
            console.log("Token:", name, "at", token);
            
            // Check BalanceManager internal balance for user (what user can trade with)
            try bm.getBalance(RECIPIENT_TO_CHECK, Currency.wrap(token)) returns (uint256 bmBalance) {
                console.log("  BalanceManager internal balance:", _formatAmount(bmBalance));
            } catch {
                console.log("  BalanceManager internal balance: ERROR - Could not read");
            }
            
            // Check user's direct ERC20 wallet balance (should be 0 with new pattern)
            try IERC20(token).balanceOf(RECIPIENT_TO_CHECK) returns (uint256 userErc20Balance) {
                console.log("  User ERC20 wallet balance:", _formatAmount(userErc20Balance));
            } catch {
                console.log("  User ERC20 wallet balance: ERROR - Could not read");
            }
            
            // Check BalanceManager's ERC20 balance (should hold the actual tokens)
            try IERC20(token).balanceOf(balanceManager) returns (uint256 bmErc20Balance) {
                console.log("  BalanceManager ERC20 balance:", _formatAmount(bmErc20Balance));
            } catch {
                console.log("  BalanceManager ERC20 balance: ERROR - Could not read");
            }
            
            // Check total supply to see if tokens are minted
            try IERC20(token).totalSupply() returns (uint256 totalSupply) {
                console.log("  Total supply:", _formatAmount(totalSupply));
                if (totalSupply > 0) {
                    console.log("  Status: MINTED");
                } else {
                    console.log("  Status: NOT MINTED");
                }
            } catch {
                console.log("  Total supply: ERROR - Could not read");
                console.log("  Status: UNKNOWN");
            }
        }
        
        console.log("");
        console.log("=== SUMMARY ===");
        
        // Summary of minted tokens
        uint256 mintedTokens = 0;
        uint256 totalTokens = 0;
        
        for (uint i = 0; i < syntheticTokens.length; i++) {
            if (syntheticTokens[i] == address(0)) continue;
            totalTokens++;
            
            try IERC20(syntheticTokens[i]).totalSupply() returns (uint256 totalSupply) {
                if (totalSupply > 0) {
                    mintedTokens++;
                }
            } catch {
                // Count as not minted if we can't read
            }
        }
        
        console.log("Minted synthetic tokens:", vm.toString(mintedTokens), "of", vm.toString(totalTokens));
        
        if (mintedTokens == totalTokens && totalTokens > 0) {
            console.log("All synthetic tokens have been minted!");
        } else if (mintedTokens > 0) {
            console.log("Some synthetic tokens are minted, others may not be");
        } else {
            console.log("No synthetic tokens appear to be minted yet");
        }
        
        console.log("");
        console.log("=== USAGE NOTES ===");
        console.log("1. Change RECIPIENT_TO_CHECK constant to check different users");
        console.log("2. BalanceManager balance = internal accounting balance");
        console.log("3. ERC20 wallet balance = actual token balance in wallet");  
        console.log("4. Total supply > 0 means tokens have been minted somewhere");
        console.log("5. For cross-chain deposits, tokens are minted to BalanceManager");
        console.log("   then credited to user's internal balance");
        console.log("6. CORRECT PATTERN: BalanceManager ERC20 balance > 0, User ERC20 balance = 0");
        
        console.log("========== BALANCE CHECK COMPLETE ==========");
    }
    
    /**
     * @dev Format amount for better readability (assuming 18 decimals)
     */
    function _formatAmount(uint256 amount) internal pure returns (string memory) {
        if (amount == 0) return "0";
        
        // Simple formatting - show raw amount and approximate decimal value
        if (amount >= 1e18) {
            uint256 whole = amount / 1e18;
            uint256 fraction = (amount % 1e18) / 1e16; // 2 decimal places
            return string(abi.encodePacked(
                vm.toString(amount), 
                " (~", 
                vm.toString(whole), 
                ".", 
                vm.toString(fraction), 
                ")"
            ));
        } else {
            return vm.toString(amount);
        }
    }
}