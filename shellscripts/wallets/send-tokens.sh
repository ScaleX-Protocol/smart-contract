#!/bin/bash

# Source quote currency configuration module
SCRIPT_DIR_EARLY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR_EARLY}/../lib/quote-currency-config.sh"

# Mint/send quote currency, WETH, WBTC, and native tokens to wallet addresses from seed phrase
# Optionally deposit tokens to BalanceManager after minting
# Usage: ./shellscripts/mint_tokens.sh [indices] [--native AMOUNT] [--quote AMOUNT] [--weth AMOUNT] [--wbtc AMOUNT] [--deposit]
# Examples:
#   ./shellscripts/mint_tokens.sh                     # Mint default amounts to all wallets (0-9)
#   ./shellscripts/mint_tokens.sh 2,3,4               # Mint to specific wallets
#   ./shellscripts/mint_tokens.sh 0-4                 # Mint to range (0,1,2,3,4)
#   ./shellscripts/mint_tokens.sh 0,2-5 --quote 10000  # Mint 10000 quote currency to selected wallets
#   ./shellscripts/mint_tokens.sh --native 0.01        # Send 0.01 native tokens to selected wallets
#   ./shellscripts/mint_tokens.sh --weth 100 --wbtc 5 # Mint specific amounts to all wallets
#   ./shellscripts/mint_tokens.sh --deposit           # Mint and deposit to BalanceManager
#   ./shellscripts/mint_tokens.sh 2,3 --deposit       # Mint and deposit for specific wallets

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

# Default mint amounts (in human-readable units)
# Native token
DEFAULT_NATIVE_AMOUNT=0.005   # 0.005 native tokens
# Crypto tokens
DEFAULT_QUOTE_AMOUNT=100000    # 100,000 quote currency (USDC, IDRX, etc.)
DEFAULT_WETH_AMOUNT=100000     # 100,000 WETH
DEFAULT_WBTC_AMOUNT=100000     # 100,000 WBTC

# RWA tokens
DEFAULT_GOLD_AMOUNT=10000     # 10,000 GOLD
DEFAULT_SILVER_AMOUNT=100000  # 100,000 SILVER
DEFAULT_GOOGLE_AMOUNT=1000    # 1,000 GOOGLE
DEFAULT_NVIDIA_AMOUNT=1000    # 1,000 NVIDIA
DEFAULT_MNT_AMOUNT=1000000    # 1,000,000 MNT
DEFAULT_APPLE_AMOUNT=1000     # 1,000 APPLE

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

# Convert human-readable amount to wei/smallest unit
to_smallest_unit() {
    local amount=$1
    local decimals=$2
    python3 -c "print(int($amount * (10 ** $decimals)))"
}

