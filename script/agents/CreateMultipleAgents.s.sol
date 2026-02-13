// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {MockERC8004Identity} from "@scalexagents/mocks/MockERC8004Identity.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title CreateMultipleAgents
 * @notice Create multiple agents using DIFFERENT wallets for fund isolation
 * @dev Each wallet = separate BalanceManager account = isolated funds
 */
contract CreateMultipleAgents is Script {
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
        address policyFactory = _extractAddress(json, "PolicyFactory");
        address balanceManager = _extractAddress(json, "BalanceManager");

        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        address quoteToken = _extractAddress(json, quoteSymbol);

        console.log("Loaded addresses:");
        console.log("  IdentityRegistry:", identityRegistry);
        console.log("  PolicyFactory:", policyFactory);
        console.log("  BalanceManager:", balanceManager);
        console.log("  Quote Token:", quoteToken);
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
                policyFactory,
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
        address policyFactory,
        address balanceManager,
        address quoteToken
    ) internal {
        vm.startBroadcast(agent.privateKey);

        // Step 1: Mint agent identity
        console.log("Step 1: Minting agent identity...");
        MockERC8004Identity(identityRegistry).mint(agent.wallet);

        // Get the token ID
        agent.agentId = MockERC8004Identity(identityRegistry).tokenOfOwnerByIndex(agent.wallet, 0);
        console.log("[OK] Agent minted with ID:", agent.agentId);

        // Step 2: Create policy
        console.log("Step 2: Creating trading policy...");
        _createPolicy(policyFactory, agent);
        console.log("[OK] Policy created");

        // Step 3: Deposit capital
        console.log("Step 3: Depositing capital...");
        _depositCapital(balanceManager, quoteToken, agent);
        console.log("[OK] Capital deposited:", agent.capitalAllocation / 1e6, "tokens");

        vm.stopBroadcast();
    }

    function _createPolicy(address policyFactory, AgentSetup memory agent) internal {
        // Create asset limits (empty for now - will be set per-asset)
        PolicyFactory.AssetLimit[] memory assetLimits = new PolicyFactory.AssetLimit[](0);

        // Create policy based on agent type
        uint256 maxDailyVolume;
        uint256 maxDrawdownBps;
        uint256 minHealthFactor;
        uint256 maxSlippageBps;
        uint256 minCooldownSeconds;

        // Conservative agent: strict limits
        if (agent.capitalAllocation == 1000e6) {
            maxDailyVolume = 5000e6;      // 5k daily volume
            maxDrawdownBps = 1000;        // 10% max drawdown
            minHealthFactor = 300;        // 1.3x health factor
            maxSlippageBps = 300;         // 3% max slippage
            minCooldownSeconds = 120;     // 2 minute cooldown
        }
        // Aggressive agent: looser limits
        else if (agent.capitalAllocation == 5000e6) {
            maxDailyVolume = 50000e6;     // 50k daily volume
            maxDrawdownBps = 2500;        // 25% max drawdown
            minHealthFactor = 250;        // 1.25x health factor
            maxSlippageBps = 500;         // 5% max slippage
            minCooldownSeconds = 30;      // 30 second cooldown
        }
        // Test agent: very strict limits
        else {
            maxDailyVolume = 2000e6;      // 2k daily volume
            maxDrawdownBps = 500;         // 5% max drawdown
            minHealthFactor = 350;        // 1.35x health factor
            maxSlippageBps = 200;         // 2% max slippage
            minCooldownSeconds = 300;     // 5 minute cooldown
        }

        PolicyFactory(policyFactory).createPolicy(
            agent.agentId,
            assetLimits,
            maxDailyVolume,
            maxDrawdownBps,
            minHealthFactor,
            maxSlippageBps,
            minCooldownSeconds
        );
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
        IBalanceManager(balanceManager).deposit(Currency.wrap(token), agent.capitalAllocation);
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
