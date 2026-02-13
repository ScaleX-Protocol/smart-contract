#!/bin/bash

# Manual Agent Setup Fix
# Works around the IdentityRegistry address mismatch by using existing setup

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== MANUAL AGENT SETUP FIX ===${NC}"
echo ""

source .env

# Addresses
WORKING_IDENTITY_REGISTRY="0xf96d030bcf6ebbaa2feadfa3849d5e690b72974a"
PRIMARY_WALLET="$PRIMARY_WALLET_ADDRESS"
AGENT_TOKEN_ID="100"  # Already minted

echo -e "${BLUE}Using:${NC}"
echo "  IdentityRegistry: $WORKING_IDENTITY_REGISTRY"
echo "  Primary Wallet: $PRIMARY_WALLET"
echo "  Agent Token ID: $AGENT_TOKEN_ID"
echo ""

# Step 1: Verify agent ownership
echo -e "${YELLOW}Step 1: Verifying agent ownership...${NC}"
OWNER=$(cast call $WORKING_IDENTITY_REGISTRY "ownerOf(uint256)" $AGENT_TOKEN_ID --rpc-url $SCALEX_CORE_RPC)
OWNER_ADDR="0x${OWNER:26}"

if [ "$OWNER_ADDR" != "${PRIMARY_WALLET,,}" ]; then
    echo -e "${RED}Error: Agent token $AGENT_TOKEN_ID not owned by primary wallet${NC}"
    echo "  Owner: $OWNER_ADDR"
    echo "  Expected: ${PRIMARY_WALLET,,}"
    exit 1
fi

echo -e "${GREEN}✓ Agent token $AGENT_TOKEN_ID owned by primary wallet${NC}"
echo ""

# Step 2: Install agent policy using PolicyFactory (works with correct IdentityRegistry)
echo -e "${YELLOW}Step 2: Installing agent policy...${NC}"
echo ""
echo -e "${BLUE}Note:${NC} PolicyFactory is configured with wrong IdentityRegistry"
echo "We'll need to either:"
echo "  a) Redeploy PolicyFactory (requires forge)"
echo "  b) Skip policy and test direct OrderBook trading"
echo "  c) Deploy a new PolicyFactory manually"
echo ""

# Step 3: Authorize executors using AgentRouter
echo -e "${YELLOW}Step 3: Executor authorization...${NC}"
echo ""
echo -e "${BLUE}Note:${NC} AgentRouter is configured with wrong IdentityRegistry"
echo "Agent authorization will fail because AgentRouter can't see our agent"
echo ""

# Summary
echo -e "${YELLOW}=== CURRENT SITUATION ===${NC}"
echo ""
echo "✅ Wallets funded and ready"
echo "✅ 10,000 IDRX deposited to BalanceManager"
echo "✅ Agent NFT #$AGENT_TOKEN_ID minted to primary wallet"
echo ""
echo "❌ AgentRouter misconfigured (can't see our agent)"
echo "❌ PolicyFactory misconfigured (can't see our agent)"
echo ""

# Alternative solution
echo -e "${YELLOW}=== ALTERNATIVE: Use Deployer's Agent ===${NC}"
echo ""
echo "Token ID 1 exists and is owned by deployer wallet"
echo "We can:"
echo "  1. Transfer token #1 to primary wallet"
echo "  2. OR use deployer wallet as agent owner"
echo ""

# Get deployer wallet
DEPLOYER=$(cast wallet address --private-key $(cast wallet derive-private-key "$SEED_PHRASE" 0))
echo "Deployer wallet: $DEPLOYER"

# Check if deployer owns token 1
TOKEN_1_OWNER=$(cast call $WORKING_IDENTITY_REGISTRY "ownerOf(uint256)" 1 --rpc-url $SCALEX_CORE_RPC 2>&1 || echo "0x0")
if [[ "$TOKEN_1_OWNER" != "0x0" ]]; then
    TOKEN_1_OWNER_ADDR="0x${TOKEN_1_OWNER:26}"
    echo "Token #1 owner: $TOKEN_1_OWNER_ADDR"

    if [ "$TOKEN_1_OWNER_ADDR" == "${DEPLOYER,,}" ]; then
        echo -e "${GREEN}✓ Deployer owns token #1${NC}"
        echo ""
        echo "Would you like to transfer token #1 to primary wallet? (y/n)"
        read -r REPLY
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Transferring token #1..."
            DEPLOYER_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" 0)

            # Transfer using the working contract
            cast send $WORKING_IDENTITY_REGISTRY "transferFrom(address,address,uint256)" \
                $DEPLOYER $PRIMARY_WALLET 1 \
                --private-key $DEPLOYER_KEY \
                --rpc-url $SCALEX_CORE_RPC \
                --legacy

            echo -e "${GREEN}✓ Token #1 transferred to primary wallet${NC}"
            AGENT_TOKEN_ID="1"
        fi
    fi
else
    echo "Token #1 does not exist on working contract"
fi

echo ""
echo -e "${YELLOW}=== RECOMMENDATION ===${NC}"
echo ""
echo "The socket error prevents forge deployment."
echo ""
echo "Best options:"
echo "  1. Fix forge/foundry installation"
echo "  2. Deploy Phase 5 from a different machine"
echo "  3. Use token #1 as workaround for immediate testing"
echo "  4. Test OrderBook directly without agent system"
echo ""
