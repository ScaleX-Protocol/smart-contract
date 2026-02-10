// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {AutoBorrowHelper} from "@scalexcore/AutoBorrowHelper.sol";
import {OrderBook} from "@scalexcore/OrderBook.sol";
import {BalanceManager} from "@scalexcore/BalanceManager.sol";

/**
 * @title DeployPhase4
 * @notice Deploys and configures AutoBorrowHelper for all OrderBooks
 * @dev Executes after Phase 3 when all OrderBooks are created
 */
contract DeployPhase4 is Script {
    struct Phase4Deployment {
        address autoBorrowHelper;
        address deployer;
        uint256 timestamp;
        uint256 blockNumber;
    }

    function run() external returns (Phase4Deployment memory deployment) {
        console.log("=== PHASE 4: AUTO BORROW HELPER DEPLOYMENT ===");
        console.log("");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        console.log("");

        // Load addresses from deployment file
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory deploymentPath = string.concat(root, "/deployments/", chainIdStr, ".json");

        if (!vm.exists(deploymentPath)) {
            revert("Deployment file not found. Run phases 1-3 first.");
        }

        // Load quote currency config from environment
        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");

        string memory json = vm.readFile(deploymentPath);
        address balanceManager = _extractAddress(json, "BalanceManager");

        // Load all pool addresses
        string memory wethPoolKey = string.concat("WETH_", quoteSymbol, "_Pool");
        string memory wbtcPoolKey = string.concat("WBTC_", quoteSymbol, "_Pool");
        string memory goldPoolKey = string.concat("GOLD_", quoteSymbol, "_Pool");
        string memory silverPoolKey = string.concat("SILVER_", quoteSymbol, "_Pool");
        string memory googlePoolKey = string.concat("GOOGLE_", quoteSymbol, "_Pool");
        string memory nvidiaPoolKey = string.concat("NVIDIA_", quoteSymbol, "_Pool");
        string memory mntPoolKey = string.concat("MNT_", quoteSymbol, "_Pool");
        string memory applePoolKey = string.concat("APPLE_", quoteSymbol, "_Pool");

        address wethPool = _extractAddress(json, wethPoolKey);
        address wbtcPool = _extractAddress(json, wbtcPoolKey);
        address goldPool = _extractAddress(json, goldPoolKey);
        address silverPool = _extractAddress(json, silverPoolKey);
        address googlePool = _extractAddress(json, googlePoolKey);
        address nvidiaPool = _extractAddress(json, nvidiaPoolKey);
        address mntPool = _extractAddress(json, mntPoolKey);
        address applePool = _extractAddress(json, applePoolKey);

        console.log("Loaded addresses:");
        console.log("  BalanceManager:", balanceManager);
        console.log("");
        console.log("Pool addresses:");
        console.log(string.concat("  WETH/", quoteSymbol, ":"), wethPool);
        console.log(string.concat("  WBTC/", quoteSymbol, ":"), wbtcPool);
        console.log(string.concat("  GOLD/", quoteSymbol, ":"), goldPool);
        console.log(string.concat("  SILVER/", quoteSymbol, ":"), silverPool);
        console.log(string.concat("  GOOGLE/", quoteSymbol, ":"), googlePool);
        console.log(string.concat("  NVIDIA/", quoteSymbol, ":"), nvidiaPool);
        console.log(string.concat("  MNT/", quoteSymbol, ":"), mntPool);
        console.log(string.concat("  APPLE/", quoteSymbol, ":"), applePool);
        console.log("");

        // Validate addresses
        require(balanceManager != address(0), "BalanceManager address is zero");
        require(wethPool != address(0), "WETH pool address is zero");
        require(wbtcPool != address(0), "WBTC pool address is zero");
        require(goldPool != address(0), "GOLD pool address is zero");
        require(silverPool != address(0), "SILVER pool address is zero");
        require(googlePool != address(0), "GOOGLE pool address is zero");
        require(nvidiaPool != address(0), "NVIDIA pool address is zero");
        require(mntPool != address(0), "MNT pool address is zero");
        require(applePool != address(0), "APPLE pool address is zero");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy AutoBorrowHelper
        console.log("Step 1: Deploying AutoBorrowHelper...");
        AutoBorrowHelper helper = new AutoBorrowHelper();
        console.log("[OK] AutoBorrowHelper deployed:", address(helper));
        console.log("");

        // Step 2: Link to all OrderBooks
        console.log("Step 2: Linking AutoBorrowHelper to OrderBooks...");

        OrderBook(wethPool).setAutoBorrowHelper(address(helper));
        console.log(string.concat("[OK] Linked to WETH/", quoteSymbol, " pool"));

        OrderBook(wbtcPool).setAutoBorrowHelper(address(helper));
        console.log(string.concat("[OK] Linked to WBTC/", quoteSymbol, " pool"));

        OrderBook(goldPool).setAutoBorrowHelper(address(helper));
        console.log(string.concat("[OK] Linked to GOLD/", quoteSymbol, " pool"));

        OrderBook(silverPool).setAutoBorrowHelper(address(helper));
        console.log(string.concat("[OK] Linked to SILVER/", quoteSymbol, " pool"));

        OrderBook(googlePool).setAutoBorrowHelper(address(helper));
        console.log(string.concat("[OK] Linked to GOOGLE/", quoteSymbol, " pool"));

        OrderBook(nvidiaPool).setAutoBorrowHelper(address(helper));
        console.log(string.concat("[OK] Linked to NVIDIA/", quoteSymbol, " pool"));

        OrderBook(mntPool).setAutoBorrowHelper(address(helper));
        console.log(string.concat("[OK] Linked to MNT/", quoteSymbol, " pool"));

        OrderBook(applePool).setAutoBorrowHelper(address(helper));
        console.log(string.concat("[OK] Linked to APPLE/", quoteSymbol, " pool"));
        console.log("");

        // Step 3: Authorize in BalanceManager
        console.log("Step 3: Authorizing AutoBorrowHelper in BalanceManager...");
        BalanceManager(balanceManager).addAuthorizedOperator(address(helper));
        console.log("[OK] AutoBorrowHelper authorized");
        console.log("");

        vm.stopBroadcast();

        // Step 4: Update deployment file
        console.log("Step 4: Updating deployment file...");
        _updateDeploymentFile(deploymentPath, address(helper));
        console.log("[OK] Deployment file updated");
        console.log("");

        console.log("[SUCCESS] Phase 4 completed!");
        console.log("AutoBorrowHelper address:", address(helper));

        // Return deployment info
        deployment = Phase4Deployment({
            autoBorrowHelper: address(helper),
            deployer: deployer,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
    }

    function _extractAddress(string memory json, string memory key) internal pure returns (address) {
        // Find the key in the JSON
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(string.concat('"', key, '": "'));

        uint256 keyPos = _indexOf(jsonBytes, keyBytes);
        if (keyPos == type(uint256).max) {
            return address(0);
        }

        // Extract address (42 characters: 0x + 40 hex digits)
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
        if (needleLength == 0) return 0;

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

        return type(uint256).max; // Not found
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
                digit = uint256(byteValue) - 87; // a-f
            } else if (byteValue >= 65 && byteValue <= 70) {
                digit = uint256(byteValue) - 55; // A-F
            } else {
                continue; // Skip non-hex characters
            }
            result = result * 16 + digit;
        }
        return result;
    }

    function _updateDeploymentFile(string memory deploymentPath, address autoBorrowHelper) internal {
        string memory json = vm.readFile(deploymentPath);

        // Read all existing addresses
        address tokenRegistry = _extractAddress(json, "TokenRegistry");
        address oracle = _extractAddress(json, "Oracle");
        address lendingManager = _extractAddress(json, "LendingManager");
        address balanceManager = _extractAddress(json, "BalanceManager");
        address poolManager = _extractAddress(json, "PoolManager");
        address scaleXRouter = _extractAddress(json, "ScaleXRouter");
        address syntheticTokenFactory = _extractAddress(json, "SyntheticTokenFactory");

        // Load quote currency config
        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        string memory syntheticQuoteSymbol = string.concat("sx", quoteSymbol);

        address quoteToken = _extractAddress(json, quoteSymbol);
        address sxQuote = _extractAddress(json, syntheticQuoteSymbol);

        address weth = _extractAddress(json, "WETH");
        address wbtc = _extractAddress(json, "WBTC");
        address gold = _extractAddress(json, "GOLD");
        address silver = _extractAddress(json, "SILVER");
        address google = _extractAddress(json, "GOOGLE");
        address nvidia = _extractAddress(json, "NVIDIA");
        address mnt = _extractAddress(json, "MNT");
        address apple = _extractAddress(json, "APPLE");
        address sxWETH = _extractAddress(json, "sxWETH");
        address sxWBTC = _extractAddress(json, "sxWBTC");
        address sxGOLD = _extractAddress(json, "sxGOLD");
        address sxSILVER = _extractAddress(json, "sxSILVER");
        address sxGOOGLE = _extractAddress(json, "sxGOOGLE");
        address sxNVIDIA = _extractAddress(json, "sxNVIDIA");
        address sxMNT = _extractAddress(json, "sxMNT");
        address sxAPPLE = _extractAddress(json, "sxAPPLE");

        // Build pool keys
        string memory wethPoolKey = string.concat("WETH_", quoteSymbol, "_Pool");
        string memory wbtcPoolKey = string.concat("WBTC_", quoteSymbol, "_Pool");
        string memory goldPoolKey = string.concat("GOLD_", quoteSymbol, "_Pool");
        string memory silverPoolKey = string.concat("SILVER_", quoteSymbol, "_Pool");
        string memory googlePoolKey = string.concat("GOOGLE_", quoteSymbol, "_Pool");
        string memory nvidiaPoolKey = string.concat("NVIDIA_", quoteSymbol, "_Pool");
        string memory mntPoolKey = string.concat("MNT_", quoteSymbol, "_Pool");
        string memory applePoolKey = string.concat("APPLE_", quoteSymbol, "_Pool");

        address wethPool = _extractAddress(json, wethPoolKey);
        address wbtcPool = _extractAddress(json, wbtcPoolKey);
        address goldPool = _extractAddress(json, goldPoolKey);
        address silverPool = _extractAddress(json, silverPoolKey);
        address googlePool = _extractAddress(json, googlePoolKey);
        address nvidiaPool = _extractAddress(json, nvidiaPoolKey);
        address mntPool = _extractAddress(json, mntPoolKey);
        address applePool = _extractAddress(json, applePoolKey);

        address deployer = _extractAddress(json, "deployer");

        string memory newJson = string.concat(
            "{\n",
            '  "networkName": "localhost",\n',
            '  "TokenRegistry": "', vm.toString(tokenRegistry), '",\n',
            '  "Oracle": "', vm.toString(oracle), '",\n',
            '  "LendingManager": "', vm.toString(lendingManager), '",\n',
            '  "BalanceManager": "', vm.toString(balanceManager), '",\n',
            '  "PoolManager": "', vm.toString(poolManager), '",\n',
            '  "ScaleXRouter": "', vm.toString(scaleXRouter), '",\n',
            '  "SyntheticTokenFactory": "', vm.toString(syntheticTokenFactory), '",\n',
            '  "AutoBorrowHelper": "', vm.toString(autoBorrowHelper), '",\n',
            '  "', quoteSymbol, '": "', vm.toString(quoteToken), '",\n',
            '  "WETH": "', vm.toString(weth), '",\n',
            '  "WBTC": "', vm.toString(wbtc), '",\n',
            '  "GOLD": "', vm.toString(gold), '",\n',
            '  "SILVER": "', vm.toString(silver), '",\n',
            '  "GOOGLE": "', vm.toString(google), '",\n',
            '  "NVIDIA": "', vm.toString(nvidia), '",\n',
            '  "MNT": "', vm.toString(mnt), '",\n',
            '  "APPLE": "', vm.toString(apple), '",\n',
            '  "', syntheticQuoteSymbol, '": "', vm.toString(sxQuote), '",\n',
            '  "sxWETH": "', vm.toString(sxWETH), '",\n',
            '  "sxWBTC": "', vm.toString(sxWBTC), '",\n',
            '  "sxGOLD": "', vm.toString(sxGOLD), '",\n',
            '  "sxSILVER": "', vm.toString(sxSILVER), '",\n',
            '  "sxGOOGLE": "', vm.toString(sxGOOGLE), '",\n',
            '  "sxNVIDIA": "', vm.toString(sxNVIDIA), '",\n',
            '  "sxMNT": "', vm.toString(sxMNT), '",\n',
            '  "sxAPPLE": "', vm.toString(sxAPPLE), '",\n',
            '  "', wethPoolKey, '": "', vm.toString(wethPool), '",\n',
            '  "', wbtcPoolKey, '": "', vm.toString(wbtcPool), '",\n',
            '  "', goldPoolKey, '": "', vm.toString(goldPool), '",\n',
            '  "', silverPoolKey, '": "', vm.toString(silverPool), '",\n',
            '  "', googlePoolKey, '": "', vm.toString(googlePool), '",\n',
            '  "', nvidiaPoolKey, '": "', vm.toString(nvidiaPool), '",\n',
            '  "', mntPoolKey, '": "', vm.toString(mntPool), '",\n',
            '  "', applePoolKey, '": "', vm.toString(applePool), '",\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "timestamp": "', vm.toString(block.timestamp), '",\n',
            '  "blockNumber": "', vm.toString(block.number), '",\n',
            '  "deploymentComplete": true\n',
            "}"
        );

        vm.writeFile(deploymentPath, newJson);
    }
}
