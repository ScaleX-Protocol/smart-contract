#!/bin/bash

# Authorize AgentRouter on all pools via upgraded PoolManager

set -e

# Load environment variables
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

if [ -z "$PRIVATE_KEY" ]; then
  echo "Error: PRIVATE_KEY not set"
  exit 1
fi

RPC="https://base-sepolia.infura.io/v3/743a342d05a5431592aee7f90048ec90"
POOL_MANAGER="0x630D8C79407CB90e0AFE68E3841eadd3F94Fc81F"
AGENT_ROUTER="0x91136624222e2faAfBfdE8E06C412649aB2b90D0"

echo "=== AUTHORIZING AGENT ROUTER ON ALL POOLS ==="
echo ""
echo "Pool Manager: $POOL_MANAGER"
echo "Agent Router: $AGENT_ROUTER"
echo ""

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

  echo "Authorizing AgentRouter on $POOL_NAME pool ($POOL_ADDR)..."
  cast send $POOL_MANAGER \
    "addAuthorizedRouterToOrderBook(address,address)" \
    $POOL_ADDR $AGENT_ROUTER \
    --rpc-url $RPC \
    --private-key $PRIVATE_KEY \
    --gas-limit 500000
  echo "[OK] $POOL_NAME authorized"
  echo ""
done

echo "[SUCCESS] All pools authorized!"
