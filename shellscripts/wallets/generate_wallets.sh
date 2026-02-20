#!/bin/bash

# Generate wallet addresses from seed phrase
# Usage: ./shellscripts/generate_wallets.sh [indices]
# Examples:
#   ./shellscripts/generate_wallets.sh           # Display all wallets (0-9)
#   ./shellscripts/generate_wallets.sh 2,3,4,5,7 # Display specific wallets
#   ./shellscripts/generate_wallets.sh 0-4       # Display range (0,1,2,3,4)
#   ./shellscripts/generate_wallets.sh 0,2-5,9   # Mix of indices and ranges

# Add foundry to PATH
export PATH="$HOME/.foundry/bin:$PATH"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../.env"

# Parse .env file manually to avoid issues with special characters
if [ -f "$ENV_FILE" ]; then
    SEED_PHRASE=$(grep "^SEED_PHRASE=" "$ENV_FILE" | cut -d'=' -f2-)
    RPC_URL=$(grep "^SCALEX_CORE_RPC=" "$ENV_FILE" | cut -d'=' -f2-)
    CORE_CHAIN_ID=$(grep "^CORE_CHAIN_ID=" "$ENV_FILE" | cut -d'=' -f2-)
    WALLET_INDICES=$(grep "^WALLET_INDICES=" "$ENV_FILE" | cut -d'=' -f2-)
fi

# Default RPC if not found
if [ -z "$RPC_URL" ]; then
    RPC_URL="https://sepolia.base.org"
fi

# Default chain ID
if [ -z "$CORE_CHAIN_ID" ]; then
    CORE_CHAIN_ID="84532"
fi

# Load token addresses from deployments
DEPLOYMENTS_FILE="$SCRIPT_DIR/../../deployments/${CORE_CHAIN_ID}.json"
if [ -f "$DEPLOYMENTS_FILE" ]; then
    WETH_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"WETH": "[^"]*"' | cut -d'"' -f4)
    USDC_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"USDC": "[^"]*"' | cut -d'"' -f4)
fi

# Fallback addresses for Base Sepolia
if [ -z "$WETH_ADDRESS" ]; then
    WETH_ADDRESS="0xCf6c841Fe5aeE3ddeEEb87dEff52cCf72E4649Ad"
fi
if [ -z "$USDC_ADDRESS" ]; then
    USDC_ADDRESS="0x44E9F25DCC735fCeABc6c784046722BcA5bBCcB5"
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

# Get indices to display (CLI arg takes priority, then env, then default all)
if [ -n "$1" ]; then
    INDICES=($(parse_indices "$1"))
elif [ -n "$WALLET_INDICES" ]; then
    INDICES=($(parse_indices "$WALLET_INDICES"))
else
    INDICES=($(parse_indices ""))
fi

echo "=============================================="
echo "  Wallet Information"
echo "=============================================="
echo ""
echo "Fetching on-chain balances and deposited balances..."
echo ""

