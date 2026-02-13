#!/bin/bash
set -e

echo "================================================================="
echo "DEPOSIT WETH & BORROW WETH TO ACHIEVE 2% APY"
echo "================================================================="
echo ""

# Load environment
source .env

# Configuration
RPC_URL="${SCALEX_CORE_RPC:-https://sepolia.base.org}"

# Accept amounts as arguments (in human-readable WETH)
DEPOSIT_WETH="${1:-200000}"  # Default: 200,000 WETH
BORROW_WETH="${2:-87000}"    # Default: 87,000 WETH

# Convert to wei
DEPOSIT_AMOUNT=$(python3 -c "print(int(${DEPOSIT_WETH} * 1e18))")
BORROW_AMOUNT=$(python3 -c "print(int(${BORROW_WETH} * 1e18))")

export DEPOSIT_AMOUNT
export BORROW_AMOUNT

echo "Configuration:"
echo "  RPC: ${RPC_URL:0:40}..."
echo "  Deposit: ${DEPOSIT_WETH} WETH"
echo "  Borrow: ${BORROW_WETH} WETH"
echo ""

echo "Executing script..."
echo ""

forge script script/lending/DepositAndBorrowWETH.s.sol:DepositAndBorrowWETH \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vv

echo ""
echo "================================================================="
echo "COMPLETE!"
echo "================================================================="
