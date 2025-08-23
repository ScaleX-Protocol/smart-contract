// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./DeployHelpers.s.sol";

interface IERC20Basic {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

type Currency is address;

interface IBalanceManagerBasic {
    function getBalance(address user, Currency currency) external view returns (uint256);
    function getLockedBalance(address user, address operator, Currency currency) external view returns (uint256);
    function getUserNonce(address user) external view returns (uint256);
}

contract SimpleRariCheck is DeployHelpers {
    
    // Default user address
    address constant DEFAULT_USER = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
    
    // BalanceManager address on Rari
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    
    // Synthetic token addresses on Rari
    address constant GS_USDT = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
    address constant GS_WETH = 0xC7A1777e80982E01e07406e6C6E8B30F5968F836;
    address constant GS_WBTC = 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF;
    
    function run() public {
        loadDeployments();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.envOr("USER_ADDRESS", DEFAULT_USER);

        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Simple Rari Balance Check ===");
        console.log("User:", user);
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("");
        
        // Check native ETH balance
        uint256 ethBalance = user.balance;
        console.log("Native ETH balance:", ethBalance);
        console.log("");
        
        // Check BalanceManager
        _checkBalanceManager(user);
        
        // Check each token
        _checkToken("gsUSDT", GS_USDT, user);
        _checkToken("gsWETH", GS_WETH, user);  
        _checkToken("gsWBTC", GS_WBTC, user);
        
        vm.stopBroadcast();
    }
    
    function _checkBalanceManager(address user) internal {
        console.log("=== BalanceManager Internal Balances ===");
        console.log("BalanceManager Address:", BALANCE_MANAGER);
        
        // Check if BalanceManager contract exists
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(BALANCE_MANAGER)
        }
        
        if (codeSize == 0) {
            console.log("ERROR: No BalanceManager contract at address");
            console.log("");
            return;
        }
        
        console.log("BalanceManager contract exists, code size:", codeSize);
        
        IBalanceManagerBasic balanceManager = IBalanceManagerBasic(BALANCE_MANAGER);
        
        // Check user nonce
        try balanceManager.getUserNonce(user) returns (uint256 nonce) {
            console.log("User nonce:", nonce);
        } catch {
            console.log("User nonce: ERROR - Failed to get nonce");
        }
        
        // Check internal balances for each token
        address[3] memory tokens = [GS_USDT, GS_WETH, GS_WBTC];
        string[3] memory names = ["gsUSDT", "gsWETH", "gsWBTC"];
        
        for (uint i = 0; i < 3; i++) {
            try balanceManager.getBalance(user, Currency.wrap(tokens[i])) returns (uint256 balance) {
                console.log("%s internal balance:", names[i], balance);
                if (balance > 0) {
                    console.log("  -> User has internal balance!");
                }
            } catch Error(string memory reason) {
                console.log("%s internal balance: ERROR -", names[i], reason);
            } catch (bytes memory lowLevelData) {
                console.log("%s internal balance: LOW-LEVEL ERROR", names[i]);
                console.logBytes(lowLevelData);
            }
        }
        
        console.log("");
    }
    
    function _checkToken(string memory name, address tokenAddr, address user) internal {
        console.log("=== %s Token ===", name);
        console.log("Address:", tokenAddr);
        
        // Check if contract exists
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(tokenAddr)
        }
        
        if (codeSize == 0) {
            console.log("ERROR: No contract at address");
            console.log("");
            return;
        }
        
        IERC20Basic token = IERC20Basic(tokenAddr);
        
        // Get balance
        try token.balanceOf(user) returns (uint256 balance) {
            console.log("Balance:", balance);
        } catch {
            console.log("Balance: ERROR - Failed to get balance");
        }
        
        // Get total supply
        try token.totalSupply() returns (uint256 supply) {
            console.log("Total Supply:", supply);
        } catch {
            console.log("Total Supply: ERROR");
        }
        
        // Get symbol
        try token.symbol() returns (string memory symbol) {
            console.log("Symbol:", symbol);
        } catch {
            console.log("Symbol: ERROR");
        }
        
        // Get decimals
        try token.decimals() returns (uint8 decimals) {
            console.log("Decimals:", decimals);
        } catch {
            console.log("Decimals: ERROR");
        }
        
        console.log("");
    }
}