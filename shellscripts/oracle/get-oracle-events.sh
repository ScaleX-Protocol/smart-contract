#!/bin/bash
set -e

ORACLE="0x83187ccD22D4e8DFf2358A09750331775A207E13"
SXIDRX="0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624"
SXWETH="0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6"
RPC="https://sepolia.base.org"

echo "=== ORACLE PRICE UPDATE EVENTS ANALYSIS ==="
echo "Oracle: $ORACLE"
echo ""

# PriceUpdate(address indexed token, uint256 price, uint256 timestamp)
PRICE_UPDATE_SIG="PriceUpdate(address,uint256,uint256)"

echo "Getting deployment block..."
# Get first transaction to oracle to find deployment block
DEPLOY_BLOCK=$(cast logs --from-block 0 --to-block latest --address $ORACLE --rpc-url $RPC 2>/dev/null | head -1 | grep -oE 'blockNumber[^,]*' | grep -oE '[0-9]+' || echo "37000000")

echo "Deployment block (approx): $DEPLOY_BLOCK"
echo ""

echo "Fetching PriceUpdate events..."
echo "Event signature: $PRICE_UPDATE_SIG"
echo ""

# Get logs using cast
echo "=== ALL EVENTS FROM ORACLE ==="
cast logs --from-block $DEPLOY_BLOCK --to-block latest --address $ORACLE --rpc-url $RPC 2>&1 | head -200

