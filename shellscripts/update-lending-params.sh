#!/bin/bash

# SCALEX Lending Interest Rate Parameter Update Script (SMART MODE)
# Updates interest rate parameters AND creates lending activity intelligently
#
# SMART FEATURES:
# - Checks current supply and borrow positions before acting
# - Only supplies/borrows what's needed to reach target utilization
# - Shows before/after comparison for each token
# - Avoids overshooting target utilization

# ========================================
# ENVIRONMENT VARIABLES
# ========================================
# REQUIRED:
# - PRIVATE_KEY: Private key for owner account (reads from .env file by default)
#
# OPTIONAL (with defaults):
# - SCALEX_CORE_RPC: RPC URL for core chain (default: http://127.0.0.1:8545)
# - CORE_CHAIN_ID: Chain ID for deployment (default: auto-detected from RPC)
# - TOKENS: Comma-separated list of tokens to update (default: ALL)
#           Available: IDRX,WETH,WBTC,GOLD,SILVER,GOOGL,NVDA,AAPL,MNT
#           Example: TOKENS="IDRX,WETH" to only update IDRX and WETH
#
# Interest Rate Parameters (in basis points, 1% = 100):
# - IDRX_BASE_RATE: Base borrow rate (default: 200 = 2%)
# - IDRX_OPTIMAL_UTIL: Optimal utilization (default: 8000 = 80%)
# - IDRX_RATE_SLOPE1: Rate slope before kink (default: 1000 = 10%)
# - IDRX_RATE_SLOPE2: Rate slope after kink (default: 5000 = 50%)
#
# Similar variables for: WETH, WBTC, GOLD, SILVER, GOOGL, NVDA, AAPL, MNT
#
# Supply and Borrow Amounts:
# - IDRX_SUPPLY_AMOUNT: Amount to supply (default: 10000)
# - IDRX_BORROW_AMOUNT: Amount to borrow (default: auto-calculated from BORROW_RATIO)
# - BORROW_RATIO: Percentage of supply to borrow (default: 30 = 30% utilization)
#
# Similar _SUPPLY_AMOUNT variables for each token
#
# USAGE EXAMPLES:
# # Basic usage with defaults (updates rates + creates 30% utilization):
# bash shellscripts/update-lending-params.sh
#
# # Update only specific tokens:
# TOKENS="IDRX,WETH" bash shellscripts/update-lending-params.sh
#
# # Update with custom interest rates:
# IDRX_BASE_RATE=300 WETH_BASE_RATE=400 bash shellscripts/update-lending-params.sh
#
# # Create 50% utilization (higher supply APY):
# BORROW_RATIO=50 bash shellscripts/update-lending-params.sh
#
# # Custom supply amounts:
# IDRX_SUPPLY_AMOUNT=50000 WETH_SUPPLY_AMOUNT=20 bash shellscripts/update-lending-params.sh
#
# # Update single token with custom parameters:
# TOKENS="IDRX" IDRX_BASE_RATE=250 IDRX_SUPPLY_AMOUNT=100000 BORROW_RATIO=40 \
# bash shellscripts/update-lending-params.sh
# ========================================

set -e

echo "🚀 Starting Lending Interest Rate Parameter Update..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track statistics
TOTAL_TOKENS_UPDATED=0
TOKENS_SUCCEEDED=0
TOKENS_FAILED=0
FAILED_TOKENS=()

