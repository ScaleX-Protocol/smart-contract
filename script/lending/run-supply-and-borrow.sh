#!/bin/bash
set -e

echo "================================================================="
echo "SUPPLY COLLATERAL AND BORROW WETH"
echo "================================================================="
echo ""

# Load environment
source .env

# Configuration
RPC_URL="${SCALEX_CORE_RPC:-https://sepolia.base.org}"
export USER_ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY")
export WETH_BORROW_AMOUNT="${1:-87000000000000000000000}"  # Default: 87,000 WETH

echo "Configuration:"
echo "  RPC: ${RPC_URL:0:40}..."
echo "  User: $USER_ADDRESS"
echo "  WETH Borrow Target: $(python3 -c "print(int($WETH_BORROW_AMOUNT) / 1e18)") WETH"
echo ""

echo "Running supply and borrow script..."
echo ""

USER_ADDRESS="$USER_ADDRESS" WETH_BORROW_AMOUNT="$WETH_BORROW_AMOUNT" \
forge script script/lending/SupplyCollateralAndBorrowWETH.s.sol:SupplyCollateralAndBorrowWETH \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --gas-limit 3000000 \
    -vv \
    2>&1 | tee /tmp/supply-and-borrow.log

echo ""
echo "================================================================="
echo "Full log saved to: /tmp/supply-and-borrow.log"
echo "================================================================="
