#!/bin/bash

# SCALEX Deployment Validation Script
# Validates deployment for any environment (local, testnet, or mainnet)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to load .env file
load_env_file() {
    local env_file="${1:-.env}"
    
    if [[ -f "$env_file" ]]; then
        echo "📝 Loading environment variables from $env_file..."
        # Read each line, skip comments and empty lines
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ $line =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            # Export valid KEY=VALUE pairs
            if [[ $line =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                export "$line"
            fi
        done < "$env_file"
        echo "✅ Environment variables loaded from $env_file"
    else
        echo "⚠️  $env_file file not found - using defaults"
    fi
}

# Function to get chain ID from RPC URL
get_chain_id() {
    local rpc_url=$1
    # Try to get chain ID from RPC
    local chain_id=$(curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' "$rpc_url" | jq -r '.result' 2>/dev/null)
    
    # If RPC call fails or returns null, default to environment variable or 31337
    if [[ -z "$chain_id" || "$chain_id" == "null" ]]; then
        echo "${CORE_CHAIN_ID:-31337}"
    else
        # Remove 0x prefix and convert to decimal
        echo $((chain_id))
    fi
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW} $1${NC}"
}

print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

# Load environment variables from .env file
load_env_file

# Set RPC URL if not already set
export SCALEX_CORE_RPC="${SCALEX_CORE_RPC:-http://127.0.0.1:8545}"

# Get chain ID for this validation
export CORE_CHAIN_ID="${CORE_CHAIN_ID:-$(get_chain_id "${SCALEX_CORE_RPC}")}"

echo "🔍 Validating SCALEX Deployment..."
echo "Timestamp: $(date)"
echo "Chain ID: $CORE_CHAIN_ID"
echo "RPC URL: ${SCALEX_CORE_RPC}"
echo ""

print_step "Checking Required Tools..."
if ! command -v jq >/dev/null 2>&1; then
    print_error "jq is required but not installed"
    exit 1
fi

if ! command -v cast >/dev/null 2>&1; then
    print_error "cast (foundry) is required but not installed"
    exit 1
fi

print_success "Required tools available"
echo ""

print_step "Validating Deployment File..."
DEPLOYMENT_FILE="deployments/${CORE_CHAIN_ID}.json"
if [ ! -f "$DEPLOYMENT_FILE" ]; then
    print_error "Deployment file missing: $DEPLOYMENT_FILE"
    print_error "Run: bash shellscripts/deploy.sh"
    exit 1
fi

print_success "Deployment file exists: $DEPLOYMENT_FILE"
echo ""

print_step "Validating Core Contracts..."

# Check if we have at least mock tokens for basic testing
HAS_MOCK_TOKENS=false
for token in "USDC" "WETH" "WBTC"; do
    ADDRESS=$(jq -r ".$token" $DEPLOYMENT_FILE 2>/dev/null)
    
    if [ "$ADDRESS" != "null" ] && [ -n "$ADDRESS" ] && [ "$ADDRESS" != "0x0000000000000000000000000000000000000000" ]; then
        CODE=$(cast code $ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x")
        if [ "$CODE" != "0x" ]; then
            print_success "Mock token $token validated: $ADDRESS"
            HAS_MOCK_TOKENS=true
        else
            print_warning "Mock token $token at $ADDRESS has no code"
        fi
    fi
done

# Check for core contracts (optional for basic data population)
HAS_CORE_CONTRACTS=true
for contract in "Oracle" "TokenRegistry" "LendingManager" "BalanceManager" "ScaleXRouter"; do
    ADDRESS=$(jq -r ".$contract" $DEPLOYMENT_FILE 2>/dev/null)
    
    if [ "$ADDRESS" = "null" ] || [ -z "$ADDRESS" ] || [ "$ADDRESS" = "0x0000000000000000000000000000000000000000" ]; then
        print_warning "Core contract $contract not found in deployment file"
        HAS_CORE_CONTRACTS=false
    else
        CODE=$(cast code $ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x")
        if [ "$CODE" = "0x" ]; then
            print_warning "Core contract $contract at $ADDRESS has no code"
            HAS_CORE_CONTRACTS=false
        else
            print_success "$contract validated: $ADDRESS"
        fi
    fi
done

if [ "$HAS_MOCK_TOKENS" = true ]; then
    print_success "Mock tokens available for testing"
else
    print_error "No valid contracts found in deployment file"
    exit 1
fi

echo ""
print_step "Checking Account Balances..."

DEFAULT_ACCOUNT="0x27dD1eBE7D826197FD163C134E79502402Fd7cB7"

# Check if account has ETH for gas
ETH_BALANCE=$(cast balance $DEFAULT_ACCOUNT --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
if [ "$ETH_BALANCE" != "0" ]; then
    print_success "Default account has ETH balance: $(cast from-wei $ETH_BALANCE)"
else
    print_warning "Default account has no ETH balance"
fi

# Check mock token balances if tokens exist
USDC_ADDRESS=$(jq -r '.USDC' $DEPLOYMENT_FILE)
if [ "$USDC_ADDRESS" != "null" ] && [ "$USDC_ADDRESS" != "0x0000000000000000000000000000000000000000" ]; then
    USDC_BALANCE=$(cast call $USDC_ADDRESS "balanceOf(address)" $DEFAULT_ACCOUNT --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    if [ "$USDC_BALANCE" != "0" ]; then
        print_success "Default account has USDC balance: $(echo $USDC_BALANCE | awk '{printf "%.2f", $1/1000000}') USDC"
    else
        print_warning "Default account has no USDC balance"
    fi
fi

echo ""
print_success " DEPLOYMENT VALIDATION PASSED!"
echo "Mock tokens available for testing"
echo "Chain ready for data population"
echo "System ready for basic data population"
echo ""
echo "You can now proceed with data population:"
echo "  ./shellscripts/populate-data.sh"
echo ""
echo "Note: Core contracts (LendingManager, Oracle) would need to be deployed for full functionality"
echo ""
echo "Validation completed at: $(date)"