# Parse command line arguments
NATIVE_AMOUNT=$DEFAULT_NATIVE_AMOUNT
QUOTE_AMOUNT=$DEFAULT_QUOTE_AMOUNT
WETH_AMOUNT=$DEFAULT_WETH_AMOUNT
WBTC_AMOUNT=$DEFAULT_WBTC_AMOUNT
GOLD_AMOUNT=$DEFAULT_GOLD_AMOUNT
SILVER_AMOUNT=$DEFAULT_SILVER_AMOUNT
GOOGLE_AMOUNT=$DEFAULT_GOOGLE_AMOUNT
NVIDIA_AMOUNT=$DEFAULT_NVIDIA_AMOUNT
MNT_AMOUNT=$DEFAULT_MNT_AMOUNT
APPLE_AMOUNT=$DEFAULT_APPLE_AMOUNT
INDICES_ARG=""
DO_DEPOSIT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --native)
            NATIVE_AMOUNT="$2"
            shift 2
            ;;
        --quote)
            QUOTE_AMOUNT="$2"
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
        --gold)
            GOLD_AMOUNT="$2"
            shift 2
            ;;
        --silver)
            SILVER_AMOUNT="$2"
            shift 2
            ;;
        --google)
            GOOGLE_AMOUNT="$2"
            shift 2
            ;;
        --nvidia)
            NVIDIA_AMOUNT="$2"
            shift 2
            ;;
        --mnt)
            MNT_AMOUNT="$2"
            shift 2
            ;;
        --apple)
            APPLE_AMOUNT="$2"
            shift 2
            ;;
        --deposit)
            DO_DEPOSIT=true
            shift
            ;;
        --help|-h)
            echo "Usage: ./shellscripts/mint_tokens.sh [indices] [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  indices          Wallet indices (0-9). Can be comma-separated or ranges."
            echo "                   Examples: 2,3,4 or 0-4 or 0,2-5,9"
            echo ""
            echo "  Native Token:"
            echo "    --native AMOUNT  Amount of native token to send (default: $DEFAULT_NATIVE_AMOUNT)"
            echo ""
            echo "  Crypto Tokens:"
            echo "    --quote AMOUNT   Amount of quote currency to mint (default: $DEFAULT_QUOTE_AMOUNT)"
            echo "    --weth AMOUNT    Amount of WETH to mint (default: $DEFAULT_WETH_AMOUNT)"
            echo "    --wbtc AMOUNT    Amount of WBTC to mint (default: $DEFAULT_WBTC_AMOUNT)"
            echo ""
            echo "  RWA Tokens:"
            echo "    --gold AMOUNT    Amount of GOLD to mint (default: $DEFAULT_GOLD_AMOUNT)"
            echo "    --silver AMOUNT  Amount of SILVER to mint (default: $DEFAULT_SILVER_AMOUNT)"
            echo "    --google AMOUNT  Amount of GOOGLE to mint (default: $DEFAULT_GOOGLE_AMOUNT)"
            echo "    --nvidia AMOUNT  Amount of NVIDIA to mint (default: $DEFAULT_NVIDIA_AMOUNT)"
            echo "    --mnt AMOUNT     Amount of MNT to mint (default: $DEFAULT_MNT_AMOUNT)"
            echo "    --apple AMOUNT   Amount of APPLE to mint (default: $DEFAULT_APPLE_AMOUNT)"
            echo ""
            echo "  Other:"
            echo "    --deposit        Also deposit minted tokens to BalanceManager"
            echo "    --help, -h       Show this help message"
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
NATIVE_AMOUNT_WEI=$(to_smallest_unit $NATIVE_AMOUNT 18)
QUOTE_AMOUNT_WEI=$(to_smallest_unit $QUOTE_AMOUNT $QUOTE_DECIMALS)
WETH_AMOUNT_WEI=$(to_smallest_unit $WETH_AMOUNT $WETH_DECIMALS)
WBTC_AMOUNT_WEI=$(to_smallest_unit $WBTC_AMOUNT $WBTC_DECIMALS)
GOLD_AMOUNT_WEI=$(to_smallest_unit $GOLD_AMOUNT $GOLD_DECIMALS)
SILVER_AMOUNT_WEI=$(to_smallest_unit $SILVER_AMOUNT $SILVER_DECIMALS)
GOOGLE_AMOUNT_WEI=$(to_smallest_unit $GOOGLE_AMOUNT $GOOGLE_DECIMALS)
NVIDIA_AMOUNT_WEI=$(to_smallest_unit $NVIDIA_AMOUNT $NVIDIA_DECIMALS)
MNT_AMOUNT_WEI=$(to_smallest_unit $MNT_AMOUNT $MNT_DECIMALS)
APPLE_AMOUNT_WEI=$(to_smallest_unit $APPLE_AMOUNT $APPLE_DECIMALS)

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
echo "  Deposit:     $DO_DEPOSIT"
echo "  RWA Tokens:  $RWA_TOKENS_AVAILABLE"
echo ""
echo "Token Addresses (Crypto):"
echo "  $QUOTE_SYMBOL:        $QUOTE_ADDRESS"
echo "  WETH:        $WETH_ADDRESS"
echo "  WBTC:        $WBTC_ADDRESS"
if [ "$RWA_TOKENS_AVAILABLE" = true ]; then
echo ""
echo "Token Addresses (RWA):"
echo "  GOLD:        $GOLD_ADDRESS"
echo "  SILVER:      $SILVER_ADDRESS"
echo "  GOOGLE:      $GOOGLE_ADDRESS"
echo "  NVIDIA:      $NVIDIA_ADDRESS"
echo "  MNT:         $MNT_ADDRESS"
echo "  APPLE:       $APPLE_ADDRESS"
fi
if [ "$DO_DEPOSIT" = true ]; then
echo ""
echo "Contract Addresses:"
echo "  BalanceManager: $BALANCE_MANAGER_ADDRESS"
fi
echo ""
echo "Mint Amounts (Native & Crypto):"
echo "  NATIVE:      $NATIVE_AMOUNT ($NATIVE_AMOUNT_WEI wei)"
echo "  $QUOTE_SYMBOL:        $QUOTE_AMOUNT ($QUOTE_AMOUNT_WEI smallest units)"
echo "  WETH:        $WETH_AMOUNT ($WETH_AMOUNT_WEI smallest units)"
echo "  WBTC:        $WBTC_AMOUNT ($WBTC_AMOUNT_WEI smallest units)"
if [ "$RWA_TOKENS_AVAILABLE" = true ]; then
echo ""
echo "Mint Amounts (RWA):"
echo "  GOLD:        $GOLD_AMOUNT ($GOLD_AMOUNT_WEI smallest units)"
echo "  SILVER:      $SILVER_AMOUNT ($SILVER_AMOUNT_WEI smallest units)"
echo "  GOOGLE:      $GOOGLE_AMOUNT ($GOOGLE_AMOUNT_WEI smallest units)"
echo "  NVIDIA:      $NVIDIA_AMOUNT ($NVIDIA_AMOUNT_WEI smallest units)"
echo "  MNT:         $MNT_AMOUNT ($MNT_AMOUNT_WEI smallest units)"
echo "  APPLE:       $APPLE_AMOUNT ($APPLE_AMOUNT_WEI smallest units)"
fi
echo ""
echo "Target Wallets: ${INDICES[*]}"
echo "=============================================="
echo ""

