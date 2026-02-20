#!/bin/bash
# Verify Indexer - Resets ponder and checks data is being indexed correctly
#
# USAGE:
#   ./shellscripts/verify-indexer.sh <chain-name>
#   ./shellscripts/verify-indexer.sh base-sepolia
#   ./shellscripts/verify-indexer.sh local
#
# WHAT IT DOES:
#   1. Loads ponder env for the given chain
#   2. Restarts ponder (pm2 restart or dev mode)
#   3. Waits for ponder GraphQL to be ready
#   4. Queries GraphQL: pools > 0, orders > 1, trades >= 1
#   5. Reports pass/fail per check

set -e

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
print_info()    { echo -e "       $1"; }

# ─── Args ─────────────────────────────────────────────────────────────────────
CHAIN_NAME="${1:-}"
if [[ -z "$CHAIN_NAME" ]]; then
    echo "Usage: $0 <chain-name>"
    echo "  chain-name: base-sepolia | core-chain | local | anvil | sepolia"
    exit 1
fi

# ─── Config ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."
INDEXER_DIR="$PROJECT_ROOT/../clob-indexer/ponder"
ENV_FILE="$INDEXER_DIR/.env.$CHAIN_NAME"

# Default ponder port; overridden by env file
PONDER_PORT="${PONDER_PORT:-42069}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"   # seconds to wait for ponder to be ready
WAIT_INTERVAL=5

echo ""
echo -e "${BLUE}========================================"
echo -e "  Indexer Verification: $CHAIN_NAME"
echo -e "========================================${NC}"
echo ""

# ─── 1. Check prerequisites ────────────────────────────────────────────────────
print_step "Checking prerequisites..."

if [[ ! -d "$INDEXER_DIR" ]]; then
    print_error "clob-indexer/ponder not found at: $INDEXER_DIR"
    echo "  Make sure clob-indexer is checked out alongside clob-dex"
    exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
    print_error "Env file not found: $ENV_FILE"
    echo "  Run update-env.sh first: ./shellscripts/update-env.sh <chain-id>"
    exit 1
fi