# First, fetch deposited balances from indexer (single request for selected addresses)
USER_LIST=""
for i in "${INDICES[@]}"; do
    PRIVATE_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" $i 2>/dev/null)
    ADDRESS=$(cast wallet address "$PRIVATE_KEY" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [ -n "$USER_LIST" ]; then
        USER_LIST="${USER_LIST}, "
    fi
    USER_LIST="${USER_LIST}\\\"${ADDRESS}\\\""
done

INDEXER_URL="https://base-sepolia-indexer.scalex.money/"

# Fetch balances
BALANCES_QUERY="{ balancess(where: { user_in: [${USER_LIST}] }, limit: 100) { items { user amount lockedAmount currency { symbol decimals } } } }"
BALANCES_RESPONSE=$(curl -s -X POST "$INDEXER_URL" -H "Content-Type: application/json" -d "{\"query\": \"$BALANCES_QUERY\"}" 2>/dev/null)


# Now display all wallet information in a single pass
for i in "${INDICES[@]}"; do
    NAME="${WALLET_NAMES[$i]}"

    # Derive private key and address
    PRIVATE_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" $i 2>/dev/null)
    ADDRESS=$(cast wallet address "$PRIVATE_KEY" 2>/dev/null)
    ADDRESS_LOWER=$(echo "$ADDRESS" | tr '[:upper:]' '[:lower:]')

    # Get native balance (ETH)
    BALANCE_WEI=$(cast balance "$ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
    BALANCE_ETH=$(cast from-wei "$BALANCE_WEI" 2>/dev/null || echo "0")

    # Get WETH balance (18 decimals)
    WETH_BALANCE_HEX=$(cast call "$WETH_ADDRESS" "balanceOf(address)" "$ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0")
    WETH_BALANCE_WEI=$(cast --to-dec "$WETH_BALANCE_HEX" 2>/dev/null || echo "0")
    WETH_BALANCE=$(cast from-wei "$WETH_BALANCE_WEI" 2>/dev/null || echo "0")

    # Get USDC balance (6 decimals)
    USDC_BALANCE_HEX=$(cast call "$USDC_ADDRESS" "balanceOf(address)" "$ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0")
    USDC_BALANCE_RAW=$(cast --to-dec "$USDC_BALANCE_HEX" 2>/dev/null || echo "0")
    USDC_BALANCE=$(echo "scale=6; $USDC_BALANCE_RAW / 1000000" | bc 2>/dev/null || echo "0")

    # Display wallet info
    echo "----------------------------------------------"
    printf "%-15s | Index: %d\n" "$NAME" "$i"
    echo "----------------------------------------------"
    echo "  Address:     $ADDRESS"
    echo "  Private Key: $PRIVATE_KEY"
    echo ""
    echo "  On-Chain Balances:"
    echo "    ETH:       $BALANCE_ETH"
    echo "    WETH:      $WETH_BALANCE"
    echo "    USDC:      $USDC_BALANCE"
    echo ""

    # Parse and display deposited balances for this user
    echo "$BALANCES_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('balancess', {}).get('items', [])
user_items = [item for item in items if item['user'].lower() == '${ADDRESS_LOWER}']
if not user_items:
    print('  Deposited Balances: None')
else:
    print('  Deposited Balances:')
    for item in sorted(user_items, key=lambda x: x['currency']['symbol']):
        symbol = item['currency']['symbol']
        decimals = item['currency']['decimals']
        amount = int(item['amount']) if item['amount'] else 0
        locked = int(item['lockedAmount']) if item['lockedAmount'] else 0
        available = amount / (10 ** decimals)
        locked_fmt = locked / (10 ** decimals)
        print(f'    {symbol:8} Available: {available:>20,.6f}  Locked: {locked_fmt:>20,.6f}')
" 2>/dev/null || echo "  Deposited Balances: Error fetching"

    # Fetch order counts per status for this user (using totalCount for accuracy)
    OPEN_COUNT=$(curl -s -X POST "$INDEXER_URL" -H "Content-Type: application/json" -d "{\"query\": \"{ orderss(where: { user: \\\"${ADDRESS_LOWER}\\\", status: \\\"OPEN\\\" }) { totalCount } }\"}" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('orderss',{}).get('totalCount',0))" 2>/dev/null || echo "0")
    FILLED_COUNT=$(curl -s -X POST "$INDEXER_URL" -H "Content-Type: application/json" -d "{\"query\": \"{ orderss(where: { user: \\\"${ADDRESS_LOWER}\\\", status: \\\"FILLED\\\" }) { totalCount } }\"}" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('orderss',{}).get('totalCount',0))" 2>/dev/null || echo "0")
    CANCELLED_COUNT=$(curl -s -X POST "$INDEXER_URL" -H "Content-Type: application/json" -d "{\"query\": \"{ orderss(where: { user: \\\"${ADDRESS_LOWER}\\\", status: \\\"CANCELLED\\\" }) { totalCount } }\"}" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('orderss',{}).get('totalCount',0))" 2>/dev/null || echo "0")

    echo ""
    echo "  Orders:"
    echo "    Open: $OPEN_COUNT  |  Filled: $FILLED_COUNT  |  Cancelled: $CANCELLED_COUNT"
    echo ""
done

echo "=============================================="
echo "  Complete"
echo "=============================================="
