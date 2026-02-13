#!/bin/bash

# Create Multiple Agents with Isolated Funds
# Each agent uses a different wallet (private key) = separate BalanceManager account

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== CREATE MULTIPLE AGENTS (ISOLATED FUNDS) ===${NC}"
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

if [ -z "$QUOTE_SYMBOL" ]; then
    export QUOTE_SYMBOL="USDC"
fi

# Check for agent private keys
if [ -z "$AGENT1_PRIVATE_KEY" ]; then
    echo -e "${RED}Error: AGENT1_PRIVATE_KEY not set${NC}"
    echo ""
    echo "Add to .env:"
    echo "  AGENT1_PRIVATE_KEY=0x..."
    echo "  AGENT2_PRIVATE_KEY=0x..."
    echo "  AGENT3_PRIVATE_KEY=0x..."
    exit 1
fi

if [ -z "$AGENT2_PRIVATE_KEY" ]; then
    echo -e "${RED}Error: AGENT2_PRIVATE_KEY not set${NC}"
    exit 1
fi

if [ -z "$AGENT3_PRIVATE_KEY" ]; then
    echo -e "${RED}Error: AGENT3_PRIVATE_KEY not set${NC}"
    exit 1
fi

# Derive wallet addresses
AGENT1_WALLET=$(cast wallet address --private-key $AGENT1_PRIVATE_KEY)
AGENT2_WALLET=$(cast wallet address --private-key $AGENT2_PRIVATE_KEY)
AGENT3_WALLET=$(cast wallet address --private-key $AGENT3_PRIVATE_KEY)

echo -e "${BLUE}Configuration:${NC}"
echo "  RPC: $SCALEX_CORE_RPC"
echo "  Quote: $QUOTE_SYMBOL"
echo ""
echo -e "${BLUE}Agents:${NC}"
echo "  Agent 1 (Conservative): $AGENT1_WALLET - 1,000 $QUOTE_SYMBOL"
echo "  Agent 2 (Aggressive): $AGENT2_WALLET - 5,000 $QUOTE_SYMBOL"
echo "  Agent 3 (Test): $AGENT3_WALLET - 500 $QUOTE_SYMBOL"
echo ""

# Warning about fund requirements
echo -e "${YELLOW}NOTE: Each wallet needs quote tokens:${NC}"
echo "  Agent 1 needs: 1,000 $QUOTE_SYMBOL"
echo "  Agent 2 needs: 5,000 $QUOTE_SYMBOL"
echo "  Agent 3 needs: 500 $QUOTE_SYMBOL"
echo "  Total: 6,500 $QUOTE_SYMBOL"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 1
fi

echo ""
echo -e "${BLUE}Creating agents...${NC}"
echo ""

# Run the script
forge script script/agents/CreateMultipleAgents.s.sol:CreateMultipleAgents \
    --rpc-url "$SCALEX_CORE_RPC" \
    --broadcast \
    --gas-estimate-multiplier 120 \
    --legacy

echo ""
echo -e "${GREEN}=== SETUP COMPLETE ===${NC}"
echo ""
echo -e "${YELLOW}Fund Isolation:${NC}"
echo "  ✓ Each agent has separate wallet"
echo "  ✓ Each wallet has separate BalanceManager account"
echo "  ✓ Agent 1's losses don't affect Agent 2 or 3"
echo "  ✓ Can track P&L per agent independently"
echo ""
echo -e "${YELLOW}To trade with Agent 1:${NC}"
echo "  export PRIVATE_KEY=\$AGENT1_PRIVATE_KEY"
echo "  ./shellscripts/test-agent-order.sh"
echo ""
echo -e "${YELLOW}To trade with Agent 2:${NC}"
echo "  export PRIVATE_KEY=\$AGENT2_PRIVATE_KEY"
echo "  ./shellscripts/test-agent-order.sh"
