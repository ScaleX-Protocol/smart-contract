#!/bin/bash

# Reset Order Books - Cancel all existing orders and repopulate with correct prices
# This script is useful after a quote currency migration or price scale fix

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo "🔄 Resetting Order Books"
echo "========================"

# Load environment
if [[ -f .env ]]; then
    source .env
fi

# Set RPC URL
export SCALEX_CORE_RPC="${SCALEX_CORE_RPC:-http://127.0.0.1:8545}"

print_step "Step 1: Canceling all existing orders..."
forge script script/trading/CancelAllOrders.s.sol:CancelAllOrders \
    --rpc-url "${SCALEX_CORE_RPC}" \
    --broadcast \
    --slow

if [[ $? -eq 0 ]]; then
    print_success "Orders canceled successfully"
else
    print_error "Failed to cancel orders"
    exit 1
fi

echo ""
print_step "Step 2: Waiting 5 seconds for cancellations to settle..."
sleep 5

echo ""
print_step "Step 3: Filling order books with correct prices..."
./shellscripts/update-orderbook-prices.sh

if [[ $? -eq 0 ]]; then
    print_success "Order books reset successfully!"
else
    print_error "Failed to fill order books"
    exit 1
fi

echo ""
print_success "🎉 Order Book Reset Complete!"
echo ""
echo "Next steps:"
echo "  1. Wait 5-10 minutes for indexer to sync"
echo "  2. Verify orders on-chain have correct prices"
echo "  3. Test market orders to ensure matching works"
