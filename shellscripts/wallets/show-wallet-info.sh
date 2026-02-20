#!/bin/bash

# Source quote currency configuration module
SCRIPT_DIR_EARLY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR_EARLY}/../lib/quote-currency-config.sh"

# Display comprehensive wallet information including balances and deposits
# Usage: ./shellscripts/show-wallet-info.sh [indices] [OPTIONS]
# Examples:
#   ./shellscripts/show-wallet-info.sh                     # Show info for all wallets (0-9)
#   ./shellscripts/show-wallet-info.sh 2,3,4               # Show info for specific wallets
#   ./shellscripts/show-wallet-info.sh 0-4                 # Show info for range (0,1,2,3,4)
#   ./shellscripts/show-wallet-info.sh --balances-only     # Show only token balances (no deposits)
#   ./shellscripts/show-wallet-info.sh --deposits-only     # Show only BalanceManager deposits
#   ./shellscripts/show-wallet-info.sh 2 --verbose         # Show verbose output with wei amounts

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
    # Crypto tokens
    WETH_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"WETH": "[^"]*"' | cut -d'"' -f4)
    QUOTE_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o "\"$QUOTE_TOKEN_KEY\": \"[^\"]*\"" | cut -d'"' -f4)
    WBTC_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"WBTC": "[^"]*"' | cut -d'"' -f4)

    # RWA tokens
    GOLD_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"GOLD": "[^"]*"' | cut -d'"' -f4)
    SILVER_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"SILVER": "[^"]*"' | cut -d'"' -f4)
    GOOGLE_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"GOOGLE": "[^"]*"' | cut -d'"' -f4)
    NVIDIA_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"NVIDIA": "[^"]*"' | cut -d'"' -f4)
    MNT_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"MNT": "[^"]*"' | cut -d'"' -f4)
    APPLE_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"APPLE": "[^"]*"' | cut -d'"' -f4)

    BALANCE_MANAGER_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"BalanceManager": "[^"]*"' | cut -d'"' -f4)
    LENDING_MANAGER_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"LendingManager": "[^"]*"' | cut -d'"' -f4)
else
    echo "Error: Deployments file not found at $DEPLOYMENTS_FILE"
    exit 1
fi

# Verify crypto token addresses (required)
if [ -z "$WETH_ADDRESS" ] || [ -z "$QUOTE_ADDRESS" ] || [ -z "$WBTC_ADDRESS" ]; then
    echo "Error: Could not find all crypto token addresses in deployments file"
    echo "  WETH: $WETH_ADDRESS"
    echo "  $QUOTE_SYMBOL: $QUOTE_ADDRESS"
    echo "  WBTC: $WBTC_ADDRESS"
    exit 1
fi

# RWA tokens are optional (may not be deployed yet)
RWA_TOKENS_AVAILABLE=false
if [ -n "$GOLD_ADDRESS" ] && [ -n "$SILVER_ADDRESS" ] && [ -n "$GOOGLE_ADDRESS" ] && \
   [ -n "$NVIDIA_ADDRESS" ] && [ -n "$MNT_ADDRESS" ] && [ -n "$APPLE_ADDRESS" ]; then
    RWA_TOKENS_AVAILABLE=true
fi

# Check if SEED_PHRASE is set
if [ -z "$SEED_PHRASE" ]; then
    echo "Error: SEED_PHRASE not found in .env file"
    exit 1
fi

# Token decimals (quote decimals loaded from config)
WETH_DECIMALS=18
WBTC_DECIMALS=8
GOLD_DECIMALS=18
SILVER_DECIMALS=18
GOOGLE_DECIMALS=18
NVIDIA_DECIMALS=18
MNT_DECIMALS=18
APPLE_DECIMALS=18

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
        echo "0.000000"
        return
    fi
    # Use Python with proper string handling for large numbers
    python3 -c "
amount = int('$amount')
decimals = int('$decimals')
result = amount / (10 ** decimals)
print('{:,.6f}'.format(result))
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

# Get BalanceManager deposit balance
get_deposit_balance() {
    local token_address=$1
    local wallet_address=$2
    local balance=$(cast call "$BALANCE_MANAGER_ADDRESS" "getBalance(address,address)(uint256)" "$wallet_address" "$token_address" --rpc-url "$RPC_URL" 2>/dev/null)
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
            echo "∞ (No Debt)"
        else
            # Divide by 1e18 to get actual value
            python3 -c "print('{:.4f}'.format(int('$hf_dec') / 1e18))"
        fi
    else
        echo "$hf"
    fi
}

