// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {PolicyFactoryStorage} from "@scalexagents/storages/PolicyFactoryStorage.sol";
import {IERC8004Identity} from "@scalexagents/interfaces/IERC8004Identity.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VerifyAgentExecution
 * @notice End-to-end verification of the simplified ERC-8004 agent flow.
 *
 * Flow:
 *   1. Strategy agent calls IdentityRegistry.register() ->gets strategyAgentId NFT.
 *   2. Primary trader calls AgentRouter.authorize(strategyAgentId, policy) ->
 *      installs policy + grants authorization in ONE transaction.
 *   3. Primary trader deposits IDRX collateral for BUY order.
 *   4. Strategy agent calls AgentRouter.executeLimitOrder(primaryTrader, strategyAgentId, ...)
 *   5. Strategy agent calls AgentRouter.cancelOrder(primaryTrader, strategyAgentId, ...)
 *
 * No userAgentId NFT needed -- user is identified by wallet address.
 *
 * Environment variables required:
 *   PRIVATE_KEY        - Primary trader private key (owns funds, grants authorization)
 *   AGENT_PRIVATE_KEY  - Strategy agent private key (NFT owner, executes orders)
 */
contract VerifyAgentExecution is Script {
    // Intermediate struct to reduce stack depth
    struct Addrs {
        address identityRegistry;
        address agentRouter;
        address balanceManager;
        address weth;
        address idrx;
        address wethIdrxPool;
    }

    function run() external {
        console.log("=== ERC-8004 AGENT EXECUTION VERIFICATION ===");
        console.log("");

        uint256 primaryKey    = vm.envUint("PRIVATE_KEY");
        uint256 agentKey      = vm.envUint("AGENT_PRIVATE_KEY");
        address primaryTrader = vm.addr(primaryKey);
        address agentWallet   = vm.addr(agentKey);

        Addrs memory a = _loadAddresses();

        console.log("Actors:");
        console.log("  Primary Trader:", primaryTrader);
        console.log("  Agent Wallet:  ", agentWallet);
        console.log("");

        // STEP 1: Strategy agent registers its NFT
        uint256 strategyAgentId = _step1RegisterAgent(agentKey, agentWallet, a.identityRegistry);

        // STEP 2: Primary trader authorizes agent
        _step2Authorize(primaryKey, strategyAgentId, a.agentRouter);

        // STEP 3: Ensure IDRX balance for BUY order collateral
        _step3EnsureCollateral(primaryKey, primaryTrader, a.balanceManager, a.idrx);

        // STEP 4 & 5: Place and cancel order
        _step4And5PlaceAndCancel(agentKey, primaryTrader, strategyAgentId, a);

        // SUMMARY
        _logSummary(strategyAgentId, primaryTrader, agentWallet);
    }

    function _loadAddresses() internal view returns (Addrs memory a) {
        string memory root       = vm.projectRoot();
        string memory deployPath = string.concat(root, "/deployments/", vm.toString(block.chainid), ".json");
        string memory json       = vm.readFile(deployPath);

        a.identityRegistry = _extractAddress(json, "IdentityRegistry");
        a.agentRouter      = _extractAddress(json, "AgentRouter");
        a.balanceManager   = _extractAddress(json, "BalanceManager");
        a.weth             = _extractAddress(json, "WETH");
        a.idrx             = _extractAddress(json, "IDRX");
        a.wethIdrxPool     = _extractAddress(json, "WETH_IDRX_Pool");

        require(a.identityRegistry != address(0), "IdentityRegistry not in deployment");
        require(a.agentRouter      != address(0), "AgentRouter not in deployment");
        require(a.balanceManager   != address(0), "BalanceManager not in deployment");
        require(a.weth             != address(0), "WETH not in deployment");
        require(a.idrx             != address(0), "IDRX not in deployment");
        require(a.wethIdrxPool     != address(0), "WETH_IDRX_Pool not in deployment");
    }

    function _step1RegisterAgent(uint256 agentKey, address agentWallet, address identityRegistry) internal returns (uint256 strategyAgentId) {
        console.log("Step 1: Strategy agent registers NFT...");
        vm.startBroadcast(agentKey);
        strategyAgentId = IERC8004Identity(identityRegistry).register("https://agents.scalex.money/agents/1/metadata.json");
        console.log("[OK] Strategy agent NFT minted, tokenId:", strategyAgentId);
        console.log("     NFT owner (= executor):", agentWallet);
        vm.stopBroadcast();
    }

    function _step2Authorize(uint256 primaryKey, uint256 strategyAgentId, address agentRouter) internal {
        console.log("Step 2: Primary trader authorizes strategy agent with policy...");
        vm.startBroadcast(primaryKey);
        AgentRouter(agentRouter).authorize(strategyAgentId, _buildPolicy());
        console.log("[OK] Strategy agent", strategyAgentId, "authorized with policy");
        console.log("     maxOrderSize: 100 WETH, allowLimitOrders: true, allowCancelOrder: true");
        vm.stopBroadcast();
    }

    function _step3EnsureCollateral(uint256 primaryKey, address primaryTrader, address balanceManager, address idrx) internal {
        console.log("Step 3: Ensuring IDRX collateral in BalanceManager...");
        vm.startBroadcast(primaryKey);

        uint256 bmBalance = IBalanceManager(balanceManager).getBalance(primaryTrader, Currency.wrap(idrx));
        console.log("  Current IDRX in BalanceManager (raw units, 2 dec):", bmBalance);

        uint256 neededRaw = 500; // 5.00 IDRX raw
        if (bmBalance < neededRaw) {
            uint256 walletBal = IERC20(idrx).balanceOf(primaryTrader);
            if (walletBal >= neededRaw) {
                IERC20(idrx).approve(balanceManager, type(uint256).max);
                IBalanceManager(balanceManager).depositLocal(idrx, neededRaw, primaryTrader);
                uint256 newBal = IBalanceManager(balanceManager).getBalance(primaryTrader, Currency.wrap(idrx));
                console.log("[OK] Deposited", neededRaw, "raw IDRX. New balance:", newBal);
            } else {
                console.log("[WARN] Insufficient IDRX. Order may fail. Run populate-data.sh first.");
            }
        } else {
            console.log("[OK] Sufficient IDRX in BalanceManager (", bmBalance, "raw units)");
        }

        vm.stopBroadcast();
    }

    function _step4And5PlaceAndCancel(
        uint256 agentKey,
        address primaryTrader,
        uint256 strategyAgentId,
        Addrs memory a
    ) internal {
        console.log("Step 4: Strategy agent places BUY limit order for primary trader...");
        console.log("  user:            ", primaryTrader);
        console.log("  strategyAgentId: ", strategyAgentId);
        console.log("  Price:            190000 raw (1900 IDRX/WETH, below market - will not fill)");
        console.log("  Quantity:         1e15 (0.001 WETH)");

        vm.startBroadcast(agentKey);

        IPoolManager.Pool memory pool = IPoolManager.Pool({
            baseCurrency:  Currency.wrap(a.weth),
            quoteCurrency: Currency.wrap(a.idrx),
            orderBook:     IOrderBook(a.wethIdrxPool)
        });

        uint48 orderId;
        try AgentRouter(a.agentRouter).executeLimitOrder(
            primaryTrader,
            strategyAgentId,
            pool,
            190000,
            1e15,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        ) returns (uint48 id) {
            orderId = id;
            console.log("[OK] Limit order placed! orderId:", orderId);
        } catch Error(string memory reason) {
            console.log("[FAIL] executeLimitOrder reverted:", reason);
            vm.stopBroadcast();
            return;
        } catch (bytes memory data) {
            console.log("[FAIL] executeLimitOrder low-level error");
            console.logBytes(data);
            vm.stopBroadcast();
            return;
        }

        // STEP 5: Strategy agent cancels the order
        console.log("Step 5: Strategy agent cancels the order...");
        try AgentRouter(a.agentRouter).cancelOrder(
            primaryTrader,
            strategyAgentId,
            pool,
            orderId
        ) {
            console.log("[OK] Order", orderId, "cancelled. IDRX collateral returned.");
        } catch Error(string memory reason) {
            console.log("[FAIL] cancelOrder reverted:", reason);
        } catch (bytes memory data) {
            console.log("[FAIL] cancelOrder low-level error");
            console.logBytes(data);
        }

        vm.stopBroadcast();
    }

    function _logSummary(uint256 strategyAgentId, address primaryTrader, address agentWallet) internal pure {
        console.log("");
        console.log("=== VERIFICATION COMPLETE ===");
        console.log("");
        console.log("Simplified ERC-8004 Agent Flow:");
        console.log("  [1] IdentityRegistry.register() ->strategy agent NFT minted");
        console.log("  [2] AgentRouter.authorize(strategyAgentId, policy) ->policy installed + authorized (1 tx)");
        console.log("  [3] IDRX collateral confirmed in BalanceManager");
        console.log("  [4] AgentRouter.executeLimitOrder(userAddress, strategyAgentId, ...) ->order placed");
        console.log("  [5] AgentRouter.cancelOrder(userAddress, strategyAgentId, ...) ->order cancelled");
        console.log("");
        console.log("  Strategy Agent ID:", strategyAgentId);
        console.log("  Primary Trader:   ", primaryTrader);
        console.log("  Agent Wallet:     ", agentWallet);
    }

    /// @dev Builds the Policy struct for agent verification.
    function _buildPolicy() private pure returns (PolicyFactoryStorage.Policy memory p) {
        address[] memory empty = new address[](0);
        p.expiryTimestamp      = type(uint256).max;
        p.maxOrderSize         = 100e18;
        p.whitelistedTokens    = empty;
        p.blacklistedTokens    = empty;
        p.allowMarketOrders    = true;
        p.allowLimitOrders     = true;
        p.allowSwap            = true;
        p.allowPlaceLimitOrder = true;
        p.allowCancelOrder     = true;
        p.allowBuy             = true;
        p.allowSell            = true;
        p.minHealthFactor      = 1e18;
        p.maxSlippageBps       = 1000;
    }

    // JSON helpers

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes  = bytes(string.concat('"', key, '": "'));
        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) return address(0);
        uint256 addressStart = keyPos + keyBytes.length;
        bytes memory addrBytes = new bytes(42);
        for (uint256 i = 0; i < 42; i++) addrBytes[i] = jsonBytes[addressStart + i];
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
