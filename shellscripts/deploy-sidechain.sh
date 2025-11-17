#!/bin/bash

# SCALEX Chain-Agnostic Side Chain Deployment Script
# Deploys side chain components for any blockchain network
# Usage: bash deploy-sidechain.sh <network> <core_chain_id> <side_chain_id> <core_balance_manager> <core_mailbox> <side_mailbox>

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW} $1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

# Check arguments
if [[ $# -lt 6 ]]; then
    print_error "Usage: $0 <network> <core_chain_id> <side_chain_id> <core_balance_manager> <core_mailbox> <side_mailbox> [additional_options]"
    echo ""
    echo "Arguments:"
    echo "  network              - Network name (e.g., arbitrum_sepolia, base_sepolia, polygon_mumbai)"
    echo "  core_chain_id        - Core chain ID (e.g., 31337)"
    echo "  side_chain_id        - Side chain ID for this deployment"
    echo "  core_balance_manager  - Address of core chain BalanceManager"
    echo "  core_mailbox         - Address of core chain mailbox"
    echo "  side_mailbox         - Address of side chain mailbox"
    echo ""
    echo "Optional arguments:"
    echo "  --skip-validation    - Skip post-deployment validation"
    echo "  --dry-run            - Show what would be deployed without executing"
    echo ""
    echo "Examples:"
    echo "  $0 base_sepolia 31337 31337 0x1234...abcd 0x5678...efgh 0x9abc...def0"
    echo "  $0 arbitrum_sepolia 31337 42161 0x1234...abcd 0x5678...efgh 0x9abc...def0 --skip-validation"
    exit 1
fi

NETWORK=$1
CORE_CHAIN_ID=$2
SIDE_CHAIN_ID=$3
CORE_BALANCE_MANAGER=$4
CORE_MAILBOX=$5
SIDE_MAILBOX=$6

# Additional options
SKIP_VALIDATION=false
DRY_RUN=false

for arg in "${@:7}"; do
    case $arg in
        --skip-validation)
            SKIP_VALIDATION=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            print_warning "Unknown option: $arg"
            ;;
    esac
done

echo "🚀 Starting SCALEX Chain-Agnostic Side Chain Deployment..."
echo "   Network: $NETWORK"
echo "   Core Chain ID: $CORE_CHAIN_ID"
echo "   Side Chain ID: $SIDE_CHAIN_ID"
echo "   Core Balance Manager: $CORE_BALANCE_MANAGER"
echo "   Core Mailbox: $CORE_MAILBOX"
echo "   Side Mailbox: $SIDE_MAILBOX"
echo "   Skip Validation: $SKIP_VALIDATION"
echo "   Dry Run: $DRY_RUN"

# Check if we're in the right directory
if [[ ! -f "Makefile" ]] || [[ ! -d "script" ]]; then
    print_error "Please run this script from the clob-dex project root directory"
    exit 1
fi

# Load environment variables from .env file if it exists
if [[ -f ".env" ]]; then
    print_step "Loading environment variables from .env file..."
    set -a  # automatically export all variables
    source .env
    set +a  # turn off auto-export
    print_success "Environment variables loaded from .env"
fi

# Check for required environment variables
check_env_var() {
    if [[ -z "${!1}" ]]; then
        print_error "Environment variable $1 is not set"
        return 1
    else
        print_success "$1: ${!1}"
        return 0
    fi
}

echo ""
print_step "Checking environment variables..."

# Required variables
REQUIRED_VARS=("PRIVATE_KEY")
missing_vars=()

for var in "${REQUIRED_VARS[@]}"; do
    if ! check_env_var "$var"; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    print_error "Missing required environment variables: ${missing_vars[*]}"
    echo ""
    echo "Please set the following environment variables:"
    for var in "${missing_vars[@]}"; do
        echo "  export $var=<your_$var>"
    done
    exit 1
fi

# Validate addresses
validate_address() {
    local address=$1
    local name=$2
    
    if [[ ! $address =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        print_error "Invalid $name address: $address"
        return 1
    fi
    return 0
}

echo ""
print_step "Validating addresses..."

validation_errors=0

if ! validate_address "$CORE_BALANCE_MANAGER" "Core Balance Manager"; then
    ((validation_errors++))
fi

if ! validate_address "$CORE_MAILBOX" "Core Mailbox"; then
    ((validation_errors++))
fi

if ! validate_address "$SIDE_MAILBOX" "Side Mailbox"; then
    ((validation_errors++))
fi

if [[ $validation_errors -gt 0 ]]; then
    print_error "Address validation failed with $validation_errors errors"
    exit 1
fi

print_success "All addresses validated successfully"

# Set timeout for long-running operations
export FORGE_TIMEOUT=1200

# Get RPC URL for the network
get_rpc_url() {
    case $1 in
        arbitrum_sepolia)
            echo "https://sepolia-rollup.arbitrum.io/rpc"
            ;;
        base_sepolia)
            echo "https://base-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY:-demo}"
            ;;
        polygon_mumbai)
            echo "https://rpc-mumbai.maticvigil.com"
            ;;
        optimism_sepolia)
            echo "https://sepolia.optimism.io"
            ;;
        avalanche_fuji)
            echo "https://api.avax-test.network/ext/bc/C/rpc"
            ;;
        bsc_testnet)
            echo "https://data-seed-prebsc-1-s1.binance.org:8545"
            ;;
        *)
            # Fallback to environment variable
            echo "${RPC_URL:-https://rpc.ankr.com/$1}"
            ;;
    esac
}

RPC_URL=$(get_rpc_url "$NETWORK")

