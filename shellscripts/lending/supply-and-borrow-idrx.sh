#!/bin/bash

# Supply IDRX as collateral and borrow IDRX to create utilization
# This creates recursive lending to generate supply APY for IDRX

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load environment
ENV_FILE="$PROJECT_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Parse environment variables
RPC_URL=$(grep "^SCALEX_CORE_RPC=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
SEED_PHRASE=$(grep "^SEED_PHRASE=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")

if [ -z "$RPC_URL" ]; then
    RPC_URL="https://sepolia.base.org"
fi

# Wallet configuration
WALLET_INDEX=${1:-0}  # Default to wallet 0 (Scalex 1)
SUPPLY_AMOUNT=${2:-10000}  # Default: supply 10,000 IDRX
BORROW_AMOUNT=${3:-7500}   # Default: borrow 7,500 IDRX (75% utilization)

echo "=========================================="
echo "IDRX Recursive Lending Setup"
echo "=========================================="
echo ""
echo "Wallet Index: $WALLET_INDEX"
echo "Supply Amount: $SUPPLY_AMOUNT IDRX"
echo "Borrow Amount: $BORROW_AMOUNT IDRX"
echo "Net Contribution: $((SUPPLY_AMOUNT - BORROW_AMOUNT)) IDRX"
echo ""

# Derive wallet address
USER_ADDRESS=$(cast wallet address --mnemonic "$SEED_PHRASE" --mnemonic-index "$WALLET_INDEX")
echo "User Address: $USER_ADDRESS"
echo ""

# Get private key for signing
PRIVATE_KEY=$(cast wallet private-key --mnemonic "$SEED_PHRASE" --mnemonic-index "$WALLET_INDEX")

# Run the script
echo "Running Forge script..."
echo ""

cd "$PROJECT_ROOT"

USER_ADDRESS=$USER_ADDRESS \
IDRX_SUPPLY_AMOUNT=$SUPPLY_AMOUNT \
IDRX_BORROW_AMOUNT=$BORROW_AMOUNT \
forge script script/lending/SupplyAndBorrowIDRX.s.sol:SupplyAndBorrowIDRX \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vvv

echo ""
echo "=========================================="
echo "Complete!"
echo "=========================================="
echo ""
echo "Expected Results:"
echo "  - IDRX pool now has +$((SUPPLY_AMOUNT - BORROW_AMOUNT)) IDRX net liquidity"
echo "  - IDRX utilization increased by $BORROW_AMOUNT IDRX"
echo "  - Supply APY for IDRX will be > 0%"
echo ""
echo "To check results:"
echo "  curl -s 'https://base-sepolia-indexer.scalex.money/api/lending/dashboard/$USER_ADDRESS?chainId=84532' | jq '.supplies[] | select(.asset == \"IDRX\")'"
