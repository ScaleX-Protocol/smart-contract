#!/bin/bash

# Agent Executor Trade
# Executor wallet signs transaction and pays gas
# But uses primary wallet's funds from BalanceManager

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

# Validate
if [ -z "$EXECUTOR_PRIVATE_KEY" ]; then
    echo -e "${RED}Error: EXECUTOR_PRIVATE_KEY not set${NC}"
    echo ""
    echo "Set the executor to use:"
    echo "  export EXECUTOR_PRIVATE_KEY=\$AGENT_EXECUTOR_1_KEY"
    echo "  export EXECUTOR_PRIVATE_KEY=\$AGENT_EXECUTOR_2_KEY"
    echo "  export EXECUTOR_PRIVATE_KEY=\$AGENT_EXECUTOR_3_KEY"
    exit 1
fi

if [ -z "$PRIMARY_WALLET_ADDRESS" ]; then
    echo -e "${RED}Error: PRIMARY_WALLET_ADDRESS not set${NC}"
    echo ""
    echo "Set the primary wallet address:"
    echo "  export PRIMARY_WALLET_ADDRESS=0x..."
    exit 1
fi

EXECUTOR_WALLET=$(cast wallet address --private-key $EXECUTOR_PRIVATE_KEY)

echo -e "${BLUE}Configuration:${NC}"
echo "  Primary Wallet (Owns Funds): $PRIMARY_WALLET_ADDRESS"
echo "  Executor Wallet (Signs Tx): $EXECUTOR_WALLET"
echo "  RPC: $SCALEX_CORE_RPC"
echo ""

echo -e "${YELLOW}How it works:${NC}"
echo "  1. Executor wallet signs the transaction (pays gas)"
echo "  2. AgentRouter checks executor is authorized"
echo "  3. Trade uses PRIMARY wallet's funds from BalanceManager"
echo "  4. Profits/losses go to PRIMARY wallet"
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
forge script script/agents/AgentExecutorTrade.s.sol:AgentExecutorTrade \
    --rpc-url "$SCALEX_CORE_RPC" \
    --broadcast \
    --gas-estimate-multiplier 120 \
    --legacy

echo ""
echo -e "${GREEN}=== TRADE COMPLETE ===${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  Executor: $EXECUTOR_WALLET (paid gas)"
echo "  Owner: $PRIMARY_WALLET_ADDRESS (funds used)"
echo ""
echo -e "${YELLOW}To trade with different executor:${NC}"
echo "  export EXECUTOR_PRIVATE_KEY=\$AGENT_EXECUTOR_2_KEY"
echo "  ./shellscripts/agent-executor-trade.sh"
