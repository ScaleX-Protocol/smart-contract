#!/bin/bash

# =============================================================================
# ScaleX Router Upgrade Script
# =============================================================================
# This script upgrades the ScaleXRouter contract via the Beacon Proxy pattern
# with full verification on Etherscan and/or Tenderly.
#
# REQUIRED ENVIRONMENT VARIABLES:
# - PRIVATE_KEY: Private key for transaction signing
# - SCALEX_CORE_RPC: RPC URL for the target chain
#
# OPTIONAL ENVIRONMENT VARIABLES:
# - CORE_CHAIN_ID: Chain ID (auto-detected if not set)
# - ETHERSCAN_API_KEY: API key for Etherscan verification
# - VERIFIER: "etherscan", "tenderly", or "both" (default: "both")
# - TENDERLY_PROJECT: Tenderly project slug
# - TENDERLY_USERNAME: Tenderly username
# - TENDERLY_ACCESS_KEY: Tenderly access key (for private projects)
#
# USAGE:
#   PRIVATE_KEY=<key> SCALEX_CORE_RPC=<rpc> bash shellscripts/upgrade_router.sh
#
# EXAMPLE (Base Sepolia with Etherscan):
#   PRIVATE_KEY=0x... \
#   SCALEX_CORE_RPC="https://sepolia.base.org" \
#   ETHERSCAN_API_KEY="your_key" \
#   bash shellscripts/upgrade_router.sh
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "\n${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Validate required environment variables
if [[ -z "$PRIVATE_KEY" ]]; then
    print_error "PRIVATE_KEY environment variable is required"
    exit 1
fi

if [[ -z "$SCALEX_CORE_RPC" ]]; then
    print_error "SCALEX_CORE_RPC environment variable is required"
    exit 1
fi

# Get chain ID if not set
if [[ -z "$CORE_CHAIN_ID" ]]; then
    CORE_CHAIN_ID=$(cast chain-id --rpc-url "$SCALEX_CORE_RPC" 2>/dev/null || echo "")
    if [[ -z "$CORE_CHAIN_ID" ]]; then
        print_error "Failed to detect chain ID from RPC"
        exit 1
    fi
fi

print_step "ScaleX Router Upgrade"
echo "  Chain ID: $CORE_CHAIN_ID"
echo "  RPC: $SCALEX_CORE_RPC"

# Check deployment file exists
DEPLOYMENT_FILE="deployments/${CORE_CHAIN_ID}.json"
if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
    print_error "Deployment file not found: $DEPLOYMENT_FILE"
    exit 1
fi

# Get router proxy address from deployment file
ROUTER_PROXY=$(cat "$DEPLOYMENT_FILE" | jq -r '.ScaleXRouter // "0x0000000000000000000000000000000000000000"')
if [[ "$ROUTER_PROXY" == "0x0000000000000000000000000000000000000000" ]]; then
    print_error "ScaleXRouter address not found in deployment file"
    exit 1
fi

print_success "Router Proxy: $ROUTER_PROXY"

# Get deployer address
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null)
print_success "Deployer: $DEPLOYER"

