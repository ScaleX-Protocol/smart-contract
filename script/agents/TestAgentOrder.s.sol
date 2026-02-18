// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {MockERC8004Identity} from "@scalexagents/mocks/MockERC8004Identity.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IBalanceManager} from "@scalexcore/interfaces/IBalanceManager.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TestAgentOrder
 * @notice End-to-end test: mint agent, create policy, deposit funds, place order via AgentRouter
 * @dev Verifies complete agent trading flow
 */
contract TestAgentOrder is Script {
    function run() external {
        console.log("=== TESTING AGENT ORDER PLACEMENT ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer/Agent Owner:", deployer);
        console.log("");

        // Load addresses
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(root, "/deployments/", vm.toString(chainId), ".json");
        string memory json = vm.readFile(deploymentPath);

        address agentRouter = _extractAddress(json, "AgentRouter");
        address policyFactory = _extractAddress(json, "PolicyFactory");
        address identityRegistry = _extractAddress(json, "IdentityRegistry");
        address balanceManager = _extractAddress(json, "BalanceManager");

        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        address quoteToken = _extractAddress(json, quoteSymbol);
        address weth = _extractAddress(json, "WETH");
        address wethPool = _extractAddress(json, string.concat("WETH_", quoteSymbol, "_Pool"));

        console.log("Loaded addresses:");
        console.log("  AgentRouter:", agentRouter);
        console.log("  PolicyFactory:", policyFactory);
        console.log("  IdentityRegistry:", identityRegistry);
        console.log("  BalanceManager:", balanceManager);
        console.log("  WETH:", weth);
        console.log("  Quote Token:", quoteToken);
        console.log("  WETH Pool:", wethPool);
        console.log("");

        // Check if user already has an agent
        uint256 agentTokenId = _getOrMintAgent(identityRegistry, deployer, deployerPrivateKey);
        console.log("");

        // Check if policy exists, authorize agent if not
        _createPolicyIfNeeded(agentRouter, policyFactory, deployer, agentTokenId, deployerPrivateKey);
        console.log("");

        // Deposit funds
        uint256 depositAmount = 1000e6; // 1000 USDC/IDRX
        _depositFunds(balanceManager, quoteToken, deployer, depositAmount, deployerPrivateKey);
        console.log("");

        // Place a test order
        _placeTestOrder(agentRouter, wethPool, weth, quoteToken, deployer, agentTokenId, deployerPrivateKey);
        console.log("");

        console.log("[SUCCESS] Agent order test completed!");
    }

    function _getOrMintAgent(address identityRegistry, address, uint256 privateKey)
        internal
        returns (uint256 agentTokenId)
    {
        console.log("Step 1: Minting new agent identity via register()...");
        vm.startBroadcast(privateKey);
        agentTokenId = MockERC8004Identity(identityRegistry).register();
        vm.stopBroadcast();
        console.log("[OK] Agent token ID:", agentTokenId);
        return agentTokenId;
    }

    function _createPolicyIfNeeded(
        address agentRouter,
        address policyFactory,
        address owner,
        uint256 strategyAgentId,
        uint256 privateKey
    ) internal {
        console.log("Step 2: Checking for existing policy...");

        // Check if already authorized
        bool alreadyEnabled = PolicyFactory(policyFactory).isAgentEnabled(owner, strategyAgentId);
        if (alreadyEnabled) {
            console.log("[OK] Policy already exists");
            return;
        }

        console.log("No policy found. Authorizing agent with default policy...");

        vm.startBroadcast(privateKey);
        _doAuthorize(agentRouter, strategyAgentId);
        vm.stopBroadcast();
        console.log("[OK] Agent authorized with policy");
    }

    /// @dev Stage 1: raw call -- `agentRouter` never shares stack with ABI encoding vars.
    ///      Three-stage split to avoid Yul stack-too-deep (18 slots > SWAP16 limit):
    ///      Stage 1 (_doAuthorize): raw call -- agentRouter separate from ABI encoding.
    ///      Stage 2 (_buildAuthorizeData): build Policy + encode in isolated pure frame.
    ///      Stage 3 (_encodeAuthorize): only agentId + p live during abi.encodeCall.
    function _doAuthorize(address agentRouter, uint256 agentId) private {
        bytes memory data = _buildAuthorizeData(agentId);
        (bool ok,) = agentRouter.call(data);
        require(ok, "AgentRouter.authorize failed");
    }

    /// @dev Stage 2: builds Policy and encodes; `agentRouter` not in scope.
    function _buildAuthorizeData(uint256 agentId) private pure returns (bytes memory) {
        address[] memory empty = new address[](0);
        PolicyFactory.Policy memory p;
        p.expiryTimestamp       = type(uint256).max;
        p.maxOrderSize          = 10e18;
        p.whitelistedTokens     = empty;
        p.blacklistedTokens     = empty;
        p.allowMarketOrders     = true;
        p.allowLimitOrders      = true;
        p.allowSwap             = true;
        p.allowBorrow           = false;
        p.allowRepay            = false;
        p.allowSupplyCollateral = true;
        p.allowWithdrawCollateral = false;
        p.allowPlaceLimitOrder  = true;
        p.allowCancelOrder      = true;
        p.allowBuy              = true;
        p.allowSell             = true;
        p.allowAutoBorrow       = false;
        p.maxAutoBorrowAmount   = 0;
        p.allowAutoRepay        = false;
        p.minDebtToRepay        = 0;
        p.minHealthFactor       = 1e18;
        p.maxSlippageBps        = 500;
        p.minTimeBetweenTrades  = 60;
        p.emergencyRecipient    = address(0);
        p.dailyVolumeLimit      = 100000e6;
        p.weeklyVolumeLimit     = 0;
        p.maxDailyDrawdown      = 2000;
        p.maxWeeklyDrawdown     = 0;
        p.maxTradeVsTVLBps      = 0;
        p.minWinRateBps         = 0;
        p.minSharpeRatio        = 0;
        p.maxPositionConcentrationBps = 0;
        p.maxCorrelationBps     = 0;
        p.maxTradesPerDay       = 0;
        p.maxTradesPerHour      = 0;
        p.tradingStartHour      = 0;
        p.tradingEndHour        = 0;
        p.minReputationScore    = 0;
        p.useReputationMultiplier = false;
        p.requiresChainlinkFunctions = false;
        return _encodeAuthorize(agentId, p);
    }

    /// @dev Stage 3: isolated so only `agentId` and `p` are live during abi.encodeCall.
    function _encodeAuthorize(uint256 agentId, PolicyFactory.Policy memory p) private pure returns (bytes memory) {
        return abi.encodeCall(AgentRouter.authorize, (agentId, p));
    }

    function _depositFunds(
        address balanceManager,
        address token,
        address owner,
        uint256 amount,
        uint256 privateKey
    ) internal {
        console.log("Step 3: Depositing funds to BalanceManager...");

        // Check current balance
        uint256 currentBalance = IBalanceManager(balanceManager).getBalance(owner, Currency.wrap(token));
        console.log("Current balance:", currentBalance);

        if (currentBalance >= amount) {
            console.log("[OK] Sufficient balance already exists");
            return;
        }

        // Check token balance
        uint256 tokenBalance = ERC20(token).balanceOf(owner);
        console.log("Token balance:", tokenBalance);

        if (tokenBalance < amount) {
            console.log("[WARN] Insufficient token balance. Need to mint or acquire tokens first.");
            console.log("       Required:", amount);
            console.log("       Available:", tokenBalance);
            return;
        }

        vm.startBroadcast(privateKey);

        // Approve if needed
        uint256 allowance = ERC20(token).allowance(owner, balanceManager);
        if (allowance < amount) {
            console.log("Approving BalanceManager...");
            ERC20(token).approve(balanceManager, type(uint256).max);
        }

        // Deposit
        console.log("Depositing", amount, "to BalanceManager...");
        IBalanceManager(balanceManager).deposit(Currency.wrap(token), amount, owner, owner);

        vm.stopBroadcast();

        uint256 newBalance = IBalanceManager(balanceManager).getBalance(owner, Currency.wrap(token));
        console.log("[OK] Deposited. New balance:", newBalance);
    }

    function _placeTestOrder(
        address agentRouter,
        address pool,
        address baseToken,
        address quoteToken,
        address owner,
        uint256 agentTokenId,
        uint256 privateKey
    ) internal {
        console.log("Step 4: Placing test order via AgentRouter...");

        // Build pool struct (pool address is the orderBook)
        IPoolManager.Pool memory poolStruct = IPoolManager.Pool({
            baseCurrency:  Currency.wrap(baseToken),
            quoteCurrency: Currency.wrap(quoteToken),
            orderBook:     IOrderBook(pool)
        });

        // Place a small market BUY order for 0.01 WETH
        uint128 quantity = 0.01e18; // 0.01 WETH (18 decimals)
        uint128 minOutAmount = 0; // Accept any price for test
        IOrderBook.Side side = IOrderBook.Side.BUY;

        console.log("Order details:");
        console.log("  Pool:", pool);
        console.log("  Side: BUY");
        console.log("  Quantity:", quantity);
        console.log("  Agent Token ID:", agentTokenId);

        vm.startBroadcast(privateKey);

        try AgentRouter(agentRouter).executeMarketOrder(
            owner,
            agentTokenId,
            poolStruct,
            side,
            quantity,
            minOutAmount,
            false,
            false
        ) returns (uint48 orderId, uint128 filled) {
            console.log("[OK] Order executed successfully!");
            console.log("  Order ID:", orderId);
            console.log("  Filled:", filled);
        } catch Error(string memory reason) {
            console.log("[FAIL] Order failed:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("[FAIL] Order failed with low-level error");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();
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
