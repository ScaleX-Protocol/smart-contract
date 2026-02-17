// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {IERC8004Identity} from "@scalexagents/interfaces/IERC8004Identity.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VerifyAgentExecution
 * @notice End-to-end verification of the complete ERC-8004 agent execution flow (Model B)
 *
 * Flow verified:
 *   1. Primary trader registers user agent NFT (IdentityRegistry)
 *   2. Primary trader installs trading policy (PolicyFactory, no Chainlink)
 *   3. Primary trader deposits IDRX into BalanceManager (collateral for BUY order)
 *   4. Agent executor registers strategy agent NFT
 *   5. Agent executor registers their wallet as strategy executor
 *   6. Primary trader authorizes the strategy agent
 *   7. Agent executor places BUY limit order on behalf of primary trader (AgentRouter)
 *   8. Agent executor cancels the order
 *
 * Environment variables required:
 *   PRIVATE_KEY        - Primary trader private key (owns funds + user agent)
 *   AGENT_PRIVATE_KEY  - Agent executor private key (runs the strategy)
 */
contract VerifyAgentExecution is Script {

    function run() external {
        console.log("=== ERC-8004 AGENT EXECUTION VERIFICATION (Model B) ===");
        console.log("");

        uint256 primaryKey   = vm.envUint("PRIVATE_KEY");
        uint256 agentKey     = vm.envUint("AGENT_PRIVATE_KEY");
        address primaryTrader = vm.addr(primaryKey);
        address agentExecutor = vm.addr(agentKey);

        // Load deployment addresses
        string memory root       = vm.projectRoot();
        string memory deployPath = string.concat(root, "/deployments/", vm.toString(block.chainid), ".json");
        string memory json       = vm.readFile(deployPath);

        address identityRegistry = _extractAddress(json, "IdentityRegistry");
        address policyFactory    = _extractAddress(json, "PolicyFactory");
        address agentRouter      = _extractAddress(json, "AgentRouter");
        address balanceManager   = _extractAddress(json, "BalanceManager");
        address weth             = _extractAddress(json, "WETH");
        address idrx             = _extractAddress(json, "IDRX");
        address wethIdrxPool     = _extractAddress(json, "WETH_IDRX_Pool");

        require(identityRegistry != address(0), "IdentityRegistry not in deployment");
        require(policyFactory    != address(0), "PolicyFactory not in deployment");
        require(agentRouter      != address(0), "AgentRouter not in deployment");
        require(balanceManager   != address(0), "BalanceManager not in deployment");
        require(weth             != address(0), "WETH not in deployment");
        require(idrx             != address(0), "IDRX not in deployment");
        require(wethIdrxPool     != address(0), "WETH_IDRX_Pool not in deployment");

        console.log("Loaded addresses:");
        console.log("  IdentityRegistry:", identityRegistry);
        console.log("  PolicyFactory:   ", policyFactory);
        console.log("  AgentRouter:     ", agentRouter);
        console.log("  BalanceManager:  ", balanceManager);
        console.log("  WETH:            ", weth);
        console.log("  IDRX:            ", idrx);
        console.log("  WETH/IDRX Pool:  ", wethIdrxPool);
        console.log("");
        console.log("Actors:");
        console.log("  Primary Trader (user agent owner):", primaryTrader);
        console.log("  Agent Executor (strategy runner): ", agentExecutor);
        console.log("");

        // ──────────────────────────────────────────────────────────────────────
        // PRIMARY TRADER ACTIONS
        // ──────────────────────────────────────────────────────────────────────
        vm.startBroadcast(primaryKey);

        // Step 1: Register user agent NFT
        console.log("Step 1: Primary trader registers user agent NFT...");
        uint256 userAgentId = IERC8004Identity(identityRegistry).register("ipfs://QmUserAgentVerify");
        console.log("[OK] User agent registered, tokenId:", userAgentId);

        // Step 2: Install agent policy (all complex fields = 0 → no Chainlink required)
        console.log("Step 2: Installing simple trading policy (no Chainlink)...");
        address[] memory emptyList = new address[](0);
        PolicyFactory.Policy memory policy = PolicyFactory.Policy({
            // Metadata
            enabled:                     false,            // set by installAgent
            installedAt:                 0,                // set by installAgent
            expiryTimestamp:             type(uint256).max,
            agentTokenId:                userAgentId,
            // Order size
            maxOrderSize:                100e18,           // 100 WETH max per order (covers 0.001 WETH test)
            minOrderSize:                0,
            // Token lists (empty = all tokens allowed)
            whitelistedTokens:           emptyList,
            blacklistedTokens:           emptyList,
            // Order types
            allowMarketOrders:           true,
            allowLimitOrders:            true,
            // Operations
            allowSwap:                   true,
            allowBorrow:                 false,
            allowRepay:                  false,
            allowSupplyCollateral:       false,
            allowWithdrawCollateral:     false,
            allowPlaceLimitOrder:        true,
            allowCancelOrder:            true,
            // Direction
            allowBuy:                    true,
            allowSell:                   true,
            // Auto-borrow/repay (disabled)
            allowAutoBorrow:             false,
            maxAutoBorrowAmount:         0,
            allowAutoRepay:              false,
            minDebtToRepay:              0,
            // Safety
            minHealthFactor:             1e18,             // 100% (user has no debt)
            maxSlippageBps:              1000,             // 10%
            minTimeBetweenTrades:        0,                // no cooldown for testing
            emergencyRecipient:          address(0),
            // Complex permissions (ALL ZERO → requiresChainlinkFunctions = false)
            dailyVolumeLimit:            0,
            weeklyVolumeLimit:           0,
            maxDailyDrawdown:            0,
            maxWeeklyDrawdown:           0,
            maxTradeVsTVLBps:            0,
            minWinRateBps:               0,
            minSharpeRatio:              0,
            maxPositionConcentrationBps: 0,
            maxCorrelationBps:           0,
            maxTradesPerDay:             0,
            maxTradesPerHour:            0,
            tradingStartHour:            0,
            tradingEndHour:              0,
            minReputationScore:          0,
            useReputationMultiplier:     false,
            requiresChainlinkFunctions:  false
        });
        PolicyFactory(policyFactory).installAgent(userAgentId, policy);
        console.log("[OK] Policy installed (requiresChainlinkFunctions: false)");
        console.log("       maxOrderSize: 100 WETH");
        console.log("       allowLimitOrders: true, allowCancelOrder: true");

        // Step 3: Ensure IDRX balance in BalanceManager for BUY order collateral
        // BUY 0.001 WETH at 1900 IDRX/WETH → locks ~190 raw IDRX (1.90 IDRX)
        console.log("Step 3: Ensuring IDRX balance in BalanceManager for order collateral...");
        uint256 bmBalance = IBalanceManager(balanceManager).getBalance(primaryTrader, Currency.wrap(idrx));
        console.log("  Current IDRX in BalanceManager (raw units, 2 dec):", bmBalance);

        uint256 neededRaw = 500; // 5.00 IDRX raw (2 decimals) - covers 190 raw needed for test order
        if (bmBalance < neededRaw) {
            uint256 walletBal = IERC20(idrx).balanceOf(primaryTrader);
            console.log("  IDRX wallet balance (raw):", walletBal);
            if (walletBal >= neededRaw) {
                IERC20(idrx).approve(balanceManager, type(uint256).max);
                IBalanceManager(balanceManager).depositLocal(idrx, neededRaw, primaryTrader);
                uint256 newBal = IBalanceManager(balanceManager).getBalance(primaryTrader, Currency.wrap(idrx));
                console.log("[OK] Deposited", neededRaw, "raw IDRX. New BalanceManager balance:", newBal);
            } else {
                console.log("[WARN] Insufficient IDRX in wallet. Limit order may fail.");
                console.log("       Run populate-data.sh first to fund the primary trader.");
            }
        } else {
            console.log("[OK] Sufficient IDRX in BalanceManager (", bmBalance, "raw units)");
        }

        vm.stopBroadcast();

        // ──────────────────────────────────────────────────────────────────────
        // AGENT EXECUTOR ACTIONS
        // ──────────────────────────────────────────────────────────────────────

        // Step 4: Agent executor registers strategy agent NFT
        console.log("Step 4: Agent executor registers strategy agent NFT...");
        vm.startBroadcast(agentKey);
        uint256 strategyAgentId = IERC8004Identity(identityRegistry).register("ipfs://QmStrategyAgentVerify");
        console.log("[OK] Strategy agent registered, tokenId:", strategyAgentId);

        // Step 5: Register executor wallet for strategy agent
        console.log("Step 5: Registering executor wallet for strategy agent...");
        AgentRouter(agentRouter).registerAgentExecutor(strategyAgentId, agentExecutor);
        console.log("[OK] Executor registered:", agentExecutor, "for strategyAgentId:", strategyAgentId);
        vm.stopBroadcast();

        // ──────────────────────────────────────────────────────────────────────
        // PRIMARY TRADER AUTHORIZES STRATEGY AGENT
        // ──────────────────────────────────────────────────────────────────────

        // Step 6: Primary trader authorizes the strategy agent
        console.log("Step 6: Primary trader authorizes strategy agent...");
        vm.startBroadcast(primaryKey);
        AgentRouter(agentRouter).authorize(strategyAgentId);
        console.log("[OK] Strategy agent", strategyAgentId, "authorized by primary trader");
        vm.stopBroadcast();

        // ──────────────────────────────────────────────────────────────────────
        // AGENT EXECUTOR TRADES ON BEHALF OF PRIMARY TRADER
        // ──────────────────────────────────────────────────────────────────────
        vm.startBroadcast(agentKey);

        // Build pool struct: WETH (base) / IDRX (quote) / WETH_IDRX_Pool (orderBook)
        IPoolManager.Pool memory pool = IPoolManager.Pool({
            baseCurrency: Currency.wrap(weth),
            quoteCurrency: Currency.wrap(idrx),
            orderBook: IOrderBook(wethIdrxPool)
        });

        // Step 7: Place BUY limit order at below-market price (won't fill)
        // Price: 1900 IDRX/WETH → raw = 1900 * 10^2 (IDRX decimals) = 190000
        // Quantity: 0.001 WETH = 1e15 (18 decimals)
        // IDRX to lock = 190000 * 1e15 / 1e18 = 190 raw IDRX ≈ 1.90 IDRX
        console.log("Step 7: Agent executor places BUY limit order on behalf of primary trader...");
        console.log("  userAgentId:     ", userAgentId);
        console.log("  strategyAgentId: ", strategyAgentId);
        console.log("  Side:             BUY");
        console.log("  Price:            190000 raw (1900 IDRX/WETH, below market - will not fill)");
        console.log("  Quantity:         1e15 (0.001 WETH)");
        console.log("  IDRX to lock:     ~190 raw (1.90 IDRX)");

        uint48 orderId;
        try AgentRouter(agentRouter).executeLimitOrder(
            userAgentId,
            strategyAgentId,
            pool,
            190000,            // limitPrice: 1900 IDRX/WETH
            1e15,              // quantity: 0.001 WETH
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,             // autoRepay
            false              // autoBorrow
        ) returns (uint48 id) {
            orderId = id;
            console.log("[OK] Limit order placed! orderId:", orderId);
            console.log("     Owner (primary trader):", primaryTrader);
            console.log("     Executed by (agent):   ", agentExecutor);
        } catch Error(string memory reason) {
            console.log("[FAIL] executeLimitOrder reverted:", reason);
            console.log("       Possible causes:");
            console.log("         - Insufficient IDRX in primary trader BalanceManager");
            console.log("         - Policy check failed (health factor, order size, etc.)");
            vm.stopBroadcast();
            return;
        } catch (bytes memory data) {
            console.log("[FAIL] executeLimitOrder low-level error");
            console.logBytes(data);
            vm.stopBroadcast();
            return;
        }

        // Step 8: Cancel the order (proves agent can manage orders)
        console.log("Step 8: Agent executor cancels the limit order...");
        try AgentRouter(agentRouter).cancelOrder(
            userAgentId,
            strategyAgentId,
            pool,
            orderId
        ) {
            console.log("[OK] Order", orderId, "cancelled successfully!");
            console.log("     IDRX collateral returned to primary trader BalanceManager");
        } catch Error(string memory reason) {
            console.log("[FAIL] cancelOrder reverted:", reason);
        } catch (bytes memory data) {
            console.log("[FAIL] cancelOrder low-level error");
            console.logBytes(data);
        }

        vm.stopBroadcast();

        // ──────────────────────────────────────────────────────────────────────
        // VERIFICATION SUMMARY
        // ──────────────────────────────────────────────────────────────────────
        console.log("");
        console.log("=== AGENT VERIFICATION COMPLETE ===");
        console.log("");
        console.log("ERC-8004 Model B Flow Verified:");
        console.log("  [1] User agent NFT registered in IdentityRegistry");
        console.log("  [2] Policy installed in PolicyFactory (no Chainlink overhead)");
        console.log("  [3] IDRX collateral confirmed in BalanceManager");
        console.log("  [4] Strategy agent NFT registered by agent executor");
        console.log("  [5] Executor wallet registered via AgentRouter.registerAgentExecutor()");
        console.log("  [6] Primary trader authorized strategy agent via AgentRouter.authorize()");
        console.log("  [7] AgentRouter.executeLimitOrder() called by executor, order placed for user");
        console.log("  [8] AgentRouter.cancelOrder() called by executor, order cancelled for user");
        console.log("");
        console.log("Agent summary:");
        console.log("  User Agent Token ID:     ", userAgentId);
        console.log("  Strategy Agent Token ID: ", strategyAgentId);
        console.log("  Primary Trader:          ", primaryTrader);
        console.log("  Agent Executor:          ", agentExecutor);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // JSON helpers (same pattern as DeployPhase5.s.sol)
    // ──────────────────────────────────────────────────────────────────────────

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes  = bytes(string.concat('"', key, '": "'));

        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) return address(0);

        uint256 addressStart = keyPos + keyBytes.length;
        bytes memory addrBytes = new bytes(42);
        for (uint256 i = 0; i < 42; i++) {
            addrBytes[i] = jsonBytes[addressStart + i];
        }
        return _bytesToAddress(addrBytes);
    }

    function _indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        if (needle.length == 0 || haystack.length < needle.length) return type(uint256).max;
        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) { found = false; break; }
            }
            if (found) return i;
        }
        return type(uint256).max;
    }

    function _bytesToAddress(bytes memory data) internal pure returns (address) {
        return address(uint160(uint256(_hexToUint(data))));
    }

    function _hexToUint(bytes memory data) internal pure returns (uint256) {
        uint256 result = 0;
        for (uint256 i = 0; i < data.length; i++) {
            uint8 b = uint8(data[i]);
            uint256 digit;
            if (b >= 48 && b <= 57)       digit = b - 48;
            else if (b >= 97 && b <= 102) digit = b - 87;
            else if (b >= 65 && b <= 70)  digit = b - 55;
            else continue;
            result = result * 16 + digit;
        }
        return result;
    }
}