# Function to get verification flags (same as deploy.sh)
get_verification_flags() {
    local chain_id=$1
    local verifier="${VERIFIER:-both}"

    # Skip verification for local networks
    if [[ "$chain_id" == "31337" ]] || [[ "$SCALEX_CORE_RPC" == *"127.0.0.1"* ]] || [[ "$SCALEX_CORE_RPC" == *"localhost"* ]]; then
        echo ""
        return 0
    fi

    # Check if we should verify (public networks only)
    if [[ "$chain_id" == "84532" ]] || [[ "$chain_id" == "11155111" ]] || [[ "$chain_id" == "1" ]] || [[ "$SCALEX_CORE_RPC" == *"base-sepolia"* ]] || [[ "$SCALEX_CORE_RPC" == *"sepolia"* ]] || [[ "$SCALEX_CORE_RPC" == *"mainnet"* ]] || [[ "$SCALEX_CORE_RPC" == *"basescan"* ]]; then

        # Both Etherscan and Tenderly verification
        if [[ "$verifier" == "both" ]]; then
            if [[ -n "$ETHERSCAN_API_KEY" && "$ETHERSCAN_API_KEY" != "dummy_key_for_local_testing" ]]; then
                case $chain_id in
                    84532) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --chain 84532" ;;
                    11155111) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api-sepolia.etherscan.io/api" ;;
                    1) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.etherscan.io/api" ;;
                    42161) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.arbiscan.io/api" ;;
                    10) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api-optimistic.etherscan.io/api" ;;
                    137) echo "--verify --etherscan-api-KEY $ETHERSCAN_API_KEY --verifier-url https://api.polygonscan.com/api" ;;
                    *)
                        if [[ "$SCALEX_CORE_RPC" == *"base"* ]]; then
                            echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.basescan.org/api"
                        else
                            echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY"
                        fi
                        ;;
                esac
            else
                print_warning "ETHERSCAN_API_KEY not set - will only verify on Tenderly"
            fi
        # Tenderly-only verification
        elif [[ "$verifier" == "tenderly" ]]; then
            if [[ -n "$TENDERLY_PROJECT" && -n "$TENDERLY_USERNAME" ]]; then
                local flags="--verify --verifier tenderly --verifier-url https://api.tenderly.co/api/v1/account/${TENDERLY_USERNAME}/project/${TENDERLY_PROJECT}"
                if [[ -n "$TENDERLY_ACCESS_KEY" ]]; then
                    flags="$flags --etherscan-api-key $TENDERLY_ACCESS_KEY"
                fi
                echo "$flags"
            else
                print_warning "TENDERLY_PROJECT or TENDERLY_USERNAME not set - skipping Tenderly verification"
            fi
        # Etherscan-only verification
        else
            if [[ -n "$ETHERSCAN_API_KEY" && "$ETHERSCAN_API_KEY" != "dummy_key_for_local_testing" ]]; then
                case $chain_id in
                    84532) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --chain 84532" ;;
                    11155111) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api-sepolia.etherscan.io/api" ;;
                    1) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.etherscan.io/api" ;;
                    *)
                        if [[ "$SCALEX_CORE_RPC" == *"base"* ]]; then
                            echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.basescan.org/api"
                        else
                            echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY"
                        fi
                        ;;
                esac
            else
                print_warning "ETHERSCAN_API_KEY not set - skipping verification"
            fi
        fi
    else
        echo ""
    fi
}

# Verify contracts on Tenderly (post-deployment)
verify_on_tenderly() {
    local impl_address=$1

    if [[ "$VERIFIER" != "tenderly" && "$VERIFIER" != "both" ]]; then
        return 0
    fi

    if [[ -z "$TENDERLY_PROJECT" || -z "$TENDERLY_USERNAME" ]]; then
        print_warning "Skipping Tenderly verification - missing credentials"
        return 1
    fi

    if ! command -v tenderly &> /dev/null; then
        print_warning "Tenderly CLI not installed - skipping Tenderly verification"
        return 1
    fi

    print_step "Verifying on Tenderly..."

    if [[ -n "$TENDERLY_ACCESS_KEY" ]]; then
        tenderly login --authentication-method access-key --access-key "$TENDERLY_ACCESS_KEY" --force > /dev/null 2>&1
    fi

    if tenderly contract verify \
        --network "$CORE_CHAIN_ID" \
        "$impl_address" \
        --project-slug "$TENDERLY_PROJECT" \
        --username "$TENDERLY_USERNAME" > /dev/null 2>&1; then
        print_success "Tenderly verification complete"
        echo "  View at: https://dashboard.tenderly.co/${TENDERLY_USERNAME}/${TENDERLY_PROJECT}"
    else
        print_warning "Tenderly verification failed (may already be verified)"
    fi
}

# Get verification flags
VERIFY_FLAGS=$(get_verification_flags $CORE_CHAIN_ID)
if [[ -n "$VERIFY_FLAGS" ]]; then
    print_success "Verification ENABLED"
else
    print_warning "Verification DISABLED (local network or missing API key)"
fi

# Step 1: Get beacon address from proxy
print_step "Step 1: Discovering beacon address..."

# EIP1967 beacon storage slot
BEACON_SLOT="0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50"
BEACON_DATA=$(cast storage "$ROUTER_PROXY" "$BEACON_SLOT" --rpc-url "$SCALEX_CORE_RPC")
BEACON_ADDRESS="0x$(echo $BEACON_DATA | sed 's/0x//' | tail -c 41)"

print_success "Beacon Address: $BEACON_ADDRESS"

# Get current implementation
CURRENT_IMPL=$(cast call "$BEACON_ADDRESS" "implementation()" --rpc-url "$SCALEX_CORE_RPC")
CURRENT_IMPL="0x$(echo $CURRENT_IMPL | sed 's/0x//' | tail -c 41)"
print_success "Current Implementation: $CURRENT_IMPL"

