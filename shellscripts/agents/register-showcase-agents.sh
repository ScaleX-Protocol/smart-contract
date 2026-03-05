#!/bin/bash
# Register 7 showcase agents on IdentityRegistry (Base Sepolia)
# Uses existing seed phrase (SEED_PHRASE) with indices 10-16
# (send-tokens.sh uses 0-9, so no overlap)
#
# Usage:
#   ./shellscripts/agents/register-showcase-agents.sh              # Register all 7
#   ./shellscripts/agents/register-showcase-agents.sh 10,12-14     # Specific indices
#   ./shellscripts/agents/register-showcase-agents.sh --dry-run    # Preview only
#   ./shellscripts/agents/register-showcase-agents.sh --fund-only  # Only fund wallets
#   ./shellscripts/agents/register-showcase-agents.sh --register-only  # Only register

set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Load .env
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../.env"

if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: .env not found at $ENV_FILE${NC}"
    exit 1
fi

# Parse .env manually to handle special characters
SEED_PHRASE=$(grep "^SEED_PHRASE=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
RPC_URL=$(grep "^SCALEX_CORE_RPC=" "$ENV_FILE" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")

if [ -z "$RPC_URL" ]; then
    RPC_URL="https://base-sepolia.g.alchemy.com/v2/jBG4sMyhez7V13jNTeQKfVfgNa54nCmF"
fi

if [ -z "$SEED_PHRASE" ]; then
    echo -e "${RED}Error: SEED_PHRASE not found in .env${NC}"
    exit 1
fi

# Funder = seed index 0 (Scalex 1 wallet, has ETH)
FUNDER_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" 0 2>/dev/null)

# ============================================================================
# Configuration
# ============================================================================

IDENTITY_REGISTRY="0x8004A818BFB912233c491871b3d84c89A494BD9e"  # Canonical ERC-8004 (indexed by 8004scan)
AGENT_ROUTER=$(jq -r '.AgentRouter' "$SCRIPT_DIR/../../deployments/84532.json" 2>/dev/null || echo "")
FUND_AMOUNT="0.001"  # ETH per wallet (~163k gas buffer)
R2_BASE="https://agents.scalex.money/agents"

# INDEX|NAME|R2_DIRECTORY
AGENTS=(
    "10|Smart Money Tracker|1"
    "17|Dip Buyer|2"
    "12|Lending Optimizer|3"
    "13|Range Trader|4"
    "14|Stop-Loss Guardian|5"
    "15|Alpha Scanner|6"
    "16|Social Sentiment Bot|7"
)

# ============================================================================
# Parse Arguments
# ============================================================================

DRY_RUN=false
FUND_ONLY=false
REGISTER_ONLY=false
INDICES_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --fund-only)
            FUND_ONLY=true
            shift
            ;;
        --register-only)
            REGISTER_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Usage: ./shellscripts/agents/register-showcase-agents.sh [indices] [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  indices             Wallet indices (10-17). Comma-separated or ranges."
            echo "                      Examples: 10,12,14 or 10-13 or 10,12-16,17"
            echo "  --dry-run           Show wallets and metadata URLs without transacting"
            echo "  --fund-only         Only send ETH to agent wallets"
            echo "  --register-only     Only register agents (assumes wallets are funded)"
            echo "  --help, -h          Show this help"
            echo ""
            echo "Agent Wallet Indices (seed phrase derivation):"
            echo "  10: Smart Money Tracker    14: Range Trader"
            echo "  17: Social Sentiment Bot   15: Stop-Loss Guardian"
            echo "  12: Dip Buyer              16: Alpha Scanner"
            echo "  13: Lending Optimizer"
            exit 0
            ;;
        *)
            if [[ "$1" =~ ^[0-9,\-]+$ ]]; then
                INDICES_ARG="$1"
            fi
            shift
            ;;
    esac
done

# ============================================================================
# Parse Indices
# ============================================================================

parse_indices() {
    local input="$1"
    local indices=()

    if [ -z "$input" ]; then
        echo "10 17 12 13 14 15 16"
        return
    fi

    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        if [[ "$part" == *-* ]]; then
            local start="${part%-*}"
            local end="${part#*-}"
            for ((i=start; i<=end; i++)); do
                if ([ "$i" -ge 10 ] && [ "$i" -le 16 ]) || [ "$i" -eq 17 ]; then
                    indices+=("$i")
                fi
            done
        else
            if ([ "$part" -ge 10 ] && [ "$part" -le 17 ]) 2>/dev/null; then
                indices+=("$part")
            fi
        fi
    done

    echo "${indices[@]}" | tr ' ' '\n' | sort -n | uniq | tr '\n' ' '
}

SELECTED_INDICES=($(parse_indices "$INDICES_ARG"))

