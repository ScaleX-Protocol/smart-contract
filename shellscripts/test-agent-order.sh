#!/bin/bash

# Test Agent Order Placement
# This script demonstrates placing an order via AgentRouter to verify full agent integration

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== AGENT ORDER PLACEMENT TEST ===${NC}"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

# Load environment
source .env

# Validate required variables
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set in .env${NC}"
    exit 1
fi

if [ -z "$SCALEX_CORE_RPC" ]; then
    echo -e "${RED}Error: SCALEX_CORE_RPC not set in .env${NC}"
    exit 1
fi

if [ -z "$QUOTE_SYMBOL" ]; then
    echo -e "${YELLOW}Warning: QUOTE_SYMBOL not set, defaulting to USDC${NC}"
    export QUOTE_SYMBOL="USDC"
fi

echo -e "${BLUE}Configuration:${NC}"
echo "  RPC: $SCALEX_CORE_RPC"
echo "  Quote Currency: $QUOTE_SYMBOL"
echo ""

# Run the test script
echo -e "${BLUE}Running agent order test...${NC}"
echo ""

forge script script/agents/TestAgentOrder.s.sol:TestAgentOrder \
    --rpc-url "$SCALEX_CORE_RPC" \
    --broadcast \
    --private-key "$PRIVATE_KEY" \
    --gas-estimate-multiplier 120 \
    --legacy

echo ""
echo -e "${GREEN}=== TEST COMPLETE ===${NC}"
echo ""
echo -e "${YELLOW}What was tested:${NC}"
echo "  ✓ Agent identity (mint if needed)"
echo "  ✓ Policy creation (create if needed)"
echo "  ✓ Fund deposit to BalanceManager"
echo "  ✓ Market order execution via AgentRouter"
echo ""
echo -e "${YELLOW}To run again:${NC}"
echo "  ./shellscripts/test-agent-order.sh"
