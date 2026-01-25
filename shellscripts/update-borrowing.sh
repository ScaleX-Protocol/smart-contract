#!/bin/bash

# SCALEX Borrowing Operations Script
# Executes borrow operations across all collateral pools

# ========================================
# ENVIRONMENT VARIABLES
# ========================================
# Before running this script, you may need to set these environment variables:
#
# REQUIRED:
# - PRIVATE_KEY: Private key for deployment account (reads from .env file by default)
# - PRIVATE_KEY_2: Private key for borrower account (reads from .env file by default)
#
# OPTIONAL:
# - SCALEX_CORE_RPC: RPC URL for core chain (default: http://127.0.0.1:8545)
# - CORE_CHAIN_ID: Chain ID for deployment (default: auto-detected from RPC)
# - EXECUTE_BORROWS: Whether to execute borrows using PRIVATE_KEY_2 (default: true)
# - FORGE_SLOW_MODE: Enable slow mode for forge broadcasts (default: true)
# - FORGE_TIMEOUT: Timeout for forge operations (default: 1200 seconds)
#
# USAGE EXAMPLES:
# # Basic usage:
# bash shellscripts/update-borrowing.sh
#
# # Skip borrowing (just check positions):
# EXECUTE_BORROWS=false bash shellscripts/update-borrowing.sh
# ========================================

# set -e  # Disabled for better error handling

# Set timeout for long-running operations (20 minutes)
export FORGE_TIMEOUT="${FORGE_TIMEOUT:-1200}"

# Set slow mode for forge script broadcasts
export FORGE_SLOW_MODE="${FORGE_SLOW_MODE:-true}"

# Build slow flag for forge commands
if [[ "$FORGE_SLOW_MODE" == "true" ]]; then
    SLOW_FLAG="--slow"
    echo "📡 Slow mode enabled"
else
    SLOW_FLAG=""
    echo "⚡ Slow mode disabled"
fi

echo "🚀 Starting Borrow Operations..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track statistics
TOTAL_BORROWS_EXECUTED=0
TOTAL_USDC_BORROWED=0
POOLS_SUCCEEDED=0
POOLS_FAILED=0
FAILED_POOLS=()

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
        echo "✅ Environment variables loaded"
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

# Load environment variables
load_env_file

# Check if we're in the right directory
if [[ ! -f "Makefile" ]] || [[ ! -d "script" ]]; then
    print_error "Please run this script from the clob-dex project root directory"
    exit 1
fi

# Set RPC URL
export SCALEX_CORE_RPC="${SCALEX_CORE_RPC:-http://127.0.0.1:8545}"

# Detect chain ID
if [[ -z "$CORE_CHAIN_ID" ]]; then
    print_step "Detecting chain ID from RPC..."
    CORE_CHAIN_ID=$(cast chain-id --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "31337")
    export CORE_CHAIN_ID
    print_success "Detected chain ID: $CORE_CHAIN_ID"
fi

# Read deployment addresses
DEPLOYMENT_FILE="deployments/${CORE_CHAIN_ID}.json"
print_step "Reading deployment addresses from ${DEPLOYMENT_FILE}..."
if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
    print_error "${DEPLOYMENT_FILE} not found! Please run deploy.sh first."
    exit 1
fi
print_success "Deployment file found"

# Set boolean flags
EXECUTE_BORROWS="${EXECUTE_BORROWS:-true}"

# Print configuration
echo ""
print_step "Configuration:"
echo "  Network: Chain ID $CORE_CHAIN_ID"
echo "  RPC: ${SCALEX_CORE_RPC}"
echo "  Execute Borrows: ${EXECUTE_BORROWS}"

# Create timestamp for report
TIMESTAMP=$(date +%s)
REPORT_FILE="/tmp/borrowing_operations_${TIMESTAMP}.md"

# ========================================
# Phase 1: Execute Borrow Operations
# ========================================
echo ""
print_step "Phase 1: Executing borrow operations..."

if [[ "$EXECUTE_BORROWS" == "true" ]]; then
    BORROW_OUTPUT="/tmp/borrow_output.log"

    forge script script/lending/ExecuteBorrows.s.sol:ExecuteBorrows \
        --rpc-url "${SCALEX_CORE_RPC}" \
        --broadcast \
        --skip-simulation \
        $SLOW_FLAG 2>&1 | tee "$BORROW_OUTPUT"

    # Parse results
    if grep -q "Borrow Operations Complete" "$BORROW_OUTPUT"; then
        # Extract totals
        TOTAL_BORROWS=$(grep "Total Borrows Executed:" "$BORROW_OUTPUT" | awk '{print $4}')
        TOTAL_USDC=$(grep "Total USDC Borrowed:" "$BORROW_OUTPUT" | awk '{print $5}')

        print_success "Borrow operations completed"
        echo "  Total Borrows: $TOTAL_BORROWS"
        echo "  Total USDC Borrowed: \$$TOTAL_USDC"

        TOTAL_BORROWS_EXECUTED=$TOTAL_BORROWS
        TOTAL_USDC_BORROWED=$TOTAL_USDC
    else
        print_warning "Some borrow operations may have failed - check logs at $BORROW_OUTPUT"
    fi
