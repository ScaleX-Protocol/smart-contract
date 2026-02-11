// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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

        // Save deployment data
        _saveDeployment(
            address(quoteToken),
            quoteSymbol,
            address(weth),
            address(wbtc),
            address(gold),
            address(silver),
            address(google),
            address(nvidia),
            address(mnt),
            address(apple),
            deployer
        );

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

        console.log("=== PHASE 1A COMPLETED ===");
        console.log("Total tokens deployed: 9 (3 crypto + 6 RWA)");
        return deployment;
    }
    
    function _saveDeployment(
        address quoteToken,
        string memory quoteSymbol,
        address weth,
        address wbtc,
        address gold,
        address silver,
        address google,
        address nvidia,
        address mnt,
        address apple,
        address deployer
    ) internal {
        string memory root = vm.projectRoot();
        uint256 chainId = block.chainid;
        string memory chainIdStr = vm.toString(chainId);
        string memory path = string.concat(root, "/deployments/", chainIdStr, "-phase1a.json");

        string memory json = string.concat(
            "{\n",
            "  \"phase\": \"1a\",\n",
            "  \"", quoteSymbol, "\": \"", vm.toString(quoteToken), "\",\n",
            "  \"WETH\": \"", vm.toString(weth), "\",\n",
            "  \"WBTC\": \"", vm.toString(wbtc), "\",\n",
            "  \"GOLD\": \"", vm.toString(gold), "\",\n",
            "  \"SILVER\": \"", vm.toString(silver), "\",\n",
            "  \"GOOGLE\": \"", vm.toString(google), "\",\n",
            "  \"NVIDIA\": \"", vm.toString(nvidia), "\",\n",
            "  \"MNT\": \"", vm.toString(mnt), "\",\n",
            "  \"APPLE\": \"", vm.toString(apple), "\",\n",
            "  \"deployer\": \"", vm.toString(deployer), "\",\n",
            "  \"timestamp\": \"", vm.toString(block.timestamp), "\",\n",
            "  \"blockNumber\": \"", vm.toString(block.number), "\"\n",
            "}"
        );

        vm.writeFile(path, json);
        console.log("Phase 1A deployment data written to:", path);
    }
}