// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external;
}

interface IChainBalanceManager {
    function deposit(address token, uint256 amount, address recipient) external;
}

contract TestRiseDeposit is Script {
    // Rise addresses
    address constant CHAIN_BALANCE_MANAGER = 0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745;
    address constant RISE_USDT = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;
    address constant RISE_WETH = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
    address constant RISE_WBTC = 0xc6b3109e45F7A479Ac324e014b6a272e4a25bF0E;
    
    // Test recipient
    address constant RECIPIENT = 0x4205B0985a88a9Bbc12d35DC23e5Fdcf16ed3c74;
    
    // Test amounts
    uint256 constant USDT_AMOUNT = 100 * 1e6;      // 100 USDT (6 decimals)
    uint256 constant WETH_AMOUNT = 1 * 1e17;       // 0.1 WETH (18 decimals)
    uint256 constant WBTC_AMOUNT = 1 * 1e6;        // 0.01 WBTC (8 decimals)

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Test Rise All Token Deposits (Post-Fix) ===");
        console.log("Rise ChainBalanceManager:", CHAIN_BALANCE_MANAGER);
        console.log("Depositor:", deployer);
        console.log("Recipient:", RECIPIENT);
        console.log("");
        
        IChainBalanceManager cbm = IChainBalanceManager(CHAIN_BALANCE_MANAGER);
        
        // Test USDT deposit
        console.log("=== 1. USDT Deposit ===");
        _depositToken(RISE_USDT, USDT_AMOUNT, "USDT", "gUSDT", cbm, deployer);
        console.log("");
        
        // Test WETH deposit
        console.log("=== 2. WETH Deposit ===");
        _depositToken(RISE_WETH, WETH_AMOUNT, "WETH", "gWETH", cbm, deployer);
        console.log("");
        
        // Test WBTC deposit
        console.log("=== 3. WBTC Deposit ===");
        _depositToken(RISE_WBTC, WBTC_AMOUNT, "WBTC", "gWBTC", cbm, deployer);
        console.log("");
        
        console.log("SUCCESS: All 3 Rise deposit transactions submitted!");
        console.log("");
        console.log("Expected outcome for all deposits:");
        console.log("1. Hyperlane messages sent to Rari");
        console.log("2. Rari BalanceManager receives messages");  
        console.log("3. TokenRegistry lookups succeed:");
        console.log("   - Rise USDT -> gUSDT");
        console.log("   - Rise WETH -> gWETH");
        console.log("   - Rise WBTC -> gWBTC");
        console.log("4. Synthetic tokens minted to recipient on Rari");
        console.log("5. All message relays should succeed (mappings fixed)");
        console.log("");
        console.log("Monitor Hyperlane explorer for message status:");
        console.log("https://hyperlane-explorer.gtxdex.xyz/");
        
        vm.stopBroadcast();
    }
    
    function _depositToken(
        address tokenAddress, 
        uint256 amount, 
        string memory tokenName,
        string memory syntheticName,
        IChainBalanceManager cbm, 
        address depositor
    ) internal {
        IERC20 token = IERC20(tokenAddress);
        
        console.log("Token:", tokenName, "->", syntheticName);
        console.log("Address:", tokenAddress);
        console.log("Amount:", amount);
        
        // Check current balance
        uint256 currentBalance = token.balanceOf(depositor);
        console.log("Current balance:", currentBalance);
        
        // Mint tokens if needed
        if (currentBalance < amount) {
            console.log("Insufficient balance, minting", tokenName);
            token.mint(depositor, amount * 2); // Mint extra for safety
            uint256 newBalance = token.balanceOf(depositor);
            console.log("New balance after mint:", newBalance);
        }
        
        // Approve ChainBalanceManager
        console.log("Approving ChainBalanceManager...");
        token.approve(address(cbm), amount);
        
        // Execute deposit
        console.log("Executing deposit...");
        cbm.deposit(tokenAddress, amount, RECIPIENT);
        console.log("SUCCESS:", tokenName, "deposit submitted!");
    }
}