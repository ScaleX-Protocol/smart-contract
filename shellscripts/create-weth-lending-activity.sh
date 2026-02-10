#!/bin/bash

# Simple script to create WETH lending activity using cast commands
# This creates borrowing activity to generate non-zero APY

set -e

# Load environment
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Configuration
RPC_URL="${SCALEX_CORE_RPC}"
DEPLOYER_PRIVATE_KEY="${PRIVATE_KEY}"

# Get contract addresses from deployment file
DEPLOYMENT_FILE="deployments/84532.json"
LENDING_MANAGER=$(jq -r '.LendingManager' "$DEPLOYMENT_FILE")
BALANCE_MANAGER=$(jq -r '.BalanceManager' "$DEPLOYMENT_FILE")
SCALEX_ROUTER=$(jq -r '.ScaleXRouter' "$DEPLOYMENT_FILE")
WETH=$(jq -r '.WETH' "$DEPLOYMENT_FILE")

echo "🚀 Creating WETH Lending Activity"
echo "=================================="
echo ""
echo "Contracts:"
echo "  ScaleXRouter: $SCALEX_ROUTER"
echo "  LendingManager: $LENDING_MANAGER"
echo "  BalanceManager: $BALANCE_MANAGER"
echo "  WETH: $WETH"
echo ""

# Check current lending state
echo "📊 Checking current WETH lending state..."
echo ""

# Get total liquidity (supply) - cast outputs "123456 [1e5]", extract just the number
TOTAL_SUPPLY=$(cast call $LENDING_MANAGER "totalLiquidity(address)(uint256)" $WETH --rpc-url "$RPC_URL" | awk '{print $1}')
TOTAL_SUPPLY_READABLE=$(python3 -c "print(f'{$TOTAL_SUPPLY / 1e18:.6f}')")

# Get total borrowed
TOTAL_BORROWED=$(cast call $LENDING_MANAGER "totalBorrowed(address)(uint256)" $WETH --rpc-url "$RPC_URL" | awk '{print $1}')
TOTAL_BORROWED_READABLE=$(python3 -c "print(f'{$TOTAL_BORROWED / 1e18:.6f}')")

