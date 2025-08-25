// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(
        address account
    ) external view returns (uint256);
    function decimals() external view returns (uint8);
    function mint(address account, uint256 amount) external;
}

interface IChainBalanceManager {
    function deposit(address token, uint256 amount, address recipient) external payable;
    function isTokenWhitelisted(
        address token
    ) external view returns (bool);
}

interface IMailbox {
    function latestDispatchedId() external view returns (bytes32);
}

contract TestAppchainDeposits is Script {
    // From deployments/appchain.json
    address constant CHAIN_BALANCE_MANAGER = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
    address constant APPCHAIN_MAILBOX = 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1;

    address constant USDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
    address constant WETH = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
    address constant WBTC = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;

    address constant RECIPIENT = 0x84d437fFC072a2c9E7E16d688D46b4Dbc95dd5e2;

    // Amounts: 100k USDT (6 decimals), 0.1 WBTC (8 decimals), 10 WETH (18 decimals)
    uint256 constant USDT_AMOUNT = 100 * 10 ** 6; // 100k USDT
    // uint256 constant WBTC_AMOUNT = 0.1 * 10 ** 8; // 0.1 WBTC
    // uint256 constant WETH_AMOUNT = 10 * 10 ** 18; // 10 WETH

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Testing Appchain Testnet Deposits ===");
        console.log("ChainBalanceManager:", CHAIN_BALANCE_MANAGER);
        console.log("Recipient:", RECIPIENT);
        console.log("Mailbox:", APPCHAIN_MAILBOX);
        console.log("");

        IChainBalanceManager cbm = IChainBalanceManager(CHAIN_BALANCE_MANAGER);
        IMailbox mailbox = IMailbox(APPCHAIN_MAILBOX);

        // Check initial message ID
        bytes32 initialMessageId = mailbox.latestDispatchedId();
        console.log("Initial latest message ID:", vm.toString(initialMessageId));
        console.log("");

        // Test USDT deposit
        console.log("=== USDT Deposit Test ===");
        console.log("Amount: 100,000 USDT (100000000000 units)");
        console.log("Token:", USDT);

        IERC20 usdt = IERC20(USDT);
        uint256 usdtBalance = usdt.balanceOf(msg.sender);
        console.log("Sender USDT balance:", usdtBalance);

        if (!cbm.isTokenWhitelisted(USDT)) {
            console.log("ERROR: USDT not whitelisted");
        } else if (usdtBalance < USDT_AMOUNT) {
            console.log("Insufficient USDT balance, minting...");
            usdt.mint(msg.sender, USDT_AMOUNT);
            console.log("Minted 100k USDT");
        }

        // Always proceed with deposit after minting or if balance sufficient
        usdt.approve(CHAIN_BALANCE_MANAGER, USDT_AMOUNT);
        console.log("USDT approved");

        cbm.deposit(USDT, USDT_AMOUNT, RECIPIENT);
        console.log("USDT deposit executed");

        bytes32 usdtMessageId = mailbox.latestDispatchedId();
        console.log("USDT Message ID:", vm.toString(usdtMessageId));
        console.log("");

        // // Test WBTC deposit
        // console.log("=== WBTC Deposit Test ===");
        // console.log("Amount: 0.1 WBTC (10000000 units)");
        // console.log("Token:", WBTC);

        // IERC20 wbtc = IERC20(WBTC);
        // uint256 wbtcBalance = wbtc.balanceOf(msg.sender);
        // console.log("Sender WBTC balance:", wbtcBalance);

        // if (!cbm.isTokenWhitelisted(WBTC)) {
        //     console.log("ERROR: WBTC not whitelisted");
        // } else if (wbtcBalance < WBTC_AMOUNT) {
        //     console.log("Insufficient WBTC balance, minting...");
        //     wbtc.mint(msg.sender, WBTC_AMOUNT);
        //     console.log("Minted 0.1 WBTC");
        // }

        // // Always proceed with deposit after minting or if balance sufficient
        // wbtc.approve(CHAIN_BALANCE_MANAGER, WBTC_AMOUNT);
        // console.log("WBTC approved");

        // cbm.deposit(WBTC, WBTC_AMOUNT, RECIPIENT);
        // console.log("WBTC deposit executed");

        // bytes32 wbtcMessageId = mailbox.latestDispatchedId();
        // console.log("WBTC Message ID:", vm.toString(wbtcMessageId));
        // console.log("");

        // // Test WETH deposit
        // console.log("=== WETH Deposit Test ===");
        // console.log("Amount: 10 WETH (10000000000000000000 units)");
        // console.log("Token:", WETH);

        // IERC20 weth = IERC20(WETH);
        // uint256 wethBalance = weth.balanceOf(msg.sender);
        // console.log("Sender WETH balance:", wethBalance);

        // if (!cbm.isTokenWhitelisted(WETH)) {
        //     console.log("ERROR: WETH not whitelisted");
        // } else if (wethBalance < WETH_AMOUNT) {
        //     console.log("Insufficient WETH balance, minting...");
        //     weth.mint(msg.sender, WETH_AMOUNT);
        //     console.log("Minted 10 WETH");
        // }

        // // Always proceed with deposit after minting or if balance sufficient
        // weth.approve(CHAIN_BALANCE_MANAGER, WETH_AMOUNT);
        // console.log("WETH approved");

        // cbm.deposit(WETH, WETH_AMOUNT, RECIPIENT);
        // console.log("WETH deposit executed");

        // bytes32 wethMessageId = mailbox.latestDispatchedId();
        // console.log("WETH Message ID:", vm.toString(wethMessageId));

        vm.stopBroadcast();

        console.log("");
        console.log("=== Appchain Testnet Deposit Test Complete ===");
        console.log("Message IDs above can be tracked on Hyperlane Explorer");
    }
}
