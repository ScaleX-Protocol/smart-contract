// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title UnifiedLiquidityMessages
 * @dev Message types and encode/decode helpers for the Arc <-> Mantle unified
 *      liquidity bridge.  Extends the existing HyperlaneMessages type-space
 *      without touching that library (which is used by live ChainBalanceManager
 *      deployments).
 *
 * Message-type constants
 * ----------------------
 *   1  DEPOSIT_MESSAGE         (HyperlaneMessages -- existing)
 *   2  WITHDRAW_MESSAGE        (HyperlaneMessages -- existing)
 *   3  LIQUIDITY_DEPOSIT       Arc -> Mantle: "I locked X USDC; mirror it on your side."
 *   4  LIQUIDITY_WITHDRAW      Mantle -> Arc: "Release X USDC to this address on Arc."
 *
 * All amounts are in USDC native decimals (6).
 */
library UnifiedLiquidityMessages {
    // ----------------------------------------------------------
    // Type constants
    // ----------------------------------------------------------
    uint8 internal constant LIQUIDITY_DEPOSIT = 3;
    uint8 internal constant LIQUIDITY_WITHDRAW = 4;

    // ----------------------------------------------------------
    // Structs
    // ----------------------------------------------------------

    /**
     * @dev Sent from Arc (UnifiedLiquidityBridge) to Mantle (MantleSideChainManager).
     *      Tells Mantle to credit `recipient` with `amount` mirrored USDC.
     */
    struct LiquidityDepositMessage {
        uint8 messageType;      // LIQUIDITY_DEPOSIT = 3
        address recipient;      // user address to credit on Mantle
        uint256 amount;         // USDC amount (6 decimals)
        uint32 sourceChainId;   // Arc domain (5042002)
        uint256 nonce;          // sender's monotonic nonce (replay guard)
    }

    /**
     * @dev Sent from Mantle (MantleSideChainManager) to Arc (UnifiedLiquidityBridge).
     *      Tells Arc to release `amount` USDC to `recipient`.
     */
    struct LiquidityWithdrawMessage {
        uint8 messageType;      // LIQUIDITY_WITHDRAW = 4
        address recipient;      // address that will receive USDC on Arc
        uint256 amount;         // USDC amount (6 decimals)
        uint32 sourceChainId;   // Mantle domain (5003)
        uint256 nonce;          // sender's monotonic nonce (replay guard)
    }

    // ----------------------------------------------------------
    // Encoding helpers
    // ----------------------------------------------------------

    function encodeLiquidityDeposit(
        address recipient,
        uint256 amount,
        uint32 sourceChainId,
        uint256 nonce
    ) internal pure returns (bytes memory) {
        return abi.encode(
            LiquidityDepositMessage({
                messageType: LIQUIDITY_DEPOSIT,
                recipient: recipient,
                amount: amount,
                sourceChainId: sourceChainId,
                nonce: nonce
            })
        );
    }

    function encodeLiquidityWithdraw(
        address recipient,
        uint256 amount,
        uint32 sourceChainId,
        uint256 nonce
    ) internal pure returns (bytes memory) {
        return abi.encode(
            LiquidityWithdrawMessage({
                messageType: LIQUIDITY_WITHDRAW,
                recipient: recipient,
                amount: amount,
                sourceChainId: sourceChainId,
                nonce: nonce
            })
        );
    }

    // ----------------------------------------------------------
    // Decoding helpers
    // ----------------------------------------------------------

    /**
     * @dev Extract just the message type byte from a raw message body.
     *      Works for both legacy HyperlaneMessages types and the new ones
     *      because abi.encode always places the first struct field at offset 0
     *      when the struct starts with a uint8 (padded to 32 bytes).
     */
    function decodeMessageType(bytes calldata messageBody) internal pure returns (uint8) {
        return abi.decode(messageBody, (uint8));
    }

    function decodeLiquidityDeposit(bytes calldata messageBody)
        internal pure returns (LiquidityDepositMessage memory)
    {
        return abi.decode(messageBody, (LiquidityDepositMessage));
    }

    function decodeLiquidityWithdraw(bytes calldata messageBody)
        internal pure returns (LiquidityWithdrawMessage memory)
    {
        return abi.decode(messageBody, (LiquidityWithdrawMessage));
    }

    // ----------------------------------------------------------
    // Replay-protection helper (mirrors HyperlaneMessages.generateMessageId)
    // ----------------------------------------------------------

    function generateMessageId(
        uint32 origin,
        bytes32 sender,
        bytes calldata messageBody
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(origin, sender, messageBody));
    }
}
