#!/bin/bash

# Quote Currency Configuration Module
# Provides centralized configuration loading and helper functions for quote currency management

# Default values for USDC (backward compatibility)
DEFAULT_QUOTE_CURRENCY="USDC"
DEFAULT_QUOTE_DECIMALS=6
DEFAULT_QUOTE_SYMBOL="USDC"
DEFAULT_QUOTE_NAME="USDC Coin"

# Default lending parameters (USDC)
DEFAULT_QUOTE_COLLATERAL_FACTOR=7500     # 75%
DEFAULT_QUOTE_LIQUIDATION_THRESHOLD=8500 # 85%
DEFAULT_QUOTE_LIQUIDATION_BONUS=800      # 8%
DEFAULT_QUOTE_RESERVE_FACTOR=1000        # 10%

# Default interest rate parameters (USDC)
DEFAULT_QUOTE_BASE_RATE=200              # 2%
DEFAULT_QUOTE_OPTIMAL_UTIL=8000          # 80%
DEFAULT_QUOTE_SLOPE1=1000                # 10%
DEFAULT_QUOTE_SLOPE2=5000                # 50%

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load quote currency configuration from environment variables
# Sets defaults if not provided
load_quote_currency_config() {
    echo "📋 Loading quote currency configuration..."

    # Core configuration
    export QUOTE_CURRENCY="${QUOTE_CURRENCY:-$DEFAULT_QUOTE_CURRENCY}"
    export QUOTE_DECIMALS="${QUOTE_DECIMALS:-$DEFAULT_QUOTE_DECIMALS}"
    export QUOTE_SYMBOL="${QUOTE_SYMBOL:-$QUOTE_CURRENCY}"
    export QUOTE_NAME="${QUOTE_NAME:-$DEFAULT_QUOTE_NAME}"

    # Lending parameters
    export QUOTE_COLLATERAL_FACTOR="${QUOTE_COLLATERAL_FACTOR:-$DEFAULT_QUOTE_COLLATERAL_FACTOR}"
    export QUOTE_LIQUIDATION_THRESHOLD="${QUOTE_LIQUIDATION_THRESHOLD:-$DEFAULT_QUOTE_LIQUIDATION_THRESHOLD}"
    export QUOTE_LIQUIDATION_BONUS="${QUOTE_LIQUIDATION_BONUS:-$DEFAULT_QUOTE_LIQUIDATION_BONUS}"
    export QUOTE_RESERVE_FACTOR="${QUOTE_RESERVE_FACTOR:-$DEFAULT_QUOTE_RESERVE_FACTOR}"

    # Interest rate parameters
    export QUOTE_BASE_RATE="${QUOTE_BASE_RATE:-$DEFAULT_QUOTE_BASE_RATE}"
    export QUOTE_OPTIMAL_UTIL="${QUOTE_OPTIMAL_UTIL:-$DEFAULT_QUOTE_OPTIMAL_UTIL}"
    export QUOTE_SLOPE1="${QUOTE_SLOPE1:-$DEFAULT_QUOTE_SLOPE1}"
    export QUOTE_SLOPE2="${QUOTE_SLOPE2:-$DEFAULT_QUOTE_SLOPE2}"

    # Validate configuration
    if ! validate_quote_currency_config; then
        echo -e "${RED}❌ Quote currency configuration validation failed${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ Quote currency configuration loaded:${NC}"
    echo "  Currency: $QUOTE_CURRENCY"
    echo "  Symbol: $QUOTE_SYMBOL"
    echo "  Decimals: $QUOTE_DECIMALS"
    echo "  Collateral Factor: $QUOTE_COLLATERAL_FACTOR ($(echo "scale=2; $QUOTE_COLLATERAL_FACTOR / 100" | bc)%)"
    echo "  Liquidation Threshold: $QUOTE_LIQUIDATION_THRESHOLD ($(echo "scale=2; $QUOTE_LIQUIDATION_THRESHOLD / 100" | bc)%)"
}

