#!/bin/bash
set -e

# Load environment
source .env

# Configuration
RPC_URL="${SCALEX_CORE_RPC:-https://sepolia.base.org}"
BORROW_WETH="${1:-20000}"  # Default: 20,000 WETH

# Convert to wei
BORROW_AMOUNT=$(python3 -c "print(int(${BORROW_WETH} * 1e18))")

export BORROW_AMOUNT

echo "Borrowing ${BORROW_WETH} WETH..."
echo ""

forge script script/lending/BorrowWETH.s.sol:BorrowWETH \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vv

echo ""
echo "COMPLETE!"
