#!/bin/bash

# Fund Agent Executor Wallets
# Sends ETH and mints IDRX to agent wallets from seed phrase wallet 0

# Add foundry to PATH
export PATH="$HOME/.foundry/bin:$PATH"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# Parse .env file
if [ -f "$ENV_FILE" ]; then
    SEED_PHRASE=$(grep "^SEED_PHRASE=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    RPC_URL=$(grep "^SCALEX_CORE_RPC=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    CORE_CHAIN_ID=$(grep "^CORE_CHAIN_ID=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    QUOTE_DECIMALS=$(grep "^QUOTE_DECIMALS=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")

    # Agent wallet addresses
    PRIMARY_WALLET=$(grep "^PRIMARY_WALLET_ADDRESS=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
fi

# Check required variables
if [ -z "$SEED_PHRASE" ] || [ -z "$PRIMARY_WALLET" ]; then
    echo "Error: Required environment variables not found in .env"
    exit 1
fi

# Default RPC if not found
if [ -z "$RPC_URL" ]; then
    RPC_URL="https://sepolia.base.org"
fi

# Default chain ID
if [ -z "$CORE_CHAIN_ID" ]; then
    CORE_CHAIN_ID="84532"
fi

# Default quote decimals
if [ -z "$QUOTE_DECIMALS" ]; then
    QUOTE_DECIMALS="6"
fi

# Load token address from deployments
DEPLOYMENTS_FILE="$SCRIPT_DIR/../deployments/${CORE_CHAIN_ID}.json"
if [ -f "$DEPLOYMENTS_FILE" ]; then
    IDRX_ADDRESS=$(cat "$DEPLOYMENTS_FILE" | grep -o '"IDRX": "[^"]*"' | cut -d'"' -f4)
else
    echo "Error: Deployments file not found at $DEPLOYMENTS_FILE"
    exit 1
fi

if [ -z "$IDRX_ADDRESS" ]; then
    echo "Error: IDRX address not found in deployments file"
    exit 1
fi

# Get sender private key (wallet 0 from seed phrase)
SENDER_PRIVATE_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" 0 2>/dev/null)
SENDER_ADDRESS=$(cast wallet address "$SENDER_PRIVATE_KEY" 2>/dev/null)

# Agent wallet addresses
EXECUTOR_1="0xfc98C3eD81138d8A5f35b30A3b735cB5362e14Dc"
EXECUTOR_2="0x6CDD4354114Eae313972C99457E4f85eb6dc5295"
EXECUTOR_3="0xfA1Bb09a1318459061ECca7Cf23021843d5dB9c2"

# Funding amounts
PRIMARY_ETH="0.1"
EXECUTOR_ETH="0.01"
PRIMARY_IDRX="10000"

# Convert to smallest units
PRIMARY_ETH_WEI=$(python3 -c "print(int($PRIMARY_ETH * (10 ** 18)))")
EXECUTOR_ETH_WEI=$(python3 -c "print(int($EXECUTOR_ETH * (10 ** 18)))")
PRIMARY_IDRX_WEI=$(python3 -c "print(int($PRIMARY_IDRX * (10 ** $QUOTE_DECIMALS)))")

echo "=============================================="
echo "  Fund Agent Executor Wallets"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  Chain ID:    $CORE_CHAIN_ID"
echo "  RPC URL:     $RPC_URL"
echo "  Sender:      $SENDER_ADDRESS"
echo ""
echo "Token Addresses:"
echo "  IDRX:        $IDRX_ADDRESS"
echo ""
echo "Target Wallets:"
echo "  Primary:     $PRIMARY_WALLET"
echo "  Executor 1:  $EXECUTOR_1"
echo "  Executor 2:  $EXECUTOR_2"
echo "  Executor 3:  $EXECUTOR_3"
echo ""
echo "Funding Amounts:"
echo "  Primary:     $PRIMARY_ETH ETH + $PRIMARY_IDRX IDRX"
echo "  Executors:   $EXECUTOR_ETH ETH each"
echo "=============================================="
echo ""

# Check sender balance
echo "Checking sender balance..."
SENDER_BALANCE=$(cast balance "$SENDER_ADDRESS" --rpc-url "$RPC_URL" --ether 2>/dev/null)
echo "  Sender has $SENDER_BALANCE ETH"
echo ""

# Fund Primary Wallet
echo "----------------------------------------------"
echo "Funding Primary Wallet: $PRIMARY_WALLET"
echo "----------------------------------------------"

echo -n "  Sending $PRIMARY_ETH ETH... "
TX_ETH=$(cast send "$PRIMARY_WALLET" --value "$PRIMARY_ETH_WEI" \
    --private-key "$SENDER_PRIVATE_KEY" \
    --rpc-url "$RPC_URL" 2>&1)
if [ $? -eq 0 ]; then
    echo "OK"
else
    echo "FAILED"
    echo "    Error: $TX_ETH"
fi
sleep 2

echo -n "  Minting $PRIMARY_IDRX IDRX... "
TX_IDRX=$(cast send "$IDRX_ADDRESS" "mint(address,uint256)" "$PRIMARY_WALLET" "$PRIMARY_IDRX_WEI" \
    --private-key "$SENDER_PRIVATE_KEY" \
    --rpc-url "$RPC_URL" 2>&1)
if [ $? -eq 0 ]; then
    echo "OK"
else
    echo "FAILED"
    echo "    Error: $TX_IDRX"
fi
sleep 2

echo ""

# Fund Executor 1
echo "----------------------------------------------"
echo "Funding Executor 1: $EXECUTOR_1"
echo "----------------------------------------------"

echo -n "  Sending $EXECUTOR_ETH ETH... "
TX_ETH=$(cast send "$EXECUTOR_1" --value "$EXECUTOR_ETH_WEI" \
    --private-key "$SENDER_PRIVATE_KEY" \
    --rpc-url "$RPC_URL" 2>&1)
if [ $? -eq 0 ]; then
    echo "OK"
else
    echo "FAILED"
    echo "    Error: $TX_ETH"
fi
sleep 2

echo ""

# Fund Executor 2
echo "----------------------------------------------"
echo "Funding Executor 2: $EXECUTOR_2"
echo "----------------------------------------------"

echo -n "  Sending $EXECUTOR_ETH ETH... "
TX_ETH=$(cast send "$EXECUTOR_2" --value "$EXECUTOR_ETH_WEI" \
    --private-key "$SENDER_PRIVATE_KEY" \
    --rpc-url "$RPC_URL" 2>&1)
if [ $? -eq 0 ]; then
    echo "OK"
else
    echo "FAILED"
    echo "    Error: $TX_ETH"
fi
sleep 2

echo ""

# Fund Executor 3
echo "----------------------------------------------"
echo "Funding Executor 3: $EXECUTOR_3"
echo "----------------------------------------------"

echo -n "  Sending $EXECUTOR_ETH ETH... "
TX_ETH=$(cast send "$EXECUTOR_3" --value "$EXECUTOR_ETH_WEI" \
    --private-key "$SENDER_PRIVATE_KEY" \
    --rpc-url "$RPC_URL" 2>&1)
if [ $? -eq 0 ]; then
    echo "OK"
else
    echo "FAILED"
    echo "    Error: $TX_ETH"
fi
sleep 2

echo ""
echo "=============================================="
echo "  Funding Complete"
echo "=============================================="
echo ""
echo "Verifying balances..."
echo ""

# Run the check script
if [ -f "$SCRIPT_DIR/check-agent-wallets.sh" ]; then
    bash "$SCRIPT_DIR/check-agent-wallets.sh"
else
    echo "Note: check-agent-wallets.sh not found, skipping balance verification"
fi
