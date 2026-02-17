#!/bin/bash
# Verify Deployment - Orchestrates full post-deployment verification
#
# USAGE:
#   ./shellscripts/verify-deployment.sh <chain-id>
#   ./shellscripts/verify-deployment.sh 84532        # Base Sepolia
#   ./shellscripts/verify-deployment.sh 31337        # Local anvil
#
# TYPICAL WORKFLOW:
#   make deploy network=base_sepolia | tee deploy.log
#   ./shellscripts/update-env.sh 84532 deploy.log
#   ./shellscripts/verify-deployment.sh 84532
#
# EXIT CODES:
#   0 - all checks passed
#   1 - one or more checks failed
#   2 - usage error or missing prerequisites

set -e

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }
print_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
print_info()    { echo -e "       $1"; }
print_section() { echo -e "\n${BOLD}$1${NC}"; echo "$(echo "$1" | sed 's/./─/g')"; }

# ─── Chain name mapping ───────────────────────────────────────────────────────
get_chain_name() {
    case "$1" in
        84532)    echo "base-sepolia" ;;
        1116)     echo "core-chain" ;;
        5003)     echo "mantle-sepolia" ;;
        11155111) echo "sepolia" ;;
        1)        echo "mainnet" ;;
        31337)    echo "local" ;;
        31338)    echo "anvil" ;;
        *)        echo "" ;;
    esac
}

# ─── Args ─────────────────────────────────────────────────────────────────────
CHAIN_ID="${1:-}"
if [[ -z "$CHAIN_ID" ]]; then
    echo "Usage: $0 <chain-id>"
    echo ""
    echo "  Supported chain IDs:"
    echo "    84532    - Base Sepolia"
    echo "    1116     - Core Chain"
    echo "    5003     - Mantle Sepolia"
    echo "    11155111 - Sepolia"
    echo "    31337    - Local (anvil)"
    echo "    31338    - Anvil (second instance)"
    echo ""
    echo "  Example workflow:"
    echo "    bash shellscripts/deploy.sh"
    echo "    bash shellscripts/update-env.sh 84532 deploy.log"
    echo "    bash shellscripts/verify-deployment.sh 84532"
    exit 2
fi

CHAIN_NAME=$(get_chain_name "$CHAIN_ID")
if [[ -z "$CHAIN_NAME" ]]; then
    print_error "Unknown chain ID: $CHAIN_ID"
    echo "  Supported: 84532, 1116, 5003, 11155111, 1, 31337, 31338"
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
DEPLOYMENT_FILE="$PROJECT_ROOT/deployments/${CHAIN_ID}.json"
INDEXER_ENV="$PROJECT_ROOT/../clob-indexer/ponder/.env.$CHAIN_NAME"

# ─── Header ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}════════════════════════════════════════${NC}"
echo -e "${BOLD}${BLUE}  Deployment Verification${NC}"
echo -e "${BOLD}${BLUE}  Chain: $CHAIN_NAME ($CHAIN_ID)${NC}"
echo -e "${BOLD}${BLUE}════════════════════════════════════════${NC}"
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_WARNINGS=0

record_pass()    { TOTAL_PASSED=$((TOTAL_PASSED + 1)); }
record_fail()    { TOTAL_FAILED=$((TOTAL_FAILED + 1)); }
record_warning() { TOTAL_WARNINGS=$((TOTAL_WARNINGS + 1)); }

# ─── SECTION 1: Prerequisites ─────────────────────────────────────────────────
print_section "1. Prerequisites"

# Check deployment file
if [[ -f "$DEPLOYMENT_FILE" ]]; then
    print_success "Deployment file found: deployments/${CHAIN_ID}.json"
    record_pass
else
    print_error "Deployment file missing: deployments/${CHAIN_ID}.json"
    print_info "Run deploy.sh first to generate deployment file"
    record_fail
    # Cannot proceed without deployment file
    echo ""
    print_error "Cannot continue without deployment file. Exiting."
    exit 1
fi

# Check update-env.sh was run (indexer env exists)
if [[ -f "$INDEXER_ENV" ]]; then
    print_success "Indexer env configured: .env.$CHAIN_NAME"
    record_pass
else
    print_error "Indexer env not found: $INDEXER_ENV"
    print_info "Run: bash shellscripts/update-env.sh $CHAIN_ID"
    record_fail
fi

# ─── SECTION 2: Contract Addresses ────────────────────────────────────────────
print_section "2. Deployed Contract Addresses"

check_address() {
    local name="$1"
    local key="$2"
    local required="${3:-true}"
    local addr

    addr=$(cat "$DEPLOYMENT_FILE" | grep -o "\"$key\":[[:space:]]*\"0x[^\"]*\"" | \
           grep -o '"0x[^"]*"' | tr -d '"' 2>/dev/null || echo "")

    if [[ -z "$addr" ]] || [[ "$addr" == "0x0000000000000000000000000000000000000000" ]]; then
        if [[ "$required" == "true" ]]; then
            print_error "$name: not deployed (key: $key)"
            record_fail
        else
            print_warning "$name: not deployed (optional)"
            record_warning
        fi
        return 1
    else
        local short="${addr:0:10}...${addr: -6}"
        print_success "$name: $short"
        record_pass
        return 0
    fi
}

