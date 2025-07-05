//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MockToken} from "../src/mocks/MockToken.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockWETH} from "../src/mocks/MockWETH.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";

contract MintTokens is DeployHelpers {
    error InvalidRecipient();
    error TokenNotDeployed(string tokenName);
    error TokenAddressNotFound(string tokenName);

    string private constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string private constant USDC_ADDRESS = "MOCK_TOKEN_USDC";
    string private constant WBTC_ADDRESS = "MOCK_TOKEN_WBTC";

    MockUSDC private mockUSDC;
    MockWETH private mockWETH;
    MockToken private mockWBTC;

    uint256 private constant WETH_MINT_AMOUNT = 1000 * 1e18;
    uint256 private constant USDC_MINT_AMOUNT = 100000 * 1e6;
    uint256 private constant WBTC_MINT_AMOUNT = 10 * 1e8;

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();

        loadDeployments();

        if (!deployed[WETH_ADDRESS].isSet) {
            revert TokenNotDeployed("WETH");
        }
        if (!deployed[USDC_ADDRESS].isSet) {
            revert TokenNotDeployed("USDC");
        }
        if (!deployed[WBTC_ADDRESS].isSet) {
            revert TokenNotDeployed("WBTC");
        }

        loadMockTokens();

        vm.startBroadcast(deployerPrivateKey);

        mintTokens();

        vm.stopBroadcast();
    }

    function loadMockTokens() private {
        address wethAddr = deployed[WETH_ADDRESS].addr;
        address usdcAddr = deployed[USDC_ADDRESS].addr;
        address wbtcAddr = deployed[WBTC_ADDRESS].addr;

        if (wethAddr == address(0)) {
            revert TokenAddressNotFound("WETH");
        }
        if (usdcAddr == address(0)) {
            revert TokenAddressNotFound("USDC");
        }
        if (wbtcAddr == address(0)) {
            revert TokenAddressNotFound("WBTC");
        }

        mockWETH = MockWETH(wethAddr);
        mockUSDC = MockUSDC(usdcAddr);
        mockWBTC = MockToken(wbtcAddr);
    }

    function mintTokens() private {
        address recipient = vm.envAddress("RECIPIENT_ADDRESS");
        
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        mockWETH.mint(recipient, WETH_MINT_AMOUNT);
        mockUSDC.mint(recipient, USDC_MINT_AMOUNT);
        mockWBTC.mint(recipient, WBTC_MINT_AMOUNT);
    }
}