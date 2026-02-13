#!/bin/bash
set -e

# Script to achieve remaining APY targets with safe borrowing
# Based on SAFE_APY_TARGETS_REPORT.md analysis
# Account has $6.8B additional borrowing capacity

echo "================================================================"
echo "ACHIEVING REMAINING APY TARGETS"
echo "================================================================"
echo ""

# Load environment - try main .env first (has Infura RPC), fallback to .env.base-sepolia
if [ -f .env ]; then
    source .env
elif [ -f .env.base-sepolia ]; then
    source .env.base-sepolia
else
    echo "Error: No .env file found"
    exit 1
fi

# Set RPC_URL from SCALEX_CORE_RPC, or use public Base Sepolia RPC
if [ -z "$RPC_URL" ]; then
    if [ -n "$SCALEX_CORE_RPC" ]; then
        RPC_URL="$SCALEX_CORE_RPC"
    else
        # Fallback to public Base Sepolia RPC
        RPC_URL="https://sepolia.base.org"
    fi
fi

if [ -z "$RPC_URL" ]; then
    echo "Error: RPC_URL not set"
    exit 1
fi

echo "Using RPC: ${RPC_URL:0:40}..."
echo ""

# Contract addresses from deployments
LENDING_MANAGER="0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c"
WETH="0x8b732595a59c9a18acA0Aca3221A656Eb38158fC"
GOLD="0x880499B04c3858B53572734cADBb84Ae8d05752a"
MNT="0x2a6Fcb07885B1Bde6330B9eD78A322059e5B302A"
TEST_ACCOUNT=$(cast wallet address --private-key "$PRIVATE_KEY")

echo "Test Account: $TEST_ACCOUNT"
echo "Lending Manager: $LENDING_MANAGER"
echo ""

# Function to check health factor
check_health_factor() {
    echo "Checking health factor..."
    HF_RAW=$(cast call $LENDING_MANAGER "getHealthFactor(address)(uint256)" $TEST_ACCOUNT --rpc-url $RPC_URL 2>&1)

    # Extract just the numeric part (before any [ or space)
    HF=$(echo "$HF_RAW" | awk '{print $1}')

    if echo "$HF" | grep -q "^[0-9]"; then
        # Valid number, calculate decimal
        if command -v python3 &> /dev/null; then
            HF_DECIMAL=$(python3 -c "print(f'{int($HF) / 1e18:.2f}')")
        else
            # Fallback to bc if python not available
            HF_DECIMAL=$(echo "scale=2; $HF / 1000000000000000000" | bc 2>/dev/null || echo "$HF (raw)")
        fi
        echo "Current Health Factor: $HF_DECIMAL"
    else
        echo "Health Factor: Unable to fetch (may indicate 0 debt or error)"
        echo "Raw response: $HF_RAW" | head -1
    fi
    echo ""
}

# Function to get pool state
get_pool_state() {
    local TOKEN=$1
    local SYMBOL=$2
    echo "Fetching $SYMBOL pool state..."

    TOTAL_LIQUIDITY_RAW=$(cast call $LENDING_MANAGER "getTotalLiquidity(address)(uint256)" $TOKEN --rpc-url $RPC_URL 2>&1)
    TOTAL_BORROWED_RAW=$(cast call $LENDING_MANAGER "getTotalBorrowed(address)(uint256)" $TOKEN --rpc-url $RPC_URL 2>&1)

    # Extract just the numeric part
    TOTAL_LIQUIDITY=$(echo "$TOTAL_LIQUIDITY_RAW" | awk '{print $1}')
    TOTAL_BORROWED=$(echo "$TOTAL_BORROWED_RAW" | awk '{print $1}')

    if echo "$TOTAL_LIQUIDITY" | grep -q "^[0-9]" && echo "$TOTAL_BORROWED" | grep -q "^[0-9]"; then
        if [ "$TOTAL_LIQUIDITY" != "0" ] && [ "$TOTAL_LIQUIDITY" -gt 0 ]; then
            if command -v python3 &> /dev/null; then
                UTIL=$(python3 -c "print(f'{int($TOTAL_BORROWED) * 100 / int($TOTAL_LIQUIDITY):.2f}')")
            else
                UTIL=$(echo "scale=2; $TOTAL_BORROWED * 100 / $TOTAL_LIQUIDITY" | bc 2>/dev/null || echo "N/A")
            fi
            echo "$SYMBOL Utilization: $UTIL%"
            echo "$SYMBOL Liquidity: $TOTAL_LIQUIDITY (raw)"
            echo "$SYMBOL Borrowed: $TOTAL_BORROWED (raw)"
        else
            echo "$SYMBOL Utilization: N/A (no liquidity)"
        fi
    else
        echo "$SYMBOL: Unable to fetch pool data"
    fi
    echo ""
}

echo "================================================================"
echo "INITIAL STATE"
echo "================================================================"
check_health_factor
get_pool_state $MNT "MNT"
get_pool_state $GOLD "GOLD"
get_pool_state $WETH "WETH"

echo "================================================================"
echo "PHASE 1: TEST BORROW (Small MNT amount)"
echo "================================================================"
echo "Testing borrow pathway with 1 MNT..."
echo ""

# Test with 1 MNT first
TEST_AMOUNT="1000000000000000000"  # 1 MNT (18 decimals)

echo "Executing test borrow..."
TEST_TX=$(cast send $LENDING_MANAGER "borrow(address,uint256)" \
    $MNT $TEST_AMOUNT \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --gas-limit 500000 \
    --json 2>&1)

