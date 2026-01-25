#!/bin/bash

# SCALEX RWA Order Book Price Update Script
# Updates RWA order books with current market prices

# ========================================
# ENVIRONMENT VARIABLES
# ========================================
# Before running this script, you may need to set these environment variables:
#
# REQUIRED:
# - PRIVATE_KEY: Private key for deployment account (reads from .env file by default)
#
# OPTIONAL (with January 2026 defaults):
# - SCALEX_CORE_RPC: RPC URL for core chain (default: http://127.0.0.1:8545)
# - CORE_CHAIN_ID: Chain ID for deployment (default: auto-detected from RPC)
# - GOLD_PRICE: Gold price in USDC with 6 decimals (default: 4450000000 = $4,450)
# - SILVER_PRICE: Silver price in USDC with 6 decimals (default: 78000000 = $78)
# - GOOGL_PRICE: Google stock price (default: 314000000 = $314)
# - NVDA_PRICE: Nvidia stock price (default: 188000000 = $188)
# - AAPL_PRICE: Apple stock price (default: 265000000 = $265)
# - MNT_PRICE: MNT token price (default: 1000000 = $1)
# - WBTC_PRICE: Bitcoin price (default: 95000000000 = $95,000)
# - CANCEL_OLD_ORDERS: Whether to cancel existing orders (default: true)
# - VERIFY_PRICES: Whether to verify on-chain (default: true)
# - FORGE_SLOW_MODE: Enable slow mode for forge broadcasts (default: true)
# - FORGE_TIMEOUT: Timeout for forge operations (default: 1200 seconds)
#
# USAGE EXAMPLES:
# # Basic usage with defaults (January 2026 prices):
# bash shellscripts/update-rwa-prices.sh
#
# # Update with custom prices:
# GOLD_PRICE=4500000000 SILVER_PRICE=80000000 bash shellscripts/update-rwa-prices.sh
#
# # Update specific network:
# SCALEX_CORE_RPC="https://base-sepolia.g.alchemy.com/v2/YOUR_KEY" bash shellscripts/update-rwa-prices.sh
#
# # Skip cancellation (only add new orders):
# CANCEL_OLD_ORDERS=false bash shellscripts/update-rwa-prices.sh
#
# # Skip verification (faster execution):
# VERIFY_PRICES=false bash shellscripts/update-rwa-prices.sh
#
# # Update all RWA prices for production:
# GOLD_PRICE=4500000000 SILVER_PRICE=80000000 GOOGL_PRICE=320000000 \
# NVDA_PRICE=190000000 AAPL_PRICE=270000000 MNT_PRICE=1000000 \
# bash shellscripts/update-rwa-prices.sh
# ========================================

# set -e  # Disabled for better error handling

# Set timeout for long-running operations (20 minutes)
export FORGE_TIMEOUT="${FORGE_TIMEOUT:-1200}"

# Set slow mode for forge script broadcasts (prevents RPC rate limiting)
export FORGE_SLOW_MODE="${FORGE_SLOW_MODE:-true}"

# Build slow flag for forge commands
if [[ "$FORGE_SLOW_MODE" == "true" ]]; then
    SLOW_FLAG="--slow"
    echo "📡 Slow mode enabled (adds delays between transactions to prevent RPC rate limiting)"
else
    SLOW_FLAG=""
    echo "⚡ Slow mode disabled (may cause RPC rate limiting on public RPCs)"
fi

echo "🚀 Starting RWA Order Book Price Update..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track statistics
TOTAL_ORDERS_CANCELLED=0
TOTAL_ORDERS_PLACED=0
POOLS_SUCCEEDED=0
POOLS_FAILED=0
FAILED_POOLS=()