# Core contracts (required)
check_address "PoolManager"    "PoolManager"    true
check_address "BalanceManager" "BalanceManager" true
check_address "ScaleXRouter"   "ScaleXRouter"   true
check_address "Oracle"         "Oracle"         true
check_address "TokenRegistry"  "TokenRegistry"  true

# Phase 4 (optional)
check_address "LendingManager"   "LendingManager"   false
check_address "AutoBorrowHelper" "AutoBorrowHelper" false

# Phase 5 - Agent infrastructure (optional)
check_address "PolicyFactory"      "PolicyFactory"      false
check_address "AgentRouter"        "AgentRouter"        false
check_address "IdentityRegistry"   "IdentityRegistry"   false
check_address "ReputationRegistry" "ReputationRegistry" false

# ─── SECTION 3: RPC Connectivity ─────────────────────────────────────────────
print_section "3. RPC Connectivity"

# Load RPC from env or deployment file
RPC_URL="${SCALEX_CORE_RPC:-}"
if [[ -z "$RPC_URL" ]] && [[ -f "$PROJECT_ROOT/.env" ]]; then
    RPC_URL=$(grep "^SCALEX_CORE_RPC=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
fi
if [[ -z "$RPC_URL" ]]; then
    # Default RPC for known chains
    case "$CHAIN_ID" in
        84532)    RPC_URL="https://sepolia.base.org" ;;
        31337)    RPC_URL="http://127.0.0.1:8545" ;;
        31338)    RPC_URL="http://127.0.0.1:8546" ;;
        *)        RPC_URL="" ;;
    esac
fi

if [[ -n "$RPC_URL" ]]; then
    BLOCK=$(cast block-number --rpc-url "$RPC_URL" 2>/dev/null || echo "")
    if [[ -n "$BLOCK" ]] && [[ "$BLOCK" -gt 0 ]]; then
        print_success "RPC connected: block $BLOCK ($RPC_URL)"
        record_pass
    else
        print_error "RPC not responding: $RPC_URL"
        record_fail
    fi
else
    print_warning "RPC URL not configured (set SCALEX_CORE_RPC)"
    record_warning
fi

# ─── SECTION 4: Indexer Verification ─────────────────────────────────────────
print_section "4. Indexer Verification"

VERIFY_INDEXER="$SCRIPT_DIR/verify-indexer.sh"

if [[ ! -f "$VERIFY_INDEXER" ]]; then
    print_error "verify-indexer.sh not found at: $VERIFY_INDEXER"
    record_fail
elif [[ ! -f "$INDEXER_ENV" ]]; then
    print_warning "Skipping indexer verification (env not configured)"
    record_warning
else
    echo ""
    # Run verify-indexer.sh and capture its exit code
    if bash "$VERIFY_INDEXER" "$CHAIN_NAME"; then
        # verify-indexer.sh prints its own pass/fail lines
        record_pass
    else
        record_fail
    fi
fi

# ─── SECTION 5: Final Report ──────────────────────────────────────────────────
TOTAL_CHECKS=$((TOTAL_PASSED + TOTAL_FAILED))

echo ""
echo -e "${BOLD}${BLUE}════════════════════════════════════════${NC}"
echo -e "${BOLD}  Verification Report${NC}"
echo -e "${BOLD}${BLUE}════════════════════════════════════════${NC}"
echo ""
echo "  Chain:    $CHAIN_NAME ($CHAIN_ID)"
echo "  Passed:   $TOTAL_PASSED / $TOTAL_CHECKS checks"
if [[ $TOTAL_WARNINGS -gt 0 ]]; then
    echo -e "  Warnings: ${YELLOW}$TOTAL_WARNINGS${NC}"
fi
if [[ $TOTAL_FAILED -gt 0 ]]; then
    echo -e "  Failed:   ${RED}$TOTAL_FAILED${NC}"
fi
echo ""

if [[ "$TOTAL_FAILED" -eq 0 ]]; then
    print_success "Deployment verified successfully!"
    echo ""
    echo "  Next steps:"
    echo "    - Start trading: bash shellscripts/populate-data.sh"
    echo "    - Monitor indexer: pm2 logs ponder-$CHAIN_NAME"
    echo ""
    exit 0
else
    print_error "Verification failed ($TOTAL_FAILED issue(s) found)"
    echo ""
    echo "  Common fixes:"
    if [[ ! -f "$INDEXER_ENV" ]]; then
        echo "    - Run update-env.sh:  bash shellscripts/update-env.sh $CHAIN_ID"
    fi
    echo "    - Re-deploy:          bash shellscripts/deploy.sh"
    echo "    - Check populate:     bash shellscripts/populate-data.sh"
    echo "    - View indexer logs:  pm2 logs ponder-$CHAIN_NAME"
    echo ""
    exit 1
fi
