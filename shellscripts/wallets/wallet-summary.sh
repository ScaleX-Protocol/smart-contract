#!/bin/bash

# Source quote currency configuration module
SCRIPT_DIR_EARLY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR_EARLY}/../lib/quote-currency-config.sh"

# Display quick summary of wallet balances (native, quote, WETH, WBTC)
# Usage: ./shellscripts/wallet-summary.sh [indices]
# Examples:
#   ./shellscripts/wallet-summary.sh           # Summary for all wallets (0-9)
#   ./shellscripts/wallet-summary.sh 2,3,4     # Summary for specific wallets
#   ./shellscripts/wallet-summary.sh 0-4       # Summary for range (0,1,2,3,4)

# Add foundry to PATH
export PATH="$HOME/.foundry/bin:$PATH"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../.env"

# Parse .env file manually to avoid issues with special characters
if [ -f "$ENV_FILE" ]; then
    SEED_PHRASE=$(grep "^SEED_PHRASE=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    RPC_URL=$(grep "^SCALEX_CORE_RPC=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    CORE_CHAIN_ID=$(grep "^CORE_CHAIN_ID=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    WALLET_INDICES=$(grep "^WALLET_INDICES=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")

    # Load quote currency configuration from .env
    export QUOTE_CURRENCY=$(grep "^QUOTE_CURRENCY=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    export QUOTE_SYMBOL=$(grep "^QUOTE_SYMBOL=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    export QUOTE_DECIMALS=$(grep "^QUOTE_DECIMALS=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
fi

# Default RPC if not found
if [ -z "$RPC_URL" ]; then
    RPC_URL="https://sepolia.base.org"
fi

# Default chain ID
if [ -z "$CORE_CHAIN_ID" ]; then
    CORE_CHAIN_ID="84532"
fi

# Load quote currency configuration
load_quote_currency_config
QUOTE_TOKEN_KEY=$(get_quote_token_key)

# Load token addresses from deployments
DEPLOYMENTS_FILE="$SCRIPT_DIR/../../deployments/${CORE_CHAIN_ID}.json"
if [ -f "$DEPLOYMENTS_FILE" ]; then
    WETH_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"WETH": "[^"]*"' | cut -d'"' -f4)
    QUOTE_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o "\"$QUOTE_TOKEN_KEY\": \"[^\"]*\"" | cut -d'"' -f4)
    WBTC_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"WBTC": "[^"]*"' | cut -d'"' -f4)
    LENDING_MANAGER_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"LendingManager": "[^"]*"' | cut -d'"' -f4)
else
    echo "Error: Deployments file not found at $DEPLOYMENTS_FILE"
    exit 1
fi

# Verify token addresses
if [ -z "$WETH_ADDRESS" ] || [ -z "$QUOTE_ADDRESS" ] || [ -z "$WBTC_ADDRESS" ]; then
    echo "Error: Could not find all crypto token addresses in deployments file"
    exit 1
fi

# Check if SEED_PHRASE is set
if [ -z "$SEED_PHRASE" ]; then
    echo "Error: SEED_PHRASE not found in .env file"
    exit 1
fi

# Token decimals
WETH_DECIMALS=18
WBTC_DECIMALS=8

# Wallet names mapping (index -> name)
declare -a WALLET_NAMES=(
    "Scalex 1"
    "Scalex 2"
    "MM Bot"
    "Trading Bot 1"
    "Trading Bot 2"
    "Trading Bot 3"
    "Faucet"
    "Trader 1"
    "Trader 2"
    "Trader 3"
)

# Parse indices argument
parse_indices() {
    local input="$1"
    local indices=()

    # If no input, return all indices 0-9
    if [ -z "$input" ]; then
        echo "0 1 2 3 4 5 6 7 8 9"
        return
    fi

    # Split by comma
    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        # Check if it's a range (contains -)
        if [[ "$part" == *-* ]]; then
            local start="${part%-*}"
            local end="${part#*-}"
            for ((i=start; i<=end; i++)); do
                if [ "$i" -ge 0 ] && [ "$i" -le 9 ]; then
                    indices+=("$i")
                fi
            done
        else
            # Single index
            if [ "$part" -ge 0 ] && [ "$part" -le 9 ] 2>/dev/null; then
                indices+=("$part")
            fi
        fi
    done

    # Remove duplicates and sort
    echo "${indices[@]}" | tr ' ' '\n' | sort -n | uniq | tr '\n' ' '
}

# Convert wei/smallest unit to human-readable amount
from_smallest_unit() {
    local amount=$1
    local decimals=$2
    # Handle empty or zero amounts
    if [ -z "$amount" ] || [ "$amount" = "0" ]; then
        echo "0.00"
        return
    fi
    # Use Python with proper string handling for large numbers
    python3 -c "
amount = int('$amount')
decimals = int('$decimals')
result = amount / (10 ** decimals)
print('{:,.2f}'.format(result))
"
}

# Get balance of native token
get_native_balance() {
    local address=$1
    local balance=$(cast balance "$address" --rpc-url "$RPC_URL" 2>/dev/null)
    # cast balance returns decimal, just echo it
    echo "${balance:-0}"
}

