// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../script/DeployHelpers.s.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {GTXRouter} from "../src/core/GTXRouter.sol";
import {BalanceManager} from "../src/core/BalanceManager.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {IPoolManager} from "../src/core/interfaces/IPoolManager.sol";
import {IOrderBook} from "../src/core/interfaces/IOrderBook.sol";
import {Currency} from "../src/core/libraries/Currency.sol";
import {PoolKey} from "../src/core/libraries/Pool.sol";

contract CalculateMinOutForSwap is Script, DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
    string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant WBTC_ADDRESS = "MOCK_TOKEN_WBTC";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";

    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    GTXRouter gtxRouter;

    // Mock tokens
    MockToken weth;
    MockToken wbtc;
    MockToken usdc;

    function setUp() public {
        loadDeployments();
        loadContracts();
    }

    function loadContracts() private {
        // Load core contracts
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
        gtxRouter = GTXRouter(deployed[GTX_ROUTER_ADDRESS].addr);

        // Load mock tokens
        weth = MockToken(deployed[WETH_ADDRESS].addr);
        wbtc = MockToken(deployed[WBTC_ADDRESS].addr);
        usdc = MockToken(deployed[USDC_ADDRESS].addr);
    }

    function run() external {
        // Example calculations
        calculateDirectSwapMinOut();
        calculateMultiHopSwapMinOut();
    }

    /// @notice Calculate minimum output for direct swap (e.g., WETH -> USDC)
    function calculateDirectSwapMinOut() public view {
        console.log("=== Direct Swap Min Output Calculation ===");
        
        Currency srcCurrency = Currency.wrap(address(weth));
        Currency dstCurrency = Currency.wrap(address(usdc));
        uint256 inputAmount = 1e18; // 1 WETH
        uint256 slippageBps = 500; // 5% slippage tolerance

        uint128 minOutAmount = gtxRouter.calculateMinOutForSwap(
            srcCurrency,
            dstCurrency,
            inputAmount,
            slippageBps
        );

        console.log("Input: %s %s", inputAmount / 1e18, "WETH");
        console.log("Expected min output: %s %s", minOutAmount / 1e6, "USDC");
        console.log("Slippage tolerance: %s%%", slippageBps / 100);
        console.log("");
    }

    /// @notice Calculate minimum output for multi-hop swap (e.g., WETH -> WBTC via USDC)
    function calculateMultiHopSwapMinOut() public view {
        console.log("=== Multi-hop Swap Min Output Calculation ===");
        
        Currency srcCurrency = Currency.wrap(address(weth));
        Currency dstCurrency = Currency.wrap(address(wbtc));
        uint256 inputAmount = 1e18; // 1 WETH
        uint256 slippageBps = 500; // 5% slippage tolerance

        uint128 finalMinOut = gtxRouter.calculateMinOutForSwap(
            srcCurrency,
            dstCurrency,
            inputAmount,
            slippageBps
        );

        console.log("Input: %s %s", inputAmount / 1e18, "WETH");
        console.log("Final min output: %s %s", finalMinOut / 1e8, "WBTC");
        console.log("Total slippage tolerance: %s%%", slippageBps / 100);
        console.log("");
    }

    /// @notice General function to calculate minimum output for any swap pair
    /// @param srcToken Address of source token
    /// @param dstToken Address of destination token  
    /// @param inputAmount Amount of source token to swap
    /// @param slippageBps Slippage tolerance in basis points (100 = 1%)
    /// @return minOutAmount Minimum amount of destination token to receive
    function calculateMinOutForSwap(
        address srcToken,
        address dstToken,
        uint256 inputAmount,
        uint256 slippageBps
    ) public view returns (uint128 minOutAmount) {
        return gtxRouter.calculateMinOutForSwap(
            Currency.wrap(srcToken),
            Currency.wrap(dstToken),
            inputAmount,
            slippageBps
        );
    }

    /// @notice Demo function showing practical usage
    function demonstrateUsage() external view {
        console.log("=== Practical Usage Examples ===");
        
        // Example 1: Direct swap with 2% slippage
        uint128 minOut1 = calculateMinOutForSwap(
            address(weth), // WETH
            address(usdc), // USDC  
            2e18,          // 2 WETH input
            200            // 2% slippage
        );
        console.log("WETH->USDC (2 ETH, 2%% slippage): %s USDC", minOut1 / 1e6);

        // Example 2: Multi-hop swap with 5% slippage
        uint128 minOut2 = calculateMinOutForSwap(
            address(weth), // WETH
            address(wbtc), // WBTC
            1e18,          // 1 WETH input
            500            // 5% slippage
        );
        console.log("WETH->WBTC (1 ETH, 5%% slippage): %s WBTC", minOut2 / 1e8);
    }
}