// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MockToken} from "@scalex/mocks/MockToken.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract DeployPhase1A is Script {
    struct Phase1ADeployment {
        address QuoteToken;  // Dynamic: USDC, IDRX, etc.
        address WETH;
        address WBTC;
        address GOLD;
        address SILVER;
        address GOOGLE;
        address NVIDIA;
        address MNT;
        address APPLE;
        address deployer;
        uint256 timestamp;
        uint256 blockNumber;
    }

    function run() external returns (Phase1ADeployment memory deployment) {
        console.log("=== PHASE 1A: TOKEN DEPLOYMENT ===");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Step 1: Deploying Mock Tokens...");

        // Quote currency token (dynamic: USDC, IDRX, etc.)
        string memory quoteName = vm.envString("QUOTE_NAME");
        string memory quoteSymbol = vm.envString("QUOTE_SYMBOL");
        uint8 quoteDecimals = uint8(vm.envUint("QUOTE_DECIMALS"));

        MockToken quoteToken = new MockToken(quoteName, quoteSymbol, quoteDecimals);
        console.log(string.concat("[OK] ", quoteSymbol, " deployed:"), address(quoteToken));

        vm.warp(block.timestamp + 5);

        MockToken weth = new MockToken("Wrapped Ether", "WETH", 18);
        console.log("[OK] WETH deployed:", address(weth));

        vm.warp(block.timestamp + 5);

        MockToken wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);
        console.log("[OK] WBTC deployed:", address(wbtc));

        vm.warp(block.timestamp + 5);

        // RWA tokens - Commodities
        MockToken gold = new MockToken("Tokenized Gold", "GOLD", 18);
        console.log("[OK] GOLD deployed:", address(gold));

        vm.warp(block.timestamp + 5);

        MockToken silver = new MockToken("Tokenized Silver", "SILVER", 18);
        console.log("[OK] SILVER deployed:", address(silver));

        vm.warp(block.timestamp + 5);

        // RWA tokens - Stocks
        MockToken google = new MockToken("Tokenized Google Stock", "GOOGL", 18);
        console.log("[OK] GOOGLE deployed:", address(google));

        vm.warp(block.timestamp + 5);

        MockToken nvidia = new MockToken("Tokenized NVIDIA Stock", "NVDA", 18);
        console.log("[OK] NVIDIA deployed:", address(nvidia));

        vm.warp(block.timestamp + 5);

        // MNT token
        MockToken mnt = new MockToken("Mantle Token", "MNT", 18);
        console.log("[OK] MNT deployed:", address(mnt));

        vm.warp(block.timestamp + 5);

        // RWA tokens - Stocks (APPLE)
        MockToken apple = new MockToken("Tokenized Apple Stock", "AAPL", 18);
        console.log("[OK] APPLE deployed:", address(apple));

        // Mint initial tokens to deployer
        console.log("Step 2: Minting initial token balances...");
        uint256 quoteMintAmount = 1_000_000 * (10 ** quoteDecimals); // 1M quote tokens
        quoteToken.mint(deployer, quoteMintAmount);
        console.log(string.concat("Minted ", quoteSymbol, ":"), quoteMintAmount);
        weth.mint(deployer, 1_000 * 1e18); // 1K WETH
        wbtc.mint(deployer, 50 * 1e8); // 50 WBTC
        gold.mint(deployer, 10_000 * 1e18); // 10K oz Gold
        silver.mint(deployer, 100_000 * 1e18); // 100K oz Silver
        google.mint(deployer, 1_000 * 1e18); // 1K GOOGL shares
        nvidia.mint(deployer, 1_000 * 1e18); // 1K NVDA shares
        mnt.mint(deployer, 1_000_000 * 1e18); // 1M MNT
        apple.mint(deployer, 1_000 * 1e18); // 1K AAPL shares

        vm.stopBroadcast();

        deployment = Phase1ADeployment({
            QuoteToken: address(quoteToken),
            WETH: address(weth),
            WBTC: address(wbtc),
            GOLD: address(gold),
            SILVER: address(silver),
            GOOGLE: address(google),
            NVIDIA: address(nvidia),
            MNT: address(mnt),
            APPLE: address(apple),
            deployer: deployer,
            timestamp: block.timestamp,
            blockNumber: block.number
        });

        // Save deployment data — pass struct (2 params) to avoid Yul stack-too-deep
        _saveDeployment(deployment, quoteSymbol);

        console.log("=== PHASE 1A COMPLETED ===");
        console.log("Total tokens deployed: 9 (3 crypto + 6 RWA)");
        return deployment;
    }

    /// @dev Takes the already-built struct (1 memory pointer) to avoid 11-param stack overflow.
    ///      Writes the phase1a JSON file using vm.serializeAddress / vm.serializeUint.
    function _saveDeployment(Phase1ADeployment memory d, string memory quoteSymbol) internal {
        _serializeAddresses(d, quoteSymbol);
        _writeDeploymentFile(d);
    }

    /// @dev Serialize all address fields into the "phase1a" json object.
    function _serializeAddresses(Phase1ADeployment memory d, string memory quoteSymbol) private {
        string memory obj = "phase1a";
        vm.serializeString(obj, "phase", "1a");
        vm.serializeAddress(obj, quoteSymbol, d.QuoteToken);
        vm.serializeAddress(obj, "WETH", d.WETH);
        vm.serializeAddress(obj, "WBTC", d.WBTC);
        vm.serializeAddress(obj, "GOLD", d.GOLD);
        vm.serializeAddress(obj, "SILVER", d.SILVER);
        vm.serializeAddress(obj, "GOOGLE", d.GOOGLE);
        vm.serializeAddress(obj, "NVIDIA", d.NVIDIA);
        vm.serializeAddress(obj, "MNT", d.MNT);
        vm.serializeAddress(obj, "APPLE", d.APPLE);
        vm.serializeAddress(obj, "deployer", d.deployer);
    }

    /// @dev Finalize and write the json file.
    function _writeDeploymentFile(Phase1ADeployment memory d) private {
        string memory obj = "phase1a";
        vm.serializeUint(obj, "timestamp", d.timestamp);
        string memory json = vm.serializeUint(obj, "blockNumber", d.blockNumber);

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/", vm.toString(block.chainid), "-phase1a.json");
        vm.writeFile(path, json);
        console.log("Phase 1A deployment data written to:", path);
    }
}
