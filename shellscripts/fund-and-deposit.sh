#!/bin/bash

# Fund and Deposit Script
# Simplified setup that just deposits funds to BalanceManager
# Skip agent minting for now

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== FUND AND DEPOSIT TO BALANCE MANAGER ===${NC}"
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
    exit 1
fi

# Derive addresses
PRIMARY_WALLET=$(cast wallet address --private-key $PRIMARY_WALLET_KEY)

# Load deployment addresses
CORE_CHAIN_ID="${CORE_CHAIN_ID:-84532}"
DEPLOYMENTS_FILE="deployments/${CORE_CHAIN_ID}.json"

if [ ! -f "$DEPLOYMENTS_FILE" ]; then
    echo -e "${RED}Error: Deployments file not found: $DEPLOYMENTS_FILE${NC}"
    exit 1
fi

BALANCE_MANAGER=$(cat "$DEPLOYMENTS_FILE" | jq -r '.BalanceManager')
QUOTE_TOKEN=$(cat "$DEPLOYMENTS_FILE" | jq -r '.'"${QUOTE_SYMBOL:-IDRX}")

echo -e "${BLUE}Configuration:${NC}"
echo "  RPC: $SCALEX_CORE_RPC"
echo "  Chain ID: $CORE_CHAIN_ID"
echo "  Quote Token: ${QUOTE_SYMBOL:-IDRX}"
echo ""
echo -e "${BLUE}Addresses:${NC}"
echo "  Primary Wallet: $PRIMARY_WALLET"
echo "  Balance Manager: $BALANCE_MANAGER"
echo "  Quote Token: $QUOTE_TOKEN"
echo ""

# Check balance
echo "Checking primary wallet balance..."
BALANCE=$(cast call $QUOTE_TOKEN "balanceOf(address)" $PRIMARY_WALLET --rpc-url $SCALEX_CORE_RPC)
BALANCE_DEC=$(python3 -c "print(int('$BALANCE', 16) // (10 ** ${QUOTE_DECIMALS:-6}))")
echo "  Current balance: $BALANCE_DEC ${QUOTE_SYMBOL:-IDRX}"
echo ""

if [ "$BALANCE_DEC" -lt 10000 ]; then
    echo -e "${YELLOW}Warning: Insufficient balance (need 10,000)${NC}"
    echo "Run ./shellscripts/fund-agent-wallets.sh first"
    exit 1
fi

# Deposit to BalanceManager
DEPOSIT_AMOUNT="10000"
DEPOSIT_AMOUNT_WEI=$(python3 -c "print($DEPOSIT_AMOUNT * (10 ** ${QUOTE_DECIMALS:-6}))")

echo "Depositing $DEPOSIT_AMOUNT ${QUOTE_SYMBOL:-IDRX} to BalanceManager..."
echo ""

# Approve
echo "1. Approving BalanceManager..."
cast send $QUOTE_TOKEN "approve(address,uint256)" $BALANCE_MANAGER "115792089237316195423570985008687907853269984665640564039457584007913129639935" \
    --private-key $PRIMARY_WALLET_KEY \
    --rpc-url $SCALEX_CORE_RPC \
    --legacy

sleep 2

# Deposit using depositLocal
echo "2. Depositing funds..."
cast send $BALANCE_MANAGER "depositLocal(address,uint256,address)" \
    $QUOTE_TOKEN $DEPOSIT_AMOUNT_WEI $PRIMARY_WALLET \
    --private-key $PRIMARY_WALLET_KEY \
    --rpc-url $SCALEX_CORE_RPC \
    --legacy

echo ""
echo -e "${GREEN}=== DEPOSIT COMPLETE ===${NC}"
echo ""
echo "Next: Test trading with AgentRouter"
echo "  ./shellscripts/agent-executor-trade.sh"
echo ""