# Get user debt for a specific token
get_user_debt() {
    local token_address=$1
    local wallet_address=$2
    if [ -z "$LENDING_MANAGER_ADDRESS" ]; then
        echo "0"
        return
    fi
    local debt=$(cast call "$LENDING_MANAGER_ADDRESS" "getUserDebt(address,address)(uint256)" "$wallet_address" "$token_address" --rpc-url "$RPC_URL" 2>/dev/null)
    if [ -z "$debt" ]; then
        echo "0"
    elif [[ "$debt" == 0x* ]]; then
        # Convert hex to decimal and strip scientific notation in brackets
        local dec=$(cast --to-dec "$debt" 2>/dev/null || echo "0")
        echo "$dec" | sed 's/ \[.*\]//'
    else
        # Strip scientific notation in brackets if present
        echo "$debt" | sed 's/ \[.*\]//'
    fi
}

# Get user position (supplied, borrowed, lastUpdate)
get_user_position() {
    local token_address=$1
    local wallet_address=$2
    if [ -z "$LENDING_MANAGER_ADDRESS" ]; then
        echo "0 0 0"
        return
    fi
    local position=$(cast call "$LENDING_MANAGER_ADDRESS" "getUserPosition(address,address)(uint256,uint256,uint256)" "$wallet_address" "$token_address" --rpc-url "$RPC_URL" 2>/dev/null)
    if [ -z "$position" ]; then
        echo "0 0 0"
    else
        # Parse the tuple output - cast returns values separated by newlines or spaces
        echo "$position" | tr '\n' ' '
    fi
}