# Get balance of ERC20 token
get_erc20_balance() {
    local token_address=$1
    local wallet_address=$2
    local balance=$(cast call "$token_address" "balanceOf(address)(uint256)" "$wallet_address" --rpc-url "$RPC_URL" 2>/dev/null)
    # cast call returns hex (0x...) or decimal, convert to decimal using cast --to-dec
    if [ -z "$balance" ]; then
        echo "0"
    elif [[ "$balance" == 0x* ]]; then
        # Convert hex to decimal and strip scientific notation in brackets [1e22]
        local dec=$(cast --to-dec "$balance" 2>/dev/null || echo "0")
        echo "$dec" | sed 's/ \[.*\]//'
    else
        # Strip scientific notation in brackets if present
        echo "$balance" | sed 's/ \[.*\]//'
    fi
}

# Get health factor from LendingManager
get_health_factor() {
    local wallet_address=$1
    if [ -z "$LENDING_MANAGER_ADDRESS" ]; then
        echo "N/A"
        return
    fi
    local hf=$(cast call "$LENDING_MANAGER_ADDRESS" "getHealthFactor(address)(uint256)" "$wallet_address" --rpc-url "$RPC_URL" 2>/dev/null)
    # Health factor is returned with 1e18 precision
    if [ -z "$hf" ]; then
        echo "N/A"
    elif [[ "$hf" == 0x* ]]; then
        local hf_dec=$(cast --to-dec "$hf" 2>/dev/null || echo "0")
        # Strip scientific notation in brackets if present
        hf_dec=$(echo "$hf_dec" | sed 's/ \[.*\]//')
        # Check if it's max uint256 (no debt)
        if [ "$hf_dec" = "115792089237316195423570985008687907853269984665640564039457584007913129639935" ]; then
            echo "∞"
        else
            # Divide by 1e18 to get actual value
            python3 -c "print('{:.2f}'.format(int('$hf_dec') / 1e18))"
        fi
    else
        echo "$hf"
    fi
}

# Parse command line arguments
INDICES_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: ./shellscripts/wallet-summary.sh [indices]"
            echo ""
            echo "Shows a quick summary table of wallet balances"
            echo ""
            echo "Options:"
            echo "  indices          Wallet indices (0-9). Can be comma-separated or ranges."
            echo "                   Examples: 2,3,4 or 0-4 or 0,2-5,9"
            echo ""
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Wallet indices:"
            echo "  0: Scalex 1      5: Trading Bot 3"
            echo "  1: Scalex 2      6: Faucet"
            echo "  2: MM Bot        7: Trader 1"
            echo "  3: Trading Bot 1 8: Trader 2"
            echo "  4: Trading Bot 2 9: Trader 3"
            exit 0
            ;;
        *)
            # Assume it's indices if it looks like numbers/ranges
            if [[ "$1" =~ ^[0-9,\-]+$ ]]; then
                INDICES_ARG="$1"
            fi
            shift
            ;;
    esac
done

# Get indices to query (CLI arg takes priority, then env, then default all)
if [ -n "$INDICES_ARG" ]; then
    INDICES=($(parse_indices "$INDICES_ARG"))
elif [ -n "$WALLET_INDICES" ]; then
    INDICES=($(parse_indices "$WALLET_INDICES"))
else
    INDICES=($(parse_indices ""))
fi

echo "============================================================================================="
echo "  Wallet Balance Summary"
echo "============================================================================================="
echo ""
printf "%-3s %-15s %-13s %-13s %-13s %-13s %-12s\n" "IDX" "NAME" "NATIVE" "$QUOTE_SYMBOL" "WETH" "WBTC" "HEALTH"
echo "---------------------------------------------------------------------------------------------"

# Display wallet summary
for i in "${INDICES[@]}"; do
    NAME="${WALLET_NAMES[$i]}"

    # Derive address for this wallet
    PRIVATE_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" $i 2>/dev/null)
    ADDRESS=$(cast wallet address "$PRIVATE_KEY" 2>/dev/null)

    # Get balances
    NATIVE_BALANCE=$(get_native_balance "$ADDRESS")
    NATIVE_READABLE=$(from_smallest_unit "$NATIVE_BALANCE" 18)

    QUOTE_BALANCE=$(get_erc20_balance "$QUOTE_ADDRESS" "$ADDRESS")
    QUOTE_READABLE=$(from_smallest_unit "$QUOTE_BALANCE" "$QUOTE_DECIMALS")

    WETH_BALANCE=$(get_erc20_balance "$WETH_ADDRESS" "$ADDRESS")
    WETH_READABLE=$(from_smallest_unit "$WETH_BALANCE" "$WETH_DECIMALS")

    WBTC_BALANCE=$(get_erc20_balance "$WBTC_ADDRESS" "$ADDRESS")
    WBTC_READABLE=$(from_smallest_unit "$WBTC_BALANCE" "$WBTC_DECIMALS")

    HEALTH_FACTOR=$(get_health_factor "$ADDRESS")

    printf "%-3s %-15s %-13s %-13s %-13s %-13s %-12s\n" \
        "$i" "$NAME" "$NATIVE_READABLE" "$QUOTE_READABLE" "$WETH_READABLE" "$WBTC_READABLE" "$HEALTH_FACTOR"
done

echo "============================================================================================="