# Verify BalanceManager address if deposit is enabled
if [ "$DO_DEPOSIT" = true ] && [ -z "$BALANCE_MANAGER_ADDRESS" ]; then
    echo "Error: BalanceManager address not found in deployments file"
    echo "  Deposit feature requires BalanceManager to be deployed"
    exit 1
fi

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

    # Send native tokens
    echo -n "  Sending $NATIVE_AMOUNT native tokens... "
    TX_NATIVE=$(cast send "$ADDRESS" --value "$NATIVE_AMOUNT_WEI" \
        --private-key "$SENDER_PRIVATE_KEY" \
        --rpc-url "$RPC_URL" 2>&1)
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "FAILED"
        echo "    Error: $TX_NATIVE"
    fi
    sleep 2

    # Mint quote currency
    echo -n "  Minting $QUOTE_AMOUNT $QUOTE_SYMBOL... "
    TX_QUOTE=$(cast send "$QUOTE_ADDRESS" "mint(address,uint256)" "$ADDRESS" "$QUOTE_AMOUNT_WEI" \
        --private-key "$SENDER_PRIVATE_KEY" \
        --rpc-url "$RPC_URL" 2>&1)
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "FAILED"
        echo "    Error: $TX_QUOTE"
    fi
    sleep 2

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
    sleep 2

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
    sleep 2

    # Mint RWA tokens if available
    if [ "$RWA_TOKENS_AVAILABLE" = true ]; then
        # Mint GOLD
        echo -n "  Minting $GOLD_AMOUNT GOLD... "
        TX_GOLD=$(cast send "$GOLD_ADDRESS" "mint(address,uint256)" "$ADDRESS" "$GOLD_AMOUNT_WEI" \
            --private-key "$SENDER_PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_GOLD"
        fi
        sleep 2

        # Mint SILVER
        echo -n "  Minting $SILVER_AMOUNT SILVER... "
        TX_SILVER=$(cast send "$SILVER_ADDRESS" "mint(address,uint256)" "$ADDRESS" "$SILVER_AMOUNT_WEI" \
            --private-key "$SENDER_PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_SILVER"
        fi
        sleep 2

        # Mint GOOGLE
        echo -n "  Minting $GOOGLE_AMOUNT GOOGLE... "
        TX_GOOGLE=$(cast send "$GOOGLE_ADDRESS" "mint(address,uint256)" "$ADDRESS" "$GOOGLE_AMOUNT_WEI" \
            --private-key "$SENDER_PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_GOOGLE"
        fi
        sleep 2

        # Mint NVIDIA
        echo -n "  Minting $NVIDIA_AMOUNT NVIDIA... "
        TX_NVIDIA=$(cast send "$NVIDIA_ADDRESS" "mint(address,uint256)" "$ADDRESS" "$NVIDIA_AMOUNT_WEI" \
            --private-key "$SENDER_PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_NVIDIA"
        fi
        sleep 2

        # Mint MNT
        echo -n "  Minting $MNT_AMOUNT MNT... "
        TX_MNT=$(cast send "$MNT_ADDRESS" "mint(address,uint256)" "$ADDRESS" "$MNT_AMOUNT_WEI" \
            --private-key "$SENDER_PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_MNT"
        fi
        sleep 2

        # Mint APPLE
        echo -n "  Minting $APPLE_AMOUNT APPLE... "
        TX_APPLE=$(cast send "$APPLE_ADDRESS" "mint(address,uint256)" "$ADDRESS" "$APPLE_AMOUNT_WEI" \
            --private-key "$SENDER_PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_APPLE"
        fi
        sleep 2
    fi

    echo ""
done

echo "=============================================="
echo "  Minting Complete"
echo "=============================================="

# Deposit tokens to BalanceManager if --deposit flag is set
if [ "$DO_DEPOSIT" = true ]; then
    echo ""
    echo "=============================================="
    echo "  Depositing Tokens to BalanceManager"
    echo "=============================================="
    echo ""

    for i in "${INDICES[@]}"; do
        NAME="${WALLET_NAMES[$i]}"

        # Derive private key and address for this wallet
        PRIVATE_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" $i 2>/dev/null)
        ADDRESS=$(cast wallet address "$PRIVATE_KEY" 2>/dev/null)

        echo "----------------------------------------------"
        printf "Depositing for: %-15s (Index: %d)\n" "$NAME" "$i"
        echo "Address: $ADDRESS"
        echo "----------------------------------------------"

        # Max approval value
        MAX_UINT="115792089237316195423570985008687907853269984665640564039457584007913129639935"

        # Approve and deposit quote currency
        echo -n "  Approving $QUOTE_SYMBOL... "
        TX_APPROVE=$(cast send "$QUOTE_ADDRESS" "approve(address,uint256)" "$BALANCE_MANAGER_ADDRESS" "$MAX_UINT" \
            --private-key "$PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_APPROVE"
        fi
        sleep 2

        echo -n "  Depositing $QUOTE_AMOUNT $QUOTE_SYMBOL... "
        TX_DEPOSIT=$(cast send "$BALANCE_MANAGER_ADDRESS" "depositLocal(address,uint256,address)" \
            "$QUOTE_ADDRESS" "$QUOTE_AMOUNT_WEI" "$ADDRESS" \
            --private-key "$PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_DEPOSIT"
        fi
        sleep 2

        # Approve and deposit WETH
        echo -n "  Approving WETH... "
        TX_APPROVE=$(cast send "$WETH_ADDRESS" "approve(address,uint256)" "$BALANCE_MANAGER_ADDRESS" "$MAX_UINT" \
            --private-key "$PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_APPROVE"
        fi
        sleep 2

        echo -n "  Depositing $WETH_AMOUNT WETH... "
        TX_DEPOSIT=$(cast send "$BALANCE_MANAGER_ADDRESS" "depositLocal(address,uint256,address)" \
            "$WETH_ADDRESS" "$WETH_AMOUNT_WEI" "$ADDRESS" \
            --private-key "$PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_DEPOSIT"
        fi
        sleep 2

        # Approve and deposit WBTC
        echo -n "  Approving WBTC... "
        TX_APPROVE=$(cast send "$WBTC_ADDRESS" "approve(address,uint256)" "$BALANCE_MANAGER_ADDRESS" "$MAX_UINT" \
            --private-key "$PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_APPROVE"
        fi
        sleep 2

        echo -n "  Depositing $WBTC_AMOUNT WBTC... "
        TX_DEPOSIT=$(cast send "$BALANCE_MANAGER_ADDRESS" "depositLocal(address,uint256,address)" \
            "$WBTC_ADDRESS" "$WBTC_AMOUNT_WEI" "$ADDRESS" \
            --private-key "$PRIVATE_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            echo "FAILED"
            echo "    Error: $TX_DEPOSIT"
        fi
        sleep 2

        # Deposit RWA tokens if available
        if [ "$RWA_TOKENS_AVAILABLE" = true ]; then
            # Approve and deposit GOLD
            echo -n "  Approving GOLD... "
            TX_APPROVE=$(cast send "$GOLD_ADDRESS" "approve(address,uint256)" "$BALANCE_MANAGER_ADDRESS" "$MAX_UINT" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_APPROVE"
            fi
            sleep 2

            echo -n "  Depositing $GOLD_AMOUNT GOLD... "
            TX_DEPOSIT=$(cast send "$BALANCE_MANAGER_ADDRESS" "depositLocal(address,uint256,address)" \
                "$GOLD_ADDRESS" "$GOLD_AMOUNT_WEI" "$ADDRESS" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_DEPOSIT"
            fi
            sleep 2

            # Approve and deposit SILVER
            echo -n "  Approving SILVER... "
            TX_APPROVE=$(cast send "$SILVER_ADDRESS" "approve(address,uint256)" "$BALANCE_MANAGER_ADDRESS" "$MAX_UINT" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_APPROVE"
            fi
            sleep 2

            echo -n "  Depositing $SILVER_AMOUNT SILVER... "
            TX_DEPOSIT=$(cast send "$BALANCE_MANAGER_ADDRESS" "depositLocal(address,uint256,address)" \
                "$SILVER_ADDRESS" "$SILVER_AMOUNT_WEI" "$ADDRESS" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_DEPOSIT"
            fi
            sleep 2

            # Approve and deposit GOOGLE
            echo -n "  Approving GOOGLE... "
            TX_APPROVE=$(cast send "$GOOGLE_ADDRESS" "approve(address,uint256)" "$BALANCE_MANAGER_ADDRESS" "$MAX_UINT" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_APPROVE"
            fi
            sleep 2

            echo -n "  Depositing $GOOGLE_AMOUNT GOOGLE... "
            TX_DEPOSIT=$(cast send "$BALANCE_MANAGER_ADDRESS" "depositLocal(address,uint256,address)" \
                "$GOOGLE_ADDRESS" "$GOOGLE_AMOUNT_WEI" "$ADDRESS" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_DEPOSIT"
            fi
            sleep 2

            # Approve and deposit NVIDIA
            echo -n "  Approving NVIDIA... "
            TX_APPROVE=$(cast send "$NVIDIA_ADDRESS" "approve(address,uint256)" "$BALANCE_MANAGER_ADDRESS" "$MAX_UINT" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_APPROVE"
            fi
            sleep 2

            echo -n "  Depositing $NVIDIA_AMOUNT NVIDIA... "
            TX_DEPOSIT=$(cast send "$BALANCE_MANAGER_ADDRESS" "depositLocal(address,uint256,address)" \
                "$NVIDIA_ADDRESS" "$NVIDIA_AMOUNT_WEI" "$ADDRESS" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_DEPOSIT"
            fi
            sleep 2

            # Approve and deposit MNT
            echo -n "  Approving MNT... "
            TX_APPROVE=$(cast send "$MNT_ADDRESS" "approve(address,uint256)" "$BALANCE_MANAGER_ADDRESS" "$MAX_UINT" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_APPROVE"
            fi
            sleep 2

            echo -n "  Depositing $MNT_AMOUNT MNT... "
            TX_DEPOSIT=$(cast send "$BALANCE_MANAGER_ADDRESS" "depositLocal(address,uint256,address)" \
                "$MNT_ADDRESS" "$MNT_AMOUNT_WEI" "$ADDRESS" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_DEPOSIT"
            fi
            sleep 2

            # Approve and deposit APPLE
            echo -n "  Approving APPLE... "
            TX_APPROVE=$(cast send "$APPLE_ADDRESS" "approve(address,uint256)" "$BALANCE_MANAGER_ADDRESS" "$MAX_UINT" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_APPROVE"
            fi
            sleep 2

            echo -n "  Depositing $APPLE_AMOUNT APPLE... "
            TX_DEPOSIT=$(cast send "$BALANCE_MANAGER_ADDRESS" "depositLocal(address,uint256,address)" \
                "$APPLE_ADDRESS" "$APPLE_AMOUNT_WEI" "$ADDRESS" \
                --private-key "$PRIVATE_KEY" \
                --rpc-url "$RPC_URL" 2>&1)
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "    Error: $TX_DEPOSIT"
            fi
            sleep 2
        fi

        echo ""
    done

    echo "=============================================="
    echo "  Deposits Complete"
    echo "=============================================="
fi
