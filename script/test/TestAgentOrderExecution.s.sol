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
 * @title TestAgentOrderExecution
 * @notice Tests complete agent order execution flow on basesepolia
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

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Ensure primary trader has tokens
        console.log("Step 1: Checking token balances...");
        uint256 idrxBalance = IERC20(idrx).balanceOf(primaryTrader);
        uint256 wethBalance = IERC20(weth).balanceOf(primaryTrader);

        console.log("  IDRX balance:", idrxBalance);
        console.log("  WETH balance:", wethBalance);

        if (idrxBalance < 10000000) { // Need at least 100,000 IDRX (assuming 2 decimals)
            console.log("  Minting IDRX...");
            MockToken(idrx).mint(primaryTrader, 10000000); // 100,000 IDRX
            console.log("  IDRX minted");
        }

        if (wethBalance < 10 ether) {
            console.log("  Minting WETH...");
            MockToken(weth).mint(primaryTrader, 10 ether);
            console.log("  WETH minted");
        }
        console.log("");

        // Step 2: Deposit to BalanceManager using depositLocal
        console.log("Step 2: Depositing to BalanceManager...");

        uint256 depositAmount = 5000000; // 50,000 IDRX

        // Approve BalanceManager
        console.log("  Approving BalanceManager for IDRX...");
        IERC20(idrx).approve(balanceManager, depositAmount);

        // Deposit using depositLocal (address token, uint256 amount, address recipient)
        console.log("  Depositing", depositAmount, "IDRX...");
        try BalanceManager(balanceManager).depositLocal(idrx, depositAmount, primaryTrader) {
            console.log("  Deposit successful!");
        } catch Error(string memory reason) {
            console.log("  Deposit failed:", reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            console.log("  Deposit failed with low-level error");
            console.logBytes(lowLevelData);
            revert("Deposit failed");
        }

        // Verify balance using Currency.wrap
        console.log("  Verifying balance in BalanceManager...");
        // Note: getBalance expects Currency type which is just address wrapped
        Currency idrxCurrency = Currency.wrap(idrx);
        uint256 bmBalance = BalanceManager(balanceManager).getBalance(primaryTrader, idrxCurrency);
        console.log("  Balance in BalanceManager:", bmBalance);

        require(bmBalance > 0, "Balance is zero after deposit!");
        console.log("");

        // Step 3: Install/verify agent
        console.log("Step 3: Installing/verifying agent...");
        uint256 agentTokenId = 1;

        bool agentEnabled = PolicyFactory(policyFactory).isAgentEnabled(primaryTrader, agentTokenId);

        // Uninstall existing agent if needed (to update policy)
        if (agentEnabled) {
            console.log("  Agent already enabled, uninstalling to update policy...");
            PolicyFactory(policyFactory).uninstallAgent(agentTokenId);
            agentEnabled = false;
        }

        if (!agentEnabled) {
            console.log("  Installing agent with updated policy...");

            // PolicyCustomization struct: (maxOrderSize, dailyVolumeLimit, expiryTimestamp, whitelistedTokens)
            // Override with higher limits suitable for 18-decimal tokens
            PolicyFactory.PolicyCustomization memory customization = PolicyFactory.PolicyCustomization({
                maxOrderSize: 10 ether, // 10 WETH max (10e18)
                dailyVolumeLimit: 100 ether, // 100 WETH daily limit
                expiryTimestamp: 0,
                whitelistedTokens: new address[](0)
            });

            try PolicyFactory(policyFactory).installAgentFromTemplate(
                agentTokenId,
                "moderate",
                customization
            ) {
                console.log("  Agent installed successfully!");
            } catch Error(string memory reason) {
                console.log("  Failed to install agent:", reason);
                revert(reason);
            } catch {
                console.log("  Failed to install agent (unknown error)");
                revert("Agent installation failed");
            }
        } else {
            console.log("  Agent already enabled");
        }

        PolicyFactory.Policy memory policy = PolicyFactory(policyFactory).getPolicy(primaryTrader, agentTokenId);
        console.log("  Policy installed at:", policy.installedAt);
        console.log("  Max order size:", policy.maxOrderSize);
        console.log("");

        // Step 4: Execute agent order via AgentRouter
        console.log("Step 4: Executing agent limit order...");
        console.log("  Order details:");
        console.log("    Pool: WETH/IDRX");
        console.log("    Side: BUY");
        console.log("    Quantity: 0.003 WETH (3e15 wei)");
        console.log("    Price: 2000 IDRX/WETH");
        console.log("    Owner:", primaryTrader);
        console.log("    Agent Token ID:", agentTokenId);
        console.log("");

        // Construct Pool struct (baseCurrency, quoteCurrency, orderBook)
        IPoolManager.Pool memory pool = IPoolManager.Pool({
            baseCurrency: Currency.wrap(weth),
            quoteCurrency: Currency.wrap(idrx),
            orderBook: IOrderBook(wethIDRXPool)
        });

        // Execute limit order
        // function executeLimitOrder(
        //     uint256 agentTokenId,
        //     IPoolManager.Pool calldata pool,
        //     uint128 price,
        //     uint128 quantity,
        //     IOrderBook.Side side,
        //     IOrderBook.TimeInForce timeInForce,
        //     bool autoRepay,
        //     bool autoBorrow
        // )

        uint128 price = 200000; // 2000 IDRX (2 decimals)
        uint128 quantity = 3000000000000000; // 0.003 WETH (3e15 wei) - should meet minTradeAmount (>= 500)
        IOrderBook.Side side = IOrderBook.Side.BUY;
        IOrderBook.TimeInForce tif = IOrderBook.TimeInForce.GTC;

        console.log("  Calling AgentRouter.executeLimitOrder...");

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
            console.log("  SUCCESS! Order placed via agent");
            console.log("  Order ID:", orderId);
            console.log("");
            console.log("=== AGENT ORDER EXECUTION VERIFIED ===");
            console.log("Agent can successfully place orders on behalf of owner!");
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
