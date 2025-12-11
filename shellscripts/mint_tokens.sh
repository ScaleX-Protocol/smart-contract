#!/bin/bash

# Mint USDC, WETH, and WBTC tokens to wallet addresses from seed phrase
# Usage: ./shellscripts/mint_tokens.sh [indices] [--usdc AMOUNT] [--weth AMOUNT] [--wbtc AMOUNT]
# Examples:
#   ./shellscripts/mint_tokens.sh                     # Mint default amounts to all wallets (0-9)
#   ./shellscripts/mint_tokens.sh 2,3,4               # Mint to specific wallets
#   ./shellscripts/mint_tokens.sh 0-4                 # Mint to range (0,1,2,3,4)
#   ./shellscripts/mint_tokens.sh 0,2-5 --usdc 10000  # Mint 10000 USDC to selected wallets
#   ./shellscripts/mint_tokens.sh --weth 100 --wbtc 5 # Mint specific amounts to all wallets

# Add foundry to PATH
export PATH="$HOME/.foundry/bin:$PATH"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

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
DEPLOYMENTS_FILE="$SCRIPT_DIR/../deployments/${CORE_CHAIN_ID}.json"
if [ -f "$DEPLOYMENTS_FILE" ]; then
    WETH_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"WETH": "[^"]*"' | cut -d'"' -f4)
    USDC_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"USDC": "[^"]*"' | cut -d'"' -f4)
    WBTC_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"WBTC": "[^"]*"' | cut -d'"' -f4)
else
    echo "Error: Deployments file not found at $DEPLOYMENTS_FILE"
    exit 1
fi

# Verify token addresses
if [ -z "$WETH_ADDRESS" ] || [ -z "$USDC_ADDRESS" ] || [ -z "$WBTC_ADDRESS" ]; then
    echo "Error: Could not find all token addresses in deployments file"
    echo "  WETH: $WETH_ADDRESS"
    echo "  USDC: $USDC_ADDRESS"
    echo "  WBTC: $WBTC_ADDRESS"
    exit 1
fi

# Check if SEED_PHRASE is set
if [ -z "$SEED_PHRASE" ]; then
    echo "Error: SEED_PHRASE not found in .env file"
    exit 1
fi

# Default mint amounts (in human-readable units)
DEFAULT_USDC_AMOUNT=100000    # 100,000 USDC
DEFAULT_WETH_AMOUNT=100       # 100 WETH
DEFAULT_WBTC_AMOUNT=10        # 10 WBTC

# Token decimals
USDC_DECIMALS=6
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

# Convert human-readable amount to wei/smallest unit
to_smallest_unit() {
    local amount=$1
    local decimals=$2
    python3 -c "print(int($amount * (10 ** $decimals)))"
}

# Parse command line arguments
USDC_AMOUNT=$DEFAULT_USDC_AMOUNT
WETH_AMOUNT=$DEFAULT_WETH_AMOUNT
WBTC_AMOUNT=$DEFAULT_WBTC_AMOUNT
INDICES_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --usdc)
            USDC_AMOUNT="$2"
            shift 2
            ;;
        --weth)
            WETH_AMOUNT="$2"
            shift 2
            ;;
        --wbtc)
            WBTC_AMOUNT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: ./shellscripts/mint_tokens.sh [indices] [--usdc AMOUNT] [--weth AMOUNT] [--wbtc AMOUNT]"
            echo ""
            echo "Options:"
            echo "  indices          Wallet indices (0-9). Can be comma-separated or ranges."
            echo "                   Examples: 2,3,4 or 0-4 or 0,2-5,9"
            echo "  --usdc AMOUNT    Amount of USDC to mint (default: $DEFAULT_USDC_AMOUNT)"
            echo "  --weth AMOUNT    Amount of WETH to mint (default: $DEFAULT_WETH_AMOUNT)"
            echo "  --wbtc AMOUNT    Amount of WBTC to mint (default: $DEFAULT_WBTC_AMOUNT)"
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

