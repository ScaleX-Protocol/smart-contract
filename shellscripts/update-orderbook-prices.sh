#!/bin/bash

# SCALEX Order Book Price Update Script
# Updates ALL order books with current market prices (except ETH/WETH)

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
# - WBTC_PRICE: Bitcoin price in USDC with 6 decimals (default: 95000000000 = $95,000)
# - GOLD_PRICE: Gold price in USDC with 6 decimals (default: 4450000000 = $4,450)
# - SILVER_PRICE: Silver price in USDC with 6 decimals (default: 78000000 = $78)
# - GOOGL_PRICE: Google stock price (default: 314000000 = $314)
# - NVDA_PRICE: Nvidia stock price (default: 188000000 = $188)
# - AAPL_PRICE: Apple stock price (default: 265000000 = $265)
# - MNT_PRICE: MNT token price (default: 1000000 = $1)
# - VERIFY_PRICES: Whether to verify on-chain (default: true)
# - EXECUTE_MARKET_ORDERS: Whether to execute market orders using PRIVATE_KEY_2 (default: true)
# - FORGE_SLOW_MODE: Enable slow mode for forge broadcasts (default: true)
# - FORGE_TIMEOUT: Timeout for forge operations (default: 1200 seconds)
#
# USAGE EXAMPLES:
# # Basic usage with defaults (January 2026 prices):
# bash shellscripts/update-orderbook-prices.sh
#
# # Update with custom prices:
# WBTC_PRICE=96000000000 GOLD_PRICE=4500000000 SILVER_PRICE=80000000 \
# bash shellscripts/update-orderbook-prices.sh
#
# # Update specific network:
# SCALEX_CORE_RPC="https://base-sepolia.g.alchemy.com/v2/YOUR_KEY" \
# bash shellscripts/update-orderbook-prices.sh
#
# # Skip verification (faster execution):
# VERIFY_PRICES=false bash shellscripts/update-orderbook-prices.sh
#
# # Update all prices for production:
# WBTC_PRICE=96000000000 GOLD_PRICE=4500000000 SILVER_PRICE=80000000 \
# GOOGL_PRICE=320000000 NVDA_PRICE=190000000 AAPL_PRICE=270000000 \
# MNT_PRICE=1050000 bash shellscripts/update-orderbook-prices.sh
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

echo "🚀 Starting Order Book Price Update (All Pools Except ETH)..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track statistics
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
        --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | head -1 | awk '{print $1}')

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

# Set quote currency from environment (default to USDC)
export QUOTE_CURRENCY="${QUOTE_CURRENCY:-USDC}"

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
export WBTC_PRICE="${WBTC_PRICE:-95000000000}"     # $95,000
export GOLD_PRICE="${GOLD_PRICE:-4450000000}"      # $4,450
export SILVER_PRICE="${SILVER_PRICE:-78000000}"    # $78
export GOOGL_PRICE="${GOOGL_PRICE:-314000000}"     # $314
export NVDA_PRICE="${NVDA_PRICE:-188000000}"       # $188
export AAPL_PRICE="${AAPL_PRICE:-265000000}"       # $265
export MNT_PRICE="${MNT_PRICE:-1000000}"           # $1

# Set boolean flags
VERIFY_PRICES="${VERIFY_PRICES:-true}"
EXECUTE_MARKET_ORDERS="${EXECUTE_MARKET_ORDERS:-true}"

# Print configuration
echo ""
print_step "Configuration:"
echo "  Network: Chain ID $CORE_CHAIN_ID"
echo "  RPC: ${SCALEX_CORE_RPC}"
echo "  Deployment: ${DEPLOYMENT_FILE}"
echo "  Quote Currency: ${QUOTE_CURRENCY}"
echo "  Total Pools: 7 (excluding WETH)"
echo "  Verify Prices: ${VERIFY_PRICES}"
echo "  Execute Market Orders: ${EXECUTE_MARKET_ORDERS}"

echo ""
print_step "Price Configuration (January 2026):"
echo "  WBTC:   \$$(format_price $WBTC_PRICE) (Bitcoin)"
echo "  GOLD:   \$$(format_price $GOLD_PRICE) (Gold RWA)"
echo "  SILVER: \$$(format_price $SILVER_PRICE) (Silver RWA)"
echo "  GOOGLE: \$$(format_price $GOOGL_PRICE) (Google Stock RWA)"
echo "  NVIDIA: \$$(format_price $NVDA_PRICE) (Nvidia Stock RWA)"
echo "  APPLE:  \$$(format_price $AAPL_PRICE) (Apple Stock RWA)"
echo "  MNT:    \$$(format_price $MNT_PRICE) (MNT Token)"

# Create timestamp for report
TIMESTAMP=$(date +%s)
REPORT_FILE="/tmp/orderbook_price_update_${TIMESTAMP}.md"

