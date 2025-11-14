#!/bin/bash

# SCALEX Local Development Validation Script
# Validates single-chain local Anvil deployment for data population

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

echo "🔍 Validating SCALEX Local Development Deployment..."
echo "Timestamp: $(date)"
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

print_step "Validating Local Deployment File..."
if [ ! -f "deployments/31337.json" ]; then
    print_error "Local deployment file missing: deployments/31337.json"
    print_error "Run: make deploy-development"
    exit 1
fi

print_success "Deployment file exists: deployments/31337.json"
echo ""

print_step "Validating Core Contracts..."
DEPLOYMENT_FILE="deployments/31337.json"
RPC_URL="http://127.0.0.1:8545"

# Check if we have at least mock tokens for basic testing
HAS_MOCK_TOKENS=false
for token in "USDC" "WETH" "WBTC"; do
    ADDRESS=$(jq -r ".$token" $DEPLOYMENT_FILE 2>/dev/null)
    
    if [ "$ADDRESS" != "null" ] && [ -n "$ADDRESS" ] && [ "$ADDRESS" != "0x0000000000000000000000000000000000000000" ]; then
        CODE=$(cast code $ADDRESS --rpc-url $RPC_URL 2>/dev/null || echo "0x")
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
for contract in "Oracle" "TokenRegistry" "LendingManager" "BalanceManager" "SCALEXRouter"; do
    ADDRESS=$(jq -r ".$contract" $DEPLOYMENT_FILE 2>/dev/null)
    
    if [ "$ADDRESS" = "null" ] || [ -z "$ADDRESS" ] || [ "$ADDRESS" = "0x0000000000000000000000000000000000000000" ]; then
        print_warning "Core contract $contract not found in deployment file"
        HAS_CORE_CONTRACTS=false
    else
        CODE=$(cast code $ADDRESS --rpc-url $RPC_URL 2>/dev/null || echo "0x")
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
ETH_BALANCE=$(cast balance $DEFAULT_ACCOUNT --rpc-url $RPC_URL 2>/dev/null || echo "0")
if [ "$ETH_BALANCE" != "0" ]; then
    print_success "Default account has ETH balance: $(cast from-wei $ETH_BALANCE)"
else
    print_warning "Default account has no ETH balance"
fi

# Check mock token balances if tokens exist
USDC_ADDRESS=$(jq -r '.USDC' $DEPLOYMENT_FILE)
if [ "$USDC_ADDRESS" != "null" ] && [ "$USDC_ADDRESS" != "0x0000000000000000000000000000000000000000" ]; then
    USDC_BALANCE=$(cast call $USDC_ADDRESS "balanceOf(address)" $DEFAULT_ACCOUNT --rpc-url $RPC_URL 2>/dev/null || echo "0")
    if [ "$USDC_BALANCE" != "0" ]; then
        print_success "Default account has USDC balance: $(echo $USDC_BALANCE | awk '{printf "%.2f", $1/1000000}') USDC"
    else
        print_warning "Default account has no USDC balance"
    fi
fi

echo ""
print_success "🎉 LOCAL DEVELOPMENT VALIDATION PASSED!"
echo "Mock tokens available for testing"
echo "Local Anvil chain ready"
echo "System ready for basic data population"
echo ""
echo "You can now proceed with data population:"
echo "  ./shellscripts/populate-data.sh"
echo ""
echo "Note: Core contracts (LendingManager, Oracle) would need to be deployed for full functionality"
echo ""
echo "Validation completed at: $(date)"