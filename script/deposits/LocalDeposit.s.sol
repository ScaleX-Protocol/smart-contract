// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title Test Local Deposit
 * @dev Test local deposit functionality using deployment data
 * 
 * Environment Variables:
 *   TOKEN_SYMBOL     - Token symbol to test (e.g., "USDC", "WETH", "WBTC")
 *   DEPOSIT_AMOUNT   - Amount to deposit (in token's native decimals)
 *   TEST_RECIPIENT   - Address to receive synthetic tokens (optional, defaults to deployer)
 *   LOCAL_TOKEN      - Address of local token to map (optional, uses deployment file)
 *
 * Usage Examples:
 *   TOKEN_SYMBOL=USDC DEPOSIT_AMOUNT=1000000000 forge script script/LocalDeposit.s.sol:LocalDeposit --rpc-url https://core-devnet.scalex.money --broadcast
 *   TOKEN_SYMBOL=WETH LOCAL_TOKEN=0x123... DEPOSIT_AMOUNT=1000000000000000000 forge script script/LocalDeposit.s.sol:LocalDeposit --rpc-url $RPC_URL --broadcast
 */
contract LocalDeposit is DeployHelpers {
    // Configuration
    string public tokenSymbol;
    uint256 public depositAmount;
    address public testRecipient;
    address public localTokenAddress;
    
    // Loaded contracts
    TokenRegistry public tokenRegistry;
    BalanceManager public balanceManager;
    IERC20 public localToken;
    address public syntheticTokenAddress;
    
    function run() external {
        // Load existing deployments first
        loadDeployments();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Load configuration from environment
        _loadConfiguration(deployer, deployer);

        console.log("========== TESTING LOCAL DEPOSIT ==========");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Test Recipient:", testRecipient);
        console.log("Token Symbol:", tokenSymbol);
        console.log("Deposit Amount:", depositAmount);
        console.log("");

        // Load contract addresses from deployments
        _loadContracts();

        vm.startBroadcast(deployerPrivateKey);

        // Execute local deposit test
        _executeLocalDepositTest();

        vm.stopBroadcast();

        console.log("");
        console.log("========== LOCAL DEPOSIT TEST COMPLETE ==========");
        console.log("[SUCCESS] Local deposit test completed");
        console.log("[INFO] Check BalanceManager balances for results");
    }
    
    function _loadConfiguration(address deployer, address signer) internal {
        // Token symbol to test
        tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("USDC"));
        
        // Load deposit amount (default based on token)
        try vm.envUint("DEPOSIT_AMOUNT") returns (uint256 amount) {
            depositAmount = amount;
        } catch {
            // Default amounts based on token decimals
            if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("USDC"))) {
                depositAmount = 1000000000; // 1000 USDC (6 decimals)
            } else if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("WETH"))) {
                depositAmount = 1000000000000000000; // 1 WETH (18 decimals)
            } else if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("WBTC"))) {
                depositAmount = 100000000; // 1 WBTC (8 decimals)
            } else {
                depositAmount = 1000000000000000000; // Default to 18 decimals
            }
        }
        
        // Test recipient (default to deployer/signer)
        testRecipient = vm.envOr("TEST_RECIPIENT", signer);
        
        // Custom local token address (optional)
        localTokenAddress = vm.envOr("LOCAL_TOKEN", address(0));
    }
    
    function _loadContracts() internal {
        // Load core contracts from deployed mapping
        require(deployed["TokenRegistry"].isSet, "TokenRegistry not found in deployments");
        require(deployed["BalanceManager"].isSet, "BalanceManager not found in deployments");
        
        tokenRegistry = TokenRegistry(deployed["TokenRegistry"].addr);
        balanceManager = BalanceManager(deployed["BalanceManager"].addr);
        
        console.log("TokenRegistry:", address(tokenRegistry));
        console.log("BalanceManager:", address(balanceManager));
        
        // Load token address
        if (localTokenAddress == address(0)) {
            // Try to load from deployment file based on token symbol
            require(deployed[tokenSymbol].isSet, string.concat("Token ", tokenSymbol, " not found in deployment"));
            localTokenAddress = deployed[tokenSymbol].addr;
        }
        
        localToken = IERC20(localTokenAddress);
        console.log("Local Token (%s):", tokenSymbol, address(localToken));
        
        // Try to load corresponding synthetic token
        string memory syntheticSymbol = string.concat("sx", tokenSymbol);
        if (deployed[syntheticSymbol].isSet) {
            syntheticTokenAddress = deployed[syntheticSymbol].addr;
            console.log("Target Synthetic Token (%s):", syntheticSymbol, syntheticTokenAddress);
        } else {
            console.log("WARNING: Synthetic token %s not found", syntheticSymbol);
            syntheticTokenAddress = address(0);
        }
    }
    
    function _executeLocalDepositTest() internal {
        console.log("========== EXECUTING LOCAL DEPOSIT ==========");
        
        uint32 currentChain = uint32(block.chainid);
        
        // Token mappings are now configured during deployment
        // No need to set up mappings here
        
        // Use testRecipient as the depositor (this is set to deployer in _loadConfiguration)
        address depositor = testRecipient;
        
        // Check initial balances
        uint256 initialTokenBalance = localToken.balanceOf(depositor);
        console.log("Initial token balance:", initialTokenBalance);
        console.log("Depositor address:", depositor);
        
        if (initialTokenBalance < depositAmount) {
            console.log("Insufficient token balance for test");
            console.log("  Required:", depositAmount);
            console.log("  Available:", initialTokenBalance);
            console.log("  Depositor:", depositor);
            console.log("  Attempting to mint additional tokens...");
            
            // Try to mint additional tokens
            try MockToken(localTokenAddress).mint(depositor, depositAmount - initialTokenBalance) {
                console.log("Successfully minted additional tokens");
                uint256 newBalance = localToken.balanceOf(depositor);
                console.log("New balance after minting:", newBalance);
                
                if (newBalance < depositAmount) {
                    console.log("ERROR: Still insufficient tokens after minting");
                    console.log("  Required:", depositAmount);
                    console.log("  Available:", newBalance);
                    revert("Insufficient token balance for deposit even after minting");
                }
            } catch Error(string memory reason) {
                console.log("ERROR: Failed to mint tokens");
                console.log("  Reason:", reason);
                console.log("  The token might not support minting or you might not have permission");
                revert("Insufficient token balance for deposit");
            } catch (bytes memory) {
                console.log("ERROR: Failed to mint tokens with low-level error");
                revert("Insufficient token balance for deposit");
            }
        }
        
        // Approve and execute deposit
        _performDeposit();
        
        console.log("Local deposit test completed successfully");
    }
    
    function _performDeposit() internal {
        address depositor = testRecipient; // Use the same address as in _executeLocalDepositTest
        
        console.log("Approving BalanceManager for token spending...");
        console.log("Depositor:", depositor);
        console.log("Amount:", depositAmount);
        
        // Step 1: Approve BalanceManager
        try localToken.approve(address(balanceManager), depositAmount) {
            console.log("Approval successful");
        } catch Error(string memory reason) {
            console.log("Approval failed:", reason);
            revert(string.concat("Token approval failed: ", reason));
        } catch (bytes memory) {
            console.log("Approval failed with low-level error");
            revert("Token approval failed with low-level error");
        }
        
        // Step 2: Check allowance
        uint256 allowance = localToken.allowance(depositor, address(balanceManager));
        console.log("Approved amount:", allowance);
        
        if (allowance < depositAmount) {
            console.log("ERROR: Approval insufficient");
            console.log("Depositor:", depositor);
            console.log("BalanceManager:", address(balanceManager));
            revert("Token allowance insufficient after approval");
        }
        
        // Step 3: Execute local deposit (this will handle the LendingManager interaction internally)
        console.log("Executing depositLocal...");
        try balanceManager.depositLocal(localTokenAddress, depositAmount, testRecipient) {
            console.log("Local deposit executed successfully");
            console.log("  Token:", localTokenAddress);
            console.log("  Amount:", depositAmount);
            console.log("  Recipient:", testRecipient);
            
            // Check final balances
            uint256 finalTokenBalance = localToken.balanceOf(depositor);
            console.log("Final token balance:", finalTokenBalance);
            
        } catch Error(string memory reason) {
            console.log("Local deposit failed:", reason);
            revert(string.concat("Local deposit failed: ", reason));
        } catch (bytes memory) {
            console.log("Local deposit failed with low-level error");
            revert("Local deposit failed with low-level error");
        }
    }
}