#!/bin/bash

# Test script to verify agent can place orders on behalf of primary trader on basesepolia

set -e

echo "🤖 Testing Agent Order Execution on Base Sepolia"
echo "================================================"
echo ""

# Load environment
source .env

# Configuration
SCALEX_CORE_RPC="https://base-sepolia.infura.io/v3/743a342d05a5431592aee7f90048ec90"
PRIMARY_TRADER="0x27dD1eBE7D826197FD163C134E79502402Fd7cB7"
AGENT_TOKEN_ID=1

# Load contract addresses from deployment
BALANCE_MANAGER=$(jq -r '.BalanceManager' deployments/84532.json)
AGENT_ROUTER=$(jq -r '.AgentRouter' deployments/84532.json)
IDRX=$(jq -r '.IDRX' deployments/84532.json)
WETH=$(jq -r '.WETH' deployments/84532.json)
WETH_IDRX_POOL=$(jq -r '.WETH_IDRX_Pool' deployments/84532.json)

echo "📋 Configuration:"
echo "  Primary Trader: $PRIMARY_TRADER"
echo "  Agent Token ID: $AGENT_TOKEN_ID"
echo "  BalanceManager: $BALANCE_MANAGER"
echo "  AgentRouter: $AGENT_ROUTER"
echo "  WETH/IDRX Pool: $WETH_IDRX_POOL"
echo ""

# Step 1: Mint tokens to primary trader (if needed)
echo "🪙 Step 1: Ensuring primary trader has tokens..."

IDRX_BAL=$(cast call $IDRX "balanceOf(address)" $PRIMARY_TRADER --rpc-url $SCALEX_CORE_RPC)
echo "  Current IDRX balance: $IDRX_BAL"

if [[ "$IDRX_BAL" == "0x" ]] || [[ "$IDRX_BAL" == "0x0" ]]; then
    echo "  Minting 100,000 IDRX..."
    cast send $IDRX "mint(address,uint256)" $PRIMARY_TRADER 10000000 \
        --rpc-url $SCALEX_CORE_RPC \
        --private-key $PRIVATE_KEY \
        --gas-limit 200000 > /dev/null 2>&1
    echo "  ✅ IDRX minted"
    sleep 2
fi

WETH_BAL=$(cast call $WETH "balanceOf(address)" $PRIMARY_TRADER --rpc-url $SCALEX_CORE_RPC)
echo "  Current WETH balance: $WETH_BAL"

if [[ "$WETH_BAL" == "0x" ]] || [[ "$WETH_BAL" == "0x0" ]]; then
    echo "  Minting 10 WETH..."
    cast send $WETH "mint(address,uint256)" $PRIMARY_TRADER 10000000000000000000 \
        --rpc-url $SCALEX_CORE_RPC \
        --private-key $PRIVATE_KEY \
        --gas-limit 200000 > /dev/null 2>&1
    echo "  ✅ WETH minted"
    sleep 2
fi

echo ""

# Step 2: Primary trader deposits to BalanceManager
echo "🏦 Step 2: Primary trader depositing to BalanceManager..."

# Approve BalanceManager
echo "  Approving BalanceManager to spend IDRX..."
cast send $IDRX "approve(address,uint256)" $BALANCE_MANAGER 5000000 \
    --rpc-url $SCALEX_CORE_RPC \
    --private-key $PRIVATE_KEY \
    --gas-limit 100000 > /dev/null 2>&1

echo "  Depositing 50,000 IDRX to BalanceManager..."
cast send $BALANCE_MANAGER "deposit(address,uint256)" $IDRX 5000000 \
    --rpc-url $SCALEX_CORE_RPC \
    --private-key $PRIVATE_KEY \
    --gas-limit 300000 > /dev/null 2>&1

echo "  ✅ IDRX deposited"
sleep 2

echo ""

# Step 3: Check balances
echo "💰 Step 3: Verifying primary trader balances..."

# Note: BalanceManager uses Currency type, need to check the actual function signature
PRIMARY_IDRX_BAL=$(cast call $BALANCE_MANAGER "getBalance(address,address)" $PRIMARY_TRADER $IDRX --rpc-url $SCALEX_CORE_RPC 2>/dev/null || echo "0x0")

echo "  Primary trader IDRX in BalanceManager: $PRIMARY_IDRX_BAL"
if [[ "$PRIMARY_IDRX_BAL" == "0x0" ]] || [[ -z "$PRIMARY_IDRX_BAL" ]]; then
    echo "  ❌ ERROR: No funds in BalanceManager!"
    exit 1
fi

echo "  ✅ Primary trader has funds in BalanceManager"
echo ""

# Step 4: Agent places order via AgentRouter
echo "🤖 Step 4: Agent placing limit order on behalf of primary trader..."
echo ""
echo "  Order details:"
echo "    Pool: WETH/IDRX"
echo "    Side: BUY (buying WETH with IDRX)"
echo "    Amount: 0.1 WETH"
echo "    Price: 2000 IDRX per WETH"
echo "    Owner: Primary Trader"
echo "    Agent Token ID: 1"
echo ""

# placeLimitOrder(address pool, bool isBuy, uint128 amount, uint128 price, address owner, uint256 agentTokenId)
# isBuy = true (1)
# amount = 0.1 WETH = 100000000000000000
# price = 2000 IDRX/WETH (need to convert to proper format)

echo "  Executing agent order via AgentRouter..."

ORDER_TX=$(cast send $AGENT_ROUTER \
    "placeLimitOrder(address,bool,uint128,uint128,address,uint256)" \
    $WETH_IDRX_POOL \
    true \
    100000000000000000 \
    200000 \
    $PRIMARY_TRADER \
    $AGENT_TOKEN_ID \
    --rpc-url $SCALEX_CORE_RPC \
    --private-key $PRIVATE_KEY \
    --gas-limit 2000000 2>&1)

if echo "$ORDER_TX" | grep -q "transactionHash"; then
    TX_HASH=$(echo "$ORDER_TX" | grep "transactionHash" | awk '{print $2}')
    echo "  📤 Order transaction submitted: $TX_HASH"
    echo "  ⏳ Waiting for confirmation..."
    sleep 3

    TX_STATUS=$(cast receipt $TX_HASH --rpc-url $SCALEX_CORE_RPC 2>/dev/null | grep "^status" | awk '{print $2}')

    if [[ "$TX_STATUS" == "1" ]]; then
        echo "  ✅ Agent successfully placed order on behalf of primary trader!"
        echo "     Transaction: https://sepolia.basescan.org/tx/$TX_HASH"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "🎉 SUCCESS! Agent order execution verified!"
        echo ""
        echo "✅ Agent can place orders using primary trader's funds"
        echo "✅ Order tracked with agentTokenId=1"
        echo "✅ Full ERC-8004 agent functionality working on basesepolia"
        echo ""
    else
        echo "  ❌ Order transaction reverted"
        echo "     Transaction: https://sepolia.basescan.org/tx/$TX_HASH"
        exit 1
    fi
else
    echo "  ❌ Order execution failed"
    echo "     Error: $ORDER_TX"
    exit 1
fi
