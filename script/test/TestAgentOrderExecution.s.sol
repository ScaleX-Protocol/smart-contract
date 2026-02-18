// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
 * @title TestAgentOrderExecution
 * @notice Tests complete agent order execution flow on basesepolia
 * @dev Updated to use the simplified ERC-8004 auth model:
 *      - User calls AgentRouter.authorize(strategyAgentId, policy) in ONE transaction
 *      - No separate executor delegation needed
 */
contract TestAgentOrderExecution is Script {

    function run() external {
        console.log("=== TESTING AGENT ORDER EXECUTION ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address primaryTrader = vm.addr(deployerPrivateKey);

        console.log("Primary Trader:", primaryTrader);
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

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Ensure primary trader has tokens
        console.log("Step 1: Checking token balances...");
        uint256 idrxBalance = IERC20(idrx).balanceOf(primaryTrader);
        uint256 wethBalance = IERC20(weth).balanceOf(primaryTrader);
        console.log("  IDRX balance:", idrxBalance);
        console.log("  WETH balance:", wethBalance);

        if (idrxBalance < 10000000) {
            console.log("  Minting IDRX...");
            MockToken(idrx).mint(primaryTrader, 10000000);
        }
        if (wethBalance < 10 ether) {
            console.log("  Minting WETH...");
            MockToken(weth).mint(primaryTrader, 10 ether);
        }
        console.log("");

        // Step 2: Deposit to BalanceManager
        console.log("Step 2: Depositing to BalanceManager...");
        uint256 depositAmount = 5000000; // 50,000 IDRX
        IERC20(idrx).approve(balanceManager, depositAmount);
        BalanceManager(balanceManager).depositLocal(idrx, depositAmount, primaryTrader);
        uint256 bmBalance = BalanceManager(balanceManager).getBalance(
            primaryTrader,
            Currency.wrap(idrx)
        );
        console.log("  Balance in BalanceManager:", bmBalance);
        require(bmBalance > 0, "Balance is zero after deposit!");
        console.log("");

        // Step 3: Register agent NFT
        console.log("Step 3: Registering agent identity...");
        uint256 agentTokenId = MockERC8004Identity(identityReg).register();
        console.log("  Agent Token ID:", agentTokenId);
        console.log("");

        // Step 4: Authorize agent with policy (installs policy + grants authorization)
        console.log("Step 4: Authorizing agent with policy...");
        _authorizeAgent(agentRouter, agentTokenId);
        bool isAuthorized = AgentRouter(agentRouter).isAuthorized(primaryTrader, agentTokenId);
        console.log("  Agent authorized:", isAuthorized);
        console.log("");

        // Step 5: Execute limit order
        console.log("Step 5: Executing agent limit order...");
        console.log("  Pool: WETH/IDRX  Side: BUY  Qty: 0.003 WETH  Price: 2000 IDRX");

        IPoolManager.Pool memory pool = IPoolManager.Pool({
            baseCurrency:  Currency.wrap(weth),
            quoteCurrency: Currency.wrap(idrx),
            orderBook:     IOrderBook(wethIDRXPool)
        });

        uint128 price    = 200000; // 2000 IDRX (2 decimals)
        uint128 quantity = 3000000000000000; // 0.003 WETH

        try AgentRouter(agentRouter).executeLimitOrder(
            primaryTrader,
            agentTokenId,
            pool,
            price,
            quantity,
            IOrderBook.Side.BUY,
            IOrderBook.TimeInForce.GTC,
            false,
            false
        ) returns (uint48 orderId) {
            console.log("  SUCCESS! Order ID:", orderId);
        } catch Error(string memory reason) {
            console.log("  FAILED:", reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            console.log("  FAILED with low-level error");
            console.logBytes(lowLevelData);
            revert("Agent order execution failed");
        }

        vm.stopBroadcast();
        console.log("");
        console.log("[SUCCESS] Agent order execution test complete!");
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
