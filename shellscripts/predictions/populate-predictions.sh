#!/usr/bin/env bash
# =============================================================================
# populate-predictions.sh
# Simulate prediction market activity: deposit sxIDRX, predict, settle, claim.
# Useful for testnet data population and integration testing.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
    source "$ROOT_DIR/.env"
fi

# ─── Required env vars ───────────────────────────────────────────────────────
: "${SCALEX_CORE_RPC:?SCALEX_CORE_RPC is required}"
: "${PRIVATE_KEY:?PRIVATE_KEY is required}"
: "${MARKET_ID:?MARKET_ID is required — specify which market to populate}"

# ─── Resolve addresses ───────────────────────────────────────────────────────
CHAIN_ID=$(cast chain-id --rpc-url "$SCALEX_CORE_RPC" 2>/dev/null)
DEPLOYMENT_FILE="$ROOT_DIR/deployments/${CHAIN_ID}.json"

if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
    echo "❌ Deployment file not found: $DEPLOYMENT_FILE"
    exit 1
fi

PRICE_PREDICTION=$(jq -r '.PricePrediction // ""' "$DEPLOYMENT_FILE")
BALANCE_MANAGER=$(jq -r '.BalanceManager // ""' "$DEPLOYMENT_FILE")
IDRX=$(jq -r '.IDRX // ""' "$DEPLOYMENT_FILE")
SX_IDRX=$(jq -r '.sxIDRX // ""' "$DEPLOYMENT_FILE")

if [[ -z "$PRICE_PREDICTION" || "$PRICE_PREDICTION" == "null" ]]; then
    echo "❌ PricePrediction not found in deployment file."
    exit 1
fi

DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")
STAKE_AMOUNT=${STAKE_AMOUNT:-100000000}  # Default: 100 IDRX (6 decimals)

echo "🎲 Populating Prediction Market Data"
echo "  Chain: $CHAIN_ID"
echo "  PricePrediction: $PRICE_PREDICTION"
echo "  Market ID: $MARKET_ID"
echo "  Deployer: $DEPLOYER"
echo "  Stake amount: $STAKE_AMOUNT"
echo ""

# ─── Helper: check sxIDRX balance ────────────────────────────────────────────
get_sx_balance() {
    cast call "$BALANCE_MANAGER" \
        "getAvailableBalance(address,address)(uint256)" \
        "$DEPLOYER" "$SX_IDRX" \
        --rpc-url "$SCALEX_CORE_RPC" 2>/dev/null || echo "0"
}

# ─── Step 1: Ensure deployer has IDRX balance ────────────────────────────────
echo "Step 1: Checking IDRX balance..."
IDRX_BALANCE=$(cast call "$IDRX" "balanceOf(address)(uint256)" "$DEPLOYER" --rpc-url "$SCALEX_CORE_RPC" 2>/dev/null || echo "0")
echo "  IDRX balance: $IDRX_BALANCE"

if [[ "$IDRX_BALANCE" -lt "$((STAKE_AMOUNT * 2))" ]]; then
    echo "  ⚠️  Low IDRX balance. Trying to mint (testnet only)..."
    cast send "$IDRX" \
        "mint(address,uint256)" \
        "$DEPLOYER" "$((STAKE_AMOUNT * 10))" \
        --rpc-url "$SCALEX_CORE_RPC" \
        --private-key "$PRIVATE_KEY" \
        --quiet 2>/dev/null || echo "  ℹ️  Mint not available on this token"
fi

# ─── Step 2: Deposit IDRX to get sxIDRX balance ──────────────────────────────
echo ""
echo "Step 2: Depositing IDRX..."
SX_BALANCE_BEFORE=$(get_sx_balance)
echo "  sxIDRX balance before: $SX_BALANCE_BEFORE"

if [[ "$SX_BALANCE_BEFORE" -lt "$STAKE_AMOUNT" ]]; then
    DEPOSIT_AMOUNT="$((STAKE_AMOUNT * 3))"
    # Approve BalanceManager
    cast send "$IDRX" \
        "approve(address,uint256)" \
        "$BALANCE_MANAGER" "$DEPOSIT_AMOUNT" \
        --rpc-url "$SCALEX_CORE_RPC" \
        --private-key "$PRIVATE_KEY" \
        --quiet

    # Deposit
    cast send "$BALANCE_MANAGER" \
        "deposit(address,uint256,address,address)" \
        "$IDRX" "$DEPOSIT_AMOUNT" "$DEPLOYER" "$DEPLOYER" \
        --rpc-url "$SCALEX_CORE_RPC" \
        --private-key "$PRIVATE_KEY" \
        --quiet
    echo "  ✅ Deposited $DEPOSIT_AMOUNT IDRX"
fi

SX_BALANCE=$(get_sx_balance)
echo "  sxIDRX balance: $SX_BALANCE"

# ─── Step 3: Place predictions ───────────────────────────────────────────────
echo ""
echo "Step 3: Placing predictions on market $MARKET_ID..."

# Predict UP
echo "  Predicting UP with $STAKE_AMOUNT..."
cast send "$PRICE_PREDICTION" \
    "predict(uint64,bool,uint256)" \
    "$MARKET_ID" "true" "$STAKE_AMOUNT" \
    --rpc-url "$SCALEX_CORE_RPC" \
    --private-key "$PRIVATE_KEY" \
    --quiet && echo "  ✅ Predicted UP" || echo "  ⚠️  Failed to predict UP (market may be closed)"

# Also predict DOWN with a smaller amount (creates balanced market)
if [[ "${PREDICT_BOTH:-false}" == "true" ]]; then
    DOWN_AMOUNT="$((STAKE_AMOUNT / 2))"
    echo "  Predicting DOWN with $DOWN_AMOUNT..."
    cast send "$PRICE_PREDICTION" \
        "predict(uint64,bool,uint256)" \
        "$MARKET_ID" "false" "$DOWN_AMOUNT" \
        --rpc-url "$SCALEX_CORE_RPC" \
        --private-key "$PRIVATE_KEY" \
        --quiet && echo "  ✅ Predicted DOWN" || echo "  ⚠️  Failed to predict DOWN"
fi

# ─── Step 4: Check market state ──────────────────────────────────────────────
echo ""
echo "Step 4: Market state after predictions..."
MARKET=$(cast call "$PRICE_PREDICTION" \
    "getMarket(uint64)((uint64,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint256,bool))" \
    "$MARKET_ID" \
    --rpc-url "$SCALEX_CORE_RPC" 2>/dev/null || echo "(failed to read market)")

echo "  Market data: $MARKET"

echo ""
echo "✅ Prediction market populated!"
echo ""
echo "Next steps:"
echo "  1. Wait for market to expire (check endTime in market data)"
echo "  2. Call requestSettlement: cast send $PRICE_PREDICTION 'requestSettlement(uint64)' $MARKET_ID --rpc-url $SCALEX_CORE_RPC --private-key \$PRIVATE_KEY"
echo "  3. Chainlink CRE will settle automatically, or call onReport() manually for testing"
echo "  4. Claim payout: cast send $PRICE_PREDICTION 'claim(uint64)' $MARKET_ID --rpc-url $SCALEX_CORE_RPC --private-key \$PRIVATE_KEY"
