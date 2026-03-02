#!/usr/bin/env bash
# =============================================================================
# deploy-price-prediction.sh
# Deploy PricePrediction contract (Phase 6) on an existing deployment.
# Uses DeployPricePrediction.s.sol which reads addresses from deployments/<chainId>.json
# and updates the file with new PricePrediction addresses.
# =============================================================================
# Required env vars:
#   PRIVATE_KEY          — Deployer private key
#   SCALEX_CORE_RPC      — RPC URL for target chain
#   KEYSTONE_FORWARDER   — Chainlink CRE KeystoneForwarder contract address
#
# Optional env vars:
#   PROTOCOL_FEE_BPS     — Protocol fee in BPS (default: 200 = 2%)
#   MIN_STAKE_AMOUNT     — Min stake in raw IDRX units (default: 10_000_000)
#   MAX_MARKET_TVL       — Max TVL per market, 0 = no cap (default: 0)
#   ETHERSCAN_API_KEY    — For source verification on block explorers
#
# Usage:
#   PRIVATE_KEY=0x... \
#   SCALEX_CORE_RPC="https://sepolia.base.org" \
#   KEYSTONE_FORWARDER=0x... \
#   bash shellscripts/deployment/deploy-price-prediction.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load .env if present
if [[ -f "$ROOT_DIR/.env" ]]; then
    source "$ROOT_DIR/.env"
fi

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
print_step()    { echo -e "\n${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

# ─── Validate required env vars ──────────────────────────────────────────────
: "${PRIVATE_KEY:?PRIVATE_KEY is required}"
: "${SCALEX_CORE_RPC:?SCALEX_CORE_RPC is required}"
: "${KEYSTONE_FORWARDER:?KEYSTONE_FORWARDER is required (Chainlink CRE forwarder address)}"

# ─── Detect chain ────────────────────────────────────────────────────────────
CHAIN_ID=$(cast chain-id --rpc-url "$SCALEX_CORE_RPC" 2>/dev/null)
DEPLOYMENT_FILE="$ROOT_DIR/deployments/${CHAIN_ID}.json"
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")

print_step "=== Phase 6: PricePrediction Deployment ==="
echo "  Chain ID:            $CHAIN_ID"
echo "  Deployer:            $DEPLOYER"
echo "  RPC:                 $SCALEX_CORE_RPC"
echo "  Deployment file:     $DEPLOYMENT_FILE"
echo "  KeystoneForwarder:   $KEYSTONE_FORWARDER"
echo "  Protocol fee (bps):  ${PROTOCOL_FEE_BPS:-200}"
echo "  Min stake:           ${MIN_STAKE_AMOUNT:-10000000}"
echo "  Max TVL:             ${MAX_MARKET_TVL:-0}"

if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
    print_error "Deployment file not found: $DEPLOYMENT_FILE"
    echo "Run the full deploy.sh first to deploy phases 1-5."
    exit 1
fi

# Check required addresses exist in deployment file
BALANCE_MANAGER=$(jq -r '.BalanceManager // ""' "$DEPLOYMENT_FILE")
ORACLE=$(jq -r '.Oracle // ""' "$DEPLOYMENT_FILE")
SX_IDRX=$(jq -r '.sxIDRX // ""' "$DEPLOYMENT_FILE")

if [[ -z "$BALANCE_MANAGER" || "$BALANCE_MANAGER" == "null" ]]; then
    print_error "BalanceManager not found in $DEPLOYMENT_FILE"
    exit 1
fi
if [[ -z "$ORACLE" || "$ORACLE" == "null" ]]; then
    print_error "Oracle not found in $DEPLOYMENT_FILE"
    exit 1
fi
if [[ -z "$SX_IDRX" || "$SX_IDRX" == "null" ]]; then
    print_error "sxIDRX not found in $DEPLOYMENT_FILE"
    exit 1
fi

echo ""
echo "  BalanceManager: $BALANCE_MANAGER"
echo "  Oracle:         $ORACLE"
echo "  sxIDRX:         $SX_IDRX"

# ─── Build verify flags ──────────────────────────────────────────────────────
VERIFY_FLAGS=""
if [[ -n "${ETHERSCAN_API_KEY:-}" ]]; then
    case "$CHAIN_ID" in
        84532) VERIFY_FLAGS="--verify --etherscan-api-key $ETHERSCAN_API_KEY --chain 84532" ;;
        11155111) VERIFY_FLAGS="--verify --etherscan-api-key $ETHERSCAN_API_KEY --chain 11155111" ;;
        1) VERIFY_FLAGS="--verify --etherscan-api-key $ETHERSCAN_API_KEY --chain 1" ;;
        *) print_warning "Unknown chain $CHAIN_ID — skipping verification" ;;
    esac
fi

# ─── Deploy ──────────────────────────────────────────────────────────────────
print_step "Deploying PricePrediction..."

cd "$ROOT_DIR"

FORGE_CMD="forge script script/deployments/DeployPricePrediction.s.sol:DeployPricePrediction \
    --rpc-url \"${SCALEX_CORE_RPC}\" \
    --broadcast \
    --private-key $PRIVATE_KEY \
    --gas-estimate-multiplier 120 \
    --legacy"

if [[ -n "$VERIFY_FLAGS" ]]; then
    FORGE_CMD="$FORGE_CMD $VERIFY_FLAGS"
fi

if eval "KEYSTONE_FORWARDER=$KEYSTONE_FORWARDER \
    PROTOCOL_FEE_BPS=${PROTOCOL_FEE_BPS:-200} \
    MIN_STAKE_AMOUNT=${MIN_STAKE_AMOUNT:-10000000} \
    MAX_MARKET_TVL=${MAX_MARKET_TVL:-0} \
    $FORGE_CMD"; then
    print_success "PricePrediction deployed!"
else
    print_error "Deployment failed. Check the forge script output above."
    exit 1
fi

# ─── Verify deployment ───────────────────────────────────────────────────────
PRICE_PREDICTION=$(jq -r '.PricePrediction // ""' "$DEPLOYMENT_FILE")
PRICE_PREDICTION_IMPL=$(jq -r '.PricePredictionImpl // ""' "$DEPLOYMENT_FILE")
PRICE_PREDICTION_BEACON=$(jq -r '.PricePredictionBeacon // ""' "$DEPLOYMENT_FILE")

if [[ -z "$PRICE_PREDICTION" || "$PRICE_PREDICTION" == "null" ]]; then
    print_error "PricePrediction address not found in deployment file after deployment."
    exit 1
fi

print_success "=== PricePrediction Deployment Complete ==="
echo ""
echo "  PricePrediction (Proxy):  $PRICE_PREDICTION"
echo "  PricePrediction (Impl):   $PRICE_PREDICTION_IMPL"
echo "  PricePrediction (Beacon): $PRICE_PREDICTION_BEACON"
echo ""
echo "Next steps:"
echo "  1. Configure Chainlink CRE workflow:"
echo "     PRICE_PREDICTION_ADDRESS=$PRICE_PREDICTION"
echo "     ORACLE_ADDRESS=$ORACLE"
echo "     cre workflow deploy cre-workflows/price-prediction/workflow.yaml"
echo ""
echo "  2. Create prediction markets:"
echo "     bash shellscripts/predictions/create-prediction-markets.sh"
echo ""
echo "  3. Update indexer with PricePrediction ABI and address:"
echo "     PricePrediction = $PRICE_PREDICTION (Chain $CHAIN_ID)"
