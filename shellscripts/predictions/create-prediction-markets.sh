#!/usr/bin/env bash
# =============================================================================
# create-prediction-markets.sh
# Create initial prediction markets on a deployed PricePrediction contract.
# =============================================================================
set -euo pipefail

# ─── Load env ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
    source "$ROOT_DIR/.env"
fi

# ─── Required env vars ───────────────────────────────────────────────────────
: "${SCALEX_CORE_RPC:?SCALEX_CORE_RPC is required}"
: "${PRIVATE_KEY:?PRIVATE_KEY is required}"

# ─── Resolve chain ID ────────────────────────────────────────────────────────
CHAIN_ID=$(cast chain-id --rpc-url "$SCALEX_CORE_RPC" 2>/dev/null)
DEPLOYMENT_FILE="$ROOT_DIR/deployments/${CHAIN_ID}.json"

if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
    echo "❌ Deployment file not found: $DEPLOYMENT_FILE"
    exit 1
fi

# ─── Load addresses ──────────────────────────────────────────────────────────
# Note: Oracle tracks sxTokens (synthetic), not underlying tokens.
# Always use sxToken addresses as baseToken for prediction markets.
PRICE_PREDICTION=$(jq -r '.PricePrediction // ""' "$DEPLOYMENT_FILE")
sxWETH=$(jq -r '.sxWETH // ""' "$DEPLOYMENT_FILE")
sxWBTC=$(jq -r '.sxWBTC // ""' "$DEPLOYMENT_FILE")
sxGOLD=$(jq -r '.sxGOLD // ""' "$DEPLOYMENT_FILE")
sxSILVER=$(jq -r '.sxSILVER // ""' "$DEPLOYMENT_FILE")
sxGOOGLE=$(jq -r '.sxGOOGLE // ""' "$DEPLOYMENT_FILE")
sxNVIDIA=$(jq -r '.sxNVIDIA // ""' "$DEPLOYMENT_FILE")
sxMNT=$(jq -r '.sxMNT // ""' "$DEPLOYMENT_FILE")
sxAPPLE=$(jq -r '.sxAPPLE // ""' "$DEPLOYMENT_FILE")
ORACLE=$(jq -r '.Oracle // ""' "$DEPLOYMENT_FILE")

if [[ -z "$PRICE_PREDICTION" || "$PRICE_PREDICTION" == "null" ]]; then
    echo "❌ PricePrediction not found in $DEPLOYMENT_FILE. Run deploy-price-prediction.sh first."
    exit 1
fi

echo "📈 Creating Prediction Markets"
echo "  Chain: $CHAIN_ID"
echo "  PricePrediction: $PRICE_PREDICTION"
echo ""

# ─── Market configuration ────────────────────────────────────────────────────
DURATION=${MARKET_DURATION:-300}  # Default: 5 minutes

# Market type values:
#   0 = Directional (UP/DOWN vs opening TWAP)
#   1 = Absolute (Above/Below strike price)

# Returns the TWAP for a token (to use as strike reference)
get_twap() {
    cast call "$ORACLE" "getTWAP(address,uint256)(uint256)" "$1" "$DURATION" \
        --rpc-url "$SCALEX_CORE_RPC" 2>/dev/null || echo "0"
}

create_market() {
    local base_token="$1"
    local market_type="$2"
    local strike_price="$3"
    local label="$4"

    echo "  Creating market: $label"
    echo "    baseToken: $base_token, type: $market_type, strike: $strike_price, duration: ${DURATION}s"

    TX=$(cast send "$PRICE_PREDICTION" \
        "createMarket(address,uint8,uint256,uint256)(uint64)" \
        "$base_token" \
        "$market_type" \
        "$strike_price" \
        "$DURATION" \
        --rpc-url "$SCALEX_CORE_RPC" \
        --private-key "$PRIVATE_KEY" \
        --json 2>/dev/null)

    if [[ $? -eq 0 ]]; then
        TX_HASH=$(echo "$TX" | jq -r '.transactionHash // "unknown"')
        echo "    ✅ Created (tx: $TX_HASH)"
    else
        echo "    ⚠️  Failed to create market: $label"
    fi
}

# ─── Create markets ──────────────────────────────────────────────────────────

# Directional markets (UP/DOWN vs opening TWAP)
[[ -n "$sxWETH"   && "$sxWETH"   != "null" ]] && create_market "$sxWETH"   "0" "0" "sxWETH UP/DOWN (${DURATION}s)"
[[ -n "$sxWBTC"   && "$sxWBTC"   != "null" ]] && create_market "$sxWBTC"   "0" "0" "sxWBTC UP/DOWN (${DURATION}s)"
[[ -n "$sxGOLD"   && "$sxGOLD"   != "null" ]] && create_market "$sxGOLD"   "0" "0" "sxGOLD UP/DOWN (${DURATION}s)"
[[ -n "$sxNVIDIA" && "$sxNVIDIA" != "null" ]] && create_market "$sxNVIDIA" "0" "0" "sxNVIDIA UP/DOWN (${DURATION}s)"
[[ -n "$sxAPPLE"  && "$sxAPPLE"  != "null" ]] && create_market "$sxAPPLE"  "0" "0" "sxAPPLE UP/DOWN (${DURATION}s)"

# Absolute markets (Above/Below strike price, using current TWAP as strike)
if [[ -n "$sxWETH" && "$sxWETH" != "null" ]]; then
    WETH_STRIKE=${WETH_STRIKE_PRICE:-$(get_twap "$sxWETH")}
    [[ "$WETH_STRIKE" != "0" ]] && create_market "$sxWETH" "1" "$WETH_STRIKE" "sxWETH Above/Below $WETH_STRIKE (${DURATION}s)"
fi

if [[ -n "$sxGOLD" && "$sxGOLD" != "null" ]]; then
    GOLD_STRIKE=${GOLD_STRIKE_PRICE:-$(get_twap "$sxGOLD")}
    [[ "$GOLD_STRIKE" != "0" ]] && create_market "$sxGOLD" "1" "$GOLD_STRIKE" "sxGOLD Above/Below $GOLD_STRIKE (${DURATION}s)"
fi

echo ""
echo "✅ Prediction markets created!"
echo ""
echo "Next steps:"
echo "  1. Users can now call predict(marketId, predictUp, amount) on $PRICE_PREDICTION"
echo "  2. After ${DURATION}s, anyone can call requestSettlement(marketId)"
echo "  3. Chainlink CRE will automatically settle the market, or owner can call onReport() for testing"
echo "  4. Winners can call claim(marketId) to receive payouts"
