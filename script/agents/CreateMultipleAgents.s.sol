// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {MockERC8004Identity} from "@scalexagents/mocks/MockERC8004Identity.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title CreateMultipleAgents
 * @notice Create multiple agents using DIFFERENT wallets for fund isolation
 * @dev Each wallet = separate BalanceManager account = isolated funds
 */
contract CreateMultipleAgents is Script {
    /// @dev Cached agentRouter address — stored in slot so it is NOT a live Yul stack variable
    ///      during the authorize() ABI encoding of the 42-field Policy struct.
    ///      Loading from storage at the CALL opcode costs 1 SLOAD but saves 1 Yul stack slot,
    ///      keeping peak depth within the EVM's SWAP16 window.
    address private _agentRouterCache;

    struct AgentSetup {
        address wallet;
        uint256 privateKey;
        uint256 agentId;
        uint256 capitalAllocation; // In quote token base units
        string name;
    }

    function run() external {
        console.log("=== CREATING MULTIPLE AGENTS WITH ISOLATED FUNDS ===");
        console.log("");

        // Load deployment addresses
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");
        string memory json = vm.readFile(deploymentPath);

        address identityRegistry = _extractAddress(json, "IdentityRegistry");
        address agentRouter      = _extractAddress(json, "AgentRouter");
        address balanceManager   = _extractAddress(json, "BalanceManager");

        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        address quoteToken = _extractAddress(json, quoteSymbol);

        console.log("Loaded addresses:");
        console.log("  IdentityRegistry:", identityRegistry);
        console.log("  AgentRouter:     ", agentRouter);
        console.log("  BalanceManager:  ", balanceManager);
        console.log("  Quote Token:     ", quoteToken);
        console.log("");

        // Define 3 agents with different wallets and capital
        AgentSetup[] memory agents = new AgentSetup[](3);

        // Agent 1: Conservative trader (1,000 USDC/IDRX)
        agents[0] = AgentSetup({
            wallet: address(0),
            privateKey: vm.envUint("AGENT1_PRIVATE_KEY"),
            agentId: 0,
            capitalAllocation: 1000e6, // 1,000 quote tokens
            name: "Conservative Agent"
        });

        // Agent 2: Aggressive trader (5,000 USDC/IDRX)
        agents[1] = AgentSetup({
            wallet: address(0),
            privateKey: vm.envUint("AGENT2_PRIVATE_KEY"),
            agentId: 0,
            capitalAllocation: 5000e6, // 5,000 quote tokens
            name: "Aggressive Agent"
        });

        // Agent 3: Test agent (500 USDC/IDRX)
        agents[2] = AgentSetup({
            wallet: address(0),
            privateKey: vm.envUint("AGENT3_PRIVATE_KEY"),
            agentId: 0,
            capitalAllocation: 500e6, // 500 quote tokens
            name: "Test Agent"
        });

        // Derive wallet addresses from private keys
        for (uint256 i = 0; i < agents.length; i++) {
            agents[i].wallet = vm.addr(agents[i].privateKey);
        }

        console.log("=== AGENT CONFIGURATION ===");
        console.log("");
        for (uint256 i = 0; i < agents.length; i++) {
            console.log(string.concat("Agent ", vm.toString(i + 1), " - ", agents[i].name));
            console.log("  Wallet:", agents[i].wallet);
            console.log("  Capital:", agents[i].capitalAllocation / 1e6, quoteSymbol);
            console.log("");
        }

        // Setup each agent
        for (uint256 i = 0; i < agents.length; i++) {
            console.log(string.concat("=== Setting up ", agents[i].name, " ==="));
            _setupAgent(
                agents[i],
                identityRegistry,
                agentRouter,
                balanceManager,
                quoteToken
            );
            console.log("");
        }

        console.log("=== VERIFICATION ===");
        console.log("");
        for (uint256 i = 0; i < agents.length; i++) {
            _verifyAgent(agents[i], balanceManager, quoteToken);
        }

        console.log("");
        console.log("[SUCCESS] All agents created with isolated funds!");
        console.log("");
        console.log("Summary:");
        console.log("--------");
        for (uint256 i = 0; i < agents.length; i++) {
            console.log(string.concat("Agent ", vm.toString(i + 1), ":"));
            console.log("  Wallet:", agents[i].wallet);
            console.log("  Agent ID:", agents[i].agentId);
            console.log("  Capital:", agents[i].capitalAllocation / 1e6, quoteSymbol);
        }
    }

    function _setupAgent(
        AgentSetup memory agent,
        address identityRegistry,
        address agentRouter,
        address balanceManager,
        address quoteToken
    ) internal {
        vm.startBroadcast(agent.privateKey);

        // Step 1: Register agent identity (caller = agent.wallet via broadcast)
        console.log("Step 1: Registering agent identity...");
        agent.agentId = MockERC8004Identity(identityRegistry).register();
        console.log("[OK] Agent registered with ID:", agent.agentId);

        // Step 2: Authorize strategy agent with policy (installs policy + grants auth in one tx)
        console.log("Step 2: Authorizing agent with policy...");
        _createPolicy(agentRouter, agent);
        console.log("[OK] Policy installed + agent authorized");

        // Step 3: Deposit capital
        console.log("Step 3: Depositing capital...");
        _depositCapital(balanceManager, quoteToken, agent);
        console.log("[OK] Capital deposited:", agent.capitalAllocation / 1e6, "tokens");

        vm.stopBroadcast();
    }

    /// @dev Stage 1: cache agentRouter in storage (NOT a live stack slot during ABI encoding),
    ///      build Policy in an isolated pure frame, then call authorize with only 2 stack params.
    function _createPolicy(address agentRouter, AgentSetup memory agent) internal {
        _agentRouterCache = agentRouter;
        _callAuthorize(agent.agentId, _buildPolicyForAgent(agent.capitalAllocation));
    }

    /// @dev Stage 2: builds Policy in an isolated pure frame — capitalAllocation is the only
    ///      live local; it dies at the function boundary before _callAuthorize runs the
    ///      42-field ABI encoding (~14 internal Yul vars). Named return avoids an extra
    ///      memory-copy temp on the caller's stack.
    function _buildPolicyForAgent(uint256 capitalAllocation)
        private pure returns (PolicyFactory.Policy memory p)
    {
        address[] memory empty = new address[](0);
        p.expiryTimestamp       = type(uint256).max;
        p.maxOrderSize          = capitalAllocation * 2;
        p.whitelistedTokens     = empty;
        p.blacklistedTokens     = empty;
        p.allowMarketOrders     = true;
        p.allowLimitOrders      = true;
        p.allowSwap             = true;
        p.allowSupplyCollateral = true;
        p.allowPlaceLimitOrder  = true;
        p.allowCancelOrder      = true;
        p.allowBuy              = true;
        p.allowSell             = true;
        p.minHealthFactor       = 1e18;
        if (capitalAllocation == 1000e6) {          // Conservative
            p.maxSlippageBps        = 300;
            p.minTimeBetweenTrades  = 120;
            p.dailyVolumeLimit      = 5000e6;
            p.maxDailyDrawdown      = 1000;
        } else if (capitalAllocation == 5000e6) {   // Aggressive
            p.maxSlippageBps        = 500;
            p.minTimeBetweenTrades  = 30;
            p.dailyVolumeLimit      = 50000e6;
            p.maxDailyDrawdown      = 2500;
        } else {                                     // Test
            p.maxSlippageBps        = 200;
            p.minTimeBetweenTrades  = 300;
            p.dailyVolumeLimit      = 2000e6;
            p.maxDailyDrawdown      = 500;
        }
    }

    /// @dev Assembly ABI encoder for authorize(uint256, Policy).
    ///      Policy has 42 fields; whitelistedTokens (field 5) and blacklistedTokens (field 6)
    ///      are the only dynamic types — always empty in scripts, so lengths are hardcoded 0.
    ///      Calldata layout: 4 (sel) + 32 (id) + 32 (Policy offset=64) + 1344 (42-word head)
    ///                       + 32 (wTokens len=0) + 32 (bTokens len=0) = 1476 bytes total.
    ///      Peak named Yul variables: ~8 — well within the 16-slot SWAP16 window.
    function _callAuthorize(uint256 agentId, PolicyFactory.Policy memory p) private {
        bytes4 sel = AgentRouter.authorize.selector;
        assembly {
            let router   := sload(_agentRouterCache.slot)
            let cdStart  := mload(0x40)
            mstore(0x40, add(cdStart, 1476))

            mstore(cdStart, sel)                    // selector (left-aligned bytes4)
            mstore(add(cdStart,  4), agentId)      // param 1
            mstore(add(cdStart, 36), 0x40)         // param 2: offset to Policy tuple = 64

            let base := add(cdStart, 68)           // Policy tuple starts here

            // Copy all 42 head words from struct memory → calldata head
            for { let i := 0 } lt(i, 42) { i := add(i, 1) } {
                mstore(add(base, mul(i, 0x20)), mload(add(p, mul(i, 0x20))))
            }

            // Overwrite field 5 (whitelistedTokens) and field 6 (blacklistedTokens)
            // with their ABI tail offsets (relative to start of Policy tuple).
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

    function _depositCapital(
        address balanceManager,
        address token,
        AgentSetup memory agent
    ) internal {
        // Check token balance
        uint256 tokenBalance = ERC20(token).balanceOf(agent.wallet);
        require(tokenBalance >= agent.capitalAllocation, "Insufficient token balance");

        // Approve
        ERC20(token).approve(balanceManager, type(uint256).max);

        // Deposit
        IBalanceManager(balanceManager).deposit(Currency.wrap(token), agent.capitalAllocation, agent.wallet, agent.wallet);
    }

    function _verifyAgent(
        AgentSetup memory agent,
        address balanceManager,
        address token
    ) internal view {
        uint256 balance = IBalanceManager(balanceManager).getBalance(
            agent.wallet,
            Currency.wrap(token)
        );

        console.log(string.concat(agent.name, ":"));
        console.log("  Wallet:", agent.wallet);
        console.log("  Agent ID:", agent.agentId);
        console.log("  Balance:", balance / 1e6, "tokens");

        if (balance == agent.capitalAllocation) {
            console.log("  Status: OK");
        } else {
            console.log("  Status: MISMATCH!");
        }
        console.log("");
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes.concat('"', bytes(key), '": "');

        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) {
            return address(0);
        }

        uint256 addressStart = keyPos + keyBytes.length;
        bytes memory addressBytes = new bytes(42);
        for (uint256 i = 0; i < 42; i++) {
            addressBytes[i] = jsonBytes[addressStart + i];
        }

        return _bytesToAddress(addressBytes);
    }

    function _indexOf(bytes memory haystack, bytes memory needle) internal pure returns (uint256) {
        if (needle.length == 0 || haystack.length < needle.length) {
            return type(uint256).max;
        }

        uint256 needleLength = needle.length;
        for (uint256 i = 0; i <= haystack.length - needleLength; i++) {
            bool found = true;
            for (uint256 j = 0; j < needleLength; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
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
            uint8 byteValue = uint8(data[i]);
            uint256 digit;
            if (byteValue >= 48 && byteValue <= 57) {
                digit = uint256(byteValue) - 48;
            } else if (byteValue >= 97 && byteValue <= 102) {
                digit = uint256(byteValue) - 87;
            } else if (byteValue >= 65 && byteValue <= 70) {
                digit = uint256(byteValue) - 55;
            } else {
                continue;
            }
            result = result * 16 + digit;
        }
        return result;
    }
}