# ========================================
# Phase 1: Place Orders with Updated Prices
# ========================================
echo ""
print_step "Phase 1: Placing orders with updated prices..."

if forge script script/trading/FillOrderBooks.s.sol:FillOrderBooks \
    --rpc-url "${SCALEX_CORE_RPC}" \
    --broadcast \
    $SLOW_FLAG 2>&1 | tee /tmp/fill_orders_output.log; then

    # Count placed orders from output
    TOTAL_BUY_ORDERS=$(grep -c "\[OK\] BUY order placed" /tmp/fill_orders_output.log || echo "0")
    TOTAL_SELL_ORDERS=$(grep -c "\[OK\] SELL order placed" /tmp/fill_orders_output.log || echo "0")
    TOTAL_ORDERS_PLACED=$((TOTAL_BUY_ORDERS + TOTAL_SELL_ORDERS))

    # Check which pools succeeded
    if grep -q "=== Filling WBTC/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling WBTC/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "WBTC: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "WBTC: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("WBTC")
    fi

    if grep -q "=== Filling GOLD/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling GOLD/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "GOLD: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "GOLD: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("GOLD")
    fi

    if grep -q "=== Filling SILVER/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling SILVER/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "SILVER: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "SILVER: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("SILVER")
    fi

    if grep -q "=== Filling GOOGLE/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling GOOGLE/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "GOOGLE: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "GOOGLE: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("GOOGLE")
    fi

    if grep -q "=== Filling NVIDIA/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling NVIDIA/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "NVIDIA: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "NVIDIA: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("NVIDIA")
    fi

    if grep -q "=== Filling MNT/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling MNT/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
        print_success "MNT: Orders placed successfully"
        POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
    else
        print_warning "MNT: Failed to place orders"
        POOLS_FAILED=$((POOLS_FAILED + 1))
        FAILED_POOLS+=("MNT")
    fi

    if grep -q "=== Filling APPLE/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log && grep -A 20 "=== Filling APPLE/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
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
# Phase 2: Verification (Optional)
# ========================================
if [[ "$VERIFY_PRICES" == "true" ]]; then
    echo ""
    print_step "Phase 2: Verifying on-chain prices..."
    echo "  ⏳ Waiting 10 seconds for transactions to be mined..."
    sleep 10

    # Read pool addresses from deployment file
    if command -v jq >/dev/null 2>&1; then
        WBTC_POOL=$(jq -r ".WBTC_${QUOTE_CURRENCY}_Pool // \"0x0\"" "$DEPLOYMENT_FILE")
        GOLD_POOL=$(jq -r ".GOLD_${QUOTE_CURRENCY}_Pool // \"0x0\"" "$DEPLOYMENT_FILE")
        SILVER_POOL=$(jq -r ".SILVER_${QUOTE_CURRENCY}_Pool // \"0x0\"" "$DEPLOYMENT_FILE")
        GOOGLE_POOL=$(jq -r ".GOOGLE_${QUOTE_CURRENCY}_Pool // \"0x0\"" "$DEPLOYMENT_FILE")
        NVIDIA_POOL=$(jq -r ".NVIDIA_${QUOTE_CURRENCY}_Pool // \"0x0\"" "$DEPLOYMENT_FILE")
        MNT_POOL=$(jq -r ".MNT_${QUOTE_CURRENCY}_Pool // \"0x0\"" "$DEPLOYMENT_FILE")
        APPLE_POOL=$(jq -r ".APPLE_${QUOTE_CURRENCY}_Pool // \"0x0\"" "$DEPLOYMENT_FILE")
    else
        print_warning "jq not found - skipping price verification"
        VERIFY_PRICES="false"
    fi

    if [[ "$VERIFY_PRICES" == "true" ]]; then
        # Verify WBTC pool
        if [[ "$WBTC_POOL" != "0x0" ]]; then
            WBTC_BUY=$(get_best_price "$WBTC_POOL" 0)
            WBTC_SELL=$(get_best_price "$WBTC_POOL" 1)
            if [[ "$WBTC_BUY" != "0" ]] && [[ "$WBTC_SELL" != "0" ]]; then
                SPREAD=$((WBTC_SELL - WBTC_BUY))
                print_success "WBTC: BUY=\$$(format_price $WBTC_BUY) SELL=\$$(format_price $WBTC_SELL) (spread: \$$(format_price $SPREAD))"
            else
                print_warning "WBTC: No orders found on-chain"
            fi
        fi

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
# Phase 3: Execute Market Orders (PRIVATE_KEY_2)
# ========================================
if [[ "$EXECUTE_MARKET_ORDERS" == "true" ]]; then
    echo ""
    print_step "Phase 3: Executing market orders (PRIVATE_KEY_2 trading against limit orders)..."
    echo "  ⏳ Waiting 10 seconds for limit orders to settle..."
    sleep 10

    # Execute market orders script
    MARKET_ORDERS_OUTPUT="/tmp/market_orders_output.log"

    # Skip simulation since it would consume the limit orders placed in Phase 1
    forge script script/trading/PlaceMarketOrders.s.sol:PlaceMarketOrders \
        --rpc-url "${SCALEX_CORE_RPC}" \
        --broadcast \
        --skip-simulation \
        $SLOW_FLAG 2>&1 | tee "$MARKET_ORDERS_OUTPUT"

    # Check if market orders succeeded
    if grep -q "Market BUY executed" "$MARKET_ORDERS_OUTPUT" && grep -q "Market SELL executed" "$MARKET_ORDERS_OUTPUT"; then
        MARKET_ORDERS_EXECUTED=$(grep -c "Market.*executed" "$MARKET_ORDERS_OUTPUT" || echo "0")
        print_success "Market orders executed: $MARKET_ORDERS_EXECUTED trades"
    else
        print_warning "Some market orders may have failed - check logs at $MARKET_ORDERS_OUTPUT"
    fi