else
    echo ""
    print_warning "Skipping borrow operations (EXECUTE_BORROWS=false)"
fi

# ========================================
# Phase 2: Verify Positions
# ========================================
echo ""
print_step "Phase 2: Verifying borrower positions..."
echo "  ⏳ Waiting 5 seconds for transactions to be mined..."
sleep 5

# Read addresses from deployment file
if command -v jq >/dev/null 2>&1; then
    USDC_ADDR=$(jq -r '.USDC // "0x0"' "$DEPLOYMENT_FILE")
    LENDING_MANAGER=$(jq -r '.LendingManager // "0x0"' "$DEPLOYMENT_FILE")
    BALANCE_MANAGER=$(jq -r '.BalanceManager // "0x0"' "$DEPLOYMENT_FILE")

    if [[ "$USDC_ADDR" != "0x0" ]] && [[ "$LENDING_MANAGER" != "0x0" ]]; then
        # Get borrower address from PRIVATE_KEY_2
        if [[ -n "$PRIVATE_KEY_2" ]]; then
            BORROWER_ADDR=$(cast address "$PRIVATE_KEY_2" 2>/dev/null || echo "0x0")

            if [[ "$BORROWER_ADDR" != "0x0" ]]; then
                echo "  Borrower Address: $BORROWER_ADDR"

                # Check USDC debt
                DEBT=$(cast call "$LENDING_MANAGER" "getUserDebt(address,address)(uint256)" "$BORROWER_ADDR" "$USDC_ADDR" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | head -1)
                if [[ -n "$DEBT" ]] && [[ "$DEBT" != "0" ]]; then
                    DEBT_USD=$(echo "scale=2; $DEBT / 1000000" | bc 2>/dev/null || echo "$DEBT / 1e6")
                    print_success "USDC Debt: \$$DEBT_USD"
                else
                    print_warning "No USDC debt found"
                fi

                # Check health factor
                HF=$(cast call "$LENDING_MANAGER" "getHealthFactor(address)(uint256)" "$BORROWER_ADDR" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | head -1)
                if [[ -n "$HF" ]] && [[ "$HF" != "0" ]]; then
                    HF_VALUE=$(echo "scale=2; $HF / 1000000000000000000" | bc 2>/dev/null || echo "$HF / 1e18")
                    if [[ $(echo "$HF_VALUE < 1.0" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
                        print_error "Health Factor: $HF_VALUE (DANGER - Below 1.0!)"
                    else
                        print_success "Health Factor: $HF_VALUE (Healthy)"
                    fi
                else
                    print_warning "Health Factor: Not available"
                fi
            fi
        fi
    fi
else
    print_warning "jq not found - skipping position verification"
fi

# ========================================
# Generate Summary Report
# ========================================
echo ""
print_step "Generating summary report..."

cat > "$REPORT_FILE" << EOF
# Borrowing Operations Report
Generated: $(date)

## Configuration
- Network: Chain ID $CORE_CHAIN_ID
- RPC: ${SCALEX_CORE_RPC}
- Deployment File: ${DEPLOYMENT_FILE}

## Summary
- **Total Borrows Executed:** $TOTAL_BORROWS_EXECUTED
- **Total USDC Borrowed:** \$$TOTAL_USDC_BORROWED

## Borrow Operations
EOF

if [[ "$EXECUTE_BORROWS" == "true" ]]; then
    echo "- **Total Operations:** ${TOTAL_BORROWS_EXECUTED}" >> "$REPORT_FILE"
    echo "- **USDC Borrowed:** \$${TOTAL_USDC_BORROWED}" >> "$REPORT_FILE"
    echo "- **Wallet:** PRIVATE_KEY_2" >> "$REPORT_FILE"
else
    echo "- Skipped (EXECUTE_BORROWS=false)" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" << EOF

## Next Steps
1. Monitor health factor to avoid liquidation
2. Repay borrowed USDC when ready
3. Withdraw collateral when debt is repaid
4. Check transaction logs below

## Transaction Logs
- Borrow Output Log: /tmp/borrow_output.log
EOF

print_success "Report saved to: $REPORT_FILE"

# ========================================
# Final Summary
# ========================================
echo ""
print_success "🎉 Borrowing Operations Complete!"
echo ""
echo "📊 Summary:"
echo "  Borrows Executed: $TOTAL_BORROWS_EXECUTED"
echo "  USDC Borrowed: \$${TOTAL_USDC_BORROWED}"
echo "  Report: $REPORT_FILE"

echo ""
print_step "🚀 Next Steps:"
echo "  • Monitor health factor to avoid liquidation"
echo "  • Borrowed USDC is available in BalanceManager"
echo "  • Use borrowed USDC for trading or other operations"
echo "  • Repay debt when done to withdraw collateral"

exit 0