# Function to load .env file
load_env_file() {
    local env_file="${1:-.env}"

    if [[ -f "$env_file" ]]; then
        echo "📝 Loading environment variables from $env_file..."
        while IFS= read -r line; do
            [[ $line =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
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

# Load environment variables from .env file
load_env_file

# Check if we're in the right directory
if [[ ! -f "Makefile" ]] || [[ ! -d "script" ]]; then
    print_error "Please run this script from the clob-dex project root directory"
    exit 1
fi

# Set RPC URL if not already set
export SCALEX_CORE_RPC="${SCALEX_CORE_RPC:-http://127.0.0.1:8545}"

# Set selected tokens (default to ALL)
export TOKENS="${TOKENS:-ALL}"

# All available tokens for reference
ALL_TOKENS=("IDRX" "WETH" "WBTC" "GOLD" "SILVER" "GOOGL" "NVDA" "AAPL" "MNT")

# Function to check if a token is selected
is_token_selected() {
    local token="$1"
    local tokens_upper=$(echo "$TOKENS" | tr '[:lower:]' '[:upper:]')

    # If ALL or empty, all tokens are selected
    if [[ "$tokens_upper" == "ALL" ]] || [[ -z "$TOKENS" ]]; then
        return 0
    fi

    # Check if token is in the comma-separated list (case-insensitive)
    if echo ",$tokens_upper," | grep -qi ",$token,"; then
        return 0
    fi

    return 1
}

# Build list of selected tokens for display
SELECTED_TOKENS=()
for token in "${ALL_TOKENS[@]}"; do
    if is_token_selected "$token"; then
        SELECTED_TOKENS+=("$token")
    fi
done
TOTAL_SELECTED_TOKENS=${#SELECTED_TOKENS[@]}

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

# Set default interest rate parameters (in basis points: 1% = 100)
# Conservative lending rates for January 2026

# IDRX (Stablecoin) - Lower rates
export IDRX_BASE_RATE="${IDRX_BASE_RATE:-200}"           # 2.00%
export IDRX_OPTIMAL_UTIL="${IDRX_OPTIMAL_UTIL:-8000}"    # 80.00%
export IDRX_RATE_SLOPE1="${IDRX_RATE_SLOPE1:-1000}"      # 10.00%
export IDRX_RATE_SLOPE2="${IDRX_RATE_SLOPE2:-5000}"      # 50.00%

# WETH (Crypto asset) - Moderate rates
export WETH_BASE_RATE="${WETH_BASE_RATE:-300}"           # 3.00%
export WETH_OPTIMAL_UTIL="${WETH_OPTIMAL_UTIL:-8000}"    # 80.00%
export WETH_RATE_SLOPE1="${WETH_RATE_SLOPE1:-1200}"      # 12.00%
export WETH_RATE_SLOPE2="${WETH_RATE_SLOPE2:-6000}"      # 60.00%

# WBTC (Crypto asset) - Moderate rates
export WBTC_BASE_RATE="${WBTC_BASE_RATE:-250}"           # 2.50%
export WBTC_OPTIMAL_UTIL="${WBTC_OPTIMAL_UTIL:-8000}"    # 80.00%
export WBTC_RATE_SLOPE1="${WBTC_RATE_SLOPE1:-1100}"      # 11.00%
export WBTC_RATE_SLOPE2="${WBTC_RATE_SLOPE2:-5500}"      # 55.00%

# GOLD (RWA) - Lower rates (stable asset)
export GOLD_BASE_RATE="${GOLD_BASE_RATE:-250}"           # 2.50%
export GOLD_OPTIMAL_UTIL="${GOLD_OPTIMAL_UTIL:-7500}"    # 75.00%
export GOLD_RATE_SLOPE1="${GOLD_RATE_SLOPE1:-900}"       # 9.00%
export GOLD_RATE_SLOPE2="${GOLD_RATE_SLOPE2:-4000}"      # 40.00%

# SILVER (RWA) - Lower rates (stable asset)
export SILVER_BASE_RATE="${SILVER_BASE_RATE:-250}"       # 2.50%
export SILVER_OPTIMAL_UTIL="${SILVER_OPTIMAL_UTIL:-7500}" # 75.00%
export SILVER_RATE_SLOPE1="${SILVER_RATE_SLOPE1:-900}"   # 9.00%
export SILVER_RATE_SLOPE2="${SILVER_RATE_SLOPE2:-4000}"  # 40.00%

# GOOGL (Stock RWA) - Higher rates (volatile)
export GOOGL_BASE_RATE="${GOOGL_BASE_RATE:-400}"         # 4.00%
export GOOGL_OPTIMAL_UTIL="${GOOGL_OPTIMAL_UTIL:-7000}"  # 70.00%
export GOOGL_RATE_SLOPE1="${GOOGL_RATE_SLOPE1:-1500}"    # 15.00%
export GOOGL_RATE_SLOPE2="${GOOGL_RATE_SLOPE2:-7000}"    # 70.00%

# NVDA (Stock RWA) - Higher rates (volatile)
export NVDA_BASE_RATE="${NVDA_BASE_RATE:-400}"           # 4.00%
export NVDA_OPTIMAL_UTIL="${NVDA_OPTIMAL_UTIL:-7000}"    # 70.00%
export NVDA_RATE_SLOPE1="${NVDA_RATE_SLOPE1:-1500}"      # 15.00%
export NVDA_RATE_SLOPE2="${NVDA_RATE_SLOPE2:-7000}"      # 70.00%

# AAPL (Stock RWA) - Higher rates (volatile)
export AAPL_BASE_RATE="${AAPL_BASE_RATE:-400}"           # 4.00%
export AAPL_OPTIMAL_UTIL="${AAPL_OPTIMAL_UTIL:-7000}"    # 70.00%
export AAPL_RATE_SLOPE1="${AAPL_RATE_SLOPE1:-1500}"      # 15.00%
export AAPL_RATE_SLOPE2="${AAPL_RATE_SLOPE2:-7000}"      # 70.00%

# MNT (Token) - Moderate rates
export MNT_BASE_RATE="${MNT_BASE_RATE:-350}"             # 3.50%
export MNT_OPTIMAL_UTIL="${MNT_OPTIMAL_UTIL:-7500}"      # 75.00%
export MNT_RATE_SLOPE1="${MNT_RATE_SLOPE1:-1300}"        # 13.00%
export MNT_RATE_SLOPE2="${MNT_RATE_SLOPE2:-6500}"        # 65.00%

# Borrow ratio (percentage of supply to borrow - creates utilization)
export BORROW_RATIO="${BORROW_RATIO:-30}"                # 30% utilization

# Print configuration
echo ""
print_step "Configuration:"
echo "  Network: Chain ID $CORE_CHAIN_ID"
echo "  RPC: ${SCALEX_CORE_RPC}"
echo "  Deployment: ${DEPLOYMENT_FILE}"
echo "  Selected Tokens: ${SELECTED_TOKENS[*]}"
echo "  Total Tokens: $TOTAL_SELECTED_TOKENS"

echo ""
print_step "Lending Activity Configuration:"
echo "  Target Utilization: ${BORROW_RATIO}% (creates non-zero supply APY)"
echo "  Supply tokens to lending pool: YES"
echo "  Borrow against collateral: YES"
echo "  Expected Result: Supply APY > 0%"

echo ""
print_step "Interest Rate Configuration:"
for token in "${SELECTED_TOKENS[@]}"; do
    BASE_VAR="${token}_BASE_RATE"
    OPTIMAL_VAR="${token}_OPTIMAL_UTIL"
    SLOPE1_VAR="${token}_RATE_SLOPE1"
    SLOPE2_VAR="${token}_RATE_SLOPE2"

    BASE=${!BASE_VAR}
    OPTIMAL=${!OPTIMAL_VAR}
    SLOPE1=${!SLOPE1_VAR}
    SLOPE2=${!SLOPE2_VAR}

    echo "  $token:"
    if command -v bc >/dev/null 2>&1; then
        echo "    Base Rate: $(echo "scale=2; $BASE / 100" | bc)%"
        echo "    Optimal Utilization: $(echo "scale=2; $OPTIMAL / 100" | bc)%"
        echo "    Rate Slope 1: $(echo "scale=2; $SLOPE1 / 100" | bc)%"
        echo "    Rate Slope 2: $(echo "scale=2; $SLOPE2 / 100" | bc)%"
    else
        echo "    Base Rate: $BASE bps"
        echo "    Optimal Utilization: $OPTIMAL bps"
        echo "    Rate Slope 1: $SLOPE1 bps"
        echo "    Rate Slope 2: $SLOPE2 bps"
    fi
done

# Create timestamp for report
TIMESTAMP=$(date +%s)
REPORT_FILE="/tmp/lending_params_update_${TIMESTAMP}.md"

# ========================================
# Update Interest Rate Parameters + Create Lending Activity
# ========================================
echo ""
print_step "Updating interest rate parameters and creating lending activity (SMART MODE)..."
echo "  Phase 0: Check current lending positions"
echo "  Phase 1: Update interest rate parameters"
echo "  Phase 2: Smart supply (only if needed)"
echo "  Phase 3: Smart borrow (to reach target utilization)"
echo "  Phase 4: Verify APY is non-zero"
echo ""

if forge script script/lending/UpdateLendingWithActivity.s.sol:UpdateLendingWithActivity \
    --rpc-url "${SCALEX_CORE_RPC}" \
    --broadcast \
    --slow 2>&1 | tee /tmp/update_lending_params_output.log; then

    # Count phase results
    TOTAL_TOKENS_UPDATED=$(grep -c "\[OK\].*interest rates set" /tmp/update_lending_params_output.log || echo "0")
    TOTAL_SUPPLIED=$(grep -c "\[OK\].*supplied:" /tmp/update_lending_params_output.log || echo "0")
    TOTAL_BORROWED=$(grep -c "\[OK\].*borrowed:" /tmp/update_lending_params_output.log || echo "0")
    NON_ZERO_APY=$(grep -c "\[OK\] Supply APY is non-zero" /tmp/update_lending_params_output.log || echo "0")

    # Check which selected tokens succeeded
    for token in "${SELECTED_TOKENS[@]}"; do
        if grep -q "\[OK\] ${token}" /tmp/update_lending_params_output.log; then
            print_success "${token}: Updated successfully"
            TOKENS_SUCCEEDED=$((TOKENS_SUCCEEDED + 1))
        else
            print_warning "${token}: Some operations may have failed"
            TOKENS_FAILED=$((TOKENS_FAILED + 1))
            FAILED_TOKENS+=("${token}")
        fi
    done

    echo ""
    print_success "Phase 1: Updated $TOTAL_TOKENS_UPDATED interest rate parameters"
    print_success "Phase 2: Supplied $TOTAL_SUPPLIED tokens to lending pools"
    print_success "Phase 3: Borrowed $TOTAL_BORROWED tokens (created utilization)"
    if [[ $NON_ZERO_APY -gt 0 ]]; then
        print_success "Phase 4: $NON_ZERO_APY tokens now have non-zero Supply APY!"
    else
        print_warning "Phase 4: Supply APY may still be 0% (need more borrowing activity)"
    fi
else
    print_error "Failed to update! Check /tmp/update_lending_params_output.log for details"
    exit 1
fi

# ========================================
# Generate Summary Report
# ========================================
echo ""
print_step "Generating summary report..."

cat > "$REPORT_FILE" << EOF
# Lending Interest Rate Parameter Update Report
Generated: $(date)

## Configuration
- Network: Chain ID $CORE_CHAIN_ID
- RPC: ${SCALEX_CORE_RPC}
- Deployment File: ${DEPLOYMENT_FILE}
- Selected Tokens: ${SELECTED_TOKENS[*]}
- Total Tokens: $TOTAL_SELECTED_TOKENS

## Lending Activity Configuration
- Target Utilization: ${BORROW_RATIO}%
- Supply tokens: YES
- Borrow against collateral: YES
- Expected Result: Supply APY > 0%

## Interest Rate Parameters (Basis Points)
EOF

for token in "${SELECTED_TOKENS[@]}"; do
    BASE_VAR="${token}_BASE_RATE"
    OPTIMAL_VAR="${token}_OPTIMAL_UTIL"
    SLOPE1_VAR="${token}_RATE_SLOPE1"
    SLOPE2_VAR="${token}_RATE_SLOPE2"

    BASE=${!BASE_VAR}
    OPTIMAL=${!OPTIMAL_VAR}
    SLOPE1=${!SLOPE1_VAR}
    SLOPE2=${!SLOPE2_VAR}

    if command -v bc >/dev/null 2>&1; then
        BASE_PCT=$(echo "scale=2; $BASE / 100" | bc)
        OPTIMAL_PCT=$(echo "scale=2; $OPTIMAL / 100" | bc)
        SLOPE1_PCT=$(echo "scale=2; $SLOPE1 / 100" | bc)
        SLOPE2_PCT=$(echo "scale=2; $SLOPE2 / 100" | bc)
    else
        BASE_PCT="$BASE bps"
        OPTIMAL_PCT="$OPTIMAL bps"
        SLOPE1_PCT="$SLOPE1 bps"
        SLOPE2_PCT="$SLOPE2 bps"
    fi

    cat >> "$REPORT_FILE" << TOKENEOF

### $token
- Base Rate: ${BASE_PCT}% ($BASE bps)
- Optimal Utilization: ${OPTIMAL_PCT}% ($OPTIMAL bps)
- Rate Slope 1: ${SLOPE1_PCT}% ($SLOPE1 bps)
- Rate Slope 2: ${SLOPE2_PCT}% ($SLOPE2 bps)
TOKENEOF
done

cat >> "$REPORT_FILE" << EOF

## Summary
- **Tokens Succeeded:** $TOKENS_SUCCEEDED/$TOTAL_SELECTED_TOKENS
- **Tokens Failed:** $TOKENS_FAILED/$TOTAL_SELECTED_TOKENS
- **Interest Rates Updated:** $TOTAL_TOKENS_UPDATED
- **Tokens Supplied:** $TOTAL_SUPPLIED
- **Tokens Borrowed:** $TOTAL_BORROWED
- **Non-Zero Supply APY:** $NON_ZERO_APY

## Failed Tokens
EOF

if [[ ${#FAILED_TOKENS[@]} -gt 0 ]]; then
    for token in "${FAILED_TOKENS[@]}"; do
        echo "- $token" >> "$REPORT_FILE"
    done
else
    echo "None - all tokens succeeded! ✅" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" << EOF

## How Interest Rates Work

### Borrow APY Calculation:
- If utilization <= optimal: \`baseRate + (utilization / optimal) * rateSlope1\`
- If utilization > optimal: \`baseRate + rateSlope1 + ((utilization - optimal) / (1 - optimal)) * rateSlope2\`

### Supply APY Calculation:
- \`Supply APY = Borrow APY × Utilization × (1 - Reserve Factor)\`

## Next Steps
1. Wait 5-10 minutes for indexer to sync
2. Monitor APY updates via lending dashboard API
3. Verify rates are applied correctly

## Transaction Logs
- Update Log: /tmp/update_lending_params_output.log
EOF

print_success "Report saved to: $REPORT_FILE"

# ========================================
# Final Summary
# ========================================
echo ""
print_success "🎉 Lending Update with Activity Complete!"
echo ""
echo "📊 Summary:"
echo "  Tokens Updated: $TOKENS_SUCCEEDED/$TOTAL_SELECTED_TOKENS ($(( TOKENS_SUCCEEDED * 100 / TOTAL_SELECTED_TOKENS ))%)"
echo "  Interest Rates Set: $TOTAL_TOKENS_UPDATED"
echo "  Tokens Supplied: $TOTAL_SUPPLIED"
echo "  Tokens Borrowed: $TOTAL_BORROWED"
if [[ $NON_ZERO_APY -gt 0 ]]; then
    echo "  Non-Zero Supply APY: $NON_ZERO_APY tokens ✅"
else
    echo "  Supply APY Status: Check dashboard (may need more activity)"
fi
echo "  Report: $REPORT_FILE"

if [[ $TOKENS_FAILED -gt 0 ]]; then
    echo ""
    print_warning "⚠️  Some tokens failed. Check logs for details:"
    echo "  - Update Log: /tmp/update_lending_params_output.log"
    echo "  - Report: $REPORT_FILE"
fi

echo ""
print_step "🚀 Next Steps:"
echo "  • Wait 5-10 minutes for indexer to sync"
echo "  • Check lending dashboard API for non-zero APY values"
echo "  • Verify supply APY > 0% due to borrowing activity"
echo "  • Adjust BORROW_RATIO to increase/decrease utilization"
echo ""
echo "  Check dashboard:"
echo "  curl http://localhost:42070/api/lending/dashboard/{address} | jq '.supplies[].realTimeRates'"

exit 0
