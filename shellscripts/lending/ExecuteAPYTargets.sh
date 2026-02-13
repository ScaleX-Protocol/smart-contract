#!/bin/bash
set -e

echo "================================================================"
echo "DIRECT APY TARGET EXECUTION"
echo "================================================================"
echo ""

# Load environment
source .env

# Use Infura RPC or fallback to public
RPC_URL="${SCALEX_CORE_RPC:-https://sepolia.base.org}"

# Contract addresses
LENDING_MANAGER="0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c"
WETH="0x8b732595a59c9a18acA0Aca3221A656Eb38158fC"
GOLD="0x880499B04c3858B53572734cADBb84Ae8d05752a"
MNT="0x2a6Fcb07885B1Bde6330B9eD78A322059e5B302A"

TEST_ACCOUNT=$(cast wallet address --private-key "$PRIVATE_KEY")

echo "Account: $TEST_ACCOUNT"
echo "RPC: ${RPC_URL:0:40}..."
echo ""

# Quick health factor check
echo "Initial Health Factor:"
cast call $LENDING_MANAGER "getHealthFactor(address)(uint256)" $TEST_ACCOUNT --rpc-url $RPC_URL 2>/dev/null | awk '{printf "%.2f\n", $1/1e18}'
echo ""

echo "================================================================"
echo "EXECUTING BORROWS"
echo "================================================================"
echo ""

# Phase 1: Test with 1 MNT
echo "1. TEST BORROW: 1 MNT"
echo "-------------------"
cast send $LENDING_MANAGER \
    "borrow(address,uint256)" \
    $MNT \
    1000000000000000000 \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --gas-limit 500000 \
    --json 2>&1 | jq -r '.transactionHash // .hash // "FAILED"' | head -1

echo ""
sleep 3

# Phase 2: Full MNT borrow - 14,961,200 MNT for 1.13% APY
echo "2. MNT: 14,961,200 tokens for 1.13% APY"
echo "----------------------------------------"
cast send $LENDING_MANAGER \
    "borrow(address,uint256)" \
    $MNT \
    14961200000000000000000000 \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --gas-limit 500000 \
    --json 2>&1 | jq -r '.transactionHash // .hash // "FAILED"' | head -1

echo ""
sleep 3

# Phase 3: GOLD borrow - 54,912 GOLD for 0.39% APY
echo "3. GOLD: 54,912 tokens for 0.39% APY"
echo "-------------------------------------"
cast send $LENDING_MANAGER \
    "borrow(address,uint256)" \
    $GOLD \
    54912000000000000000000 \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --gas-limit 500000 \
    --json 2>&1 | jq -r '.transactionHash // .hash // "FAILED"' | head -1

echo ""
sleep 3

# Phase 4: WETH borrow - 685,246 WETH for 2% APY (MAIN TARGET)
echo "4. WETH: 685,246 tokens for 2.00% APY (MAIN TARGET)"
echo "----------------------------------------------------"
cast send $LENDING_MANAGER \
    "borrow(address,uint256)" \
    $WETH \
    685246385199241070903296 \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --gas-limit 500000 \
    --json 2>&1 | jq -r '.transactionHash // .hash // "FAILED"' | head -1

echo ""
sleep 3

echo "================================================================"
echo "FINAL STATE"
echo "================================================================"
echo ""

echo "Final Health Factor:"
cast call $LENDING_MANAGER "getHealthFactor(address)(uint256)" $TEST_ACCOUNT --rpc-url $RPC_URL 2>/dev/null | awk '{printf "%.2f\n", $1/1e18}'

echo ""
echo "================================================================"
echo "Wait 30 seconds, then verify via indexer:"
echo "curl -s http://localhost:42070/api/lending/dashboard/$TEST_ACCOUNT"
echo "================================================================"