# Verify ownership
BEACON_OWNER=$(cast call "$BEACON_ADDRESS" "owner()" --rpc-url "$SCALEX_CORE_RPC")
BEACON_OWNER="0x$(echo $BEACON_OWNER | sed 's/0x//' | tail -c 41)"
print_success "Beacon Owner: $BEACON_OWNER"

# Check if deployer is owner
DEPLOYER_LOWER=$(echo "$DEPLOYER" | tr '[:upper:]' '[:lower:]')
BEACON_OWNER_LOWER=$(echo "$BEACON_OWNER" | tr '[:upper:]' '[:lower:]')
if [[ "$DEPLOYER_LOWER" != "$BEACON_OWNER_LOWER" ]]; then
    print_error "Deployer is not the beacon owner!"
    echo "  Deployer: $DEPLOYER"
    echo "  Owner: $BEACON_OWNER"
    exit 1
fi

# Step 2: Deploy new implementation with verification
print_step "Step 2: Deploying new ScaleXRouter implementation..."

# Build the forge create command
FORGE_CMD="forge create src/core/ScaleXRouter.sol:ScaleXRouter --rpc-url $SCALEX_CORE_RPC --private-key $PRIVATE_KEY --broadcast"

if [[ -n "$VERIFY_FLAGS" ]]; then
    FORGE_CMD="$FORGE_CMD $VERIFY_FLAGS"
fi

echo "  Running: forge create src/core/ScaleXRouter.sol:ScaleXRouter ..."

# Execute and capture output
DEPLOY_OUTPUT=$(eval "$FORGE_CMD" 2>&1)
DEPLOY_EXIT_CODE=$?

echo "$DEPLOY_OUTPUT"

if [[ $DEPLOY_EXIT_CODE -ne 0 ]]; then
    print_error "Failed to deploy new implementation"
    exit 1
fi

NEW_IMPL=$(echo "$DEPLOY_OUTPUT" | grep "Deployed to:" | awk '{print $3}')

if [[ -z "$NEW_IMPL" ]]; then
    print_error "Failed to extract new implementation address"
    exit 1
fi

print_success "New Implementation: $NEW_IMPL"

# Step 3: Upgrade beacon
print_step "Step 3: Upgrading beacon to new implementation..."

UPGRADE_TX=$(cast send "$BEACON_ADDRESS" "upgradeTo(address)" "$NEW_IMPL" \
    --rpc-url "$SCALEX_CORE_RPC" \
    --private-key "$PRIVATE_KEY" 2>&1)

if [[ $? -ne 0 ]]; then
    print_error "Failed to upgrade beacon"
    echo "$UPGRADE_TX"
    exit 1
fi

print_success "Beacon upgraded successfully"

# Step 4: Verify upgrade
print_step "Step 4: Verifying upgrade..."

sleep 3  # Wait for transaction to be mined

VERIFIED_IMPL=$(cast call "$BEACON_ADDRESS" "implementation()" --rpc-url "$SCALEX_CORE_RPC")
VERIFIED_IMPL="0x$(echo $VERIFIED_IMPL | sed 's/0x//' | tail -c 41)"

NEW_IMPL_LOWER=$(echo "$NEW_IMPL" | tr '[:upper:]' '[:lower:]')
VERIFIED_IMPL_LOWER=$(echo "$VERIFIED_IMPL" | tr '[:upper:]' '[:lower:]')

if [[ "$NEW_IMPL_LOWER" == "$VERIFIED_IMPL_LOWER" ]]; then
    print_success "Implementation verified: $VERIFIED_IMPL"
else
    print_error "Implementation mismatch!"
    echo "  Expected: $NEW_IMPL"
    echo "  Got: $VERIFIED_IMPL"
    exit 1
fi

# Step 5: Tenderly verification (if enabled)
if [[ "$VERIFIER" == "tenderly" || "$VERIFIER" == "both" ]]; then
    verify_on_tenderly "$NEW_IMPL"
fi

# Summary
echo ""
echo "=============================================="
print_success "ScaleXRouter Upgrade Complete!"
echo "=============================================="
echo "  Chain ID: $CORE_CHAIN_ID"
echo "  Router Proxy: $ROUTER_PROXY"
echo "  Beacon: $BEACON_ADDRESS"
echo "  Old Implementation: $CURRENT_IMPL"
echo "  New Implementation: $NEW_IMPL"
echo ""
echo "All proxies using this beacon are now upgraded."