if [ ${#SELECTED_INDICES[@]} -eq 0 ]; then
    echo -e "${RED}Error: No valid indices selected (must be 10-16)${NC}"
    exit 1
fi

# ============================================================================
# Get Agent Config by Index
# ============================================================================

get_agent_config() {
    local target_index=$1
    for agent in "${AGENTS[@]}"; do
        IFS='|' read -r idx name r2dir <<< "$agent"
        if [ "$idx" -eq "$target_index" ]; then
            echo "$idx|$name|$r2dir"
            return 0
        fi
    done
    return 1
}

# ============================================================================
# Display Header
# ============================================================================

FUNDER_ADDRESS=$(cast wallet address "$FUNDER_KEY" 2>/dev/null)

echo -e "${BLUE}==============================================
  ScaleX Showcase Agent Registration
==============================================${NC}"
echo ""
echo "Configuration:"
echo "  Registry:    $IDENTITY_REGISTRY"
echo "  RPC URL:     $RPC_URL"
echo "  Funder:      $FUNDER_ADDRESS (seed index 0)"
echo "  Fund Amount: $FUND_AMOUNT ETH per wallet"
echo -e "  Mode:        ${YELLOW}$([ "$DRY_RUN" = true ] && echo "DRY RUN" || ([ "$FUND_ONLY" = true ] && echo "FUND ONLY" || ([ "$REGISTER_ONLY" = true ] && echo "REGISTER ONLY" || echo "FULL")))${NC}"
echo ""
echo "Selected Agents:"

for idx in "${SELECTED_INDICES[@]}"; do
    config=$(get_agent_config "$idx")
    IFS='|' read -r _ name r2dir <<< "$config"
    AGENT_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" "$idx" 2>/dev/null)
    ADDRESS=$(cast wallet address "$AGENT_KEY" 2>/dev/null)
    echo "  [$idx] $name"
    echo "       Wallet:   $ADDRESS"
    echo "       Metadata: $R2_BASE/$r2dir/metadata.json"
done

echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${GREEN}Dry run complete. No transactions sent.${NC}"
    exit 0
fi

# ============================================================================
# Phase 1: Fund Wallets
# ============================================================================

if [ "$REGISTER_ONLY" != true ]; then
    echo -e "${BLUE}Phase 1: Funding Wallets${NC}"
    echo "----------------------------------------------"

    FUND_WEI=$(python3 -c "print(int($FUND_AMOUNT * 10**18))")

    for idx in "${SELECTED_INDICES[@]}"; do
        config=$(get_agent_config "$idx")
        IFS='|' read -r _ name r2dir <<< "$config"
        AGENT_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" "$idx" 2>/dev/null)
        ADDRESS=$(cast wallet address "$AGENT_KEY" 2>/dev/null)

        # Check existing balance
        BALANCE=$(cast balance "$ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null)
        BALANCE_ETH=$(python3 -c "print(f'{int(\"$BALANCE\") / 10**18:.6f}')" 2>/dev/null)

        if [ "$(python3 -c "print(1 if int('$BALANCE') >= $FUND_WEI else 0)")" = "1" ]; then
            echo -e "  [$idx] $name — ${GREEN}already has ${BALANCE_ETH} ETH, skipping${NC}"
            continue
        fi

        echo -n "  [$idx] $name — funding $FUND_AMOUNT ETH... "
        TX=$(cast send "$ADDRESS" --value "$FUND_WEI" \
            --private-key "$FUNDER_KEY" \
            --rpc-url "$RPC_URL" 2>&1)
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
            echo "       Error: $TX"
        fi
        sleep 2
    done

    echo ""
fi

if [ "$FUND_ONLY" = true ]; then
    echo -e "${GREEN}Funding complete.${NC} Run with --register-only to register agents."
    exit 0
fi

# ============================================================================
# Phase 2: Register Agents
# ============================================================================

echo -e "${BLUE}Phase 2: Registering Agents${NC}"
echo "----------------------------------------------"

declare -a REGISTERED_IDS=()

for idx in "${SELECTED_INDICES[@]}"; do
    config=$(get_agent_config "$idx")
    IFS='|' read -r _ name r2dir <<< "$config"
    AGENT_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" "$idx" 2>/dev/null)
    ADDRESS=$(cast wallet address "$AGENT_KEY" 2>/dev/null)
    METADATA_URL="$R2_BASE/$r2dir/metadata.json"

    echo -n "  [$idx] $name — registering... "
    TX_OUTPUT=$(cast send "$IDENTITY_REGISTRY" \
        "register(string)" "$METADATA_URL" \
        --private-key "$AGENT_KEY" \
        --rpc-url "$RPC_URL" 2>&1)

    if [ $? -eq 0 ]; then
        TX_HASH=$(echo "$TX_OUTPUT" | grep "^transactionHash" | awk '{print $2}')
        STATUS=$(echo "$TX_OUTPUT" | grep "^status" | awk '{print $2}')

        if [[ "$STATUS" == *"success"* ]] || [[ "$STATUS" == "1" ]]; then
            # Parse token ID from Transfer event log (last topic = tokenId)
            TOKEN_ID_HEX=$(echo "$TX_OUTPUT" | grep -oE '"0x[0-9a-f]{64}"' | tail -1 | tr -d '"' 2>/dev/null)
            if [ -n "$TOKEN_ID_HEX" ]; then
                TOKEN_ID=$(python3 -c "print(int('$TOKEN_ID_HEX', 16))")
            else
                TOKEN_ID="?"
            fi
            echo -e "${GREEN}OK${NC} — Token ID: $TOKEN_ID (tx: $TX_HASH)"
            REGISTERED_IDS+=("$idx|$name|$TOKEN_ID")
        else
            echo -e "${RED}REVERTED${NC} (tx: $TX_HASH)"
        fi
    else
        echo -e "${RED}FAILED${NC}"
        echo "       Error: $(echo "$TX_OUTPUT" | head -3)"
    fi
    sleep 3
done

echo ""

# ============================================================================
# Phase 3: List on Marketplace
# ============================================================================

if [ -n "$AGENT_ROUTER" ] && [ "$AGENT_ROUTER" != "null" ] && [ "$AGENT_ROUTER" != "0x0000000000000000000000000000000000000000" ]; then
    echo -e "${BLUE}Phase 3: Listing on Marketplace${NC}"
    echo "----------------------------------------------"

    for entry in "${REGISTERED_IDS[@]}"; do
        IFS='|' read -r idx name token_id <<< "$entry"

        if [ "$token_id" = "?" ]; then
            echo -e "  [$idx] $name — ${YELLOW}token ID unknown, skipping marketplace listing${NC}"
            continue
        fi

        AGENT_KEY=$(cast wallet derive-private-key "$SEED_PHRASE" "$idx" 2>/dev/null)

        echo -n "  [$idx] $name (Token #$token_id) — listing on marketplace... "
        LIST_TX=$(cast send "$AGENT_ROUTER" \
            "listOnMarketplace(uint256)" "$token_id" \
            --private-key "$AGENT_KEY" \
            --rpc-url "$RPC_URL" 2>&1)

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
            echo "       Error: $(echo "$LIST_TX" | head -3)"
        fi
        sleep 2
    done

    echo ""
else
    echo -e "${YELLOW}Skipping marketplace listing — AgentRouter not found in deployments/84532.json${NC}"
    echo ""
fi

# ============================================================================
# Phase 4: Verify
# ============================================================================

echo -e "${BLUE}Phase 4: Verification${NC}"
echo "----------------------------------------------"

for entry in "${REGISTERED_IDS[@]}"; do
    IFS='|' read -r idx name token_id <<< "$entry"

    if [ "$token_id" = "?" ]; then
        echo -e "  [$idx] $name — ${YELLOW}token ID unknown, verify manually${NC}"
        continue
    fi

    echo -n "  [$idx] $name (Token #$token_id) — "
    URI=$(cast call "$IDENTITY_REGISTRY" "tokenURI(uint256)(string)" "$token_id" --rpc-url "$RPC_URL" 2>/dev/null)

    if [ -n "$URI" ] && [ "$URI" != '""' ]; then
        URI_CLEAN=$(echo "$URI" | tr -d '"')
        echo "tokenURI = $URI_CLEAN"

        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URI_CLEAN")
        if [ "$HTTP_CODE" = "200" ]; then
            AGENT_NAME=$(curl -s "$URI_CLEAN" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name','?'))" 2>/dev/null)
            echo -e "       ${GREEN}Metadata OK${NC} — name: $AGENT_NAME"
        else
            echo -e "       ${RED}Metadata FAILED${NC} — HTTP $HTTP_CODE"
        fi
    else
        echo -e "${RED}tokenURI is empty!${NC}"
    fi
done

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${GREEN}==============================================
  Registration Complete
==============================================${NC}"
echo ""
if [ ${#REGISTERED_IDS[@]} -gt 0 ]; then
    echo "Registered Agents:"
    for entry in "${REGISTERED_IDS[@]}"; do
        IFS='|' read -r idx name token_id <<< "$entry"
        echo "  [$idx] $name → Token ID: $token_id"
    done
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Check agents on frontend: http://localhost:3000/agents"
    echo "  2. Authorize agents for users: ./shellscripts/agents/user-authorize-agent.sh"
else
    echo "No agents were registered."
fi
echo ""
