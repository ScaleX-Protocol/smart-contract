#!/bin/bash

# Borrow IDRX to create utilization and generate supply APY

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
BORROW_AMOUNT_IDRX=${2:-750000}   # Amount in IDRX units
BORROW_AMOUNT=$((BORROW_AMOUNT_IDRX * 100))  # Convert to base units (2 decimals)

echo "=========================================="
echo "Borrow IDRX - Create Utilization"
echo "=========================================="
echo ""
echo "Wallet Index: $WALLET_INDEX"
echo "Borrow Amount: $BORROW_AMOUNT_IDRX IDRX"
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

BORROW_AMOUNT=$BORROW_AMOUNT \
PRIVATE_KEY=$PRIVATE_KEY \
forge script script/lending/BorrowIDRX.s.sol:BorrowIDRX \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vvv

echo ""
echo "=========================================="
echo "Complete!"
echo "=========================================="
echo ""
echo "Check results:"
echo "  curl -s 'https://base-sepolia-indexer.scalex.money/api/lending/dashboard/$USER_ADDRESS?chainId=84532' | jq '.supplies[] | select(.asset == \"IDRX\")'"
