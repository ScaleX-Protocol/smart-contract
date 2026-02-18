// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../../src/core/interfaces/ILendingManager.sol";
import "../../src/core/interfaces/IScaleXRouter.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title DiagnoseBorrowIssue
 * @notice Diagnoses why borrowing fails by checking all constraints
 * @dev Usage: forge script script/lending/DiagnoseBorrowIssue.s.sol --rpc-url base-sepolia
 */
contract DiagnoseBorrowIssue is Script {
    IScaleXRouter public router;
    ILendingManager public lendingManager;

    address public IDRX_ADDRESS = 0x80FD9a0F8BCA5255692016D67E0733bf5262C142;
    address public WETH_ADDRESS = 0x8b732595a59c9a18acA0Aca3221A656Eb38158fC;
    address public WBTC_ADDRESS = 0x54911080AB22017e1Ca55F10Ff06AE707428fb0D;

    function setUp() public {
        // Load router address from environment
        address routerAddress = vm.envAddress("SCALEX_ROUTER");
        router = IScaleXRouter(routerAddress);
        lendingManager = ILendingManager(router.lendingManager());

        console.log("================================================================================");
        console.log("LENDING DIAGNOSTICS");
        console.log("================================================================================");
        console.log("Router:", address(router));
        console.log("LendingManager:", address(lendingManager));
        console.log("");
    }

    function run() public view {
        address user = msg.sender;

        // Get user's current state
        console.log("USER ACCOUNT:", user);
        console.log("");

        // Check health factor
        uint256 healthFactor = router.getHealthFactor(user);
        console.log("Current Health Factor:", healthFactor / 1e18, ".", (healthFactor % 1e18) / 1e16);
        console.log("(Health Factor must be >= 1.0 to borrow)");
        console.log("");

        // Check each asset
        _checkAsset("IDRX", IDRX_ADDRESS, user);
        _checkAsset("WETH", WETH_ADDRESS, user);
        _checkAsset("WBTC", WBTC_ADDRESS, user);

        // Check borrowing capacity for IDRX
        console.log("================================================================================");
        console.log("BORROWING CAPACITY FOR IDRX");
        console.log("================================================================================");

        uint256 availableLiquidity = lendingManager.getAvailableLiquidity(IDRX_ADDRESS);
        uint8 decimals = IERC20Metadata(IDRX_ADDRESS).decimals();
        console.log("Available IDRX in Pool:", _formatAmount(availableLiquidity, decimals), "IDRX");
        console.log("");

        // Test different borrow amounts
        uint256[] memory testAmounts = new uint256[](5);
        testAmounts[0] = 10 * (10 ** decimals);    // 10 IDRX
        testAmounts[1] = 30 * (10 ** decimals);    // 30 IDRX
        testAmounts[2] = 50 * (10 ** decimals);    // 50 IDRX
        testAmounts[3] = 100 * (10 ** decimals);   // 100 IDRX
        testAmounts[4] = 200 * (10 ** decimals);   // 200 IDRX

        console.log("Testing different borrow amounts:");
        console.log("");

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];
            console.log("Attempting to borrow:", _formatAmount(amount, decimals), "IDRX");

            // Check projected health factor
            uint256 projectedHF = lendingManager.getProjectedHealthFactor(user, IDRX_ADDRESS, amount);
            console.log("  Projected Health Factor:", projectedHF / 1e18, ".", (projectedHF % 1e18) / 1e16);

            if (projectedHF < 1e18) {
                console.log("  Status: WILL FAIL - Insufficient Collateral");
                console.log("  (Health factor would drop below 1.0)");
            } else if (amount > availableLiquidity) {
                console.log("  Status: WILL FAIL - Insufficient Liquidity");
                console.log("  (Not enough IDRX in pool)");
            } else {
                console.log("  Status: SHOULD SUCCEED");
            }
            console.log("");
        }

        // Calculate maximum borrowable amount
        console.log("================================================================================");
        console.log("MAXIMUM BORROWABLE CALCULATION");
        console.log("================================================================================");
        _calculateMaxBorrowable(user, IDRX_ADDRESS);
    }

    function _checkAsset(string memory symbol, address token, address user) internal view {
        console.log("--", symbol, "--");
        console.log("Address:", token);

        uint256 supply = router.getUserSupply(user, token);
        uint256 debt = router.getUserDebt(user, token);
        uint8 decimals = IERC20Metadata(token).decimals();

        console.log("Supplied:", _formatAmount(supply, decimals), symbol);
        console.log("Borrowed:", _formatAmount(debt, decimals), symbol);
        console.log("");
    }

    function _formatAmount(uint256 amount, uint8 decimals) internal pure returns (string memory) {
        uint256 whole = amount / (10 ** decimals);
        uint256 fraction = amount % (10 ** decimals);

        // Show up to 6 decimal places
        uint256 displayDecimals = decimals > 6 ? 6 : decimals;
        uint256 divisor = 10 ** (decimals - displayDecimals);
        fraction = fraction / divisor;

        return string(abi.encodePacked(
            _uintToString(whole),
            ".",
            _padLeft(_uintToString(fraction), displayDecimals)
        ));
    }

    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _padLeft(string memory str, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= length) {
            return str;
        }

        bytes memory result = new bytes(length);
        uint256 padding = length - strBytes.length;

        for (uint256 i = 0; i < padding; i++) {
            result[i] = "0";
        }
        for (uint256 i = 0; i < strBytes.length; i++) {
            result[padding + i] = strBytes[i];
        }

        return string(result);
    }

    function _calculateMaxBorrowable(address user, address token) internal view {
        // This is a simplified calculation
        // Real max = (totalCollateral * minLT - totalDebt) / tokenPrice

        uint256 currentHF = router.getHealthFactor(user);
        console.log("Current Health Factor:", currentHF / 1e18, ".", (currentHF % 1e18) / 1e16);

        // If HF is already < 1.0, can't borrow anything
        if (currentHF < 1e18) {
            console.log("Cannot borrow - health factor already below 1.0");
            return;
        }

        console.log("");
        console.log("To calculate exact max borrowable:");
        console.log("1. Check your total collateral value across all assets");
        console.log("2. Find the minimum liquidation threshold among your collateral");
        console.log("3. Calculate: (collateral * min_LT - current_debt) = remaining borrowing power");
        console.log("4. Convert to token amount using current price");
        console.log("");
        console.log("The projected health factor for each amount above shows if it's safe.");
    }
}
