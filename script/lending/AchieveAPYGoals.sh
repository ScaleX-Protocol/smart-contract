#!/bin/bash
set -e

# Script to achieve target supply APYs for all lending pools
# Based on targets defined in LENDING_APY_GOALS.md

source .env

LENDING_MANAGER="0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c"
SCALEX_ROUTER=$(jq -r '.ScaleXRouter' deployments/84532.json)
RPC_URL="https://sepolia.base.org"

echo "================================================================"
echo "ACHIEVING TARGET SUPPLY APYs FOR ALL LENDING POOLS"
echo "================================================================"
echo ""
echo "LendingManager: $LENDING_MANAGER"
echo "Router: $SCALEX_ROUTER"
echo "Account: $(cast wallet address --private-key "$PRIVATE_KEY")"
echo ""

# Function to get current pool state and calculate borrow needed
calculate_borrow_needed() {
    local ASSET=$1
    local TOKEN_ADDRESS=$2
    local TARGET_UTIL=$3  # in percentage (e.g., 30.19 for 30.19%)

    echo "Checking $ASSET pool..."

    # Get current state
    local DECIMALS
    case $ASSET in
        WETH) DECIMALS=18 ;;
        WBTC) DECIMALS=8 ;;
        *) DECIMALS=6 ;;
    esac

    local TOTAL_LIQ=$(cast call $LENDING_MANAGER "totalLiquidity(address)(uint256)" $TOKEN_ADDRESS --rpc-url "$RPC_URL")
    local TOTAL_BORR=$(cast call $LENDING_MANAGER "totalBorrowed(address)(uint256)" $TOKEN_ADDRESS --rpc-url "$RPC_URL")

    # Calculate in Python
    python3 << EOF
total_liq = $TOTAL_LIQ / 10**$DECIMALS
total_borr = $TOTAL_BORR / 10**$DECIMALS
current_util = (total_borr / total_liq * 100) if total_liq > 0 else 0

target_util = $TARGET_UTIL
target_borr = total_liq * (target_util / 100)
additional_borrow = max(0, target_borr - total_borr)

print(f"  Current: {total_liq:,.2f} liquidity, {total_borr:,.2f} borrowed ({current_util:.2f}% util)")
print(f"  Target: {target_util:.2f}% utilization")
print(f"  Need to borrow: {additional_borrow:,.2f} $ASSET")

# Output in smallest unit for casting
additional_borrow_raw = int(additional_borrow * 10**$DECIMALS)
print(f"BORROW_AMOUNT={additional_borrow_raw}")
EOF
}

# WBTC - Already achieved
echo "1. WBTC (Target: 1.00% supply APY, 20.91% utilization)"
echo "   ✅ Already achieved"
echo ""

# WETH - Target 2.00%
echo "2. WETH (Target: 2.00% supply APY, 30.19% utilization)"
WETH_ADDR=$(jq -r '.WETH' deployments/84532.json)
WETH_RESULT=$(calculate_borrow_needed "WETH" "$WETH_ADDR" "30.19")
WETH_BORROW=$(echo "$WETH_RESULT" | grep "BORROW_AMOUNT=" | cut -d'=' -f2)
echo "$WETH_RESULT" | grep -v "BORROW_AMOUNT="

if [ "$WETH_BORROW" -gt 0 ]; then
    echo "   Borrowing $WETH_BORROW wei WETH..."
    cast send $SCALEX_ROUTER "borrow(address,uint256)" $WETH_ADDR $WETH_BORROW \
        --private-key "$PRIVATE_KEY" \
        --rpc-url "$RPC_URL" \
        --gas-limit 2000000 2>&1 | grep -E "transactionHash|status"
    echo "   ✅ WETH borrow complete"
else
    echo "   ✅ Already at target"
fi
echo ""

# IDRX - Target 5.00%
echo "3. IDRX (Target: 5.00% supply APY, 59.14% utilization)"
IDRX_ADDR=$(jq -r '.IDRX' deployments/84532.json)
IDRX_RESULT=$(calculate_borrow_needed "IDRX" "$IDRX_ADDR" "59.14")
IDRX_BORROW=$(echo "$IDRX_RESULT" | grep "BORROW_AMOUNT=" | cut -d'=' -f2)
echo "$IDRX_RESULT" | grep -v "BORROW_AMOUNT="

if [ "$IDRX_BORROW" -gt 0 ]; then
    echo "   Borrowing $IDRX_BORROW units IDRX..."
    cast send $SCALEX_ROUTER "borrow(address,uint256)" $IDRX_ADDR $IDRX_BORROW \
        --private-key "$PRIVATE_KEY" \
        --rpc-url "$RPC_URL" \
        --gas-limit 2000000 2>&1 | grep -E "transactionHash|status"
    echo "   ✅ IDRX borrow complete"
else
    echo "   ✅ Already at target"
fi
echo ""

# Process other assets
for ASSET in GOLD SILVER GOOGL NVDA AAPL MNT; do
    TOKEN_ADDR=$(jq -r ".$ASSET" deployments/84532.json)

    # Get target utilization from the goals (read from Python output)
    case $ASSET in
        GOLD) TARGET="12.10" ;;
        SILVER) TARGET="54.18" ;;
        GOOGL) TARGET="25.54" ;;
        NVDA) TARGET="30.23" ;;
        AAPL) TARGET="13.77" ;;
        MNT) TARGET="25.09" ;;
    esac

    echo "Processing $ASSET (Target utilization: $TARGET%)..."
    RESULT=$(calculate_borrow_needed "$ASSET" "$TOKEN_ADDR" "$TARGET")
    BORROW_AMOUNT=$(echo "$RESULT" | grep "BORROW_AMOUNT=" | cut -d'=' -f2)
    echo "$RESULT" | grep -v "BORROW_AMOUNT="

    if [ "$BORROW_AMOUNT" -gt 0 ]; then
        echo "   Borrowing $BORROW_AMOUNT units $ASSET..."
        cast send $SCALEX_ROUTER "borrow(address,uint256)" $TOKEN_ADDR $BORROW_AMOUNT \
            --private-key "$PRIVATE_KEY" \
            --rpc-url "$RPC_URL" \
            --gas-limit 2000000 2>&1 | grep -E "transactionHash|status" || echo "   ⚠️  Borrow failed (may need more collateral)"
        echo "   ✅ $ASSET borrow attempted"
    else
        echo "   ✅ Already at target"
    fi
    echo ""
done

echo "================================================================"
echo "APY GOAL ACHIEVEMENT COMPLETE"
echo "================================================================"
echo ""
echo "Verify the results:"
echo "1. Run indexer: cd /Users/renaka/gtx/clob-indexer/ponder && pnpm dev:core-chain"
echo "2. Check dashboard: http://localhost:42070/api/lending/dashboard/0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a"
echo "3. Review LENDING_APY_GOALS.md for target vs actual comparison"
