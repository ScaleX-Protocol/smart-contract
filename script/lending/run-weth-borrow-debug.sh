#!/bin/bash
set -e

echo "================================================================="
echo "WETH BORROW DEBUG - VERBOSE EXECUTION"
echo "================================================================="
echo ""

# Load environment
source .env

# Configuration
RPC_URL="${SCALEX_CORE_RPC:-https://sepolia.base.org}"
export BORROWER_ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY")
export BORROW_AMOUNT="${1:-87000000000000000000000}"  # Default: 87,000 WETH

echo "Configuration:"
echo "  RPC: ${RPC_URL:0:40}..."
echo "  Borrower: $BORROWER_ADDRESS"
echo "  Borrow Amount: $(python3 -c "print(int($BORROW_AMOUNT) / 1e18)") WETH"
echo ""

# Run with verbose output (-vvvv)
echo "Running debug script with -vvvv (full traces)..."
echo ""

BORROWER_ADDRESS="$BORROWER_ADDRESS" BORROW_AMOUNT="$BORROW_AMOUNT" \
forge script script/lending/DebugWETHBorrow.s.sol:DebugWETHBorrow \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vvvv \
    --gas-limit 2000000 \
    2>&1 | tee /tmp/weth-borrow-debug.log

echo ""
echo "================================================================="
echo "Full debug log saved to: /tmp/weth-borrow-debug.log"
echo "================================================================="
