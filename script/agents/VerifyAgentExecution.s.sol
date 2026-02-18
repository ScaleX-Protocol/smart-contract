// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
    /// @dev Temporary storage for agentRouter so it doesn't occupy a Yul stack slot
    ///      during authorize() ABI encoding. Loading from storage at the CALL opcode
    ///      saves 1 stack slot vs passing it as a function parameter.
    address private _agentRouterCache;

    function run() external {
        console.log("=== ERC-8004 AGENT EXECUTION VERIFICATION ===");
        console.log("");

        uint256 primaryKey    = vm.envUint("PRIVATE_KEY");
        uint256 agentKey      = vm.envUint("AGENT_PRIVATE_KEY");
        address primaryTrader = vm.addr(primaryKey);
        address agentWallet   = vm.addr(agentKey);

        string memory root       = vm.projectRoot();
        string memory deployPath = string.concat(root, "/deployments/", vm.toString(block.chainid), ".json");
        string memory json       = vm.readFile(deployPath);

        address identityRegistry = _extractAddress(json, "IdentityRegistry");
        address agentRouter      = _extractAddress(json, "AgentRouter");
        address balanceManager   = _extractAddress(json, "BalanceManager");
        address weth             = _extractAddress(json, "WETH");
        address idrx             = _extractAddress(json, "IDRX");
        address wethIdrxPool     = _extractAddress(json, "WETH_IDRX_Pool");

        require(identityRegistry != address(0), "IdentityRegistry not in deployment");
        require(agentRouter      != address(0), "AgentRouter not in deployment");
        require(balanceManager   != address(0), "BalanceManager not in deployment");
        require(weth             != address(0), "WETH not in deployment");
        require(idrx             != address(0), "IDRX not in deployment");
        require(wethIdrxPool     != address(0), "WETH_IDRX_Pool not in deployment");

        console.log("Actors:");
        console.log("  Primary Trader:", primaryTrader);
        console.log("  Agent Wallet:  ", agentWallet);
        console.log("");

        // STEP 1: Strategy agent registers its NFT
        console.log("Step 1: Strategy agent registers NFT...");
        vm.startBroadcast(agentKey);
        uint256 strategyAgentId = IERC8004Identity(identityRegistry).register("ipfs://QmStrategyAgentVerify");
        console.log("[OK] Strategy agent NFT minted, tokenId:", strategyAgentId);
        console.log("     NFT owner (= executor):", agentWallet);
        vm.stopBroadcast();

        // STEP 2: Primary trader calls authorize(strategyAgentId, policy).
        //         Three-function encode->call split avoids Yul stack-too-deep:
        //         _doAuthorize makes the raw call; _buildAuthorizeData builds
        //         calldata in a pure frame without agentRouter in scope;
        //         _encodeAuthorize is isolated so only agentId + p are live
        //         during abi.encodeCall (~14 internal Yul vars for 42-field Policy).
        console.log("Step 2: Primary trader authorizes strategy agent with policy...");
        vm.startBroadcast(primaryKey);
        _doAuthorize(agentRouter, strategyAgentId);
        console.log("[OK] Strategy agent", strategyAgentId, "authorized with policy");
        console.log("     maxOrderSize: 100 WETH, allowLimitOrders: true, allowCancelOrder: true");
        vm.stopBroadcast();

        // STEP 3: Ensure IDRX balance for BUY order collateral
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

        // STEP 4: Strategy agent places BUY limit order for primary trader
        console.log("Step 4: Strategy agent places BUY limit order for primary trader...");
        console.log("  user:            ", primaryTrader);
        console.log("  strategyAgentId: ", strategyAgentId);
        console.log("  Price:            190000 raw (1900 IDRX/WETH, below market - will not fill)");
        console.log("  Quantity:         1e15 (0.001 WETH)");

        vm.startBroadcast(agentKey);

        IPoolManager.Pool memory pool = IPoolManager.Pool({
            baseCurrency:  Currency.wrap(weth),
            quoteCurrency: Currency.wrap(idrx),
            orderBook:     IOrderBook(wethIdrxPool)
        });

        uint48 orderId;
        try AgentRouter(agentRouter).executeLimitOrder(
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
        try AgentRouter(agentRouter).cancelOrder(
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

        // SUMMARY
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

    /// @dev Two-stage split: cache agentRouter in storage (so it's not a live stack slot
    ///      during ABI encoding), build Policy in an isolated pure frame, then call
    ///      authorize with only 2 stack params — the minimum needed for the 42-field struct.
    function _doAuthorize(address agentRouter, uint256 strategyAgentId) internal {
        _agentRouterCache = agentRouter;
        _callAuthorize(strategyAgentId, _makeVerifyPolicy());
    }

    /// @dev Builds the Policy struct in an isolated pure frame — no outer locals in scope.
    ///      Only non-zero fields are set; Solidity zero-initializes all others automatically.
    function _makeVerifyPolicy() private pure returns (PolicyFactory.Policy memory p) {
        address[] memory emptyList = new address[](0);
        p.expiryTimestamp      = type(uint256).max;
        p.maxOrderSize         = 100e18;
        p.whitelistedTokens    = emptyList;
        p.blacklistedTokens    = emptyList;
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

    /// @dev Assembly ABI encoder for authorize(uint256, Policy).
    ///      Policy has 42 fields; whitelistedTokens (field 5) and blacklistedTokens (field 6)
    ///      are the only dynamic types — always empty in scripts, so lengths are hardcoded 0.
    ///      Calldata layout: 4 (sel) + 32 (id) + 32 (Policy offset=64) + 1344 (42-word head)
    ///                       + 32 (wTokens len=0) + 32 (bTokens len=0) = 1476 bytes total.
    ///      Peak named Yul variables: ~8 — well within the 16-slot SWAP16 window.
    function _callAuthorize(uint256 strategyAgentId, PolicyFactory.Policy memory p) private {
        bytes4 sel = AgentRouter.authorize.selector;
        assembly {
            let router   := sload(_agentRouterCache.slot)
            let cdStart  := mload(0x40)
            mstore(0x40, add(cdStart, 1476))

            mstore(cdStart, sel)                        // selector (left-aligned bytes4)
            mstore(add(cdStart,  4), strategyAgentId)  // param 1
            mstore(add(cdStart, 36), 0x40)             // param 2: offset to Policy tuple = 64

            let base := add(cdStart, 68)               // Policy tuple starts here

            // Copy all 42 head words from struct memory → calldata head
            for { let i := 0 } lt(i, 42) { i := add(i, 1) } {
                mstore(add(base, mul(i, 0x20)), mload(add(p, mul(i, 0x20))))
            }

            // Overwrite field 5 (whitelistedTokens) and field 6 (blacklistedTokens)
            // with their ABI tail offsets (relative to start of Policy tuple).
            // Tail begins right after the 42-word head: 42*32 = 0x540.
            mstore(add(base, 0xa0), 0x540)  // whitelistedTokens at base+0x540
            mstore(add(base, 0xc0), 0x560)  // blacklistedTokens at base+0x560

            // Write empty array lengths in the tail
            mstore(add(base, 0x540), 0)     // whitelistedTokens.length = 0
            mstore(add(base, 0x560), 0)     // blacklistedTokens.length  = 0

            let ok := call(gas(), router, 0, cdStart, 1476, 0, 0)
            if iszero(ok) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
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