# Calculate utilization using Python for large number support
UTILIZATION=$(python3 -c "
total_supply = $TOTAL_SUPPLY
total_borrowed = $TOTAL_BORROWED
if total_supply > 0:
    print(f'{(total_borrowed * 100 / total_supply):.2f}')
else:
    print('0')
")

echo "Current State:"
echo "  Total Supply: $TOTAL_SUPPLY_READABLE WETH"
echo "  Total Borrowed: $TOTAL_BORROWED_READABLE WETH"
echo "  Utilization: $UTILIZATION%"
echo ""

# Get deployer address
DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")
echo "Deployer: $DEPLOYER"
echo ""

# Check if deployer has collateral
echo "📋 Checking collateral..."
DEPLOYER_SUPPLY=$(cast call $LENDING_MANAGER "getUserSupply(address,address)(uint256)" $DEPLOYER $WETH --rpc-url "$RPC_URL" 2>/dev/null | awk '{print $1}')
if [ -z "$DEPLOYER_SUPPLY" ] || [ "$DEPLOYER_SUPPLY" = "" ]; then
    DEPLOYER_SUPPLY="0"
fi
DEPLOYER_SUPPLY_READABLE=$(python3 -c "print(f'{${DEPLOYER_SUPPLY:-0} / 1e18:.6f}')")
echo "  Your supplied WETH: $DEPLOYER_SUPPLY_READABLE"

# If no supply, we need to deposit first
HAS_SUPPLY=$(python3 -c "print('yes' if $DEPLOYER_SUPPLY > 0 else 'no')")
if [ "$HAS_SUPPLY" = "no" ]; then
    echo ""
    echo "⚠️  You need to supply WETH as collateral first!"
    echo ""
    echo "Run: bash shellscripts/supply-weth-collateral.sh"
    exit 1
fi
echo ""

# Get WETH collateral factor
ASSET_CONFIG=$(cast call $LENDING_MANAGER "assetConfigs(address)(uint256,uint256,uint256,uint256,bool)" $WETH --rpc-url "$RPC_URL" | head -1)
COLLATERAL_FACTOR=$(echo "$ASSET_CONFIG" | awk '{print $1}')
echo "Collateral Factor: $COLLATERAL_FACTOR bps ($(python3 -c "print(f'{$COLLATERAL_FACTOR / 100:.0f}%')"))"

# Calculate maximum safe borrow based on user's collateral
# Use 75% of max to stay safe (collateral factor is 80%, we use 60% = 0.8 * 0.75)
SAFE_BORROW_RATIO=60
MAX_USER_BORROW=$(python3 -c "
deployer_supply = $DEPLOYER_SUPPLY
safe_ratio = $SAFE_BORROW_RATIO
print(int(deployer_supply * safe_ratio / 100))
")
MAX_USER_BORROW_READABLE=$(python3 -c "print(f'{$MAX_USER_BORROW / 1e18:.6f}')")

# Target utilization for the POOL (default 30%)
TARGET_POOL_UTILIZATION=${BORROW_RATIO:-30}
TARGET_POOL_BORROW=$(python3 -c "
total_supply = $TOTAL_SUPPLY
target_util = $TARGET_POOL_UTILIZATION
print(int(total_supply * target_util / 100))
")
NEEDED_FOR_POOL=$(python3 -c "
target = $TARGET_POOL_BORROW
current = $TOTAL_BORROWED
print(int(target - current))
")

# Borrow the MINIMUM of: what user can borrow, or what's needed for pool target
NEEDED_BORROW=$(python3 -c "
max_user = $MAX_USER_BORROW
needed_pool = $NEEDED_FOR_POOL
print(min(max_user, needed_pool))
")
NEEDED_BORROW_READABLE=$(python3 -c "print(f'{$NEEDED_BORROW / 1e18:.6f}')")

echo "Your Max Safe Borrow: $MAX_USER_BORROW_READABLE WETH ($(python3 -c "print(f'{$SAFE_BORROW_RATIO}%')") of your collateral)"
echo "Pool Target (${TARGET_POOL_UTILIZATION}% util): $(python3 -c "print(f'{$NEEDED_FOR_POOL / 1e18:.6f}')") WETH needed"
echo "Will borrow: $NEEDED_BORROW_READABLE WETH"
echo ""

# Check if we need to borrow (use Python for large number comparison)
NEEDS_BORROW=$(python3 -c "print('yes' if $NEEDED_BORROW > 0 else 'no')")
if [ "$NEEDS_BORROW" = "no" ]; then
    echo "✅ Already at or above target utilization!"
    exit 0
fi

# Check borrowing power
echo "📋 Checking borrowing power..."
HEALTH_FACTOR=$(cast call $LENDING_MANAGER "getHealthFactor(address)(uint256)" $DEPLOYER --rpc-url "$RPC_URL" | awk '{print $1}')
HEALTH_FACTOR_READABLE=$(python3 -c "print(f'{${HEALTH_FACTOR:-0} / 1e18:.2f}')" 2>/dev/null || echo "N/A")
echo "  Health Factor: $HEALTH_FACTOR_READABLE"

# Health factor > 1e18 (1.0) is healthy
IS_HEALTHY=$(python3 -c "print('yes' if ${HEALTH_FACTOR:-0} > 1000000000000000000 else 'no')")
if [ "$IS_HEALTHY" = "no" ]; then
    echo ""
    echo "⚠️  Health factor too low - you may not have enough collateral to borrow"
    echo "  Consider supplying more WETH first"
    exit 1
fi

# Borrow to reach target utilization (via ScaleXRouter)
echo ""
echo "🔄 Borrowing $NEEDED_BORROW_READABLE WETH via ScaleXRouter..."
echo ""

cast send $SCALEX_ROUTER \
    "borrow(address,uint256)" \
    $WETH \
    $NEEDED_BORROW \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --rpc-url "$RPC_URL" \
    --gas-limit 1000000

echo ""
echo "✅ Borrow transaction sent!"
echo ""

# Check new state
echo "📊 Verifying new state..."
sleep 2

NEW_TOTAL_BORROWED=$(cast call $LENDING_MANAGER "totalBorrowed(address)(uint256)" $WETH --rpc-url "$RPC_URL" | awk '{print $1}')
NEW_TOTAL_BORROWED_READABLE=$(python3 -c "print(f'{$NEW_TOTAL_BORROWED / 1e18:.6f}')")
NEW_UTILIZATION=$(python3 -c "print(f'{($NEW_TOTAL_BORROWED * 100 / $TOTAL_SUPPLY):.2f}')")

echo "  New Total Borrowed: $NEW_TOTAL_BORROWED_READABLE WETH"
echo "  New Utilization: $NEW_UTILIZATION%"
echo ""

echo "✅ Done! Wait 5-10 minutes for indexer to update, then check:"
echo ""
echo "  curl -s http://localhost:42070/api/lending/dashboard/$DEPLOYER | \\"
echo "    jq '.supplies[] | select(.asset == \"WETH\") | .realTimeRates.supplyAPY'"
echo ""
echo "You should see a non-zero APY!"
