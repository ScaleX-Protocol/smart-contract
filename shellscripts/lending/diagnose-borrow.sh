#!/bin/bash

# Diagnose Borrowing Issue
# Usage: ./script/lending/diagnose-borrow.sh

set -e

echo "🔍 Running Lending Diagnostics..."
echo ""

# Load environment
source .env.base-sepolia

# Run the diagnostic script
forge script script/lending/DiagnoseBorrowIssue.s.sol \
    --rpc-url base-sepolia \
    --sender $DEPLOYER_ADDRESS \
    -vv

echo ""
echo "✅ Diagnostics complete!"
echo ""
echo "📊 Analysis:"
echo "   - If projected HF < 1.0 → Insufficient collateral"
echo "   - If amount > available liquidity → Insufficient liquidity in pool"
echo "   - If both checks pass → Should succeed (check for other issues)"
