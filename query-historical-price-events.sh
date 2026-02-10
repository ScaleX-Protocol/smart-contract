#!/bin/bash

ORACLE="0x83187ccD22D4e8DFf2358A09750331775A207E13"
SXIDRX="0x70aF07fBa93Fe4A17d9a6C9f64a2888eAF8E9624"
SXWETH="0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6"
RPC="https://sepolia.base.org"
PRICE_UPDATE_SIG="0xac7b695c6873047ad50339f850f4ae3f6b8f6ef63ed1a8b22f7d36a1c6bd46f3"

echo "=== HISTORICAL ORACLE PRICE UPDATES ==="
echo "Oracle: $ORACLE"
echo ""

# Get current block
CURRENT_BLOCK=$(cast block-number --rpc-url $RPC)
echo "Current block: $CURRENT_BLOCK"

# Query last 10000 blocks
FROM_BLOCK=$((CURRENT_BLOCK - 10000))
echo "Querying from block: $FROM_BLOCK"
echo ""

echo "Fetching PriceUpdate events for sxIDRX..."
IDRX_TOPIC="0x00000000000000000000000070af07fba93fe4a17d9a6c9f64a2888eaf8e9624"

# Build filter for sxIDRX price updates
echo "cast logs \\"
echo "  --from-block $FROM_BLOCK \\"
echo "  --to-block latest \\"
echo "  --address $ORACLE \\"
echo "  --rpc-url $RPC \\"
echo "  $PRICE_UPDATE_SIG \\"
echo "  $IDRX_TOPIC" | sh 2>&1 | head -50

