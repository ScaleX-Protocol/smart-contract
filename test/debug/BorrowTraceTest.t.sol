// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IScaleXRouter {
    function borrow(address token, uint256 amount) external;
}

interface IBalanceManager {
    function getBalance(address user, bytes32 currency) external view returns (uint256);
    function getSyntheticToken(address token) external view returns (address);
}

interface ILendingManager {
    function getTotalLiquidity(address token) external view returns (uint256);
    function getTotalBorrowed(address token) external view returns (uint256);
    function getUserBorrowed(address user, address token) external view returns (uint256);
}

interface IOracle {
    function getPriceForCollateral(address token) external view returns (uint256);
    function isPriceStale(address token) external view returns (bool);
}

contract BorrowTraceTest is Test {
    // Deployed contracts on Lisk Sepolia
    address constant SCALEX_ROUTER = 0x0280D808e55EEF601baA7f516A911c8d7469FB77;
    address constant BALANCE_MANAGER = 0x35C0de28D4917F7017A57401370feA6A38121FC8;
    address constant LENDING_MANAGER = 0x86ad7E133e6bA69b0Cd05a7B173a195ceA6a51F2;
    address constant ORACLE = 0x9AA212Ddd987FBcD0D058206159098802Da10868;

    address constant USDC = 0x3D07EAD4dB56bE5c555dA4e66b766BF7e0A5Fe5D;
    address constant WETH = 0x8f4AF46cfFDA37c5F97664395A088e184c6e8E84;
    address constant sxUSDC = 0xC2Cb1A5b80F4D7db7B04F7dBc250204BA9e3F655;
    address constant sxWETH = 0x2b3a28cE0Cd7e03DAA5a4a3b20E6dA30FA9f20a7;

    address constant USER = 0x73c7448760517E3E903C0b72ff26E702A5f8c305;

    // Fork setup
    string LISK_SEPOLIA_RPC = "https://lisk-sepolia.drpc.org";

    function setUp() public {
        // Create fork
        vm.createSelectFork(LISK_SEPOLIA_RPC);

        console.log("=== SETUP ===");
        console.log("Fork created at block:", block.number);
        console.log("User:", USER);
    }

    function testBorrowWithDetailedTrace() public {
        console.log("\n=== PRE-BORROW STATE ===");

        // Check user balances
        IBalanceManager bm = IBalanceManager(BALANCE_MANAGER);
        uint256 usdcBalance = bm.getBalance(USER, bytes32(uint256(uint160(sxUSDC))));
        uint256 wethBalance = bm.getBalance(USER, bytes32(uint256(uint160(sxWETH))));

        console.log("User USDC balance:", usdcBalance);
        console.log("User WETH balance:", wethBalance);

        // Check lending pool state
        ILendingManager lm = ILendingManager(LENDING_MANAGER);
        uint256 totalLiquidity = lm.getTotalLiquidity(USDC);
        uint256 totalBorrowed = lm.getTotalBorrowed(USDC);

        console.log("Total USDC liquidity:", totalLiquidity);
        console.log("Total USDC borrowed:", totalBorrowed);
        console.log("Available liquidity:", totalLiquidity - totalBorrowed);

        // Check oracle prices
        IOracle oracle = IOracle(ORACLE);
        uint256 usdcPrice = oracle.getPriceForCollateral(sxUSDC);
        uint256 wethPrice = oracle.getPriceForCollateral(sxWETH);
        bool usdcStale = oracle.isPriceStale(sxUSDC);
        bool wethStale = oracle.isPriceStale(sxWETH);

        console.log("sxUSDC price:", usdcPrice);
        console.log("sxWETH price:", wethPrice);
        console.log("sxUSDC stale:", usdcStale);
        console.log("sxWETH stale:", wethStale);

        console.log("\n=== ATTEMPTING BORROW ===");
        console.log("Borrowing 1 USDC (1000000 wei)");

        // Impersonate user
        vm.startPrank(USER);

        // Try to borrow - this should show detailed trace with -vvvv
        IScaleXRouter(SCALEX_ROUTER).borrow(USDC, 1_000000); // 1 USDC

        vm.stopPrank();

        console.log("\n=== BORROW SUCCESS ===");

        // Check post-borrow state
        uint256 userBorrowed = lm.getUserBorrowed(USER, USDC);
        console.log("User borrowed after:", userBorrowed);
    }

    function testBorrowSmallAmount() public {
        console.log("\n=== TESTING VERY SMALL BORROW ===");

        vm.startPrank(USER);

        // Try to borrow even smaller amount
        console.log("Borrowing 0.01 USDC (10000 wei)");
        IScaleXRouter(SCALEX_ROUTER).borrow(USDC, 10000); // 0.01 USDC

        vm.stopPrank();

        console.log("Small borrow succeeded");
    }

    function testDirectBalanceManagerCall() public {
        console.log("\n=== TESTING DIRECT BALANCE MANAGER CALL ===");

        // This will fail because we're not authorized, but we can see the revert trace
        vm.startPrank(SCALEX_ROUTER);

        // Try calling BalanceManager.borrowForUser directly
        // We need the interface
        (bool success,) = BALANCE_MANAGER.call(
            abi.encodeWithSignature("borrowForUser(address,address,uint256)", USER, USDC, 1_000000)
        );

        console.log("Direct call success:", success);

        vm.stopPrank();
    }
}
