#!/bin/bash

# Manual upgrade and authorization script
# Run this if forge script broadcasts are not working

set -e

# Load environment variables
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

if [ -z "$PRIVATE_KEY" ]; then
  echo "Error: PRIVATE_KEY not set. Please set it in .env or export it."
  exit 1
fi

RPC="https://base-sepolia.infura.io/v3/743a342d05a5431592aee7f90048ec90"

echo "=== MANUAL UPGRADE AND AUTHORIZATION ==="
echo ""

# Step 1: Deploy OrderBook implementation
echo "Step 1: Deploying OrderBook implementation..."
ORDERBOOK_IMPL=$(forge create src/core/OrderBook.sol:OrderBook \
  --rpc-url $RPC \
  --private-key $PRIVATE_KEY \
  --json | jq -r '.deployedTo')
echo "OrderBook implementation: $ORDERBOOK_IMPL"
echo ""

# Step 2: Deploy PoolManager implementation
echo "Step 2: Deploying PoolManager implementation..."
POOLMANAGER_IMPL=$(forge create src/core/PoolManager.sol:PoolManager \
  --rpc-url $RPC \
  --private-key $PRIVATE_KEY \
  --json | jq -r '.deployedTo')
echo "PoolManager implementation: $POOLMANAGER_IMPL"
echo ""

# Step 3: Upgrade OrderBook beacon
echo "Step 3: Upgrading OrderBook beacon..."
cast send 0xF756457e5CB37EB69A36cb62326Ae0FeE20f0765 \
  "upgradeTo(address)" $ORDERBOOK_IMPL \
  --rpc-url $RPC \
  --private-key $PRIVATE_KEY
echo "OrderBook beacon upgraded!"
echo ""

# Step 4: Upgrade PoolManager beacon
echo "Step 4: Upgrading PoolManager beacon..."
cast send 0x2122F7Afef5D7E921482C0c55d4F975c50577D90 \
  "upgradeTo(address)" $POOLMANAGER_IMPL \
  --rpc-url $RPC \
  --private-key $PRIVATE_KEY
echo "PoolManager beacon upgraded!"
echo ""

# Step 5: Authorize AgentRouter on all pools
echo "Step 5: Authorizing AgentRouter on all pools..."

POOL_MANAGER="0x630D8C79407CB90e0AFE68E3841eadd3F94Fc81F"
AGENT_ROUTER="0x91136624222e2faAfBfdE8E06C412649aB2b90D0"

POOLS=(
  "0x629A14ee7dC9D29A5EB676FBcEF94E989Bc0DEA1:WETH"
  "0xF436bE2abbf4471d7E68a6f8d93B4195b1c6FbE3:WBTC"
  "0x5EF80d453CED464E135B4b25e9eD423b033ad87F:GOLD"
  "0x1f90De5A004b727c4e2397ECf15fc3C8F300b035:SILVER"
  "0x876805DC517c4822fE7646c325451eA14263F125:GOOGLE"
  "0x0026812e5DFaA969f1827748003A3b5A3CcBA084:NVIDIA"
  "0xFA783bdcC0128cbc7c99847e7afA40B20A3c16F9:MNT"
  "0x82228b2Df03EA8a446F384D6c62e87e5E7bF4cd7:APPLE"
)

for pool_info in "${POOLS[@]}"; do
  POOL_ADDR="${pool_info%%:*}"
  POOL_NAME="${pool_info##*:}"

  echo "  Authorizing AgentRouter on $POOL_NAME pool..."
  cast send $POOL_MANAGER \
    "addAuthorizedRouterToOrderBook(address,address)" \
    $POOL_ADDR $AGENT_ROUTER \
    --rpc-url $RPC \
    --private-key $PRIVATE_KEY
  echo "  [OK] $POOL_NAME"
done

echo ""
echo "[SUCCESS] All upgrades and authorizations complete!"
echo "OrderBook implementation: $ORDERBOOK_IMPL"
echo "PoolManager implementation: $POOLMANAGER_IMPL"
