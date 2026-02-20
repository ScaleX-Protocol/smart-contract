#!/bin/bash

# SCALEX Order Book Price Update Script
# Updates selected order books with current market prices (except ETH/WETH)

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
# - MARKETS: Comma-separated list of markets to update (default: ALL)
#            Available: WETH,WBTC,GOLD,SILVER,GOOGLE,NVIDIA,APPLE,MNT
#            Example: MARKETS="WBTC,GOLD" to only update WBTC and GOLD pools
# - WETH_PRICE: Ethereum price in quote currency (default: 3300 * PRICE_MULTIPLIER = $3,300)
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
# # Basic usage with defaults (January 2026 prices, all markets):
# bash shellscripts/update-orderbook-prices.sh
#
# # Update only specific markets:
# MARKETS="WBTC,GOLD" bash shellscripts/update-orderbook-prices.sh
#
# # Update single market with custom price:
# MARKETS="WBTC" WBTC_PRICE=96000000000 bash shellscripts/update-orderbook-prices.sh
#
# # Update RWA markets only:
# MARKETS="GOLD,SILVER,GOOGLE,NVIDIA,APPLE" bash shellscripts/update-orderbook-prices.sh
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

echo "🚀 Starting Order Book Price Update..."

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

# Set selected markets (default to ALL)
# Available markets: WBTC, GOLD, SILVER, GOOGLE, NVIDIA, APPLE, MNT
export MARKETS="${MARKETS:-ALL}"

# All available markets for reference
ALL_MARKETS=("WETH" "WBTC" "GOLD" "SILVER" "GOOGLE" "NVIDIA" "APPLE" "MNT")

# Function to check if a market is selected
is_market_selected() {
    local market="$1"
    local markets_upper=$(echo "$MARKETS" | tr '[:lower:]' '[:upper:]')

    # If ALL or empty, all markets are selected
    if [[ "$markets_upper" == "ALL" ]] || [[ -z "$MARKETS" ]]; then
        return 0
    fi

    # Check if market is in the comma-separated list (case-insensitive)
    if echo ",$markets_upper," | grep -qi ",$market,"; then
        return 0
    fi

    return 1
}

# Build list of selected markets for display
SELECTED_MARKETS=()
for market in "${ALL_MARKETS[@]}"; do
    if is_market_selected "$market"; then
        SELECTED_MARKETS+=("$market")
    fi
