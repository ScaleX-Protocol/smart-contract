// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IPricePrediction} from "../interfaces/IPricePrediction.sol";
import {Currency} from "../libraries/Currency.sol";

abstract contract PricePredictionStorage {
    // keccak256(abi.encode(uint256(keccak256("scalex.clob.storage.priceprediction")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x46c0956a2e6e9186531a98b6c0b8c5df3fae5bff9ad91b78b25614f011e35400;

    /// @custom:storage-location erc7201:scalex.clob.storage.priceprediction
    struct Storage {
        // Core contract references
        address balanceManager;
        address oracle;
        address keystoneForwarder; // Chainlink CRE forwarder address

        // Settlement token (sxUSDC only at launch)
        Currency collateralCurrency;

        // Fee and limits
        uint256 protocolFeeBps; // Protocol fee in basis points (e.g., 200 = 2%)
        uint256 minStakeAmount; // Minimum stake per position (e.g., 10e6 for 10 USDC)
        uint256 maxMarketTvl;   // Max total stake per market (0 = no cap)

        // Markets
        uint64 nextMarketId;
        mapping(uint64 => IPricePrediction.Market) markets;

        // User positions: marketId => user => Position
        mapping(uint64 => mapping(address => IPricePrediction.Position)) positions;

        // Protocol fee accumulator (held in this contract's BalanceManager balance)
        uint256 accumulatedFees;
    }

    function getStorage() internal pure returns (Storage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}
