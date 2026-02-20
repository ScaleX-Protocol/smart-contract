#!/bin/bash

# Supply WETH as collateral to the lending pool
# This deposits to BalanceManager which automatically supplies to LendingManager

set -e

# Load environment
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Configuration
RPC_URL="${SCALEX_CORE_RPC}"
PRIVATE_KEY="${PRIVATE_KEY}"
SUPPLY_AMOUNT="${SUPPLY_AMOUNT:-1000}" # Default 1000 WETH

# Get contract addresses
DEPLOYMENT_FILE="deployments/84532.json"
LENDING_MANAGER=$(jq -r '.LendingManager' "$DEPLOYMENT_FILE")
BALANCE_MANAGER=$(jq -r '.BalanceManager' "$DEPLOYMENT_FILE")
WETH=$(jq -r '.WETH' "$DEPLOYMENT_FILE")

echo "🏦 Supplying WETH as Collateral (via BalanceManager Deposit)"
echo "============================================================="
echo ""
echo "Contracts:"
echo "  LendingManager: $LENDING_MANAGER"
echo "  BalanceManager: $BALANCE_MANAGER"
echo "  WETH: $WETH"
echo ""

# Get deployer address
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")
echo "Deployer: $DEPLOYER"
echo "Supply Amount: $SUPPLY_AMOUNT WETH"
echo ""

# Convert to wei (18 decimals)
SUPPLY_AMOUNT_WEI=$(python3 -c "print(int($SUPPLY_AMOUNT * 1e18))")

# Check WETH token balance (not BalanceManager balance)
echo "📋 Checking your WETH token balance..."
WETH_BALANCE=$(cast call $WETH "balanceOf(address)(uint256)" $DEPLOYER --rpc-url "$RPC_URL" | awk '{print $1}')
WETH_BALANCE_READABLE=$(python3 -c "print(f'{${WETH_BALANCE:-0} / 1e18:.6f}')")
echo "  Your WETH token balance: $WETH_BALANCE_READABLE"

# Check current BalanceManager balance
BM_BALANCE=$(cast call $BALANCE_MANAGER "getBalance(address,address)(uint256)" $DEPLOYER $WETH --rpc-url "$RPC_URL" | awk '{print $1}')
BM_BALANCE_READABLE=$(python3 -c "print(f'{${BM_BALANCE:-0} / 1e18:.6f}')")
echo "  Your BalanceManager balance: $BM_BALANCE_READABLE"

# Check current lending supply
LENDING_SUPPLY=$(cast call $LENDING_MANAGER "getUserSupply(address,address)(uint256)" $DEPLOYER $WETH --rpc-url "$RPC_URL" 2>/dev/null | awk '{print $1}')
if [ -z "$LENDING_SUPPLY" ]; then
    LENDING_SUPPLY="0"
fi
LENDING_SUPPLY_READABLE=$(python3 -c "print(f'{${LENDING_SUPPLY:-0} / 1e18:.6f}')")
echo "  Your lending supply: $LENDING_SUPPLY_READABLE"
echo ""

# Check if we have enough WETH tokens
HAS_ENOUGH=$(python3 -c "print('yes' if ${WETH_BALANCE:-0} >= $SUPPLY_AMOUNT_WEI else 'no')")
if [ "$HAS_ENOUGH" = "no" ]; then
    echo "⚠️  Insufficient WETH token balance!"
    echo "  You need $SUPPLY_AMOUNT WETH but only have $WETH_BALANCE_READABLE WETH"
    echo ""
    echo "Please acquire more WETH first"
    exit 1
fi

# Approve BalanceManager to spend WETH
echo "🔄 Step 1: Approving BalanceManager to spend WETH..."
cast send $WETH \
    "approve(address,uint256)" \
    $BALANCE_MANAGER \
    $SUPPLY_AMOUNT_WEI \
    --private-key "$PRIVATE_KEY" \
    --rpc-url "$RPC_URL" \
    --gas-limit 100000 > /dev/null

echo "✅ Approval successful"
echo ""

# Deposit to BalanceManager (this automatically supplies to LendingManager)
echo "🔄 Step 2: Depositing to BalanceManager (auto-supplies to LendingManager)..."
echo ""

cast send $BALANCE_MANAGER \
    "deposit(address,uint256,address,address)" \
    $WETH \
    $SUPPLY_AMOUNT_WEI \
    $DEPLOYER \
    $DEPLOYER \
    --private-key "$PRIVATE_KEY" \
    --rpc-url "$RPC_URL" \
    --gas-limit 500000

echo ""
echo "✅ Deposit transaction sent!"
echo ""

# Verify
echo "📊 Verifying..."
sleep 3

# Check new balances
NEW_BM_BALANCE=$(cast call $BALANCE_MANAGER "getBalance(address,address)(uint256)" $DEPLOYER $WETH --rpc-url "$RPC_URL" | awk '{print $1}')
NEW_BM_BALANCE_READABLE=$(python3 -c "print(f'{${NEW_BM_BALANCE:-0} / 1e18:.6f}')")

NEW_LENDING_SUPPLY=$(cast call $LENDING_MANAGER "getUserSupply(address,address)(uint256)" $DEPLOYER $WETH --rpc-url "$RPC_URL" 2>/dev/null | awk '{print $1}')
if [ -z "$NEW_LENDING_SUPPLY" ]; then
    NEW_LENDING_SUPPLY="0"
fi
NEW_LENDING_SUPPLY_READABLE=$(python3 -c "print(f'{${NEW_LENDING_SUPPLY:-0} / 1e18:.6f}')")

echo "  New BalanceManager balance: $NEW_BM_BALANCE_READABLE (+$(python3 -c "print(f'{($NEW_BM_BALANCE - $BM_BALANCE) / 1e18:.6f}')"))"
echo "  New lending supply: $NEW_LENDING_SUPPLY_READABLE (+$(python3 -c "print(f'{($NEW_LENDING_SUPPLY - $LENDING_SUPPLY) / 1e18:.6f}')"))"
echo ""
echo "✅ Done! You now have WETH supplied as collateral in LendingManager."
echo ""
echo "Next step: Create borrowing activity to generate APY:"
echo "  bash shellscripts/create-weth-lending-activity.sh"
