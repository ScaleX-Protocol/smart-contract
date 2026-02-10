#!/bin/bash
set -e

echo "================================================================"
echo "APY TARGET EXECUTION - V2 (Higher Gas Limit)"
echo "================================================================"
echo ""

# Load environment
source .env

# Use public Base Sepolia RPC (no rate limits)
RPC_URL="https://sepolia.base.org"

# Contract addresses
LENDING_MANAGER="0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c"
WETH="0x8b732595a59c9a18acA0Aca3221A656Eb38158fC"
GOLD="0x880499B04c3858B53572734cADBb84Ae8d05752a"
MNT="0x2a6Fcb07885B1Bde6330B9eD78A322059e5B302A"

TEST_ACCOUNT=$(cast wallet address --private-key "$PRIVATE_KEY")

echo "Account: $TEST_ACCOUNT"
echo "RPC: $RPC_URL"
echo ""

# Health factor check
echo "Initial Health Factor:"
cast call $LENDING_MANAGER "getHealthFactor(address)(uint256)" $TEST_ACCOUNT --rpc-url $RPC_URL 2>/dev/null | awk '{printf "%.2f\n", $1/1e18}'
echo ""

echo "================================================================"
echo "EXECUTING BORROWS WITH 2M GAS LIMIT"
echo "================================================================"
echo ""

# Test with 1 MNT first - 2M gas limit
echo "1. TEST BORROW: 1 MNT (2M gas)"
echo "-------------------------------"
TX=$(cast send $LENDING_MANAGER \
    "borrow(address,uint256)" \
    $MNT \
    1000000000000000000 \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --gas-limit 2000000 \
    --json 2>&1)

if echo "$TX" | jq -e '.transactionHash or .hash' > /dev/null 2>&1; then
    TX_HASH=$(echo "$TX" | jq -r '.transactionHash // .hash')
    echo "TX: $TX_HASH"

    # Wait and check status
    sleep 5
    STATUS=$(cast receipt $TX_HASH --rpc-url $RPC_URL --json 2>&1 | jq -r '.status')
    if [ "$STATUS" == "0x1" ]; then
        echo "✅ SUCCESS! Test borrow worked with 2M gas."
        echo ""

        # Proceed with full borrows
        echo "================================================================"
        echo "EXECUTING FULL BORROWS"
        echo "================================================================"
        echo ""

        # MNT - 14,961,200 MNT for 1.13% APY
        echo "2. MNT: 14,961,200 tokens for 1.13% APY"
        echo "----------------------------------------"
        cast send $LENDING_MANAGER \
            "borrow(address,uint256)" \
            $MNT \
            14961200000000000000000000 \
            --private-key $PRIVATE_KEY \
            --rpc-url $RPC_URL \
            --gas-limit 2000000 \
            2>&1 | tee /tmp/mnt_borrow.log

        sleep 5

        # GOLD - 54,912 GOLD for 0.39% APY
        echo ""
        echo "3. GOLD: 54,912 tokens for 0.39% APY"
        echo "-------------------------------------"
        cast send $LENDING_MANAGER \
            "borrow(address,uint256)" \
            $GOLD \
            54912000000000000000000 \
            --private-key $PRIVATE_KEY \
            --rpc-url $RPC_URL \
            --gas-limit 2000000 \
            2>&1 | tee /tmp/gold_borrow.log

        sleep 5

        # WETH - 685,246 WETH for 2% APY
        echo ""
        echo "4. WETH: 685,246 tokens for 2.00% APY"
        echo "--------------------------------------"
        cast send $LENDING_MANAGER \
            "borrow(address,uint256)" \
            $WETH \
            685246385199241070903296 \
            --private-key $PRIVATE_KEY \
            --rpc-url $RPC_URL \
            --gas-limit 2000000 \
            2>&1 | tee /tmp/weth_borrow.log

    else
        echo "❌ FAILED with status: $STATUS"
        echo "Even with 2M gas, the borrow failed."
        echo "This suggests a different issue than gas limit."
    fi
else
    echo "❌ Transaction submission failed"
    echo "$TX"
fi

echo ""
echo "================================================================"
echo "FINAL STATE"
echo "================================================================"
echo ""

echo "Final Health Factor:"
cast call $LENDING_MANAGER "getHealthFactor(address)(uint256)" $TEST_ACCOUNT --rpc-url $RPC_URL 2>/dev/null | awk '{printf "%.2f\n", $1/1e18}'

echo ""
echo "Wait 30 seconds for indexer, then check:"
echo "curl -s http://localhost:42070/api/lending/dashboard/$TEST_ACCOUNT | jq '.supplies[] | select(.asset == \"WETH\" or .asset == \"GOLD\" or .asset == \"MNT\") | {asset, apy}'"