else
    echo ""
    print_warning "Skipping market order execution (EXECUTE_MARKET_ORDERS=false)"
fi

# ========================================
# Generate Summary Report
# ========================================
echo ""
print_step "Generating summary report..."

cat > "$REPORT_FILE" << EOF
# Order Book Price Update Report
Generated: $(date)

## Configuration
- Network: Chain ID $CORE_CHAIN_ID
- RPC: ${SCALEX_CORE_RPC}
- Deployment File: ${DEPLOYMENT_FILE}
- Total Pools: 7 (excluding WETH)

## Price Configuration (January 2026)
- WBTC: \$$(format_price $WBTC_PRICE) (Bitcoin)
- GOLD: \$$(format_price $GOLD_PRICE) (Gold RWA)
- SILVER: \$$(format_price $SILVER_PRICE) (Silver RWA)
- GOOGLE: \$$(format_price $GOOGL_PRICE) (Google Stock RWA)
- NVIDIA: \$$(format_price $NVDA_PRICE) (Nvidia Stock RWA)
- APPLE: \$$(format_price $AAPL_PRICE) (Apple Stock RWA)
- MNT: \$$(format_price $MNT_PRICE) (MNT Token)

## Summary
- **Pools Succeeded:** $POOLS_SUCCEEDED/7
- **Pools Failed:** $POOLS_FAILED/7
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

## Market Orders Executed
EOF

if [[ "$EXECUTE_MARKET_ORDERS" == "true" ]] && [[ -n "${MARKET_ORDERS_EXECUTED:-}" ]]; then
    echo "- **Total Trades:** ${MARKET_ORDERS_EXECUTED}" >> "$REPORT_FILE"
    echo "- **Wallet:** PRIVATE_KEY_2 (different from limit order wallet)" >> "$REPORT_FILE"
    echo "- **Result:** Trades executed between different wallets ✅" >> "$REPORT_FILE"
else
    echo "- Skipped (EXECUTE_MARKET_ORDERS=false)" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" << EOF

## Next Steps
1. Wait 5-10 minutes for indexer to sync
2. Monitor trades via indexer GraphQL API
3. Check transaction logs below

## Transaction Logs
- Fill Orders Log: /tmp/fill_orders_output.log
- Market Orders Log: /tmp/market_orders_output.log
EOF

print_success "Report saved to: $REPORT_FILE"

# ========================================
# Final Summary
# ========================================
echo ""
print_success "🎉 Order Book Price Update Complete!"
echo ""
echo "📊 Summary:"
echo "  Pools Updated: $POOLS_SUCCEEDED/7 ($(( POOLS_SUCCEEDED * 100 / 7 ))%)"
echo "  Orders Placed: $TOTAL_ORDERS_PLACED"
if [[ "$EXECUTE_MARKET_ORDERS" == "true" ]] && [[ -n "${MARKET_ORDERS_EXECUTED:-}" ]]; then
    echo "  Market Orders Executed: $MARKET_ORDERS_EXECUTED trades (PRIVATE_KEY_2)"
fi
echo "  Report: $REPORT_FILE"

if [[ $POOLS_FAILED -gt 0 ]]; then
    echo ""
    print_warning "⚠️  Some pools failed. Check logs for details:"
    echo "  - Fill Orders: /tmp/fill_orders_output.log"
    echo "  - Report: $REPORT_FILE"
fi

echo ""
print_step "🚀 Next Steps:"
echo "  • Wait 5-10 minutes for indexer to sync"
if [[ "$EXECUTE_MARKET_ORDERS" == "true" ]]; then
    echo "  • Trades have been executed between PRIVATE_KEY and PRIVATE_KEY_2"
    echo "  • Monitor trade activity via indexer GraphQL API"
else
    echo "  • MM bot can trade against these orders using PRIVATE_KEY_2"
fi
echo "  • Monitor prices via on-chain queries or indexer"

exit 0
