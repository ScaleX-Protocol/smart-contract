#!/bin/bash

# User Authorize Agent
# User wallet grants a strategy agent permission to execute orders on their behalf.
# Run this AFTER create-multiple-agents.sh has registered the agent NFTs.
#
# Flow:
#   1. create-multiple-agents.sh  →  agent wallets register NFTs, get strategyAgentIds
#   2. This script                →  user calls AgentRouter.authorize(strategyAgentId, policy)
#   3. Agent wallet can now call  →  AgentRouter.execute*(userAddress, strategyAgentId, ...)
#
# Required env vars:
#   USER_PRIVATE_KEY    — wallet that owns funds and is granting authorization
#   STRATEGY_AGENT_ID  — NFT token ID of the agent to authorize (printed by create-multiple-agents.sh)
#
# Usage:
#   USER_PRIVATE_KEY=0x... STRATEGY_AGENT_ID=123 bash shellscripts/user-authorize-agent.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== USER AUTHORIZE AGENT ===${NC}"
echo ""

# Check .env
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

source .env

# Validate required variables
if [ -z "$SCALEX_CORE_RPC" ]; then
    echo -e "${RED}Error: SCALEX_CORE_RPC not set in .env${NC}"
    exit 1
fi

if [ -z "$USER_PRIVATE_KEY" ]; then
    echo -e "${RED}Error: USER_PRIVATE_KEY not set${NC}"
    echo ""
    echo "Set it before running:"
    echo "  USER_PRIVATE_KEY=0x... STRATEGY_AGENT_ID=123 bash shellscripts/user-authorize-agent.sh"
    exit 1
fi

if [ -z "$STRATEGY_AGENT_ID" ]; then
    echo -e "${RED}Error: STRATEGY_AGENT_ID not set${NC}"
    echo ""
    echo "Get the agent ID from the output of create-multiple-agents.sh, then:"
    echo "  STRATEGY_AGENT_ID=123 bash shellscripts/user-authorize-agent.sh"
    exit 1
fi

USER_WALLET=$(cast wallet address --private-key $USER_PRIVATE_KEY)

echo -e "${BLUE}Authorization details:${NC}"
echo "  User Wallet:       $USER_WALLET"
echo "  Strategy Agent ID: $STRATEGY_AGENT_ID"
echo ""
echo "This will allow agent $STRATEGY_AGENT_ID to execute orders using $USER_WALLET's funds."
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 1
fi

echo ""
echo -e "${BLUE}Authorizing agent...${NC}"
echo ""

USER_PRIVATE_KEY=$USER_PRIVATE_KEY STRATEGY_AGENT_ID=$STRATEGY_AGENT_ID \
forge script script/agents/UserAuthorizeAgent.s.sol:UserAuthorizeAgent \
    --rpc-url "$SCALEX_CORE_RPC" \
    --broadcast \
    --gas-estimate-multiplier 120 \
    --legacy

echo ""
echo -e "${GREEN}=== AUTHORIZATION COMPLETE ===${NC}"
echo ""
echo -e "${YELLOW}Agent $STRATEGY_AGENT_ID can now trade on behalf of:${NC}"
echo "  $USER_WALLET"
echo ""
echo "To revoke at any time:"
echo "  cast send <AgentRouter> \"revoke(uint256)\" $STRATEGY_AGENT_ID --private-key \$USER_PRIVATE_KEY"