# Parse command line arguments
INDICES_ARG=""
SHOW_BALANCES=true
SHOW_DEPOSITS=true
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --balances-only)
            SHOW_DEPOSITS=false
            shift
            ;;
        --deposits-only)
            SHOW_BALANCES=false
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: ./shellscripts/show-wallet-info.sh [indices] [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  indices          Wallet indices (0-9). Can be comma-separated or ranges."
            echo "                   Examples: 2,3,4 or 0-4 or 0,2-5,9"
            echo ""
            echo "  --balances-only  Show only token balances (skip BalanceManager deposits)"
            echo "  --deposits-only  Show only BalanceManager deposits (skip token balances)"
            echo "  --verbose, -v    Show verbose output including wei amounts"
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

echo "=============================================="
echo "  Wallet Information Display"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  Chain ID:    $CORE_CHAIN_ID"
echo "  RPC URL:     $RPC_URL"
echo "  RWA Tokens:  $RWA_TOKENS_AVAILABLE"
echo ""
echo "Querying Wallets: ${INDICES[*]}"
echo "=============================================="
echo ""

# Display wallet information
for i in "${INDICES[@]}"; do
    NAME="${WALLET_NAMES[$i]}"

    # Derive address for this wallet
    PRIVATE_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" $i 2>/dev/null)
    ADDRESS=$(cast wallet address "$PRIVATE_KEY" 2>/dev/null)

    echo "=============================================="
    printf "Wallet: %-15s (Index: %d)\n" "$NAME" "$i"
    echo "Address: $ADDRESS"
    echo "=============================================="
    echo ""

    # Show lending health if LendingManager is available
    if [ -n "$LENDING_MANAGER_ADDRESS" ]; then
        echo "Lending Health:"
        echo "----------------------------------------------"
        HEALTH_FACTOR=$(get_health_factor "$ADDRESS")
        printf "  Health Factor: %s\n" "$HEALTH_FACTOR"
        echo ""
    fi

    if [ "$SHOW_BALANCES" = true ]; then
        echo "Token Balances:"
        echo "----------------------------------------------"

        # Get native balance
        NATIVE_BALANCE=$(get_native_balance "$ADDRESS")
        NATIVE_READABLE=$(from_smallest_unit "$NATIVE_BALANCE" 18)
        printf "  %-10s %20s" "NATIVE:" "$NATIVE_READABLE"
        if [ "$VERBOSE" = true ]; then
            printf " (%s wei)" "$NATIVE_BALANCE"
        fi
        echo ""

        # Get quote currency balance
        QUOTE_BALANCE=$(get_erc20_balance "$QUOTE_ADDRESS" "$ADDRESS")
        QUOTE_READABLE=$(from_smallest_unit "$QUOTE_BALANCE" "$QUOTE_DECIMALS")
        printf "  %-10s %20s" "$QUOTE_SYMBOL:" "$QUOTE_READABLE"
        if [ "$VERBOSE" = true ]; then
            printf " (%s smallest units)" "$QUOTE_BALANCE"
        fi
        echo ""

        # Get WETH balance
        WETH_BALANCE=$(get_erc20_balance "$WETH_ADDRESS" "$ADDRESS")
        WETH_READABLE=$(from_smallest_unit "$WETH_BALANCE" "$WETH_DECIMALS")
        printf "  %-10s %20s" "WETH:" "$WETH_READABLE"
        if [ "$VERBOSE" = true ]; then
            printf " (%s smallest units)" "$WETH_BALANCE"
        fi
        echo ""

        # Get WBTC balance
        WBTC_BALANCE=$(get_erc20_balance "$WBTC_ADDRESS" "$ADDRESS")
        WBTC_READABLE=$(from_smallest_unit "$WBTC_BALANCE" "$WBTC_DECIMALS")
        printf "  %-10s %20s" "WBTC:" "$WBTC_READABLE"
        if [ "$VERBOSE" = true ]; then
            printf " (%s smallest units)" "$WBTC_BALANCE"
        fi
        echo ""

        # Get RWA token balances if available
        if [ "$RWA_TOKENS_AVAILABLE" = true ]; then
            echo ""
            echo "  RWA Token Balances:"
            echo "  ----------------------------------------"

            GOLD_BALANCE=$(get_erc20_balance "$GOLD_ADDRESS" "$ADDRESS")
            GOLD_READABLE=$(from_smallest_unit "$GOLD_BALANCE" "$GOLD_DECIMALS")
            printf "  %-10s %20s" "GOLD:" "$GOLD_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$GOLD_BALANCE"
            fi
            echo ""

            SILVER_BALANCE=$(get_erc20_balance "$SILVER_ADDRESS" "$ADDRESS")
            SILVER_READABLE=$(from_smallest_unit "$SILVER_BALANCE" "$SILVER_DECIMALS")
            printf "  %-10s %20s" "SILVER:" "$SILVER_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$SILVER_BALANCE"
            fi
            echo ""

            GOOGLE_BALANCE=$(get_erc20_balance "$GOOGLE_ADDRESS" "$ADDRESS")
            GOOGLE_READABLE=$(from_smallest_unit "$GOOGLE_BALANCE" "$GOOGLE_DECIMALS")
            printf "  %-10s %20s" "GOOGLE:" "$GOOGLE_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$GOOGLE_BALANCE"
            fi
            echo ""

            NVIDIA_BALANCE=$(get_erc20_balance "$NVIDIA_ADDRESS" "$ADDRESS")
            NVIDIA_READABLE=$(from_smallest_unit "$NVIDIA_BALANCE" "$NVIDIA_DECIMALS")
            printf "  %-10s %20s" "NVIDIA:" "$NVIDIA_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$NVIDIA_BALANCE"
            fi
            echo ""

            MNT_BALANCE=$(get_erc20_balance "$MNT_ADDRESS" "$ADDRESS")
            MNT_READABLE=$(from_smallest_unit "$MNT_BALANCE" "$MNT_DECIMALS")
            printf "  %-10s %20s" "MNT:" "$MNT_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$MNT_BALANCE"
            fi
            echo ""

            APPLE_BALANCE=$(get_erc20_balance "$APPLE_ADDRESS" "$ADDRESS")
            APPLE_READABLE=$(from_smallest_unit "$APPLE_BALANCE" "$APPLE_DECIMALS")
            printf "  %-10s %20s" "APPLE:" "$APPLE_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$APPLE_BALANCE"
            fi
            echo ""
        fi

        echo ""
    fi

    if [ "$SHOW_DEPOSITS" = true ]; then
        if [ -n "$BALANCE_MANAGER_ADDRESS" ]; then
            echo "BalanceManager Deposits:"
            echo "----------------------------------------------"

            # Get deposit balances
            QUOTE_DEPOSIT=$(get_deposit_balance "$QUOTE_ADDRESS" "$ADDRESS")
            QUOTE_DEPOSIT_READABLE=$(from_smallest_unit "$QUOTE_DEPOSIT" "$QUOTE_DECIMALS")
            printf "  %-10s %20s" "$QUOTE_SYMBOL:" "$QUOTE_DEPOSIT_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$QUOTE_DEPOSIT"
            fi
            echo ""

            WETH_DEPOSIT=$(get_deposit_balance "$WETH_ADDRESS" "$ADDRESS")
            WETH_DEPOSIT_READABLE=$(from_smallest_unit "$WETH_DEPOSIT" "$WETH_DECIMALS")
            printf "  %-10s %20s" "WETH:" "$WETH_DEPOSIT_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$WETH_DEPOSIT"
            fi
            echo ""

            WBTC_DEPOSIT=$(get_deposit_balance "$WBTC_ADDRESS" "$ADDRESS")
            WBTC_DEPOSIT_READABLE=$(from_smallest_unit "$WBTC_DEPOSIT" "$WBTC_DECIMALS")
            printf "  %-10s %20s" "WBTC:" "$WBTC_DEPOSIT_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$WBTC_DEPOSIT"
            fi
            echo ""

            # Get RWA deposit balances if available
            if [ "$RWA_TOKENS_AVAILABLE" = true ]; then
                echo ""
                echo "  RWA Token Deposits:"
                echo "  ----------------------------------------"

                GOLD_DEPOSIT=$(get_deposit_balance "$GOLD_ADDRESS" "$ADDRESS")
                GOLD_DEPOSIT_READABLE=$(from_smallest_unit "$GOLD_DEPOSIT" "$GOLD_DECIMALS")
                printf "  %-10s %20s" "GOLD:" "$GOLD_DEPOSIT_READABLE"
                if [ "$VERBOSE" = true ]; then
                    printf " (%s smallest units)" "$GOLD_DEPOSIT"
                fi
                echo ""

                SILVER_DEPOSIT=$(get_deposit_balance "$SILVER_ADDRESS" "$ADDRESS")
                SILVER_DEPOSIT_READABLE=$(from_smallest_unit "$SILVER_DEPOSIT" "$SILVER_DECIMALS")
                printf "  %-10s %20s" "SILVER:" "$SILVER_DEPOSIT_READABLE"
                if [ "$VERBOSE" = true ]; then
                    printf " (%s smallest units)" "$SILVER_DEPOSIT"
                fi
                echo ""

                GOOGLE_DEPOSIT=$(get_deposit_balance "$GOOGLE_ADDRESS" "$ADDRESS")
                GOOGLE_DEPOSIT_READABLE=$(from_smallest_unit "$GOOGLE_DEPOSIT" "$GOOGLE_DECIMALS")
                printf "  %-10s %20s" "GOOGLE:" "$GOOGLE_DEPOSIT_READABLE"
                if [ "$VERBOSE" = true ]; then
                    printf " (%s smallest units)" "$GOOGLE_DEPOSIT"
                fi
                echo ""

                NVIDIA_DEPOSIT=$(get_deposit_balance "$NVIDIA_ADDRESS" "$ADDRESS")
                NVIDIA_DEPOSIT_READABLE=$(from_smallest_unit "$NVIDIA_DEPOSIT" "$NVIDIA_DECIMALS")
                printf "  %-10s %20s" "NVIDIA:" "$NVIDIA_DEPOSIT_READABLE"
                if [ "$VERBOSE" = true ]; then
                    printf " (%s smallest units)" "$NVIDIA_DEPOSIT"
                fi
                echo ""

                MNT_DEPOSIT=$(get_deposit_balance "$MNT_ADDRESS" "$ADDRESS")
                MNT_DEPOSIT_READABLE=$(from_smallest_unit "$MNT_DEPOSIT" "$MNT_DECIMALS")
                printf "  %-10s %20s" "MNT:" "$MNT_DEPOSIT_READABLE"
                if [ "$VERBOSE" = true ]; then
                    printf " (%s smallest units)" "$MNT_DEPOSIT"
                fi
                echo ""

                APPLE_DEPOSIT=$(get_deposit_balance "$APPLE_ADDRESS" "$ADDRESS")
                APPLE_DEPOSIT_READABLE=$(from_smallest_unit "$APPLE_DEPOSIT" "$APPLE_DECIMALS")
                printf "  %-10s %20s" "APPLE:" "$APPLE_DEPOSIT_READABLE"
                if [ "$VERBOSE" = true ]; then
                    printf " (%s smallest units)" "$APPLE_DEPOSIT"
                fi
                echo ""
            fi

            echo ""
        else
            echo "BalanceManager: Not deployed"
            echo ""
        fi
    fi

    # Show lending positions if LendingManager is available
    if [ -n "$LENDING_MANAGER_ADDRESS" ]; then
        echo "Lending Positions (Debt):"
        echo "----------------------------------------------"

        # Get debt for crypto tokens
        QUOTE_DEBT=$(get_user_debt "$QUOTE_ADDRESS" "$ADDRESS")
        QUOTE_DEBT_READABLE=$(from_smallest_unit "$QUOTE_DEBT" "$QUOTE_DECIMALS")
        printf "  %-10s %20s" "$QUOTE_SYMBOL:" "$QUOTE_DEBT_READABLE"
        if [ "$VERBOSE" = true ]; then
            printf " (%s smallest units)" "$QUOTE_DEBT"
        fi
        echo ""

        WETH_DEBT=$(get_user_debt "$WETH_ADDRESS" "$ADDRESS")
        WETH_DEBT_READABLE=$(from_smallest_unit "$WETH_DEBT" "$WETH_DECIMALS")
        printf "  %-10s %20s" "WETH:" "$WETH_DEBT_READABLE"
        if [ "$VERBOSE" = true ]; then
            printf " (%s smallest units)" "$WETH_DEBT"
        fi
        echo ""

        WBTC_DEBT=$(get_user_debt "$WBTC_ADDRESS" "$ADDRESS")
        WBTC_DEBT_READABLE=$(from_smallest_unit "$WBTC_DEBT" "$WBTC_DECIMALS")
        printf "  %-10s %20s" "WBTC:" "$WBTC_DEBT_READABLE"
        if [ "$VERBOSE" = true ]; then
            printf " (%s smallest units)" "$WBTC_DEBT"
        fi
        echo ""

        # Get RWA debt if available
        if [ "$RWA_TOKENS_AVAILABLE" = true ]; then
            echo ""
            echo "  RWA Token Debt:"
            echo "  ----------------------------------------"

            GOLD_DEBT=$(get_user_debt "$GOLD_ADDRESS" "$ADDRESS")
            GOLD_DEBT_READABLE=$(from_smallest_unit "$GOLD_DEBT" "$GOLD_DECIMALS")
            printf "  %-10s %20s" "GOLD:" "$GOLD_DEBT_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$GOLD_DEBT"
            fi
            echo ""

            SILVER_DEBT=$(get_user_debt "$SILVER_ADDRESS" "$ADDRESS")
            SILVER_DEBT_READABLE=$(from_smallest_unit "$SILVER_DEBT" "$SILVER_DECIMALS")
            printf "  %-10s %20s" "SILVER:" "$SILVER_DEBT_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$SILVER_DEBT"
            fi
            echo ""

            GOOGLE_DEBT=$(get_user_debt "$GOOGLE_ADDRESS" "$ADDRESS")
            GOOGLE_DEBT_READABLE=$(from_smallest_unit "$GOOGLE_DEBT" "$GOOGLE_DECIMALS")
            printf "  %-10s %20s" "GOOGLE:" "$GOOGLE_DEBT_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$GOOGLE_DEBT"
            fi
            echo ""

            NVIDIA_DEBT=$(get_user_debt "$NVIDIA_ADDRESS" "$ADDRESS")
            NVIDIA_DEBT_READABLE=$(from_smallest_unit "$NVIDIA_DEBT" "$NVIDIA_DECIMALS")
            printf "  %-10s %20s" "NVIDIA:" "$NVIDIA_DEBT_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$NVIDIA_DEBT"
            fi
            echo ""

            MNT_DEBT=$(get_user_debt "$MNT_ADDRESS" "$ADDRESS")
            MNT_DEBT_READABLE=$(from_smallest_unit "$MNT_DEBT" "$MNT_DECIMALS")
            printf "  %-10s %20s" "MNT:" "$MNT_DEBT_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$MNT_DEBT"
            fi
            echo ""

            APPLE_DEBT=$(get_user_debt "$APPLE_ADDRESS" "$ADDRESS")
            APPLE_DEBT_READABLE=$(from_smallest_unit "$APPLE_DEBT" "$APPLE_DECIMALS")
            printf "  %-10s %20s" "APPLE:" "$APPLE_DEBT_READABLE"
            if [ "$VERBOSE" = true ]; then
                printf " (%s smallest units)" "$APPLE_DEBT"
            fi
            echo ""
        fi

        echo ""
    fi

    echo ""
done

echo "=============================================="
echo "  Query Complete"
echo "=============================================="
