#!/bin/bash

ORACLE="0x83187ccD22D4e8DFf2358A09750331775A207E13"
IDRX="0x80fd9a0f8bca5255692016d67e0733bf5262c142"
WETH="0x8b732595a59c9a18aca0aca3221a656eb38158fc"
RPC="https://sepolia.base.org"

echo "=== ORACLE INVESTIGATION ==="
echo "Oracle: $ORACLE"
echo ""

# Try different methods
echo "Method 1: getTokenPrice(address)"
echo -n "IDRX: "
cast call $ORACLE "getTokenPrice(address)(uint256)" $IDRX --rpc-url $RPC 2>&1 || echo "FAILED"
echo -n "WETH: "
cast call $ORACLE "getTokenPrice(address)(uint256)" $WETH --rpc-url $RPC 2>&1 || echo "FAILED"
echo ""

echo "Method 2: Check if prices are cached/stored"
echo -n "IDRX price (storage): "
cast call $ORACLE "prices(address)(uint256)" $IDRX --rpc-url $RPC 2>&1 || echo "No prices mapping"
echo -n "WETH price (storage): "
cast call $ORACLE "prices(address)(uint256)" $WETH --rpc-url $RPC 2>&1 || echo "No prices mapping"
echo ""

echo "Method 3: Check oracle type/implementation"
echo -n "Oracle code size: "
cast code $ORACLE --rpc-url $RPC | wc -c
echo ""

echo "Let's check what's in the oracle contract..."
cast code $ORACLE --rpc-url $RPC | head -c 200
echo ""
