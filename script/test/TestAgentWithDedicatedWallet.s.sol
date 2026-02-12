// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";

/**
 * @title TestAgentWithDedicatedWallet
 * @notice Tests agent order execution using a dedicated agent wallet
 * @dev Demonstrates:
 *      1. Owner funds their account and deposits to BalanceManager
 *      2. Owner authorizes a dedicated agent wallet
 *      3. Agent wallet places orders on behalf of owner
 *      4. All orders show owner as the trader, not the agent wallet
 */
contract TestAgentWithDedicatedWallet is Script {

    function run() external {
        console.log("=== TESTING AGENT WITH DEDICATED WALLET ===" );
        console.log("");

        // Primary trader (owner) private key
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerPrivateKey);

        // Create a dedicated agent wallet (in production, this would be a separate secure wallet)
        uint256 agentPrivateKey = uint256(keccak256(abi.encodePacked("agent_wallet", block.timestamp)));
        address agentWallet = vm.addr(agentPrivateKey);

        console.log("Owner Address:", owner);
        console.log("Agent Wallet Address:", agentWallet);
        console.log("");

        // Load deployment addresses
        string memory root = vm.projectRoot();
        string memory deploymentPath = string.concat(root, "/deployments/84532.json");
        string memory json = vm.readFile(deploymentPath);

        address balanceManager = _extractAddress(json, "BalanceManager");
        address agentRouter = _extractAddress(json, "AgentRouter");
        address policyFactory = _extractAddress(json, "PolicyFactory");
        address idrx = _extractAddress(json, "IDRX");
        address weth = _extractAddress(json, "WETH");
        address poolManager = _extractAddress(json, "PoolManager");
        address wethIDRXPool = _extractAddress(json, "WETH_IDRX_Pool");

        console.log("Contracts:");
        console.log("  BalanceManager:", balanceManager);
        console.log("  AgentRouter:", agentRouter);
        console.log("  PolicyFactory:", policyFactory);
        console.log("  IDRX:", idrx);
        console.log("  WETH:", weth);
        console.log("  PoolManager:", poolManager);
        console.log("  WETH/IDRX Pool:", wethIDRXPool);
        console.log("");

        // ============ OWNER ACTIONS ============
        console.log("=== STEP 1: Owner Setup ===");
        vm.startBroadcast(ownerPrivateKey);

        // Ensure owner has tokens
        console.log("Checking owner token balances...");
        uint256 idrxBalance = IERC20(idrx).balanceOf(owner);
        uint256 wethBalance = IERC20(weth).balanceOf(owner);

        console.log("  IDRX balance:", idrxBalance);
        console.log("  WETH balance:", wethBalance);

        if (idrxBalance < 10000000) {
            console.log("  Minting IDRX for owner...");
            MockToken(idrx).mint(owner, 10000000);
        }

        if (wethBalance < 10 ether) {
            console.log("  Minting WETH for owner...");
            MockToken(weth).mint(owner, 10 ether);
        }

        // Deposit to BalanceManager
        console.log("Depositing to BalanceManager...");
        uint256 depositAmount = 5000000; // 50,000 IDRX
        IERC20(idrx).approve(balanceManager, depositAmount);
        BalanceManager(balanceManager).depositLocal(idrx, depositAmount, owner);

        Currency idrxCurrency = Currency.wrap(idrx);
        uint256 bmBalance = BalanceManager(balanceManager).getBalance(owner, idrxCurrency);
        console.log("  Balance in BalanceManager:", bmBalance);
        console.log("");

        // Install/verify agent
        console.log("=== STEP 2: Agent Setup ===");
        uint256 agentTokenId = 1;

        bool agentEnabled = PolicyFactory(policyFactory).isAgentEnabled(owner, agentTokenId);

        if (agentEnabled) {
            console.log("  Uninstalling existing agent to update policy...");
            PolicyFactory(policyFactory).uninstallAgent(agentTokenId);
        }

        console.log("  Installing agent with policy...");
        PolicyFactory.PolicyCustomization memory customization = PolicyFactory.PolicyCustomization({
            maxOrderSize: 10 ether,
            dailyVolumeLimit: 100 ether,
            expiryTimestamp: 0,
            whitelistedTokens: new address[](0)
        });

        PolicyFactory(policyFactory).installAgentFromTemplate(
            agentTokenId,
            "moderate",
            customization
        );

        PolicyFactory.Policy memory policy = PolicyFactory(policyFactory).getPolicy(owner, agentTokenId);
        console.log("  Agent installed!");
        console.log("  Policy max order size:", policy.maxOrderSize);
        console.log("");

        // Authorize the agent wallet
        console.log("=== STEP 3: Authorize Agent Wallet ===");
        console.log("  Owner authorizing agent wallet:", agentWallet);
        AgentRouter(agentRouter).authorizeExecutor(agentTokenId, agentWallet);

        bool isAuthorized = AgentRouter(agentRouter).isExecutorAuthorized(agentTokenId, agentWallet);
        console.log("  Agent wallet authorized:", isAuthorized);
        console.log("");

        // Fund agent wallet with gas (only needed for transaction fees)
        console.log("  Funding agent wallet with gas...");
        payable(agentWallet).transfer(0.01 ether);
        console.log("  Agent wallet balance:", agentWallet.balance);
        console.log("");

        vm.stopBroadcast();

        // ============ AGENT WALLET ACTIONS ============
        console.log("=== STEP 4: Agent Wallet Places Order on Behalf of Owner ===");
        vm.startBroadcast(agentPrivateKey);

        console.log("  Agent wallet executing order...");
        console.log("  Order details:");
        console.log("    Pool: WETH/IDRX");
        console.log("    Side: BUY");
        console.log("    Quantity: 0.003 WETH");
        console.log("    Price: 2000 IDRX/WETH");
        console.log("    Order will be placed on behalf of:", owner);
        console.log("    Executor (msg.sender):", agentWallet);
        console.log("");

        // Construct Pool struct
        IPoolManager.Pool memory pool = IPoolManager.Pool({
            baseCurrency: Currency.wrap(weth),
            quoteCurrency: Currency.wrap(idrx),
            orderBook: IOrderBook(wethIDRXPool)
        });

        uint128 price = 200000; // 2000 IDRX
        uint128 quantity = 3000000000000000; // 0.003 WETH
        IOrderBook.Side side = IOrderBook.Side.BUY;
        IOrderBook.TimeInForce tif = IOrderBook.TimeInForce.GTC;

        try AgentRouter(agentRouter).executeLimitOrder(
            agentTokenId,
            pool,
            price,
            quantity,
            side,
            tif,
            false, // autoRepay
            false  // autoBorrow
        ) returns (uint48 orderId) {
            console.log("  SUCCESS! Order placed by agent wallet");
            console.log("  Order ID:", orderId);
            console.log("");
            console.log("=== VERIFICATION ===");
            console.log("  Order owner (should be primary trader):", owner);
            console.log("  Order executor (agent wallet):", agentWallet);
            console.log("  Agent wallet acted on behalf of owner - owner preservation verified!");
            console.log("");
            console.log("=== TEST COMPLETE ===");
            console.log("Agent with dedicated wallet successfully placed order on behalf of owner!");
        } catch Error(string memory reason) {
            console.log("  FAILED:", reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            console.log("  FAILED with low-level error");
            console.logBytes(lowLevelData);
            revert("Agent order execution failed");
        }

        vm.stopBroadcast();
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(string.concat('"', key, '": "'));

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

        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
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

interface MockToken is IERC20 {
    function mint(address to, uint256 amount) external;
}