if echo "$TEST_TX" | grep -q "transactionHash"; then
    echo "✅ Test borrow successful!"
    TEST_HASH=$(echo "$TEST_TX" | jq -r '.transactionHash // .hash // empty')
    if [ -n "$TEST_HASH" ]; then
        echo "Transaction: $TEST_HASH"
    fi
    echo ""

    echo "Waiting 5 seconds for transaction to settle..."
    sleep 5

    check_health_factor

    # Proceed with full borrows
    echo "================================================================"
    echo "PHASE 2: EXECUTE FULL BORROWS"
    echo "================================================================"
    echo ""

    # 1. MNT - 1.13% Target
    echo "--- Borrowing MNT for 1.13% APY target ---"
    MNT_AMOUNT="14961200000000000000000000"  # 14,961,200 MNT
    echo "Amount: 14,961,200 MNT"
    echo "Expected value: ~$6.7M"
    echo ""

    MNT_TX=$(cast send $LENDING_MANAGER "borrow(address,uint256)" \
        $MNT $MNT_AMOUNT \
        --private-key $PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --gas-limit 500000 \
        --json 2>&1)

    if echo "$MNT_TX" | grep -q "transactionHash"; then
        echo "✅ MNT borrow successful!"
        MNT_HASH=$(echo "$MNT_TX" | jq -r '.transactionHash // .hash // empty')
        if [ -n "$MNT_HASH" ]; then
            echo "Transaction: $MNT_HASH"
        fi
    else
        echo "❌ MNT borrow failed"
        echo "$MNT_TX" | head -20
    fi
    echo ""
    sleep 5
    check_health_factor
    get_pool_state $MNT "MNT"

    # 2. GOLD - 0.39% Target
    echo "--- Borrowing GOLD for 0.39% APY target ---"
    GOLD_AMOUNT="54912000000000000000000"  # 54,912 GOLD
    echo "Amount: 54,912 GOLD"
    echo "Expected value: ~$244M"
    echo ""

    GOLD_TX=$(cast send $LENDING_MANAGER "borrow(address,uint256)" \
        $GOLD $GOLD_AMOUNT \
        --private-key $PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --gas-limit 500000 \
        --json 2>&1)

    if echo "$GOLD_TX" | grep -q "transactionHash"; then
        echo "✅ GOLD borrow successful!"
        GOLD_HASH=$(echo "$GOLD_TX" | jq -r '.transactionHash // .hash // empty')
        if [ -n "$GOLD_HASH" ]; then
            echo "Transaction: $GOLD_HASH"
        fi
    else
        echo "❌ GOLD borrow failed"
        echo "$GOLD_TX" | head -20
    fi
    echo ""
    sleep 5
    check_health_factor
    get_pool_state $GOLD "GOLD"

    # 3. WETH - 2.00% Target (MAIN TARGET)
    echo "--- Borrowing WETH for 2.00% APY target ---"
    WETH_AMOUNT="685246385199241070903296"  # 685,246 WETH
    echo "Amount: 685,246 WETH"
    echo "Expected value: ~$817M"
    echo "This is the main target!"
    echo ""

    WETH_TX=$(cast send $LENDING_MANAGER "borrow(address,uint256)" \
        $WETH $WETH_AMOUNT \
        --private-key $PRIVATE_KEY \
        --rpc-url $RPC_URL \
        --gas-limit 500000 \
        --json 2>&1)

    if echo "$WETH_TX" | grep -q "transactionHash"; then
        echo "✅ WETH borrow successful! 🎉"
        WETH_HASH=$(echo "$WETH_TX" | jq -r '.transactionHash // .hash // empty')
        if [ -n "$WETH_HASH" ]; then
            echo "Transaction: $WETH_HASH"
        fi
    else
        echo "❌ WETH borrow failed"
        echo "$WETH_TX" | head -20
    fi
    echo ""
    sleep 5
    check_health_factor
    get_pool_state $WETH "WETH"

else
    echo "❌ Test borrow FAILED"
    echo "This indicates an issue with the borrowing pathway."
    echo ""
    echo "Error details:"
    echo "$TEST_TX" | head -20
    echo ""
    echo "Common issues:"
    echo "1. Insufficient collateral (though analysis shows plenty)"
    echo "2. Contract paused or restricted"
    echo "3. Token not properly configured"
    echo "4. Gas estimation failure"
    echo ""
    echo "Check the LendingManager contract state and try again."
    exit 1
fi

echo "================================================================"
echo "FINAL STATE"
echo "================================================================"
check_health_factor
echo "Final pool states:"
get_pool_state $MNT "MNT"
get_pool_state $GOLD "GOLD"
get_pool_state $WETH "WETH"

echo "================================================================"
echo "VERIFICATION"
echo "================================================================"
echo ""
echo "Wait 30 seconds for indexer to sync, then check:"
echo "curl -s http://localhost:42070/api/lending/dashboard/$TEST_ACCOUNT | jq '.supplies[] | select(.asset == \"WETH\" or .asset == \"GOLD\" or .asset == \"MNT\") | {asset, apy}'"
echo ""
echo "Expected results:"
echo "- WETH: ~2.00% APY"
echo "- GOLD: ~0.39% APY"
echo "- MNT: ~1.13% APY"
echo ""
echo "See SAFE_APY_TARGETS_REPORT.md for full analysis."
