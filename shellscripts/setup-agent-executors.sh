#!/bin/bash

# Setup Agent Executors
# Primary wallet owns funds, agent wallets execute trades on behalf of primary wallet

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse flags
SKIP_CONFIRM=false
if [[ "$1" == "--yes" ]] || [[ "$1" == "-y" ]]; then
    SKIP_CONFIRM=true
fi

echo -e "${BLUE}=== SETUP AGENT EXECUTORS ===${NC}"
echo ""

# Check .env
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

source .env

# Validate required variables
if [ -z "$SCALEX_CORE_RPC" ]; then
    echo -e "${RED}Error: SCALEX_CORE_RPC not set${NC}"
    exit 1
fi

if [ -z "$PRIMARY_WALLET_KEY" ]; then
    echo -e "${RED}Error: PRIMARY_WALLET_KEY not set${NC}"
    echo ""
    echo "Add to .env:"
    echo "  PRIMARY_WALLET_KEY=0x...  # Wallet that owns funds"
    exit 1
fi

if [ -z "$AGENT_EXECUTOR_1_KEY" ]; then
    echo -e "${RED}Error: Agent executor keys not set${NC}"
    echo ""
    echo "Add to .env:"
    echo "  AGENT_EXECUTOR_1_KEY=0x...  # Conservative agent"
    echo "  AGENT_EXECUTOR_2_KEY=0x...  # Aggressive agent"
    echo "  AGENT_EXECUTOR_3_KEY=0x...  # Market maker agent"
    exit 1
fi

# Derive addresses
PRIMARY_WALLET=$(cast wallet address --private-key $PRIMARY_WALLET_KEY)
EXECUTOR1=$(cast wallet address --private-key $AGENT_EXECUTOR_1_KEY)
EXECUTOR2=$(cast wallet address --private-key $AGENT_EXECUTOR_2_KEY)
EXECUTOR3=$(cast wallet address --private-key $AGENT_EXECUTOR_3_KEY)

echo -e "${BLUE}Configuration:${NC}"
echo "  RPC: $SCALEX_CORE_RPC"
echo "  Quote: ${QUOTE_SYMBOL:-USDC}"
echo ""
echo -e "${BLUE}Primary Wallet (Owns Funds):${NC}"
echo "  Address: $PRIMARY_WALLET"
echo "  Needs: 10,000 ${QUOTE_SYMBOL:-USDC} tokens"
echo ""
echo -e "${BLUE}Agent Executors (Trade on Behalf):${NC}"
echo "  1. Conservative: $EXECUTOR1 (needs gas only)"
echo "  2. Aggressive: $EXECUTOR2 (needs gas only)"
echo "  3. Market Maker: $EXECUTOR3 (needs gas only)"
echo ""

echo -e "${YELLOW}Fund Structure:${NC}"
echo "  - Primary wallet deposits 10,000 ${QUOTE_SYMBOL:-USDC} to BalanceManager"
echo "  - Agent executors are authorized to trade using those funds"
echo "  - Agent executors pay their own gas fees"
echo "  - All profits/losses accrue to primary wallet"
echo ""

if [ "$SKIP_CONFIRM" = false ]; then
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}Running setup...${NC}"
echo ""

# Run the setup script
forge script script/agents/SetupAgentExecutors.s.sol:SetupAgentExecutors \
    --rpc-url "$SCALEX_CORE_RPC" \
    --broadcast \
    --gas-estimate-multiplier 120 \
    --legacy

echo ""
echo -e "${GREEN}=== SETUP COMPLETE ===${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Fund executor wallets with gas (small amount of ETH):"
echo "   - Send 0.01 ETH to $EXECUTOR1"
echo "   - Send 0.01 ETH to $EXECUTOR2"
echo "   - Send 0.01 ETH to $EXECUTOR3"
echo ""
echo "2. Test trading with executor 1:"
echo "   export EXECUTOR_PRIVATE_KEY=\$AGENT_EXECUTOR_1_KEY"
echo "   export PRIMARY_WALLET_ADDRESS=$PRIMARY_WALLET"
echo "   ./shellscripts/agent-executor-trade.sh"
echo ""
echo "3. Switch to executor 2:"
echo "   export EXECUTOR_PRIVATE_KEY=\$AGENT_EXECUTOR_2_KEY"
echo "   ./shellscripts/agent-executor-trade.sh"
