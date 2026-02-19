#!/bin/bash

# Register Agent Identities
# Each agent wallet mints its own ERC-8004 NFT (strategyAgentId).
# After this, users run user-authorize-agent.sh to grant each agent permission.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== REGISTER AGENT IDENTITIES ===${NC}"
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

if [ -z "$AGENT1_PRIVATE_KEY" ] || [ -z "$AGENT2_PRIVATE_KEY" ] || [ -z "$AGENT3_PRIVATE_KEY" ]; then
    echo -e "${RED}Error: Agent private keys not set${NC}"
    echo ""
    echo "Add to .env:"
    echo "  AGENT1_PRIVATE_KEY=0x...  # Agent 1 wallet"
    echo "  AGENT2_PRIVATE_KEY=0x...  # Agent 2 wallet"
    echo "  AGENT3_PRIVATE_KEY=0x...  # Agent 3 wallet"
    exit 1
fi

# Derive wallet addresses
AGENT1_WALLET=$(cast wallet address --private-key $AGENT1_PRIVATE_KEY)
AGENT2_WALLET=$(cast wallet address --private-key $AGENT2_PRIVATE_KEY)
AGENT3_WALLET=$(cast wallet address --private-key $AGENT3_PRIVATE_KEY)

echo -e "${BLUE}Agent wallets:${NC}"
echo "  Agent 1: $AGENT1_WALLET"
echo "  Agent 2: $AGENT2_WALLET"
echo "  Agent 3: $AGENT3_WALLET"
echo ""
echo "Each wallet will register an ERC-8004 NFT identity."
echo "The printed strategyAgentId values are needed for user authorization."
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 1
fi

echo ""
echo -e "${BLUE}Registering agents...${NC}"
echo ""

forge script script/agents/CreateMultipleAgents.s.sol:CreateMultipleAgents \
    --rpc-url "$SCALEX_CORE_RPC" \
    --broadcast \
    --gas-estimate-multiplier 120 \
    --legacy

echo ""
echo -e "${GREEN}=== REGISTRATION COMPLETE ===${NC}"
echo ""
echo -e "${YELLOW}Next step:${NC}"
echo "  Users must authorize each agent before it can trade on their behalf."
echo ""
echo "  For each user + agent pair, run:"
echo "    USER_PRIVATE_KEY=<user_key> STRATEGY_AGENT_ID=<agent_id> bash shellscripts/user-authorize-agent.sh"
echo ""
echo "  The strategyAgentId for each agent is printed above."
