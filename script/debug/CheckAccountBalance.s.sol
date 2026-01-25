// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IBalanceManager} from "../../src/core/interfaces/IBalanceManager.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CheckAccountBalance is Script {
    function run() external view {
        // Load deployment addresses
        address balanceManagerAddr = 0x182C3A05a8921AC5c15881A5704Ce727Fa95BE88;
        address usdc = 0xa570b31f63D2a3C754d04eD95d89CD9DE91c80B4;
        address weth = 0x040E8E92c30404d2CfD8caed6117c5d05AA4E38D;
        address wbtc = 0x853E82796152fcd679500349A5d023251C003418;
        address sxUSDC = 0x26A73EEc138d5447dda2CA82311aA0FCb7C27267;
        address sxWETH = 0x5b64d5e63eBdeebF72fa92e4fa25Ad67C7c06893;
        address sxWBTC = 0x335F64c0F5768293c42F7167b509C39977BF3f31;

        address wethUsdcPool = 0x32E1Fc921863436D5a9951E87A148575b41E4905;
        address wbtcUsdcPool = 0x2bdee8553224D84AF02ce90B73D372Aba7Ad561E;

        address account = 0x0f27AceC819E7F7D9df847831C3F3DB6e237d0F2;

        IBalanceManager balanceManager = IBalanceManager(balanceManagerAddr);

        console.log("=== Account Balance Check ===");
        console.log("Account:", account);
        console.log("");

        // Check sxUSDC balances
        console.log("--- sxUSDC ---");
        Currency sxUsdcCurrency = Currency.wrap(sxUSDC);
        uint256 freeSxUsdc = balanceManager.getBalance(account, sxUsdcCurrency);
        console.log("Free balance:", freeSxUsdc);

        // Check locked balances for each pool
        uint256 lockedSxUsdcWethPool = balanceManager.getLockedBalance(account, wethUsdcPool, sxUsdcCurrency);
        uint256 lockedSxUsdcWbtcPool = balanceManager.getLockedBalance(account, wbtcUsdcPool, sxUsdcCurrency);
        console.log("Locked in WETH/USDC pool:", lockedSxUsdcWethPool);
        console.log("Locked in WBTC/USDC pool:", lockedSxUsdcWbtcPool);
        console.log("Total locked:", lockedSxUsdcWethPool + lockedSxUsdcWbtcPool);
        console.log("Total balance:", freeSxUsdc + lockedSxUsdcWethPool + lockedSxUsdcWbtcPool);
        console.log("");

        // Check sxWETH balances
        console.log("--- sxWETH ---");
        Currency sxWethCurrency = Currency.wrap(sxWETH);
        uint256 freeSxWeth = balanceManager.getBalance(account, sxWethCurrency);
        console.log("Free balance:", freeSxWeth);

        uint256 lockedSxWethWethPool = balanceManager.getLockedBalance(account, wethUsdcPool, sxWethCurrency);
        console.log("Locked in WETH/USDC pool:", lockedSxWethWethPool);
        console.log("Total balance:", freeSxWeth + lockedSxWethWethPool);
        console.log("");

        // Check sxWBTC balances
        console.log("--- sxWBTC ---");
        Currency sxWbtcCurrency = Currency.wrap(sxWBTC);
        uint256 freeSxWbtc = balanceManager.getBalance(account, sxWbtcCurrency);
        console.log("Free balance:", freeSxWbtc);

        uint256 lockedSxWbtcWbtcPool = balanceManager.getLockedBalance(account, wbtcUsdcPool, sxWbtcCurrency);
        console.log("Locked in WBTC/USDC pool:", lockedSxWbtcWbtcPool);
        console.log("Total balance:", freeSxWbtc + lockedSxWbtcWbtcPool);
        console.log("");

        // Summary
        console.log("=== Summary ===");
        console.log("Total free balance (all tokens):", freeSxUsdc + freeSxWeth + freeSxWbtc);
        console.log("Total locked balance (all tokens):", lockedSxUsdcWethPool + lockedSxUsdcWbtcPool + lockedSxWethWethPool + lockedSxWbtcWbtcPool);
    }
}
