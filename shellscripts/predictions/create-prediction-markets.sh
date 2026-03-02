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
PRICE_PREDICTION=$(jq -r '.PricePrediction // ""' "$DEPLOYMENT_FILE")
WETH=$(jq -r '.WETH // ""' "$DEPLOYMENT_FILE")
WBTC=$(jq -r '.WBTC // ""' "$DEPLOYMENT_FILE")

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

# Directional markets (UP/DOWN)
if [[ -n "$WETH" && "$WETH" != "null" ]]; then
    create_market "$WETH" "0" "0" "WETH/IDRX UP/DOWN (${DURATION}s)"
fi

if [[ -n "$WBTC" && "$WBTC" != "null" ]]; then
    create_market "$WBTC" "0" "0" "WBTC/IDRX UP/DOWN (${DURATION}s)"
fi

# Absolute market (Above/Below strike) — use current price as reference
# Strike price should be provided via env var for precise control
if [[ -n "${WETH_STRIKE_PRICE:-}" ]] && [[ -n "$WETH" && "$WETH" != "null" ]]; then
    create_market "$WETH" "1" "$WETH_STRIKE_PRICE" "WETH/IDRX Above/Below $WETH_STRIKE_PRICE (${DURATION}s)"
fi

echo ""
echo "✅ Prediction markets created!"
echo ""
echo "Next steps:"
echo "  1. Users can now call predict(marketId, predictUp, amount) on $PRICE_PREDICTION"
echo "  2. After ${DURATION}s, anyone can call requestSettlement(marketId)"
echo "  3. Chainlink CRE will automatically settle the market"
echo "  4. Winners can call claim(marketId) to receive payouts"
