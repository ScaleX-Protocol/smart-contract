#!/bin/bash

# List all wallet addresses derived from seed phrase
# Usage: ./shellscripts/list-wallets.sh [indices]
# Examples:
#   ./shellscripts/list-wallets.sh           # List all wallets (0-9)
#   ./shellscripts/list-wallets.sh 2,3,4     # List specific wallets
#   ./shellscripts/list-wallets.sh 0-4       # List range (0,1,2,3,4)

# Add foundry to PATH
export PATH="$HOME/.foundry/bin:$PATH"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# Parse .env file manually to avoid issues with special characters
if [ -f "$ENV_FILE" ]; then
    SEED_PHRASE=$(grep "^SEED_PHRASE=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    WALLET_INDICES=$(grep "^WALLET_INDICES=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
fi

# Check if SEED_PHRASE is set
if [ -z "$SEED_PHRASE" ]; then
    echo "Error: SEED_PHRASE not found in .env file"
    exit 1
fi

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

# Parse command line arguments
INDICES_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: ./shellscripts/list-wallets.sh [indices]"
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

# Get indices to list (CLI arg takes priority, then env, then default all)
if [ -n "$INDICES_ARG" ]; then
    INDICES=($(parse_indices "$INDICES_ARG"))
elif [ -n "$WALLET_INDICES" ]; then
    INDICES=($(parse_indices "$WALLET_INDICES"))
else
    INDICES=($(parse_indices ""))
fi

echo "=============================================="
echo "  Wallet Address List"
echo "=============================================="
echo ""

# List wallet addresses
for i in "${INDICES[@]}"; do
    NAME="${WALLET_NAMES[$i]}"

    # Derive address for this wallet
    PRIVATE_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" $i 2>/dev/null)
    ADDRESS=$(cast wallet address "$PRIVATE_KEY" 2>/dev/null)

    printf "%d  %-15s  %s\n" "$i" "$NAME" "$ADDRESS"
done

echo ""
echo "=============================================="
