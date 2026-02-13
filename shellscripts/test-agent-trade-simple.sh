#!/bin/bash

# Simple Agent Executor Trade Test
# Uses cast directly to avoid forge socket error

set -e

source .env

# Configuration
AGENT_ID="100"
EXECUTOR_KEY="$AGENT_EXECUTOR_1_KEY"
EXECUTOR_ADDR="0xfc98C3eD81138d8A5f35b30A3b735cB5362e14Dc"
PRIMARY_WALLET="$PRIMARY_WALLET_ADDRESS"

# New contract addresses
AGENT_ROUTER="0x36f229515bf0e4c74165b214c56bE8c0b49a1574"
WETH_POOL=$(cat deployments/84532.json | jq -r '.WETH_IDRX_Pool')
WETH=$(cat deployments/84532.json | jq -r '.WETH')
IDRX=$(cat deployments/84532.json | jq -r '.IDRX')

echo "=== AGENT EXECUTOR TRADE TEST ==="
echo ""
echo "Agent ID: $AGENT_ID"
echo "Primary Wallet: $PRIMARY_WALLET"
echo "Executor: $EXECUTOR_ADDR"
echo ""

# Step 1: Verify executor authorization
echo "1. Verifying executor authorization..."
AUTH=$(cast call $AGENT_ROUTER "isExecutorAuthorized(uint256,address)" $AGENT_ID $EXECUTOR_ADDR --rpc-url $SCALEX_CORE_RPC)
if [ "$AUTH" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
    echo "✅ Executor is authorized"
else
    echo "❌ Executor not authorized!"
    exit 1
fi
echo ""

# Step 2: Check BalanceManager balance
echo "2. Checking BalanceManager balance..."
BAL_MGR=$(cat deployments/84532.json | jq -r '.BalanceManager')

# Get balance - this requires calling the right function
# Let's check if we can see the balance
echo "   Balance Manager: $BAL_MGR"
echo "   Primary Wallet: $PRIMARY_WALLET"
echo ""

# Step 3: Place a small test market order
echo "3. Placing test market order..."
echo "   Pool: WETH/IDRX"
echo "   Side: BUY"
echo "   Amount: 0.01 WETH (~$30)"
echo ""

# Order parameters
SIDE=0  # 0 = BUY, 1 = SELL
QUANTITY="10000000000000000"  # 0.01 WETH (18 decimals)

# Create pool struct bytes
# PoolStruct has: token0, token1, poolAddress
POOL_DATA=$(cast abi-encode "f((address,address,address))" "($WETH,$IDRX,$WETH_POOL)")

echo "Executing market order via AgentRouter..."
echo ""

# Call executeMarketOrder
# function executeMarketOrder(
#     uint256 agentTokenId,
#     PoolStruct calldata pool,
#     OrderSide side,
#     uint128 quantity,
#     uint128 minOutAmount,
#     bool useAutoBorrow,
#     bool autoRepay
# )

cast send $AGENT_ROUTER \
    "executeMarketOrder(uint256,(address,address,address),uint8,uint128,uint128,bool,bool)" \
    $AGENT_ID \
    "($WETH,$IDRX,$WETH_POOL)" \
    $SIDE \
    $QUANTITY \
    0 \
    false \
    false \
    --private-key "$EXECUTOR_KEY" \
    --rpc-url "$SCALEX_CORE_RPC" \
    --legacy \
    --gas-limit 1000000

echo ""
echo "=== TEST COMPLETE ==="
echo ""
