#!/bin/bash

ORACLE="0x83187ccD22D4e8DFf2358A09750331775A207E13"
IDRX="0x80fd9a0f8bca5255692016d67e0733bf5262c142"
WETH="0x8b732595a59c9a18aca0aca3221a656eb38158fc"
RPC="https://sepolia.base.org"

echo "=== ORACLE CONFIGURATION CHECK ==="
echo "Oracle: $ORACLE"
echo ""

echo "=== Method 1: Check Price Feed Addresses ==="
echo -n "IDRX price feed address: "
cast call $ORACLE "priceFeeds(address)(address)" $IDRX --rpc-url $RPC 2>&1 | head -1
echo -n "WETH price feed address: "
cast call $ORACLE "priceFeeds(address)(address)" $WETH --rpc-url $RPC 2>&1 | head -1
echo ""

echo "=== Method 2: Check if tokens are registered ==="
echo -n "Is IDRX registered: "
cast call $ORACLE "isTokenSupported(address)(bool)" $IDRX --rpc-url $RPC 2>&1 | head -1
echo -n "Is WETH registered: "
cast call $ORACLE "isTokenSupported(address)(bool)" $WETH --rpc-url $RPC 2>&1 | head -1
echo ""

echo "=== Method 3: Try getting latest prices ==="
echo -n "IDRX latest price: "
cast call $ORACLE "latestPrice(address)(uint256)" $IDRX --rpc-url $RPC 2>&1 | head -1
echo -n "WETH latest price: "
cast call $ORACLE "latestPrice(address)(uint256)" $WETH --rpc-url $RPC 2>&1 | head -1
echo ""

echo "=== Method 4: Check supported assets list ==="
echo "Supported assets:"
cast call $ORACLE "getSupportedAssets()(address[])" --rpc-url $RPC 2>&1 | head -10
echo ""

echo "=== Method 5: Check owner/admin ==="
echo -n "Oracle owner: "
cast call $ORACLE "owner()(address)" --rpc-url $RPC 2>&1 | head -1
echo ""
