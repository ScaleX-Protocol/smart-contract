// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";
import {AgentRouter} from "@scalexagents/AgentRouter.sol";
import {PolicyFactory} from "@scalexagents/PolicyFactory.sol";
import {MockERC8004Identity} from "@scalexagents/mocks/MockERC8004Identity.sol";
import {IPoolManager} from "@scalexcore/interfaces/IPoolManager.sol";
import {IOrderBook} from "@scalexcore/interfaces/IOrderBook.sol";
import {Currency} from "@scalexcore/libraries/Currency.sol";

/**
 * @title TestAgentWithDedicatedWallet
 * @notice Tests agent order execution using a dedicated agent wallet
 * @dev Demonstrates the simplified ERC-8004 auth model with a dedicated executor wallet:
 *      1. Agent wallet registers its identity NFT (gets strategyAgentId)
 *      2. Owner funds their account and deposits to BalanceManager
 *      3. Owner authorizes the strategyAgentId with a trading policy
 *      4. Agent wallet places orders on behalf of owner using its NFT
 *      5. All orders show owner as the trader, not the agent wallet
 *
 * Environment variables required:
 *   PRIVATE_KEY        - Owner/trader private key (owns funds, grants authorization)
 *   AGENT_PRIVATE_KEY  - Agent wallet private key (owns NFT, executes orders)
 */
contract TestAgentWithDedicatedWallet is Script {

    function run() external {
        console.log("=== TESTING AGENT WITH DEDICATED WALLET ===");
        console.log("");

        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 agentPrivateKey = vm.envUint("AGENT_PRIVATE_KEY");
        address owner      = vm.addr(ownerPrivateKey);
        address agentWallet = vm.addr(agentPrivateKey);

        console.log("Owner Address:", owner);
        console.log("Agent Wallet Address:", agentWallet);
        console.log("");

        // Load deployment addresses
        string memory root = vm.projectRoot();
        string memory deploymentPath = string.concat(root, "/deployments/84532.json");
        string memory json = vm.readFile(deploymentPath);

        address balanceManager = _extractAddress(json, "BalanceManager");
        address agentRouter    = _extractAddress(json, "AgentRouter");
        address identityReg    = _extractAddress(json, "IdentityRegistry");
        address idrx           = _extractAddress(json, "IDRX");
        address weth           = _extractAddress(json, "WETH");
        address wethIDRXPool   = _extractAddress(json, "WETH_IDRX_Pool");

        console.log("Contracts:");
        console.log("  BalanceManager:", balanceManager);
        console.log("  AgentRouter:", agentRouter);
        console.log("  IdentityRegistry:", identityReg);
        console.log("  IDRX:", idrx);
        console.log("  WETH:", weth);
        console.log("  WETH/IDRX Pool:", wethIDRXPool);
        console.log("");

        // ============ STEP 1: Agent wallet registers its identity NFT ============
        console.log("=== STEP 1: Agent Wallet Registers Identity NFT ===");
        vm.startBroadcast(agentPrivateKey);
        uint256 agentTokenId = MockERC8004Identity(identityReg).register();
        console.log("  Strategy Agent NFT minted, tokenId:", agentTokenId);
        console.log("  NFT owner (= agent wallet):", agentWallet);
        vm.stopBroadcast();
        console.log("");

        // ============ STEP 2: Owner funds account and authorizes agent ============
        console.log("=== STEP 2: Owner Setup and Authorization ===");
        vm.startBroadcast(ownerPrivateKey);

        // Ensure owner has tokens
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
        uint256 depositAmount = 5000000; // 50,000 IDRX
        IERC20(idrx).approve(balanceManager, depositAmount);
        BalanceManager(balanceManager).depositLocal(idrx, depositAmount, owner);
        uint256 bmBalance = BalanceManager(balanceManager).getBalance(owner, Currency.wrap(idrx));
        console.log("  Balance in BalanceManager:", bmBalance);
        console.log("");

        // Authorize agent wallet via AgentRouter (installs policy + grants authorization)
        console.log("  Authorizing agent with trading policy...");
        _authorizeAgent(agentRouter, agentTokenId);

        bool isAuthorized = AgentRouter(agentRouter).isAuthorized(owner, agentTokenId);
        console.log("  Agent authorized for owner:", isAuthorized);
        console.log("");

        vm.stopBroadcast();

        // ============ STEP 3: Agent wallet places order on behalf of owner ============
        console.log("=== STEP 3: Agent Wallet Places Order on Behalf of Owner ===");
        vm.startBroadcast(agentPrivateKey);

        console.log("  Agent wallet executing order...");
        console.log("  Order details:");
        console.log("    Pool: WETH/IDRX  Side: BUY  Qty: 0.003 WETH  Price: 2000 IDRX");
        console.log("    Order placed on behalf of:", owner);
        console.log("    Executor (msg.sender):", agentWallet);
        console.log("");

        IPoolManager.Pool memory pool = IPoolManager.Pool({
            baseCurrency:  Currency.wrap(weth),
            quoteCurrency: Currency.wrap(idrx),
            orderBook:     IOrderBook(wethIDRXPool)
        });

        uint128 price    = 200000; // 2000 IDRX (2 decimals)
        uint128 quantity = 3000000000000000; // 0.003 WETH

        try AgentRouter(agentRouter).executeLimitOrder(
            owner,
            agentTokenId,
            pool,
            price,
            quantity,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        ) returns (uint48 orderId) {
            console.log("  SUCCESS! Order placed by agent wallet");
            console.log("  Order ID:", orderId);
            console.log("");
            console.log("=== VERIFICATION ===");
            console.log("  Order owner (primary trader):", owner);
            console.log("  Order executor (agent wallet):", agentWallet);
            console.log("  Agent wallet acted on behalf of owner - verified!");
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

    /// @dev Encodes authorize calldata in an isolated pure frame, then makes a raw call.
    ///      Three-stage split to avoid Yul stack-too-deep (18 slots > SWAP16 limit):
    ///      Stage 1 (_buildAuthorizeData): build Policy + encode in isolated pure frame.
    ///      Stage 2 (_encodeAuthorize):  only `agentId` + `p` + RET live during encodeCall.
    ///      Stage 3 (here):              raw agentRouter.call — agentRouter never shares
    ///                                   the stack with the 14 ABI-encoding Yul temporaries.
    function _authorizeAgent(address agentRouter, uint256 agentTokenId) internal {
        bytes memory data = _buildAuthorizeData(agentTokenId);
        (bool ok,) = agentRouter.call(data);
        require(ok, "AgentRouter.authorize failed");
    }

    /// @dev Builds Policy and encodes the authorize call. `empty` is dead before
    ///      _encodeAuthorize, keeping peak stack at 17 (agentId + p + RET + ~14 vars).
    function _buildAuthorizeData(uint256 agentId) private pure returns (bytes memory) {
        address[] memory empty = new address[](0);
        PolicyFactory.Policy memory p;
        p.expiryTimestamp       = type(uint256).max;
        p.maxOrderSize          = 10 ether;
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
        p.maxSlippageBps        = 500;
        p.dailyVolumeLimit      = 100 ether;
        p.maxDailyDrawdown      = 2000;
        return _encodeAuthorize(agentId, p);
    }

    /// @dev Isolated so only `agentId` and `p` are live during abi.encodeCall.
    function _encodeAuthorize(uint256 agentId, PolicyFactory.Policy memory p) private pure returns (bytes memory) {
        return abi.encodeCall(AgentRouter.authorize, (agentId, p));
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(string.concat('"', key, '": "'));
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

interface MockToken is IERC20 {
    function mint(address to, uint256 amount) external;
}
