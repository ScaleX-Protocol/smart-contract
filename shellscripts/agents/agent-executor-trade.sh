#!/bin/bash

# Agent Executor Trade
# Agent wallet signs transaction and pays gas
# But uses user wallet's funds from BalanceManager

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== AGENT EXECUTOR TRADE ===${NC}"
echo ""

# Check .env
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

source .env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate
if [ -z "$AGENT_PRIVATE_KEY" ]; then
    echo -e "${RED}Error: AGENT_PRIVATE_KEY not set${NC}"
    echo ""
    echo "Set the agent to use:"
    echo "  export AGENT_PRIVATE_KEY=\$AGENT_1_KEY"
    echo "  export AGENT_PRIVATE_KEY=\$AGENT_2_KEY"
    echo "  export AGENT_PRIVATE_KEY=\$AGENT_3_KEY"
    exit 1
fi

if [ -z "$USER_ADDRESS" ]; then
    echo -e "${RED}Error: USER_ADDRESS not set${NC}"
    echo ""
    echo "Set the user wallet address:"
    echo "  export USER_ADDRESS=0x..."
    exit 1
fi

AGENT_WALLET=$(cast wallet address --private-key $AGENT_PRIVATE_KEY)

# Load deployment addresses
CORE_CHAIN_ID=${CORE_CHAIN_ID:-84532}
DEPLOYMENTS_FILE="$SCRIPT_DIR/../../deployments/${CORE_CHAIN_ID}.json"
BALANCE_MANAGER_ADDRESS=$(grep -o '"BalanceManager": "[^"]*"' "$DEPLOYMENTS_FILE" | cut -d'"' -f4)
QUOTE_SYMBOL=${QUOTE_SYMBOL:-IDRX}
QUOTE_ADDRESS=$(grep -o "\"$QUOTE_SYMBOL\": \"[^\"]*\"" "$DEPLOYMENTS_FILE" | cut -d'"' -f4)
QUOTE_DECIMALS=${QUOTE_DECIMALS:-6}

echo -e "${BLUE}Configuration:${NC}"
echo "  User Wallet (Owns Funds): $USER_ADDRESS"
echo "  Agent Wallet (Signs Tx):  $AGENT_WALLET"
echo "  RPC: $SCALEX_CORE_RPC"
echo ""

# Check user wallet balance in BalanceManager
echo -e "${BLUE}Checking user wallet balance in BalanceManager...${NC}"
USER_BM_BALANCE=$(cast call "$BALANCE_MANAGER_ADDRESS" \
    "getBalance(address,address)(uint256)" \
    "$USER_ADDRESS" "$QUOTE_ADDRESS" \
    --rpc-url "$SCALEX_CORE_RPC" 2>/dev/null || echo "0")
USER_BM_BALANCE=$(echo "$USER_BM_BALANCE" | tr -d '[:space:]')

echo "  $QUOTE_SYMBOL balance in BalanceManager: $USER_BM_BALANCE"
echo ""

# If balance is 0 or empty, offer to fund via send-tokens.sh
if [ -z "$USER_BM_BALANCE" ] || [ "$USER_BM_BALANCE" = "0" ]; then
    echo -e "${YELLOW}Warning: User wallet has no $QUOTE_SYMBOL in BalanceManager.${NC}"
    echo "  Limit orders require quote currency locked in BalanceManager."
    echo ""
    read -p "Run send-tokens.sh to mint and deposit tokens first? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${BLUE}Minting and depositing tokens...${NC}"
        bash "$SCRIPT_DIR/../wallets/send-tokens.sh" --deposit
        echo ""
    fi
fi

echo -e "${YELLOW}How it works:${NC}"
echo "  1. Agent wallet signs the transaction (pays gas)"
echo "  2. AgentRouter checks agent is authorized"
echo "  3. Trade uses USER wallet's funds from BalanceManager"
echo "  4. Profits/losses go to USER wallet"
echo ""

read -p "Place order? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 1
fi

echo ""
echo -e "${BLUE}Placing order...${NC}"
echo ""

# Run the trade script
STRATEGY_AGENT_ID=${STRATEGY_AGENT_ID:-0} \
QUOTE_SYMBOL=$QUOTE_SYMBOL \
forge script script/agents/AgentExecutorTrade.s.sol:AgentExecutorTrade \
    --rpc-url "$SCALEX_CORE_RPC" \
    --broadcast \
    --gas-estimate-multiplier 120 \
    --slow \
    --legacy

echo ""
echo -e "${GREEN}=== TRADE COMPLETE ===${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  Agent: $AGENT_WALLET (paid gas)"
echo "  User: $USER_ADDRESS (funds used)"
echo ""
echo -e "${YELLOW}To trade with different agent:${NC}"
echo "  export AGENT_PRIVATE_KEY=\$AGENT_2_KEY"
echo "  ./shellscripts/agent-executor-trade.sh"
