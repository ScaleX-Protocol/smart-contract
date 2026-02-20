#!/bin/bash

# Simple test to borrow 1 WETH through ScaleXRouter

set -e

source .env

SCALEX_ROUTER=$(jq -r '.ScaleXRouter' deployments/84532.json)
WETH=$(jq -r '.WETH' deployments/84532.json)
DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)

echo "=== Simple Borrow Test ==="
echo "Deployer: $DEPLOYER"
echo "ScaleXRouter: $SCALEX_ROUTER"
echo "WETH: $WETH"
echo ""
echo "Attempting to borrow 1 WETH..."
echo ""

# Try borrowing 1 WETH
cast send $SCALEX_ROUTER \
    "borrow(address,uint256)" \
    $WETH \
    1000000000000000000 \
    --private-key $PRIVATE_KEY \
    --rpc-url $SCALEX_CORE_RPC \
    --gas-limit 1000000

echo ""
echo "If you see status 1 above, borrowing WORKED!"
echo "If you see status 0, it failed and we need more debugging."