# Load ponder port from env file
LOADED_PORT=$(grep "^PONDER_PORT=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
if [[ -n "$LOADED_PORT" ]]; then
    PONDER_PORT="$LOADED_PORT"
fi

GRAPHQL_URL="http://localhost:${PONDER_PORT}/graphql"
print_info "Ponder port: $PONDER_PORT"
print_info "GraphQL URL: $GRAPHQL_URL"
print_success "Prerequisites OK"
echo ""

# ─── 2. Restart ponder ────────────────────────────────────────────────────────
print_step "Restarting ponder indexer..."

# Determine pm2 app name based on chain
PM2_APP="ponder-${CHAIN_NAME}"

if command -v pm2 &>/dev/null; then
    if pm2 list 2>/dev/null | grep -q "$PM2_APP"; then
        print_info "Restarting pm2 app: $PM2_APP"
        pm2 restart "$PM2_APP" --update-env 2>/dev/null || true
        sleep 3
        print_success "pm2 restart issued"
    else
        print_warning "pm2 app '$PM2_APP' not found - skipping restart"
        print_info "Start ponder manually: cd $INDEXER_DIR && ponder dev"
    fi
else
    print_warning "pm2 not found - skipping restart (assuming ponder is already running)"
fi
echo ""

# ─── 3. Wait for GraphQL to be ready ─────────────────────────────────────────
print_step "Waiting for ponder GraphQL to be ready (timeout: ${WAIT_TIMEOUT}s)..."

elapsed=0
while true; do
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$GRAPHQL_URL" \
        -H "Content-Type: application/json" \
        -d '{"query":"{ __typename }"}' 2>/dev/null || echo "000")

    if [[ "$STATUS_CODE" == "200" ]]; then
        print_success "GraphQL is ready"
        break
    fi

    if [[ $elapsed -ge $WAIT_TIMEOUT ]]; then
        print_error "Timed out waiting for ponder GraphQL after ${WAIT_TIMEOUT}s"
        print_info "Check ponder logs: pm2 logs $PM2_APP"
        exit 1
    fi

    echo -ne "  Waiting... ${elapsed}s (HTTP $STATUS_CODE)\r"
    sleep "$WAIT_INTERVAL"
    elapsed=$((elapsed + WAIT_INTERVAL))
done
echo ""

# ─── 4. GraphQL verification queries ─────────────────────────────────────────
print_step "Running GraphQL verification queries..."

run_graphql() {
    local query="$1"
    curl -s -X POST "$GRAPHQL_URL" \
        -H "Content-Type: application/json" \
        -d "{\"query\":\"$query\"}" 2>/dev/null
}

CHECKS_PASSED=0
CHECKS_FAILED=0

# ─── Check: pools exist ───────────────────────────────────────────────────────
POOLS_RESP=$(run_graphql "{ pools { items { id coin } } }")
POOLS_COUNT=$(echo "$POOLS_RESP" | grep -o '"id"' | wc -l | tr -d ' ')

if [[ "$POOLS_COUNT" -ge 1 ]]; then
    print_success "Pools indexed: $POOLS_COUNT pool(s)"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_error "No pools found in indexer"
    print_info "Response: $POOLS_RESP"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

# ─── Check: orders > 1 ───────────────────────────────────────────────────────
ORDERS_RESP=$(run_graphql "{ orders(limit: 10) { items { id status } } }")
ORDERS_COUNT=$(echo "$ORDERS_RESP" | grep -o '"id"' | wc -l | tr -d ' ')

if [[ "$ORDERS_COUNT" -ge 2 ]]; then
    print_success "Orders indexed: $ORDERS_COUNT order(s) (need > 1)"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
elif [[ "$ORDERS_COUNT" -ge 1 ]]; then
    print_warning "Orders indexed: $ORDERS_COUNT (expected > 1, may need populate-data.sh)"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
else
    print_error "No orders found in indexer (run populate-data.sh to generate data)"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

# ─── Check: trades >= 1 ──────────────────────────────────────────────────────
TRADES_RESP=$(run_graphql "{ trades(limit: 5) { items { id } } }")
TRADES_COUNT=$(echo "$TRADES_RESP" | grep -o '"id"' | wc -l | tr -d ' ')

if [[ "$TRADES_COUNT" -ge 1 ]]; then
    print_success "Trades indexed: $TRADES_COUNT trade(s)"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_warning "No trades found (populate-data.sh places opposing orders to create fills)"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

# ─── Check: indexer status ───────────────────────────────────────────────────
STATUS_RESP=$(run_graphql "{ indexerStatuses { items { id latestBlockNumber } } }")
LATEST_BLOCK=$(echo "$STATUS_RESP" | grep -o '"latestBlockNumber":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -n "$LATEST_BLOCK" ]] && [[ "$LATEST_BLOCK" != "0" ]]; then
    print_success "Indexer synced to block: $LATEST_BLOCK"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    print_warning "Could not read indexer sync status"
fi

echo ""

# ─── 5. Summary ──────────────────────────────────────────────────────────────
echo -e "${BLUE}========================================"
echo -e "  Indexer Verification Summary"
echo -e "========================================${NC}"
echo ""
echo "  Chain:   $CHAIN_NAME"
echo "  GraphQL: $GRAPHQL_URL"
echo ""
echo "  Passed: $CHECKS_PASSED"
echo "  Failed: $CHECKS_FAILED"
echo ""

if [[ "$CHECKS_FAILED" -eq 0 ]]; then
    print_success "All indexer checks passed!"
    exit 0
else
    print_error "$CHECKS_FAILED check(s) failed"
    echo ""
    echo "  Troubleshooting:"
    echo "    - Orders/trades missing? Run: bash shellscripts/populate-data.sh"
    echo "    - Ponder not syncing?   Check: pm2 logs $PM2_APP"
    echo "    - Wrong addresses?      Re-run: bash shellscripts/update-env.sh <chain-id>"
    echo ""
    exit 1
fi