done
TOTAL_SELECTED_POOLS=${#SELECTED_MARKETS[@]}

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

# Read quote currency decimals from .env (defaults to 6 for USDC)
QUOTE_DECIMALS_VALUE=$(grep "^QUOTE_DECIMALS=" .env 2>/dev/null | cut -d'=' -f2 || echo "6")
export QUOTE_DECIMALS="${QUOTE_DECIMALS:-$QUOTE_DECIMALS_VALUE}"

# Calculate price multiplier based on quote decimals
# For IDRX (2 decimals): 10^2 = 100
# For USDC (6 decimals): 10^6 = 1,000,000
if command -v bc >/dev/null 2>&1; then
    PRICE_MULTIPLIER=$(echo "10^${QUOTE_DECIMALS}" | bc)
else
    # Fallback for systems without bc
    PRICE_MULTIPLIER=1
    for ((i=0; i<QUOTE_DECIMALS; i++)); do
        PRICE_MULTIPLIER=$((PRICE_MULTIPLIER * 10))
    done
fi

# Set default prices (January 2026 market prices) scaled to quote currency decimals
export WETH_PRICE="${WETH_PRICE:-$((3300 * PRICE_MULTIPLIER))}"      # $3,300
export WBTC_PRICE="${WBTC_PRICE:-$((95000 * PRICE_MULTIPLIER))}"     # $95,000
export GOLD_PRICE="${GOLD_PRICE:-$((4450 * PRICE_MULTIPLIER))}"      # $4,450
export SILVER_PRICE="${SILVER_PRICE:-$((78 * PRICE_MULTIPLIER))}"    # $78
export GOOGL_PRICE="${GOOGL_PRICE:-$((314 * PRICE_MULTIPLIER))}"     # $314
export NVDA_PRICE="${NVDA_PRICE:-$((188 * PRICE_MULTIPLIER))}"       # $188
export AAPL_PRICE="${AAPL_PRICE:-$((265 * PRICE_MULTIPLIER))}"       # $265
export MNT_PRICE="${MNT_PRICE:-$((1 * PRICE_MULTIPLIER))}"           # $1

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
echo "  Selected Markets: ${SELECTED_MARKETS[*]}"
echo "  Total Pools: $TOTAL_SELECTED_POOLS (excluding WETH)"
echo "  Verify Prices: ${VERIFY_PRICES}"
echo "  Execute Market Orders: ${EXECUTE_MARKET_ORDERS}"

echo ""
print_step "Price Configuration (January 2026):"
echo "  Quote Decimals: ${QUOTE_DECIMALS}"
echo "  Price Multiplier: ${PRICE_MULTIPLIER}"
echo "  WETH:   \$$(format_price $WETH_PRICE $QUOTE_DECIMALS) (Ethereum)"
echo "  WBTC:   \$$(format_price $WBTC_PRICE $QUOTE_DECIMALS) (Bitcoin)"
echo "  GOLD:   \$$(format_price $GOLD_PRICE $QUOTE_DECIMALS) (Gold RWA)"
echo "  SILVER: \$$(format_price $SILVER_PRICE $QUOTE_DECIMALS) (Silver RWA)"
echo "  GOOGLE: \$$(format_price $GOOGL_PRICE $QUOTE_DECIMALS) (Google Stock RWA)"
echo "  NVIDIA: \$$(format_price $NVDA_PRICE $QUOTE_DECIMALS) (Nvidia Stock RWA)"
echo "  APPLE:  \$$(format_price $AAPL_PRICE $QUOTE_DECIMALS) (Apple Stock RWA)"
echo "  MNT:    \$$(format_price $MNT_PRICE $QUOTE_DECIMALS) (MNT Token)"

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

    # Check which selected pools succeeded
    for market in "${SELECTED_MARKETS[@]}"; do
        if grep -q "=== Filling ${market}/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log && \
           grep -A 20 "=== Filling ${market}/${QUOTE_CURRENCY} Order Book ===" /tmp/fill_orders_output.log | grep -q "\[OK\]"; then
            print_success "${market}: Orders placed successfully"
            POOLS_SUCCEEDED=$((POOLS_SUCCEEDED + 1))
        else
            print_warning "${market}: Failed to place orders"
            POOLS_FAILED=$((POOLS_FAILED + 1))
            FAILED_POOLS+=("${market}")
        fi
    done

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

    # Read pool addresses from deployment file (only for selected markets)
    if command -v jq >/dev/null 2>&1; then
        for market in "${SELECTED_MARKETS[@]}"; do
            POOL_ADDR=$(jq -r ".${market}_${QUOTE_CURRENCY}_Pool // \"0x0\"" "$DEPLOYMENT_FILE")
            # Use dynamic variable assignment
            declare "${market}_POOL=$POOL_ADDR"
        done
    else
        print_warning "jq not found - skipping price verification"
        VERIFY_PRICES="false"
    fi

    if [[ "$VERIFY_PRICES" == "true" ]]; then
        # Verify only selected pools
        for market in "${SELECTED_MARKETS[@]}"; do
            POOL_VAR="${market}_POOL"
            POOL_ADDR="${!POOL_VAR}"

            if [[ -n "$POOL_ADDR" ]] && [[ "$POOL_ADDR" != "0x0" ]] && [[ "$POOL_ADDR" != "null" ]]; then
                BEST_BUY=$(get_best_price "$POOL_ADDR" 0)
                BEST_SELL=$(get_best_price "$POOL_ADDR" 1)

                if [[ "$BEST_BUY" != "0" ]] && [[ "$BEST_SELL" != "0" ]]; then
                    SPREAD=$((BEST_SELL - BEST_BUY))
                    print_success "${market}: BUY=\$$(format_price $BEST_BUY $QUOTE_DECIMALS) SELL=\$$(format_price $BEST_SELL $QUOTE_DECIMALS) (spread: \$$(format_price $SPREAD $QUOTE_DECIMALS))"
                elif [[ "$BEST_BUY" != "0" ]] || [[ "$BEST_SELL" != "0" ]]; then
                    print_warning "${market}: Partial orders found (BUY=\$$(format_price $BEST_BUY $QUOTE_DECIMALS) SELL=\$$(format_price $BEST_SELL $QUOTE_DECIMALS))"
                else
                    print_warning "${market}: No orders found on-chain"
                fi
            else
                print_warning "${market}: Pool not found in deployment file"
            fi
        done
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
- Quote Currency: ${QUOTE_CURRENCY} (${QUOTE_DECIMALS} decimals)
- Selected Markets: ${SELECTED_MARKETS[*]}
- Total Pools: $TOTAL_SELECTED_POOLS (excluding WETH)

## Price Configuration (January 2026)
- WETH: \$$(format_price $WETH_PRICE $QUOTE_DECIMALS) (Ethereum)
- WBTC: \$$(format_price $WBTC_PRICE $QUOTE_DECIMALS) (Bitcoin)
- GOLD: \$$(format_price $GOLD_PRICE $QUOTE_DECIMALS) (Gold RWA)
- SILVER: \$$(format_price $SILVER_PRICE $QUOTE_DECIMALS) (Silver RWA)
- GOOGLE: \$$(format_price $GOOGL_PRICE $QUOTE_DECIMALS) (Google Stock RWA)
- NVIDIA: \$$(format_price $NVDA_PRICE $QUOTE_DECIMALS) (Nvidia Stock RWA)
- APPLE: \$$(format_price $AAPL_PRICE $QUOTE_DECIMALS) (Apple Stock RWA)
- MNT: \$$(format_price $MNT_PRICE $QUOTE_DECIMALS) (MNT Token)

## Summary
- **Pools Succeeded:** $POOLS_SUCCEEDED/$TOTAL_SELECTED_POOLS
- **Pools Failed:** $POOLS_FAILED/$TOTAL_SELECTED_POOLS
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
echo "  Pools Updated: $POOLS_SUCCEEDED/$TOTAL_SELECTED_POOLS ($(( POOLS_SUCCEEDED * 100 / TOTAL_SELECTED_POOLS ))%)"
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