# Get indices to mint to (CLI arg takes priority, then env, then default all)
if [ -n "$INDICES_ARG" ]; then
    INDICES=($(parse_indices "$INDICES_ARG"))
elif [ -n "$WALLET_INDICES" ]; then
    INDICES=($(parse_indices "$WALLET_INDICES"))
else
    INDICES=($(parse_indices ""))
fi

# Convert amounts to smallest units
USDC_AMOUNT_WEI=$(to_smallest_unit $USDC_AMOUNT $USDC_DECIMALS)
WETH_AMOUNT_WEI=$(to_smallest_unit $WETH_AMOUNT $WETH_DECIMALS)
WBTC_AMOUNT_WEI=$(to_smallest_unit $WBTC_AMOUNT $WBTC_DECIMALS)

# Get private key for first wallet (index 0) to send transactions
SENDER_PRIVATE_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" 0 2>/dev/null)
SENDER_ADDRESS=$(cast wallet address "$SENDER_PRIVATE_KEY" 2>/dev/null)

echo "=============================================="
echo "  Token Minting Script"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  Chain ID:    $CORE_CHAIN_ID"
echo "  RPC URL:     $RPC_URL"
echo "  Sender:      $SENDER_ADDRESS"
echo ""
echo "Token Addresses:"
echo "  USDC:        $USDC_ADDRESS"
echo "  WETH:        $WETH_ADDRESS"
echo "  WBTC:        $WBTC_ADDRESS"
echo ""
echo "Mint Amounts:"
echo "  USDC:        $USDC_AMOUNT ($USDC_AMOUNT_WEI smallest units)"
echo "  WETH:        $WETH_AMOUNT ($WETH_AMOUNT_WEI smallest units)"
echo "  WBTC:        $WBTC_AMOUNT ($WBTC_AMOUNT_WEI smallest units)"
echo ""
echo "Target Wallets: ${INDICES[*]}"
echo "=============================================="
echo ""

# Mint tokens to each wallet
for i in "${INDICES[@]}"; do
    NAME="${WALLET_NAMES[$i]}"

    # Derive address for this wallet
    PRIVATE_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" $i 2>/dev/null)
    ADDRESS=$(cast wallet address "$PRIVATE_KEY" 2>/dev/null)

    echo "----------------------------------------------"
    printf "Minting to: %-15s (Index: %d)\n" "$NAME" "$i"
    echo "Address: $ADDRESS"
    echo "----------------------------------------------"

    # Mint USDC
    echo -n "  Minting $USDC_AMOUNT USDC... "
    TX_USDC=$(cast send "$USDC_ADDRESS" "mint(address,uint256)" "$ADDRESS" "$USDC_AMOUNT_WEI" \
        --private-key "$SENDER_PRIVATE_KEY" \
        --rpc-url "$RPC_URL" 2>&1)
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "FAILED"
        echo "    Error: $TX_USDC"
    fi

    # Mint WETH
    echo -n "  Minting $WETH_AMOUNT WETH... "
    TX_WETH=$(cast send "$WETH_ADDRESS" "mint(address,uint256)" "$ADDRESS" "$WETH_AMOUNT_WEI" \
        --private-key "$SENDER_PRIVATE_KEY" \
        --rpc-url "$RPC_URL" 2>&1)
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "FAILED"
        echo "    Error: $TX_WETH"
    fi

    # Mint WBTC
    echo -n "  Minting $WBTC_AMOUNT WBTC... "
    TX_WBTC=$(cast send "$WBTC_ADDRESS" "mint(address,uint256)" "$ADDRESS" "$WBTC_AMOUNT_WEI" \
        --private-key "$SENDER_PRIVATE_KEY" \
        --rpc-url "$RPC_URL" 2>&1)
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "FAILED"
        echo "    Error: $TX_WBTC"
    fi

    echo ""
done

echo "=============================================="
echo "  Minting Complete"
echo "=============================================="