# Function to load .env file
load_env_file() {
    local env_file="${1:-.env}"

    if [[ -f "$env_file" ]]; then
        echo "📝 Loading environment variables from $env_file..."
        # Read each line, skip comments and empty lines
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ $line =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue

            # Export valid KEY=VALUE pairs
            if [[ $line =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                export "$line"
            fi
        done < "$env_file"
        echo "✅ Environment variables loaded from $env_file"
    else
        echo "⚠️  $env_file file not found - using defaults"
    fi
}

# Function to print colored output
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

# Function to format price from wei to USD
format_price() {
    local price_wei=$1
    local decimals=${2:-6}  # Default to 6 decimals (USDC)

    if command -v bc >/dev/null 2>&1; then
        echo "scale=2; $price_wei / 10^$decimals" | bc
    else
        # Fallback to awk if bc not available
        echo "$price_wei" | awk -v dec=$decimals '{printf "%.2f", $1/(10^dec)}'
    fi
}

# Function to get best price for a pool
get_best_price() {
    local orderbook=$1
    local side=$2  # 0=BUY, 1=SELL

    local result=$(cast call "$orderbook" "getBestPrice(uint8)(uint128,uint256)" "$side" \
        --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | head -1)

    if [[ -n "$result" ]] && [[ "$result" != "0" ]]; then
        echo "$result"
    else
        echo "0"
    fi
}

# Load environment variables from .env file
load_env_file

# Check if we're in the right directory
if [[ ! -f "Makefile" ]] || [[ ! -d "script" ]]; then
    print_error "Please run this script from the clob-dex project root directory"
    exit 1
fi

# Set RPC URL if not already set
export SCALEX_CORE_RPC="${SCALEX_CORE_RPC:-http://127.0.0.1:8545}"

# Try to detect chain ID from RPC if not set
if [[ -z "$CORE_CHAIN_ID" ]]; then
    print_step "Detecting chain ID from RPC..."
    CORE_CHAIN_ID=$(cast chain-id --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "31337")
    export CORE_CHAIN_ID
    print_success "Detected chain ID: $CORE_CHAIN_ID"
fi

# Read deployment addresses from ${CORE_CHAIN_ID}.json
DEPLOYMENT_FILE="deployments/${CORE_CHAIN_ID}.json"
print_step "Reading deployment addresses from ${DEPLOYMENT_FILE}..."
if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
    print_error "${DEPLOYMENT_FILE} file not found! Please run deploy.sh first."
    exit 1
fi
print_success "Deployment file found"

# Set default prices (January 2026 market prices)
export GOLD_PRICE="${GOLD_PRICE:-4450000000}"      # $4,450
export SILVER_PRICE="${SILVER_PRICE:-78000000}"     # $78
export GOOGL_PRICE="${GOOGL_PRICE:-314000000}"      # $314
export NVDA_PRICE="${NVDA_PRICE:-188000000}"        # $188
export AAPL_PRICE="${AAPL_PRICE:-265000000}"        # $265
export MNT_PRICE="${MNT_PRICE:-1000000}"            # $1
export WBTC_PRICE="${WBTC_PRICE:-95000000000}"      # $95,000

# Set boolean flags
CANCEL_OLD_ORDERS="${CANCEL_OLD_ORDERS:-true}"
VERIFY_PRICES="${VERIFY_PRICES:-true}"

# Print configuration
echo ""
print_step "Configuration:"
echo "  Network: Chain ID $CORE_CHAIN_ID"
echo "  RPC: ${SCALEX_CORE_RPC}"
echo "  Deployment: ${DEPLOYMENT_FILE}"
echo "  Cancel Old Orders: ${CANCEL_OLD_ORDERS}"
echo "  Verify Prices: ${VERIFY_PRICES}"

echo ""
print_step "Price Configuration (January 2026):"
echo "  GOLD:   \$$(format_price $GOLD_PRICE)"
echo "  SILVER: \$$(format_price $SILVER_PRICE)"
echo "  GOOGLE: \$$(format_price $GOOGL_PRICE)"
echo "  NVIDIA: \$$(format_price $NVDA_PRICE)"
echo "  APPLE:  \$$(format_price $AAPL_PRICE)"
echo "  MNT:    \$$(format_price $MNT_PRICE)"
echo "  WBTC:   \$$(format_price $WBTC_PRICE)"

# Create timestamp for report
TIMESTAMP=$(date +%s)
REPORT_FILE="/tmp/rwa_price_update_${TIMESTAMP}.md"

# ========================================
# Phase 1: Cancel Old Orders (Optional)
# ========================================
if [[ "$CANCEL_OLD_ORDERS" == "true" ]]; then
    echo ""
    print_step "Phase 1: Cancelling old orders..."

    if forge script script/trading/CancelOldOrders.s.sol:CancelOldOrders \
        --rpc-url "${SCALEX_CORE_RPC}" \
        --broadcast \
        $SLOW_FLAG 2>&1 | tee /tmp/cancel_orders_output.log; then

        # Count cancelled orders from output
        GOLD_CANCELLED=$(grep -A 1 "=== Canceling Orders: sxGOLD" /tmp/cancel_orders_output.log | grep "Cancelled.*orders" | grep -oE "[0-9]+" | head -1)
        SILVER_CANCELLED=$(grep -A 1 "=== Canceling Orders: sxSILVER" /tmp/cancel_orders_output.log | grep "Cancelled.*orders" | grep -oE "[0-9]+" | head -1)
        GOOGLE_CANCELLED=$(grep -A 1 "=== Canceling Orders: sxGOOGLE" /tmp/cancel_orders_output.log | grep "Cancelled.*orders" | grep -oE "[0-9]+" | head -1)
        NVIDIA_CANCELLED=$(grep -A 1 "=== Canceling Orders: sxNVIDIA" /tmp/cancel_orders_output.log | grep "Cancelled.*orders" | grep -oE "[0-9]+" | head -1)
        MNT_CANCELLED=$(grep -A 1 "=== Canceling Orders: sxMNT" /tmp/cancel_orders_output.log | grep "Cancelled.*orders" | grep -oE "[0-9]+" | head -1)
        APPLE_CANCELLED=$(grep -A 1 "=== Canceling Orders: sxAPPLE" /tmp/cancel_orders_output.log | grep "Cancelled.*orders" | grep -oE "[0-9]+" | head -1)

        # Set default to 0 if not found
        GOLD_CANCELLED=${GOLD_CANCELLED:-0}
        SILVER_CANCELLED=${SILVER_CANCELLED:-0}
        GOOGLE_CANCELLED=${GOOGLE_CANCELLED:-0}
        NVIDIA_CANCELLED=${NVIDIA_CANCELLED:-0}
        MNT_CANCELLED=${MNT_CANCELLED:-0}
        APPLE_CANCELLED=${APPLE_CANCELLED:-0}

        TOTAL_ORDERS_CANCELLED=$((GOLD_CANCELLED + SILVER_CANCELLED + GOOGLE_CANCELLED + NVIDIA_CANCELLED + MNT_CANCELLED + APPLE_CANCELLED))

        echo "  GOLD: Cancelled $GOLD_CANCELLED orders"
        echo "  SILVER: Cancelled $SILVER_CANCELLED orders"
        echo "  GOOGLE: Cancelled $GOOGLE_CANCELLED orders"
        echo "  NVIDIA: Cancelled $NVIDIA_CANCELLED orders"
        echo "  MNT: Cancelled $MNT_CANCELLED orders"
        echo "  APPLE: Cancelled $APPLE_CANCELLED orders"

        print_success "Cancelled $TOTAL_ORDERS_CANCELLED total orders"
    else
        print_warning "Order cancellation had errors, but continuing..."
    fi
else
    echo ""
    print_warning "Skipping order cancellation (CANCEL_OLD_ORDERS=false)"
fi

# ========================================
# Phase 2: Place Orders with Updated Prices
# ========================================
echo ""
print_step "Phase 2: Placing orders with updated prices..."

if forge script script/trading/FillRWAOrderBooks.s.sol:FillRWAOrderBooks \
    --rpc-url "${SCALEX_CORE_RPC}" \
    --broadcast \
    $SLOW_FLAG 2>&1 | tee /tmp/fill_orders_output.log; then

    # Count placed orders from output
    TOTAL_BUY_ORDERS=$(grep -c "\[OK\] BUY order placed" /tmp/fill_orders_output.log || echo "0")
    TOTAL_SELL_ORDERS=$(grep -c "\[OK\] SELL order placed" /tmp/fill_orders_output.log || echo "0")
    TOTAL_ORDERS_PLACED=$((TOTAL_BUY_ORDERS + TOTAL_SELL_ORDERS))

    # Check which pools succeeded
    if grep -q "=== Filling GOLD/USDC Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling GOLD/USDC Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "GOLD: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "GOLD: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("GOLD")
    fi

    if grep -q "=== Filling SILVER/USDC Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling SILVER/USDC Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "SILVER: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "SILVER: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("SILVER")
    fi

    if grep -q "=== Filling GOOGLE/USDC Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling GOOGLE/USDC Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "GOOGLE: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "GOOGLE: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("GOOGLE")
    fi

    if grep -q "=== Filling NVIDIA/USDC Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling NVIDIA/USDC Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "NVIDIA: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "NVIDIA: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("NVIDIA")
    fi

    if grep -q "=== Filling MNT/USDC Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling MNT/USDC Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "MNT: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "MNT: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("MNT")
    fi

    if grep -q "=== Filling APPLE/USDC Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling APPLE/USDC Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "APPLE: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "APPLE: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("APPLE")
    fi

    print_success "Placed $TOTAL_ORDERS_PLACED total orders ($TOTAL_BUY_ORDERS BUY, $TOTAL_SELL_ORDERS SELL)"
else
    print_error "Failed to place orders! Check /tmp/fill_orders_output.log for details"
    exit 1
fi

# ========================================
# Phase 3: Verification (Optional)
# ========================================
if [[ "$VERIFY_PRICES" == "true" ]]; then
    echo ""
    print_step "Phase 3: Verifying on-chain prices..."
    echo "  ⏳ Waiting 10 seconds for transactions to be mined..."
    sleep 10

    # Read pool addresses from deployment file
    if command -v jq >/dev/null 2>&1; then
        GOLD_POOL=$(jq -r '.GOLD_USDC_Pool // "0x0"' "$DEPLOYMENT_FILE")
        SILVER_POOL=$(jq -r '.SILVER_USDC_Pool // "0x0"' "$DEPLOYMENT_FILE")
        GOOGLE_POOL=$(jq -r '.GOOGLE_USDC_Pool // "0x0"' "$DEPLOYMENT_FILE")
        NVIDIA_POOL=$(jq -r '.NVIDIA_USDC_Pool // "0x0"' "$DEPLOYMENT_FILE")
        MNT_POOL=$(jq -r '.MNT_USDC_Pool // "0x0"' "$DEPLOYMENT_FILE")
        APPLE_POOL=$(jq -r '.APPLE_USDC_Pool // "0x0"' "$DEPLOYMENT_FILE")
    else
        print_warning "jq not found - skipping price verification"
        VERIFY_PRICES="false"
    fi

    if [[ "$VERIFY_PRICES" == "true" ]]; then
        # Verify GOLD pool
        if [[ "$GOLD_POOL" != "0x0" ]]; then
            GOLD_BUY=$(get_best_price "$GOLD_POOL" 0)
            GOLD_SELL=$(get_best_price "$GOLD_POOL" 1)
            if [[ "$GOLD_BUY" != "0" ]] && [[ "$GOLD_SELL" != "0" ]]; then
                SPREAD=$((GOLD_SELL - GOLD_BUY))
                print_success "GOLD: BUY=\$$(format_price $GOLD_BUY) SELL=\$$(format_price $GOLD_SELL) (spread: \$$(format_price $SPREAD))"
            else
                print_warning "GOLD: No orders found on-chain"
            fi
        fi

        # Verify SILVER pool
        if [[ "$SILVER_POOL" != "0x0" ]]; then
            SILVER_BUY=$(get_best_price "$SILVER_POOL" 0)
            SILVER_SELL=$(get_best_price "$SILVER_POOL" 1)
            if [[ "$SILVER_BUY" != "0" ]] && [[ "$SILVER_SELL" != "0" ]]; then
                SPREAD=$((SILVER_SELL - SILVER_BUY))
                print_success "SILVER: BUY=\$$(format_price $SILVER_BUY) SELL=\$$(format_price $SILVER_SELL) (spread: \$$(format_price $SPREAD))"
            else
                print_warning "SILVER: No orders found on-chain"
            fi
        fi

        # Verify GOOGLE pool
        if [[ "$GOOGLE_POOL" != "0x0" ]]; then
            GOOGLE_BUY=$(get_best_price "$GOOGLE_POOL" 0)
            GOOGLE_SELL=$(get_best_price "$GOOGLE_POOL" 1)
            if [[ "$GOOGLE_BUY" != "0" ]] && [[ "$GOOGLE_SELL" != "0" ]]; then
                SPREAD=$((GOOGLE_SELL - GOOGLE_BUY))
                print_success "GOOGLE: BUY=\$$(format_price $GOOGLE_BUY) SELL=\$$(format_price $GOOGLE_SELL) (spread: \$$(format_price $SPREAD))"
            else
                print_warning "GOOGLE: No orders found on-chain"
            fi
        fi

        # Verify NVIDIA pool
        if [[ "$NVIDIA_POOL" != "0x0" ]]; then
            NVIDIA_BUY=$(get_best_price "$NVIDIA_POOL" 0)
            NVIDIA_SELL=$(get_best_price "$NVIDIA_POOL" 1)
            if [[ "$NVIDIA_BUY" != "0" ]] && [[ "$NVIDIA_SELL" != "0" ]]; then
                SPREAD=$((NVIDIA_SELL - NVIDIA_BUY))
                print_success "NVIDIA: BUY=\$$(format_price $NVIDIA_BUY) SELL=\$$(format_price $NVIDIA_SELL) (spread: \$$(format_price $SPREAD))"
            else
                print_warning "NVIDIA: No orders found on-chain"
            fi
        fi

        # Verify MNT pool
        if [[ "$MNT_POOL" != "0x0" ]]; then
            MNT_BUY=$(get_best_price "$MNT_POOL" 0)
            MNT_SELL=$(get_best_price "$MNT_POOL" 1)
            if [[ "$MNT_BUY" != "0" ]] || [[ "$MNT_SELL" != "0" ]]; then
                if [[ "$MNT_BUY" != "0" ]] && [[ "$MNT_SELL" != "0" ]]; then
                    SPREAD=$((MNT_SELL - MNT_BUY))
                    print_success "MNT: BUY=\$$(format_price $MNT_BUY) SELL=\$$(format_price $MNT_SELL) (spread: \$$(format_price $SPREAD))"
                else
                    print_warning "MNT: Partial orders found (BUY=\$$(format_price $MNT_BUY) SELL=\$$(format_price $MNT_SELL))"
                fi
            else
                print_warning "MNT: No orders found on-chain"
            fi
        fi

        # Verify APPLE pool
        if [[ "$APPLE_POOL" != "0x0" ]]; then
            APPLE_BUY=$(get_best_price "$APPLE_POOL" 0)
            APPLE_SELL=$(get_best_price "$APPLE_POOL" 1)
            if [[ "$APPLE_BUY" != "0" ]] && [[ "$APPLE_SELL" != "0" ]]; then
                SPREAD=$((APPLE_SELL - APPLE_BUY))
                print_success "APPLE: BUY=\$$(format_price $APPLE_BUY) SELL=\$$(format_price $APPLE_SELL) (spread: \$$(format_price $SPREAD))"
            else
                print_warning "APPLE: No orders found on-chain"
            fi
        fi
    fi
else
    echo ""
    print_warning "Skipping price verification (VERIFY_PRICES=false)"
fi

# ========================================
# Generate Summary Report
# ========================================
echo ""
print_step "Generating summary report..."

cat > "$REPORT_FILE" << EOF
# RWA Order Book Price Update Report
Generated: $(date)

## Configuration
- Network: Chain ID $CORE_CHAIN_ID
- RPC: ${SCALEX_CORE_RPC}
- Deployment File: ${DEPLOYMENT_FILE}

## Price Configuration (January 2026)
- GOLD: \$$(format_price $GOLD_PRICE)
- SILVER: \$$(format_price $SILVER_PRICE)
- GOOGLE: \$$(format_price $GOOGL_PRICE)
- NVIDIA: \$$(format_price $NVDA_PRICE)
- APPLE: \$$(format_price $AAPL_PRICE)
- MNT: \$$(format_price $MNT_PRICE)
- WBTC: \$$(format_price $WBTC_PRICE)

## Summary
- **Pools Succeeded:** $POOLS_SUCCEEDED/6
- **Pools Failed:** $POOLS_FAILED/6
- **Orders Cancelled:** $TOTAL_ORDERS_CANCELLED
- **Orders Placed:** $TOTAL_ORDERS_PLACED ($TOTAL_BUY_ORDERS BUY, $TOTAL_SELL_ORDERS SELL)

## Failed Pools
EOF

if [[ ${#FAILED_POOLS[@]} -gt 0 ]]; then
    for pool in "${FAILED_POOLS[@]}"; do
        echo "- $pool" >> "$REPORT_FILE"
    done
else
    echo "None - all pools succeeded! ✅" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" << EOF

## Next Steps
1. Wait 5-10 minutes for indexer to sync
2. MM bot will trade against these orders
3. Monitor via indexer GraphQL API
4. Check transaction logs: /tmp/fill_orders_output.log

## Transaction Logs
- Cancel Orders Log: /tmp/cancel_orders_output.log
- Fill Orders Log: /tmp/fill_orders_output.log
EOF

print_success "Report saved to: $REPORT_FILE"

# ========================================
# Final Summary
# ========================================
echo ""
print_success "🎉 RWA Price Update Complete!"
echo ""
echo "📊 Summary:"
echo "  Pools Updated: $POOLS_SUCCEEDED/6 ($(( POOLS_SUCCEEDED * 100 / 6 ))%)"
echo "  Orders Cancelled: $TOTAL_ORDERS_CANCELLED"
echo "  Orders Placed: $TOTAL_ORDERS_PLACED"
echo "  Report: $REPORT_FILE"

if [[ $POOLS_FAILED -gt 0 ]]; then
    echo ""
    print_warning "⚠️  Some pools failed. Check logs for details:"
    echo "  - Cancel Orders: /tmp/cancel_orders_output.log"
    echo "  - Fill Orders: /tmp/fill_orders_output.log"
    echo "  - Report: $REPORT_FILE"
fi

echo ""
print_step "🚀 Next Steps:"
echo "  • Wait 5-10 minutes for indexer to sync"
echo "  • MM bot will trade against these orders"
echo "  • Monitor prices via on-chain queries or indexer"

exit 0
