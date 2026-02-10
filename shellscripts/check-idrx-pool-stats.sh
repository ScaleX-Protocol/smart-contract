#!/bin/bash

# Check IDRX pool statistics directly from LendingManager contract
# This queries the pool-level data to investigate the liquidity issue

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# Load environment
if [ -f "$ENV_FILE" ]; then
    RPC_URL=$(grep "^SCALEX_CORE_RPC=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    CORE_CHAIN_ID=$(grep "^CORE_CHAIN_ID=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
fi

# Defaults
RPC_URL=${RPC_URL:-"https://sepolia.base.org"}
CORE_CHAIN_ID=${CORE_CHAIN_ID:-"84532"}

# Load addresses from deployments
DEPLOYMENTS_FILE="$SCRIPT_DIR/../deployments/${CORE_CHAIN_ID}.json"
if [ ! -f "$DEPLOYMENTS_FILE" ]; then
    echo "Error: Deployments file not found at $DEPLOYMENTS_FILE"
    exit 1
fi

LENDING_MANAGER=$(cat "$DEPLOYMENTS_FILE" | grep -o '"LendingManager": "[^"]*"' | cut -d'"' -f4)
IDRX=$(cat "$DEPLOYMENTS_FILE" | grep -o '"IDRX": "[^"]*"' | cut -d'"' -f4)

echo "=============================================="
echo "  IDRX Pool Statistics"
echo "=============================================="
echo ""
echo "LendingManager: $LENDING_MANAGER"
echo "IDRX Token:     $IDRX"
echo "RPC URL:        $RPC_URL"
echo ""

# Query pool statistics from LendingManager
echo "Querying LendingManager contract..."
echo ""

# totalLiquidity(address token) returns uint256
TOTAL_LIQUIDITY=$(cast call "$LENDING_MANAGER" "totalLiquidity(address)(uint256)" "$IDRX" --rpc-url "$RPC_URL" 2>/dev/null)
TOTAL_LIQUIDITY_DEC=$(cast --to-dec "$TOTAL_LIQUIDITY" 2>/dev/null | sed 's/ \[.*\]//')

# totalBorrowed(address token) returns uint256
TOTAL_BORROWED=$(cast call "$LENDING_MANAGER" "totalBorrowed(address)(uint256)" "$IDRX" --rpc-url "$RPC_URL" 2>/dev/null)
TOTAL_BORROWED_DEC=$(cast --to-dec "$TOTAL_BORROWED" 2>/dev/null | sed 's/ \[.*\]//')

# totalSupplied(address token) returns uint256
TOTAL_SUPPLIED=$(cast call "$LENDING_MANAGER" "totalSupplied(address)(uint256)" "$IDRX" --rpc-url "$RPC_URL" 2>/dev/null)
TOTAL_SUPPLIED_DEC=$(cast --to-dec "$TOTAL_SUPPLIED" 2>/dev/null | sed 's/ \[.*\]//')

# Convert from smallest units (2 decimals for IDRX)
TOTAL_LIQUIDITY_IDRX=$(python3 -c "print('{:,.2f}'.format(int('$TOTAL_LIQUIDITY_DEC') / 100))")
TOTAL_BORROWED_IDRX=$(python3 -c "print('{:,.2f}'.format(int('$TOTAL_BORROWED_DEC') / 100))")
TOTAL_SUPPLIED_IDRX=$(python3 -c "print('{:,.2f}'.format(int('$TOTAL_SUPPLIED_DEC') / 100))")

# Calculate utilization
if [ "$TOTAL_LIQUIDITY_DEC" != "0" ]; then
    UTILIZATION=$(python3 -c "print('{:.6f}%'.format((int('$TOTAL_BORROWED_DEC') / int('$TOTAL_LIQUIDITY_DEC')) * 100))")
else
    UTILIZATION="N/A (zero liquidity)"
fi

echo "=============================================="
echo "  Pool Statistics (from Smart Contract)"
echo "=============================================="
echo ""
echo "Total Liquidity:  $TOTAL_LIQUIDITY_IDRX IDRX"
echo "  (Raw value: $TOTAL_LIQUIDITY_DEC smallest units)"
echo ""
echo "Total Supplied:   $TOTAL_SUPPLIED_IDRX IDRX"
echo "  (Raw value: $TOTAL_SUPPLIED_DEC smallest units)"
echo ""
echo "Total Borrowed:   $TOTAL_BORROWED_IDRX IDRX"
echo "  (Raw value: $TOTAL_BORROWED_DEC smallest units)"
echo ""
echo "Utilization Rate: $UTILIZATION"
echo ""
echo "=============================================="

# Check if liquidity is suspiciously high
if [ "$TOTAL_LIQUIDITY_DEC" -gt "1000000000000000000000" ]; then
    echo ""
    echo "⚠️  WARNING: Total liquidity is abnormally high!"
    echo ""
    echo "This appears to be a configuration issue:"
    echo "- Liquidity > 1 quintillion IDRX"
    echo "- This makes it impossible to create meaningful utilization"
    echo "- Even billions in borrowing creates ~0% utilization"
    echo ""
    echo "Possible causes:"
    echo "1. MAX_UINT or overflow in totalLiquidity calculation"
    echo "2. Test environment initialized with unlimited liquidity"
    echo "3. Smart contract bug in liquidity tracking"
    echo ""
    echo "Recommendation:"
    echo "- Check LendingManager.sol totalLiquidity() implementation"
    echo "- Verify pool initialization parameters"
    echo "- Consider redeploying with realistic liquidity cap"
fi

echo ""
echo "Done!"
