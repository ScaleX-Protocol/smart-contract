// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";
import {BalanceManager} from "../src/core/BalanceManager.sol";
import {SyntheticToken} from "../src/token/SyntheticToken.sol";
import {TokenRegistry} from "../src/core/TokenRegistry.sol";

/**
 * @title TestCrossChainFlow
 * @dev End-to-end test script for cross-chain deposit → relay → mint flow
 */
contract TestCrossChainFlow is Script {
    using stdJson for string;

    // Test amounts
    uint256 constant USDT_AMOUNT = 100 * 10**6; // 100 USDT (6 decimals)
    uint256 constant WETH_AMOUNT = 1 ether; // 1 WETH (18 decimals)
    uint256 constant WBTC_AMOUNT = 1 * 10**8; // 1 WBTC (8 decimals)

    // Appchain token addresses
    address constant APPCHAIN_USDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
    address constant APPCHAIN_WETH = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
    address constant APPCHAIN_WBTC = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;

    // Network configurations
    struct NetworkInfo {
        string name;
        uint256 chainId;
        uint32 domainId;
        address chainBalanceManager;
        string deploymentFile;
    }

    NetworkInfo appchain = NetworkInfo({
        name: "Appchain",
        chainId: 4661,
        domainId: 4661,
        chainBalanceManager: 0x0165878A594ca255338adfa4d48449f69242Eb8F,
        deploymentFile: "deployments/appchain.json"
    });

    NetworkInfo arbitrumSepolia = NetworkInfo({
        name: "Arbitrum Sepolia",
        chainId: 421614,
        domainId: 421614,
        chainBalanceManager: 0x288D991A64Ed02171d0beC0DC788ad76421e1169,
        deploymentFile: "deployments/arbitrum-sepolia.json"
    });

    NetworkInfo riseSepolia = NetworkInfo({
        name: "Rise Sepolia", 
        chainId: 11155931,
        domainId: 11155931,
        chainBalanceManager: 0xB1a78eeF392baa3bD244E32625F9C1b5b04a8cdB,
        deploymentFile: "deployments/rise-sepolia.json"
    });

    // Rari (destination) addresses
    address constant RARI_BALANCE_MANAGER = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    address constant RARI_TOKEN_REGISTRY = 0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6;
    address constant RARI_GSUSDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
    address constant RARI_GSWETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
    address constant RARI_GSWBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;

    function run() public {
        string memory network = vm.envString("NETWORK");
        string memory action = vm.envString("ACTION");
        
        if (keccak256(bytes(action)) == keccak256(bytes("deposit"))) {
            if (keccak256(bytes(network)) == keccak256(bytes("appchain"))) {
                testAppchainDeposits();
            } else if (keccak256(bytes(network)) == keccak256(bytes("rise-sepolia"))) {
                testRiseSepoliaDeposits();
            } else if (keccak256(bytes(network)) == keccak256(bytes("arbitrum-sepolia"))) {
                testArbitrumSepoliaDeposits();
            } else {
                revert("Unknown network for deposit. Use: appchain, rise-sepolia, arbitrum-sepolia");
            }
        } else if (keccak256(bytes(action)) == keccak256(bytes("check"))) {
            checkRariBalances();
        } else {
            revert("Unknown action. Use: deposit or check");
        }
    }

    function testAppchainDeposits() public {
        console.log("=== Testing Appchain Deposits ===");
        
        vm.startBroadcast();
        address user = msg.sender;
        
        ChainBalanceManager cbm = ChainBalanceManager(appchain.chainBalanceManager);
        
        // Test USDT deposit
        console.log("Depositing USDT...");
        testTokenDeposit(cbm, APPCHAIN_USDT, USDT_AMOUNT, user, "USDT");
        
        // Test WETH deposit  
        console.log("Depositing WETH...");
        testTokenDeposit(cbm, APPCHAIN_WETH, WETH_AMOUNT, user, "WETH");
        
        // Test WBTC deposit
        console.log("Depositing WBTC...");
        testTokenDeposit(cbm, APPCHAIN_WBTC, WBTC_AMOUNT, user, "WBTC");
        
        vm.stopBroadcast();
        
        console.log("Appchain deposits completed! Check balances on Rari after relay...");
    }

    function testRiseSepoliaDeposits() public {
        console.log("=== Testing Rise Sepolia Deposits ===");
        console.log("Note: Using mock tokens for Rise Sepolia testing");
        
        vm.startBroadcast();
        address user = msg.sender;
        
        ChainBalanceManager cbm = ChainBalanceManager(riseSepolia.chainBalanceManager);
        
        // For Rise Sepolia, we need to use available tokens or deploy mock ones
        // This is a placeholder - would need actual token addresses on Rise Sepolia
        console.log("Rise Sepolia deposit testing requires token setup first");
        
        vm.stopBroadcast();
    }

    function testArbitrumSepoliaDeposits() public {
        console.log("=== Testing Arbitrum Sepolia Deposits ===");
        console.log("Note: Using mock tokens for Arbitrum Sepolia testing");
        
        vm.startBroadcast();
        address user = msg.sender;
        
        ChainBalanceManager cbm = ChainBalanceManager(arbitrumSepolia.chainBalanceManager);
        
        // For Arbitrum Sepolia, we need to use available tokens
        // This is a placeholder - would need actual token addresses on Arbitrum Sepolia
        console.log("Arbitrum Sepolia deposit testing requires token setup first");
        
        vm.stopBroadcast();
    }

    function testTokenDeposit(
        ChainBalanceManager cbm,
        address token,
        uint256 amount,
        address user,
        string memory symbol
    ) internal {
        IERC20 tokenContract = IERC20(token);
        
        // Check user balance
        uint256 userBalance = tokenContract.balanceOf(user);
        console.log("User", symbol, "balance:", userBalance);
        
        if (userBalance < amount) {
            console.log("Insufficient", symbol, "balance for test");
            return;
        }
        
        // Check allowance
        uint256 allowance = tokenContract.allowance(user, address(cbm));
        if (allowance < amount) {
            console.log("Approving", symbol, "spending...");
            tokenContract.approve(address(cbm), amount);
        }
        
        // Get user nonce before deposit
        uint256 nonceBefore = cbm.getUserNonce(user);
        console.log("User nonce before:", nonceBefore);
        
        // Perform deposit
        console.log("Depositing", amount, symbol, "to ChainBalanceManager...");
        cbm.bridgeToSynthetic(token, amount);
        
        // Get user nonce after deposit
        uint256 nonceAfter = cbm.getUserNonce(user);
        console.log("User nonce after:", nonceAfter);
        
        console.log("Deposit successful! Message sent for", symbol);
    }

    function checkRariBalances() public {
        console.log("=== Checking Rari Synthetic Token Balances ===");
        
        address user = msg.sender;
        
        // Check gsUSDT balance
        SyntheticToken gsUSDT = SyntheticToken(RARI_GSUSDT);
        uint256 gsUsdtBalance = gsUSDT.balanceOf(user);
        console.log("gsUSDT balance:", gsUsdtBalance);
        
        // Check gsWETH balance
        SyntheticToken gsWETH = SyntheticToken(RARI_GSWETH);
        uint256 gsWethBalance = gsWETH.balanceOf(user);
        console.log("gsWETH balance:", gsWethBalance);
        
        // Check gsWBTC balance
        SyntheticToken gsWBTC = SyntheticToken(RARI_GSWBTC);
        uint256 gsWbtcBalance = gsWBTC.balanceOf(user);
        console.log("gsWBTC balance:", gsWbtcBalance);
        
        // Check BalanceManager balances
        BalanceManager bm = BalanceManager(RARI_BALANCE_MANAGER);
        TokenRegistry tr = TokenRegistry(RARI_TOKEN_REGISTRY);
        
        // Convert token addresses to currency IDs for BalanceManager
        console.log("=== BalanceManager Internal Balances ===");
        
        // Note: Would need to check how currency IDs are mapped in BalanceManager
        console.log("BalanceManager balance checking requires currency ID mapping");
        
        if (gsUsdtBalance > 0 || gsWethBalance > 0 || gsWbtcBalance > 0) {
            console.log("SUCCESS: Cross-chain deposits detected on Rari!");
        } else {
            console.log("No cross-chain deposits detected yet. Check if Hyperlane relayer is running.");
        }
    }

    function logTokenInfo(address token, string memory symbol) internal view {
        IERC20 tokenContract = IERC20(token);
        console.log("Token:", symbol);
        console.log("Address:", token);
        
        try tokenContract.totalSupply() returns (uint256 supply) {
            console.log("Total Supply:", supply);
        } catch {
            console.log("Could not read total supply");
        }
    }
}