if [[ -z "$RPC_URL" ]]; then
    print_error "Could not determine RPC URL for network: $NETWORK"
    echo "Please set RPC_URL environment variable manually"
    exit 1
fi

print_success "RPC URL: $RPC_URL"

# Check if network is reachable
print_step "Testing network connectivity..."
if ! curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' "$RPC_URL" | grep -q "result"; then
    print_error "Network is not reachable: $NETWORK"
    exit 1
fi
print_success "Network connectivity verified"

# Deployment functions
deploy_side_chain_balance_manager() {
    print_step "Deploying Side Chain Balance Manager (Chain ID: $SIDE_CHAIN_ID)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would deploy Side Chain Balance Manager"
        return 0
    fi
    
    # Set environment variables for deployment
    export CORE_BALANCE_MANAGER
    export CORE_MAILBOX
    export SIDE_MAILBOX
    export SIDE_CHAIN_ID
    
    # Deploy Side Chain Balance Manager
    make deploy-side-chain-bm network=$NETWORK
    
    print_success "Side Chain Balance Manager deployed"
}

update_side_chain_mappings() {
    print_step "Updating Side Chain Mappings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would update side chain mappings"
        return 0
    fi
    
    # Update side chain mappings
    make update-side-chain-mappings network=$NETWORK
    
    print_success "Side Chain mappings updated"
}

validate_deployment() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        print_warning "Skipping deployment validation"
        return 0
    fi
    
    print_step "Validating Side Chain Deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would validate deployment"
        return 0
    fi
    
    # Check if deployment file exists
    deployment_file="deployments/${SIDE_CHAIN_ID}.json"
    
    if [[ -f "$deployment_file" ]]; then
        print_success "Deployment file found: $deployment_file"
        
        # Extract key contract addresses
        chain_balance_manager=$(jq -r '.ChainBalanceManager // "NOT_FOUND"' "$deployment_file")
        
        echo ""
        print_step "📋 Deployed Contracts:"
        echo "  Chain Balance Manager: $chain_balance_manager"
        
        # Validate contracts are deployed
        if [[ "$chain_balance_manager" != "NOT_FOUND" ]] && [[ "$chain_balance_manager" != "null" ]]; then
            print_success "All contracts deployed successfully"
        else
            print_error "Some contracts may not have deployed properly"
            return 1
        fi
    else
        print_error "Deployment file not found: $deployment_file"
        return 1
    fi
}

create_deployment_summary() {
    local deployment_file="deployments/${SIDE_CHAIN_ID}.json"
    
    if [[ ! -f "$deployment_file" ]]; then
        print_warning "Deployment file not found, skipping summary creation"
        return 0
    fi
    
    print_step "Creating deployment summary..."
    
    local summary_file="deployments/sidechain_${SIDE_CHAIN_ID}_summary.json"
    
    # Create summary JSON
    cat > "$summary_file" << EOF
{
    "deployment": {
        "network": "$NETWORK",
        "core_chain_id": $CORE_CHAIN_ID,
        "side_chain_id": $SIDE_CHAIN_ID,
        "core_balance_manager": "$CORE_BALANCE_MANAGER",
        "core_mailbox": "$CORE_MAILBOX",
        "side_mailbox": "$SIDE_MAILBOX",
        "timestamp": $(date +%s),
        "deployed_by": "$(whoami)"
    },
    "contracts": $(jq '{ChainBalanceManager: .ChainBalanceManager}' "$deployment_file"),
    "configuration": {
        "cross_chain_enabled": true,
        "hyperlane_messaging": true,
        "balance_management": true
    }
}
EOF
    
    print_success "Deployment summary saved to: $summary_file"
}

# Deployment execution
echo ""
print_step "Starting Side Chain Deployment Process..."

# Step 1: Deploy Side Chain Balance Manager
deploy_side_chain_balance_manager

# Step 2: Update Side Chain Mappings
update_side_chain_mappings

# Step 3: Validate Deployment
validate_deployment

# Step 4: Create Deployment Summary
create_deployment_summary

echo ""
print_success " Side Chain Deployment completed successfully!"

echo ""
print_step "📋 Deployment Summary:"
echo "  🌐 Network: $NETWORK"
echo "  📍 Side Chain ID: $SIDE_CHAIN_ID"
echo "  🔗 Core Chain ID: $CORE_CHAIN_ID"
echo "  📄 Deployment File: deployments/${SIDE_CHAIN_ID}.json"
echo "  📊 Summary File: deployments/sidechain_${SIDE_CHAIN_ID}_summary.json"

echo ""
print_step "🔗 Cross-Chain Configuration:"
echo "  Core Balance Manager: $CORE_BALANCE_MANAGER"
echo "  Core Mailbox: $CORE_MAILBOX"
echo "  Side Mailbox: $SIDE_MAILBOX"
echo "  Side Chain Balance Manager: Deployed"

echo ""
echo "Next steps:"
echo "  🔍 Test cross-chain: make test-cross-chain-deposit network=$NETWORK side_chain=$SIDE_CHAIN_ID core_chain=$CORE_CHAIN_ID token=USDC amount=1000000"
echo "  📊 Check balances: make check-side-chain-balance network=$NETWORK"
echo "  📖 View deployment: cat deployments/sidechain_${SIDE_CHAIN_ID}_summary.json"

echo ""
print_success "🚀 Side Chain is ready for cross-chain operations!"
echo ""
print_step "📚 Integration Notes:"
echo "  - Side chain is now connected to core chain via Hyperlane"
echo "  - Cross-chain deposits can be initiated from this side chain"
echo "  - Balance Manager handles asset bridging and synthetic tokens"
echo "  - Users can deposit assets to access core chain markets"