# Validate quote currency configuration
validate_quote_currency_config() {
    local errors=0

    # Validate decimals (must be between 0 and 18)
    if ! validate_quote_decimals "$QUOTE_DECIMALS"; then
        echo -e "${RED}❌ Invalid QUOTE_DECIMALS: $QUOTE_DECIMALS (must be 0-18)${NC}"
        errors=$((errors + 1))
    fi

    # Validate collateral factor (must be between 0 and 10000)
    if [[ $QUOTE_COLLATERAL_FACTOR -lt 0 || $QUOTE_COLLATERAL_FACTOR -gt 10000 ]]; then
        echo -e "${RED}❌ Invalid QUOTE_COLLATERAL_FACTOR: $QUOTE_COLLATERAL_FACTOR (must be 0-10000)${NC}"
        errors=$((errors + 1))
    fi

    # Validate liquidation threshold (must be >= collateral factor and <= 10000)
    if [[ $QUOTE_LIQUIDATION_THRESHOLD -lt $QUOTE_COLLATERAL_FACTOR || $QUOTE_LIQUIDATION_THRESHOLD -gt 10000 ]]; then
        echo -e "${RED}❌ Invalid QUOTE_LIQUIDATION_THRESHOLD: $QUOTE_LIQUIDATION_THRESHOLD (must be >= CF and <= 10000)${NC}"
        errors=$((errors + 1))
    fi

    # Validate liquidation bonus (must be between 0 and 5000)
    if [[ $QUOTE_LIQUIDATION_BONUS -lt 0 || $QUOTE_LIQUIDATION_BONUS -gt 5000 ]]; then
        echo -e "${RED}❌ Invalid QUOTE_LIQUIDATION_BONUS: $QUOTE_LIQUIDATION_BONUS (must be 0-5000)${NC}"
        errors=$((errors + 1))
    fi

    # Validate reserve factor (must be between 0 and 10000)
    if [[ $QUOTE_RESERVE_FACTOR -lt 0 || $QUOTE_RESERVE_FACTOR -gt 10000 ]]; then
        echo -e "${RED}❌ Invalid QUOTE_RESERVE_FACTOR: $QUOTE_RESERVE_FACTOR (must be 0-10000)${NC}"
        errors=$((errors + 1))
    fi

    # Validate symbol is not empty
    if [[ -z "$QUOTE_SYMBOL" ]]; then
        echo -e "${RED}❌ QUOTE_SYMBOL cannot be empty${NC}"
        errors=$((errors + 1))
    fi

    return $errors
}

# Validate quote decimals (0-18)
validate_quote_decimals() {
    local decimals=$1

    # Check if it's a number
    if ! [[ "$decimals" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Check range
    if [[ $decimals -lt 0 || $decimals -gt 18 ]]; then
        return 1
    fi

    return 0
}

# Get quote token key for JSON lookup
# Returns: USDC, IDRX, etc.
get_quote_token_key() {
    echo "$QUOTE_SYMBOL"
}

# Get synthetic quote token key for JSON lookup
# Returns: sxUSDC, sxIDRX, etc.
get_synthetic_quote_key() {
    echo "sx${QUOTE_SYMBOL}"
}

# Get pool key for JSON lookup
# Args: $1 = base symbol (e.g., WETH, WBTC)
# Returns: WETH_USDC_Pool, WBTC_IDRX_Pool, etc.
get_pool_key() {
    local base_symbol=$1
    echo "${base_symbol}_${QUOTE_SYMBOL}_Pool"
}

# Calculate quote amount with correct decimals
# Args: $1 = amount (e.g., 1000 for 1000 tokens)
# Returns: amount scaled to quote decimals
calculate_quote_amount() {
    local amount=$1
    local decimals=${QUOTE_DECIMALS}
    echo "$amount * 10^$decimals" | bc
}

# Get decimal multiplier for quote currency
# Returns: 10^QUOTE_DECIMALS
get_quote_decimal_multiplier() {
    echo "10^$QUOTE_DECIMALS" | bc
}

# Print quote currency configuration summary
print_quote_config() {
    echo ""
    echo "========================================="
    echo "Quote Currency Configuration"
    echo "========================================="
    echo "Currency:     $QUOTE_CURRENCY"
    echo "Symbol:       $QUOTE_SYMBOL"
    echo "Name:         $QUOTE_NAME"
    echo "Decimals:     $QUOTE_DECIMALS"
    echo ""
    echo "Lending Parameters:"
    echo "  Collateral Factor:        $QUOTE_COLLATERAL_FACTOR ($(echo "scale=2; $QUOTE_COLLATERAL_FACTOR / 100" | bc)%)"
    echo "  Liquidation Threshold:    $QUOTE_LIQUIDATION_THRESHOLD ($(echo "scale=2; $QUOTE_LIQUIDATION_THRESHOLD / 100" | bc)%)"
    echo "  Liquidation Bonus:        $QUOTE_LIQUIDATION_BONUS ($(echo "scale=2; $QUOTE_LIQUIDATION_BONUS / 100" | bc)%)"
    echo "  Reserve Factor:           $QUOTE_RESERVE_FACTOR ($(echo "scale=2; $QUOTE_RESERVE_FACTOR / 100" | bc)%)"
    echo ""
    echo "Interest Rate Parameters:"
    echo "  Base Rate:                $QUOTE_BASE_RATE ($(echo "scale=2; $QUOTE_BASE_RATE / 100" | bc)%)"
    echo "  Optimal Utilization:      $QUOTE_OPTIMAL_UTIL ($(echo "scale=2; $QUOTE_OPTIMAL_UTIL / 100" | bc)%)"
    echo "  Rate Slope 1:             $QUOTE_SLOPE1 ($(echo "scale=2; $QUOTE_SLOPE1 / 100" | bc)%)"
    echo "  Rate Slope 2:             $QUOTE_SLOPE2 ($(echo "scale=2; $QUOTE_SLOPE2 / 100" | bc)%)"
    echo "========================================="
    echo ""
}
