#!/bin/bash

# SCALEX Local Development Deployment Script
# Deploys CLOB DEX + Lending Protocol for local development

# ========================================
# ENVIRONMENT VARIABLES
# ========================================
# Before running this script, you may need to set these environment variables:
#
# REQUIRED:
# - PRIVATE_KEY: Private key for deployment account (reads from .env file by default)
#
# OPTIONAL (with defaults):
# - SCALEX_CORE_RPC: RPC URL for core chain (default: http://127.0.0.1:8545)
# - SCALEX_SIDE_RPC: RPC URL for side chain (default: http://127.0.0.1:8545)
# - CORE_CHAIN_ID: Chain ID for deployment (default: auto-detected from RPC)
# - FORGE_TIMEOUT: Timeout for forge operations (default: 1200 seconds)
# - FORGE_SLOW_MODE: Enable slow mode for forge broadcasts to prevent RPC rate limiting (default: true)
# - ETHERSCAN_API_KEY: API key for contract verification on public networks (optional)
# - VERIFIER: Verification service to use: "both" (default), "etherscan", or "tenderly"
# - TENDERLY_PROJECT: Tenderly project slug (required for Tenderly verification)
# - TENDERLY_USERNAME: Tenderly username (required for Tenderly verification)
# - TENDERLY_ACCESS_KEY: Tenderly access key (optional, for private projects)
#
# USAGE EXAMPLES:
# # Basic usage (deploys upgradeable agent infrastructure):
# bash shellscripts/deploy.sh
#
# # With custom RPC:
# SCALEX_CORE_RPC="http://localhost:8545" bash shellscripts/deploy.sh
#
# # With Etherscan verification on Base Sepolia:
# SCALEX_CORE_RPC="https://sepolia.base.org" ETHERSCAN_API_KEY="your_key" bash shellscripts/deploy.sh
#
# # With Tenderly verification on Base Sepolia:
# SCALEX_CORE_RPC="https://sepolia.base.org" VERIFIER="tenderly" \
# TENDERLY_PROJECT="my-project" TENDERLY_USERNAME="myusername" bash shellscripts/deploy.sh
#
# # With BOTH Etherscan and Tenderly verification:
# SCALEX_CORE_RPC="https://sepolia.base.org" VERIFIER="both" \
# ETHERSCAN_API_KEY="your_key" TENDERLY_PROJECT="my-project" \
# TENDERLY_USERNAME="myusername" bash shellscripts/deploy.sh
#
# # With custom private key and RPC:
# PRIVATE_KEY="0xYourPrivateKey" SCALEX_CORE_RPC="http://localhost:8545" bash shellscripts/deploy.sh
#
# # Using .env file:
#
# # Disable slow mode (not recommended for public RPCs):
# FORGE_SLOW_MODE="false" bash shellscripts/deploy.sh
# echo "0xYourPrivateKey" > .env
# SCALEX_CORE_RPC="http://localhost:8545" bash shellscripts/deploy.sh
# ========================================

# set -e  # Exit on any error - REMOVED for better error handling

# Set timeout for long-running operations (20 minutes)
export FORGE_TIMEOUT=1200

# Set slow mode for forge script broadcasts (prevents RPC rate limiting)
# Set to "false" to disable slow mode (not recommended for public RPCs)
export FORGE_SLOW_MODE="${FORGE_SLOW_MODE:-true}"

# Build slow flag for forge commands
if [[ "$FORGE_SLOW_MODE" == "true" ]]; then
    SLOW_FLAG="--slow"
    echo "📡 Slow mode enabled (adds delays between transactions to prevent RPC rate limiting)"
else
    SLOW_FLAG=""
    echo "⚡ Slow mode disabled (may cause RPC rate limiting on public RPCs)"
fi

echo "🚀 Starting SCALEX Core Chain Deployment (CLOB DEX + Lending Protocol)..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source quote currency configuration module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/quote-currency-config.sh"

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

# Helper function to convert padded synthetic token address to proper format
convert_synthetic_address() {
    local padded_address="$1"
    if [[ ${#padded_address} -gt 42 ]]; then
        echo "0x${padded_address: -40}"
    else
        echo "$padded_address"
    fi
}

# Helper function to normalize addresses for comparison
# Strips leading zeros and converts to lowercase
normalize_address() {
    local address="$1"
    # Remove 0x prefix, strip leading zeros, convert to lowercase, add 0x back
    local normalized=$(echo "$address" | sed 's/^0x//i' | sed 's/^0*//' | tr '[:upper:]' '[:lower:]')
    echo "0x${normalized}"
}

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

# Function to verify operator authorization
verify_authorization() {
    local balance_manager=$1
    local operator=$2
    local operator_name=$3

    echo "  🔍 Checking if $operator_name is authorized..."
    sleep 2  # Rate limiting delay
    local is_authorized=$(cast call $balance_manager "isAuthorizedOperator(address)(bool)" $operator --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "false")

    if [[ "$is_authorized" == "true" ]]; then
        print_success "  ✅ $operator_name is authorized"
        return 0
    else
        # Fallback: Check for OperatorSet event (for older contracts without isAuthorizedOperator function)
        echo "  🔍 Fallback: Checking event logs for authorization..."
        local event_sig="0x1a594081ae893ab78e67d9b9e843547318164322d32c65369d78a96172d9dc8f"
        local operator_padded=$(printf "0x%064s" "${operator:2}" | tr ' ' '0')

        # Check recent blocks for OperatorSet event
        local has_event=$(cast logs --address $balance_manager \
            --from-block -1000 \
            "$event_sig" \
            "$operator_padded" \
            --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | grep -c "$operator_padded" || echo "0")

        if [[ "$has_event" -gt "0" ]]; then
            print_success "  ✅ $operator_name is authorized (verified via events)"
            return 0
        else
            print_error "  ❌ $operator_name is NOT authorized"
            return 1
        fi
    fi
}

# Function to manually authorize operator with retry
authorize_operator() {
    local balance_manager=$1
    local operator=$2
    local operator_name=$3
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        echo "  🔄 Attempt $attempt of $max_attempts to authorize $operator_name..."
        sleep 2  # Rate limiting delay

        if cast send $balance_manager "setAuthorizedOperator(address,bool)" $operator true \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1 2>/dev/null; then

            # Verify it was actually set
            sleep 3
            if verify_authorization "$balance_manager" "$operator" "$operator_name"; then
                return 0
            fi
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            echo "  ⏳ Waiting 5s before retry..."
            sleep 5
        fi
        attempt=$((attempt + 1))
    done

    print_error "  ❌ Failed to authorize $operator_name after $max_attempts attempts"
    return 1
}

# Function to get verification flags for forge commands
get_verification_flags() {
    local chain_id=$1
    local verifier="${VERIFIER:-both}"  # Default to both Etherscan and Tenderly if not set

    # Skip verification for local networks
    if [[ "$chain_id" == "31337" ]] || [[ "$SCALEX_CORE_RPC" == *"127.0.0.1"* ]] || [[ "$SCALEX_CORE_RPC" == *"localhost"* ]]; then
        echo ""
        return 0
    fi

    # Check if we should verify (public networks only)
    if [[ "$chain_id" == "84532" ]] || [[ "$chain_id" == "11155111" ]] || [[ "$chain_id" == "1" ]] || [[ "$SCALEX_CORE_RPC" == *"base-sepolia"* ]] || [[ "$SCALEX_CORE_RPC" == *"sepolia"* ]] || [[ "$SCALEX_CORE_RPC" == *"mainnet"* ]] || [[ "$SCALEX_CORE_RPC" == *"basescan"* ]]; then

        # Both Etherscan and Tenderly verification
        if [[ "$verifier" == "both" ]]; then
            # Primary: Use Etherscan for inline verification (during forge script)
            # Secondary: Tenderly will be done post-deployment
            if [[ -n "$ETHERSCAN_API_KEY" && "$ETHERSCAN_API_KEY" != "dummy_key_for_local_testing" ]]; then
                case $chain_id in
                    84532) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --chain 84532" ;;
                    11155111) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api-sepolia.etherscan.io/api" ;;
                    1) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.etherscan.io/api" ;;
                    42161) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.arbiscan.io/api" ;;
                    10) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api-optimistic.etherscan.io/api" ;;
                    137) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.polygonscan.com/api" ;;
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
                # Add access key if provided (for private projects)
                if [[ -n "$TENDERLY_ACCESS_KEY" ]]; then
                    flags="$flags --etherscan-api-key $TENDERLY_ACCESS_KEY"
                fi
                echo "$flags"
            else
                print_warning "TENDERLY_PROJECT or TENDERLY_USERNAME not set - skipping Tenderly verification"
                echo "  To enable Tenderly verification, set:"
                echo "  export VERIFIER='tenderly'"
                echo "  export TENDERLY_PROJECT='your-project-slug'"
                echo "  export TENDERLY_USERNAME='your-username'"
                echo "  export TENDERLY_ACCESS_KEY='your-access-key' # optional, for private projects"
                echo ""
            fi
        # Etherscan-only verification (default)
        else
            if [[ -n "$ETHERSCAN_API_KEY" && "$ETHERSCAN_API_KEY" != "dummy_key_for_local_testing" && "$ETHERSCAN_API_KEY" != "" ]]; then
                case $chain_id in
                    84532) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --chain 84532" ;;
                    11155111) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api-sepolia.etherscan.io/api" ;;
                    1) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.etherscan.io/api" ;;
                    42161) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.arbiscan.io/api" ;;
                    10) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api-optimistic.etherscan.io/api" ;;
                    137) echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.polygonscan.com/api" ;;
                    *)
                        # Try to auto-detect verifier URL from RPC hostname
                        if [[ "$SCALEX_CORE_RPC" == *"base"* ]]; then
                            echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY --verifier-url https://api.basescan.org/api"
                        else
                            echo "--verify --etherscan-api-key $ETHERSCAN_API_KEY"
                        fi
                        ;;
                esac
            else
                print_warning "ETHERSCAN_API_KEY not set or invalid - skipping contract verification"
                echo "  To enable verification, set a valid API key:"
                echo "  export ETHERSCAN_API_KEY='your_actual_api_key_here'"
                echo ""
            fi
        fi
    else
        # Local development - no verification needed
        echo ""
    fi
}

# Function to verify contracts on Tenderly (post-deployment)
verify_on_tenderly() {
    local chain_id=$1
    local deployment_file="deployments/${chain_id}.json"

    # Check if Tenderly verification is needed
    if [[ "$VERIFIER" != "tenderly" && "$VERIFIER" != "both" ]]; then
        return 0
    fi

    # Validate Tenderly credentials
    if [[ -z "$TENDERLY_PROJECT" || -z "$TENDERLY_USERNAME" ]]; then
        print_warning "Skipping Tenderly verification - missing TENDERLY_PROJECT or TENDERLY_USERNAME"
        return 1
    fi

    # Check if tenderly CLI is installed
    if ! command -v tenderly &> /dev/null; then
        print_warning "Tenderly CLI not installed - skipping Tenderly verification"
        echo "  Install with: npm install -g @tenderly/cli"
        echo "  Or: curl https://raw.githubusercontent.com/Tenderly/tenderly-cli/master/scripts/install-linux.sh | sh"
        return 1
    fi

    print_step "Verifying contracts on Tenderly..."

    # Check if deployment file exists
    if [[ ! -f "$deployment_file" ]]; then
        print_error "Deployment file not found: $deployment_file"
        return 1
    fi

    # Login to Tenderly (if access key is provided)
    if [[ -n "$TENDERLY_ACCESS_KEY" ]]; then
        echo "  🔐 Logging in to Tenderly..."
        tenderly login --authentication-method access-key --access-key "$TENDERLY_ACCESS_KEY" --force > /dev/null 2>&1
    fi

    # Extract contract addresses from deployment file
    local contracts=($(jq -r 'to_entries[] | select(.value | startswith("0x")) | .key' "$deployment_file" 2>/dev/null))

    if [[ ${#contracts[@]} -eq 0 ]]; then
        print_warning "No contracts found in deployment file"
        return 1
    fi

    echo "  📋 Found ${#contracts[@]} contracts to verify on Tenderly"

    # Verify each contract on Tenderly
    local success_count=0
    local fail_count=0

    for contract_name in "${contracts[@]}"; do
        local contract_address=$(jq -r ".$contract_name" "$deployment_file")

        # Skip if address is invalid
        if [[ ! "$contract_address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            continue
        fi

        echo "  🔍 Verifying $contract_name at $contract_address..."

        # Use tenderly contract verify command
        if tenderly contract verify \
            --network "$chain_id" \
            "$contract_address" \
            --project-slug "$TENDERLY_PROJECT" \
            --username "$TENDERLY_USERNAME" > /dev/null 2>&1; then
            success_count=$((success_count + 1))
            echo "    ✅ $contract_name verified"
        else
            fail_count=$((fail_count + 1))
            echo "    ❌ $contract_name verification failed"
        fi

        # Small delay to avoid rate limiting
        sleep 1
    done

    echo ""
    print_success "Tenderly verification complete: $success_count succeeded, $fail_count failed"
    echo "  🌐 View at: https://dashboard.tenderly.co/${TENDERLY_USERNAME}/${TENDERLY_PROJECT}"

    return 0
}

# Function to validate verification setup
validate_verification_setup() {
    local chain_id=$1
    local verifier="${VERIFIER:-both}"  # Default to both if not set

    # Only validate on public networks
    if [[ "$chain_id" == "31337" ]] || [[ "$SCALEX_CORE_RPC" == *"127.0.0.1"* ]] || [[ "$SCALEX_CORE_RPC" == *"localhost"* ]]; then
        return 0  # Skip validation for local development
    fi

    # Check if forge verify-contract command is available
    if ! forge verify-contract --help >/dev/null 2>&1; then
        print_warning "forge verify-contract command not available - verification disabled"
        return 1
    fi

    local validation_passed=true

    # Validate Etherscan setup (if needed)
    if [[ "$verifier" == "etherscan" || "$verifier" == "both" ]]; then
        if [[ -n "$ETHERSCAN_API_KEY" ]]; then
            if [[ ${#ETHERSCAN_API_KEY} -lt 10 ]] || [[ "$ETHERSCAN_API_KEY" == "dummy_key_for_local_testing" ]]; then
                print_error "Invalid ETHERSCAN_API_KEY format"
                echo "  Expected: Real API key (at least 10 characters)"
                echo "  Current: ${ETHERSCAN_API_KEY:0:10}..."
                validation_passed=false
            else
                print_success "✅ Etherscan API key validated"
            fi
        else
            print_warning "⚠️  No ETHERSCAN_API_KEY set - Etherscan verification will be skipped"
            if [[ "$verifier" == "etherscan" ]]; then
                validation_passed=false
            fi
        fi
    fi

    # Validate Tenderly setup (if needed)
    if [[ "$verifier" == "tenderly" || "$verifier" == "both" ]]; then
        if [[ -n "$TENDERLY_PROJECT" && -n "$TENDERLY_USERNAME" ]]; then
            print_success "✅ Tenderly credentials validated"

            # Check if Tenderly CLI is installed (optional warning)
            if ! command -v tenderly &> /dev/null; then
                print_warning "⚠️  Tenderly CLI not installed - verification will use API only"
                echo "  Install with: npm install -g @tenderly/cli"
            fi
        else
            print_error "❌ Missing Tenderly credentials"
            echo "  Required: TENDERLY_PROJECT and TENDERLY_USERNAME"
            if [[ "$verifier" == "tenderly" ]]; then
                validation_passed=false
            fi
        fi
    fi

    if [[ "$validation_passed" == true ]]; then
        print_success "Verification setup validated"
        return 0
    else
        return 1
    fi
}

# Load environment variables from .env file
load_env_file

# Load quote currency configuration
load_quote_currency_config

# Check if we're in the right directory
if [[ ! -f "Makefile" ]] || [[ ! -d "script" ]]; then
    print_error "Please run this script from the clob-dex project root directory"
    exit 1
fi

# Local Development Mode Only
print_step "🔧 Running in LOCAL DEVELOPMENT MODE - using hardcoded configuration..."

# Hardcoded mailbox values for development
export CORE_MAILBOX="0x0000000000000000000000000000000000000000"
export SIDE_MAILBOX="0x0000000000000000000000000000000000000000"
# Load environment variables from .env file
if [[ -f ".env" ]]; then
    source .env
fi

export PRIVATE_KEY="${PRIVATE_KEY:-$(cat .env 2>/dev/null | head -1 | tr -d '\n' || echo "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")}"

# Support both Anvil and dedicated devnets
# Always prioritize local Anvil unless explicitly overridden
if [[ -z "$SCALEX_CORE_RPC" ]]; then
    export SCALEX_CORE_RPC="http://127.0.0.1:8545"
    print_success "Using local Anvil RPC (default): ${SCALEX_CORE_RPC}"
else
    # Check if the provided RPC is a remote devnet, if so warn user
    if [[ "$SCALEX_CORE_RPC" != *"127.0.0.1"* && "$SCALEX_CORE_RPC" != *"localhost"* ]]; then
        print_warning "Using remote devnet RPC: ${SCALEX_CORE_RPC}"
        print_warning "For local development, use: SCALEX_CORE_RPC=http://127.0.0.1:8545"
    else
        print_success "Using RPC from environment: ${SCALEX_CORE_RPC}"
    fi
fi

# Same logic for side chain RPC
if [[ -z "$SCALEX_SIDE_RPC" ]]; then
    export SCALEX_SIDE_RPC="http://127.0.0.1:8545"
    print_success "Using local Anvil RPC for side chain (default): ${SCALEX_SIDE_RPC}"
else
    # Check if the provided RPC is a remote devnet, if so warn user
    if [[ "$SCALEX_SIDE_RPC" != *"127.0.0.1"* && "$SCALEX_SIDE_RPC" != *"localhost"* ]]; then
        print_warning "Using remote devnet RPC for side chain: ${SCALEX_SIDE_RPC}"
    else
        print_success "Using side RPC from environment: ${SCALEX_SIDE_RPC}"
    fi
fi

print_success "Local development mode configured:"
echo "  CORE_MAILBOX: $CORE_MAILBOX"
echo "  SIDE_MAILBOX: $SIDE_MAILBOX"
echo ""

# Get chain ID from RPC URL or default to 31337
get_chain_id() {
    local rpc_url=$1
    # Try to get chain ID from RPC
    local chain_id=$(curl -s -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' "$rpc_url" | jq -r '.result' 2>/dev/null)
    
    # If RPC call fails or returns null, default to CORE_CHAIN_ID
    if [[ -z "$chain_id" || "$chain_id" == "null" ]]; then
        echo "${CORE_CHAIN_ID:-31337}"
    else
        # Remove 0x prefix and convert to decimal
        echo $((chain_id))
    fi
}

# Get chain ID for this deployment
export CORE_CHAIN_ID="${CORE_CHAIN_ID:-$(get_chain_id "${SCALEX_CORE_RPC:-https://core-devnet.scalex.money}")}"
print_success "Detected Core Chain ID: $CORE_CHAIN_ID"

# Check verification status and validate setup
VERIFY_FLAGS=$(get_verification_flags $CORE_CHAIN_ID)
if [[ -n "$VERIFY_FLAGS" ]]; then
    validate_verification_setup $CORE_CHAIN_ID
    if [[ $? -eq 0 ]]; then
        print_success "Contract verification ENABLED and validated for this deployment"
    else
        print_warning "Contract verification setup issues detected - verification may fail"
        echo "  Consider fixing the above issues or proceed without verification"
        read -p "  Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Deployment cancelled by user"
            exit 1
        fi
        # Disable verification if user continues
        VERIFY_FLAGS=""
    fi
else
    print_warning "Contract verification DISABLED (local network or missing API key)"
fi

# Step 1: Clean Previous Data
print_step "Step 1: Cleaning previous deployment data for chain ${CORE_CHAIN_ID}..."
mkdir -p deployments/
rm -f deployments/${CORE_CHAIN_ID}.json
rm -rf broadcast/ cache/ out/
print_success "Previous data cleaned for chain ${CORE_CHAIN_ID}"

# Step 2: Phase 1A - Deploy Tokens
print_step "Step 2: Phase 1A - Deploying Tokens..."
VERIFY_FLAGS=$(get_verification_flags $CORE_CHAIN_ID)
# Split VERIFY_FLAGS into array to handle multiple arguments properly
if [[ -n "$VERIFY_FLAGS" ]]; then
    # Use eval to properly split verification flags (safer approach with controlled input)
    if eval "CORE_MAILBOX=\$CORE_MAILBOX SIDE_MAILBOX=\$SIDE_MAILBOX forge script script/deployments/DeployPhase1A.s.sol:DeployPhase1A --rpc-url \"\${SCALEX_CORE_RPC}\" --broadcast --private-key \$PRIVATE_KEY --gas-estimate-multiplier 120 $SLOW_FLAG $VERIFY_FLAGS"; then
        print_success "Phase 1A deployment completed"
    else
        print_error "❌ Phase 1A deployment FAILED!"
        exit 1
    fi
else
    if CORE_MAILBOX=$CORE_MAILBOX SIDE_MAILBOX=$SIDE_MAILBOX forge script script/deployments/DeployPhase1A.s.sol:DeployPhase1A --rpc-url "${SCALEX_CORE_RPC}" --broadcast --private-key $PRIVATE_KEY --gas-estimate-multiplier 120 $SLOW_FLAG; then
        print_success "Phase 1A deployment completed"
    else
        print_error "❌ Phase 1A deployment FAILED!"
        exit 1
    fi
fi

# Add delay between phases
echo "⏳ Waiting 15 seconds before Phase 1B..."
sleep 15

# Step 2.1: Phase 1B - Deploy Core Infrastructure
print_step "Step 2.1: Phase 1B - Deploying Core Infrastructure..."
# Split VERIFY_FLAGS into array to handle multiple arguments properly
if [[ -n "$VERIFY_FLAGS" ]]; then
    # Use eval to properly split verification flags (safer approach with controlled input)
    if eval "CORE_MAILBOX=\$CORE_MAILBOX SIDE_MAILBOX=\$SIDE_MAILBOX forge script script/deployments/DeployPhase1B.s.sol:DeployPhase1B --rpc-url \"\${SCALEX_CORE_RPC}\" --broadcast --private-key \$PRIVATE_KEY --gas-estimate-multiplier 120 $SLOW_FLAG $VERIFY_FLAGS"; then
        print_success "Phase 1B deployment completed"
    else
        print_error "❌ Phase 1B deployment FAILED!"
        exit 1
    fi
else
    if CORE_MAILBOX=$CORE_MAILBOX SIDE_MAILBOX=$SIDE_MAILBOX forge script script/deployments/DeployPhase1B.s.sol:DeployPhase1B --rpc-url "${SCALEX_CORE_RPC}" --broadcast --private-key $PRIVATE_KEY --gas-estimate-multiplier 120 $SLOW_FLAG; then
        print_success "Phase 1B deployment completed"
    else
        print_error "❌ Phase 1B deployment FAILED!"
        exit 1
    fi
fi

# Add delay between phases
echo "⏳ Waiting 15 seconds before Phase 1C..."
sleep 15

# Step 2.2: Phase 1C - Deploy Final Infrastructure
print_step "Step 2.2: Phase 1C - Deploying Final Infrastructure..."
# Split VERIFY_FLAGS into array to handle multiple arguments properly
if [[ -n "$VERIFY_FLAGS" ]]; then
    # Use eval to properly split verification flags (safer approach with controlled input)
    if eval "CORE_MAILBOX=\$CORE_MAILBOX SIDE_MAILBOX=\$SIDE_MAILBOX forge script script/deployments/DeployPhase1C.s.sol:DeployPhase1C --rpc-url \"\${SCALEX_CORE_RPC}\" --broadcast --private-key \$PRIVATE_KEY --gas-estimate-multiplier 120 $SLOW_FLAG $VERIFY_FLAGS"; then
        print_success "Phase 1C deployment completed"
    else
        print_error "❌ Phase 1C deployment FAILED!"
        exit 1
    fi
else
    if CORE_MAILBOX=$CORE_MAILBOX SIDE_MAILBOX=$SIDE_MAILBOX forge script script/deployments/DeployPhase1C.s.sol:DeployPhase1C --rpc-url "${SCALEX_CORE_RPC}" --broadcast --private-key $PRIVATE_KEY --gas-estimate-multiplier 120 $SLOW_FLAG; then
        print_success "Phase 1C deployment completed"
    else
        print_error "❌ Phase 1C deployment FAILED!"
        exit 1
    fi
fi

# Add delay before Phase 2
echo "⏳ Waiting 30 seconds before Phase 2 to prevent rate limiting..."
sleep 30

# Step 2.5: Phase 2 - Configure and Setup Contracts  
print_step "Step 2.5: Phase 2 - Configuration and Setup..."

# Read Phase 1 addresses and set as environment variables for Phase 2
if [[ -f "deployments/${CORE_CHAIN_ID}.json" ]]; then
    echo "Reading Phase 1 deployment addresses..."
    
    # Validate JSON is valid first
    if ! jq empty deployments/${CORE_CHAIN_ID}.json 2>/dev/null; then
        print_error "Phase 1 deployment JSON is invalid!"
        echo "Attempting to fix JSON format..."
        # Fix missing commas before running jq
        sed -i '' 's/"}$/",/g' deployments/${CORE_CHAIN_ID}.json
        sed -i '' 's/"}$/"/g' deployments/${CORE_CHAIN_ID}.json
        
        # Try to add missing comma before deployer line
        if grep -q '"SyntheticTokenFactory"' deployments/${CORE_CHAIN_ID}.json && grep -q '"deployer"' deployments/${CORE_CHAIN_ID}.json; then
            sed -i '' 's/"SyntheticTokenFactory": ".*"/&,/' deployments/${CORE_CHAIN_ID}.json
        fi
    fi
    
    # Extract addresses with error handling
    # Dynamic quote token extraction
    QUOTE_TOKEN_KEY=$(get_quote_token_key)
    QUOTE_TOKEN_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r ".$QUOTE_TOKEN_KEY // \"0x0000000000000000000000000000000000000000\"" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")

    # Other token addresses
    WETH_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.WETH // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    WBTC_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.WBTC // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    GOLD_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.GOLD // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    SILVER_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.SILVER // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    GOOGLE_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.GOOGLE // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    NVIDIA_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.NVIDIA // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    MNT_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.MNT // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    APPLE_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.APPLE // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")

    # Core contract addresses
    TOKEN_REGISTRY_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.TokenRegistry // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    ORACLE_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.Oracle // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    LENDING_MANAGER_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.LendingManager // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    BALANCE_MANAGER_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.BalanceManager // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    POOL_MANAGER_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.PoolManager // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    SCALEX_ROUTER_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.ScaleXRouter // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    SYNTHETIC_TOKEN_FACTORY_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.SyntheticTokenFactory // "0x0000000000000000000000000000000000000000"' 2>/dev/null || echo "0x0000000000000000000000000000000000000000")

    # Export for Phase 2 script
    export QUOTE_TOKEN_ADDRESS
    export QUOTE_CURRENCY
    export QUOTE_SYMBOL
    export QUOTE_NAME
    export QUOTE_DECIMALS
    export QUOTE_COLLATERAL_FACTOR
    export QUOTE_LIQUIDATION_THRESHOLD
    export QUOTE_LIQUIDATION_BONUS
    export QUOTE_RESERVE_FACTOR
    export QUOTE_BASE_RATE
    export QUOTE_OPTIMAL_UTIL
    export QUOTE_SLOPE1
    export QUOTE_SLOPE2
    export WETH_ADDRESS
    export WBTC_ADDRESS
    export GOLD_ADDRESS
    export SILVER_ADDRESS
    export GOOGLE_ADDRESS
    export NVIDIA_ADDRESS
    export MNT_ADDRESS
    export APPLE_ADDRESS
    export TOKEN_REGISTRY_ADDRESS
    export ORACLE_ADDRESS
    export LENDING_MANAGER_ADDRESS
    export BALANCE_MANAGER_ADDRESS
    export POOL_MANAGER_ADDRESS
    export SCALEX_ROUTER_ADDRESS
    export SYNTHETIC_TOKEN_FACTORY_ADDRESS

    echo "Phase 1 addresses loaded for Phase 2:"
    echo "  Quote Currency:"
    echo "    $QUOTE_SYMBOL: $QUOTE_TOKEN_ADDRESS"
    echo "  Crypto Tokens:"
    echo "    WETH: $WETH_ADDRESS"
    echo "    WBTC: $WBTC_ADDRESS"
    echo "  RWA Tokens:"
    echo "    GOLD: $GOLD_ADDRESS"
    echo "    SILVER: $SILVER_ADDRESS"
    echo "    GOOGLE: $GOOGLE_ADDRESS"
    echo "    NVIDIA: $NVIDIA_ADDRESS"
    echo "    MNT: $MNT_ADDRESS"
    echo "    APPLE: $APPLE_ADDRESS"
    echo "  Core Contracts:"
    echo "    TokenRegistry: $TOKEN_REGISTRY_ADDRESS"
    echo "    Oracle: $ORACLE_ADDRESS"
    echo "    LendingManager: $LENDING_MANAGER_ADDRESS"
    echo "    BalanceManager: $BALANCE_MANAGER_ADDRESS"
    echo "    PoolManager: $POOL_MANAGER_ADDRESS"
    echo "    ScaleXRouter: $SCALEX_ROUTER_ADDRESS"
    echo "    SyntheticTokenFactory: $SYNTHETIC_TOKEN_FACTORY_ADDRESS"
else
    print_error "Phase 1 deployment file not found!"
    exit 1
fi

# Split VERIFY_FLAGS into array to handle multiple arguments properly
print_step "Executing Phase 2 deployment (this will show transaction details)..."
if [[ -n "$VERIFY_FLAGS" ]]; then
    # Use eval to properly split verification flags (safer approach with controlled input)
    if eval "CORE_MAILBOX=\$CORE_MAILBOX SIDE_MAILBOX=\$SIDE_MAILBOX forge script script/deployments/DeployPhase2.s.sol:DeployPhase2 --rpc-url \"\${SCALEX_CORE_RPC}\" --broadcast --private-key \$PRIVATE_KEY --gas-estimate-multiplier 120 $SLOW_FLAG $VERIFY_FLAGS"; then
        print_success "Phase 2 deployment transactions completed"
    else
        print_error "❌ Phase 2 deployment FAILED! Check the forge output above for details."
        exit 1
    fi
else
    if CORE_MAILBOX=$CORE_MAILBOX SIDE_MAILBOX=$SIDE_MAILBOX forge script script/deployments/DeployPhase2.s.sol:DeployPhase2 --rpc-url "${SCALEX_CORE_RPC}" --broadcast --private-key $PRIVATE_KEY --gas-estimate-multiplier 120 $SLOW_FLAG; then
        print_success "Phase 2 deployment transactions completed"
    else
        print_error "❌ Phase 2 deployment FAILED! Check the forge output above for details."
        exit 1
    fi
fi

# Verify critical authorizations were set by Phase 2
print_step "Step 2.6: Verifying Phase 2 Authorizations..."

# Read contract addresses for verification
BALANCE_MANAGER_ADDRESS=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.BalanceManager // "0x0000000000000000000000000000000000000000"')
SCALEX_ROUTER_ADDRESS=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.ScaleXRouter // "0x0000000000000000000000000000000000000000"')
POOL_MANAGER_ADDRESS=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.PoolManager // "0x0000000000000000000000000000000000000000"')

if [[ "$BALANCE_MANAGER_ADDRESS" == "0x0000000000000000000000000000000000000000" ]]; then
    print_error "BalanceManager address not found in deployment file"
    exit 1
fi

# Verify ScaleXRouter authorization
if ! verify_authorization "$BALANCE_MANAGER_ADDRESS" "$SCALEX_ROUTER_ADDRESS" "ScaleXRouter"; then
    print_warning "ScaleXRouter not authorized. Attempting manual authorization..."
    if ! authorize_operator "$BALANCE_MANAGER_ADDRESS" "$SCALEX_ROUTER_ADDRESS" "ScaleXRouter"; then
        print_warning "⚠️ WARNING: Could not verify ScaleXRouter authorization via contract call."
        print_warning "   This may be due to missing getter function in older contract version."
        print_warning "   If authorization transactions succeeded (check tx logs), you can continue."
        print_warning "   Continuing deployment..."
    fi
fi

# Verify PoolManager authorization
if ! verify_authorization "$BALANCE_MANAGER_ADDRESS" "$POOL_MANAGER_ADDRESS" "PoolManager"; then
    print_warning "PoolManager not authorized. Attempting manual authorization..."
    if ! authorize_operator "$BALANCE_MANAGER_ADDRESS" "$POOL_MANAGER_ADDRESS" "PoolManager"; then
        print_warning "⚠️ WARNING: Could not verify PoolManager authorization via contract call."
        print_warning "   This may be due to missing getter function in older contract version."
        print_warning "   If authorization transactions succeeded (check tx logs), you can continue."
        print_warning "   Continuing deployment..."
    fi
fi

print_success "✅ All Phase 2 authorizations verified successfully"

# Add delay between Phase 2 and Phase 3 to prevent rate limiting
echo "⏳ Waiting 20 seconds before Phase 3 to prevent rate limiting..."
sleep 20

# Step 3: Phase 3 - Final Integration Testing
print_step "Step 3: Phase 3 - Final Integration Testing..."
print_success "Oracle deployment included in unified deployment"

  # Step 4: Configure System Integration
print_step "Step 4: Configuring System Integration..."

print_success "Using deployed contracts from unified deployment"

# Get contract addresses from deployments
BALANCE_MANAGER_ADDRESS=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.BalanceManager // "0x0000000000000000000000000000000000000000"')
TOKEN_REGISTRY_ADDRESS=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.TokenRegistry // "0x0000000000000000000000000000000000000000"')
LENDING_MANAGER_ADDRESS=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.LendingManager // "0x0000000000000000000000000000000000000000"')
ORACLE_ADDRESS=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.Oracle // "0x0000000000000000000000000000000000000000"')

  print_step "Step 4.1: Configuring BalanceManager → LendingManager connection..."
    
    # Helper function to retry RPC calls with delay
    retry_rpc_call() {
        local max_attempts=3
        local delay=2
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            echo "  🔄 Attempt $attempt of $max_attempts..."
            if "$@"; then
                return 0
            fi
            
            if [[ $attempt -lt $max_attempts ]]; then
                echo "  ⏳ Waiting ${delay}s before retry..."
                sleep $delay
                delay=$((delay * 2))
            fi
            attempt=$((attempt + 1))
        done
        
        echo "   Max retries exceeded"
        return 1
    }
    
    # Set LendingManager in BalanceManager if not already set
    echo "  📊 Checking BalanceManager → LendingManager connection..."
    sleep 2  # Rate limiting delay
    CURRENT_LENDING_MANAGER=$(cast call $BALANCE_MANAGER_ADDRESS "lendingManager()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    if [[ "$CURRENT_LENDING_MANAGER" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "  🔗 Setting LendingManager in BalanceManager..."
        sleep 2  # Rate limiting delay
        if retry_rpc_call cast send $BALANCE_MANAGER_ADDRESS "setLendingManager(address)" $LENDING_MANAGER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1; then
            print_success "BalanceManager → LendingManager connection established"
        else
            print_error "Failed to set LendingManager in BalanceManager after retries"
        fi
    else
        print_success "BalanceManager → LendingManager already configured"
    fi
    
    # Set BalanceManager in LendingManager if not already set (CRITICAL for supplyForUser access)
    sleep 2  # Rate limiting delay
    echo "  📊 Checking LendingManager → BalanceManager connection..."
    CURRENT_BALANCE_MANAGER=$(cast call $LENDING_MANAGER_ADDRESS "balanceManager()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    if [[ "$CURRENT_BALANCE_MANAGER" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "  🔗 Setting BalanceManager in LendingManager..."
        sleep 2  # Rate limiting delay
        if retry_rpc_call cast send $LENDING_MANAGER_ADDRESS "setBalanceManager(address)" $BALANCE_MANAGER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1; then
            print_success "LendingManager → BalanceManager connection established"
            
            # Verify the connection was set correctly
            sleep 3
            VERIFIED_BALANCE_MANAGER=$(cast call $LENDING_MANAGER_ADDRESS "balanceManager()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
            if [[ "$(normalize_address "$VERIFIED_BALANCE_MANAGER")" == "$(normalize_address "$BALANCE_MANAGER_ADDRESS")" ]]; then
                print_success "BalanceManager address verified in LendingManager: $VERIFIED_BALANCE_MANAGER"
            else
                print_error "BalanceManager address verification failed: $VERIFIED_BALANCE_MANAGER (expected: $BALANCE_MANAGER_ADDRESS)"
            fi
        else
            print_error "Failed to set BalanceManager in LendingManager after retries"
        fi
    else
        print_success "LendingManager → BalanceManager already configured: $CURRENT_BALANCE_MANAGER"
    fi
    
    # Set LendingManager in ScaleXRouter if not already set (CRITICAL for borrowing functionality)
    sleep 2  # Rate limiting delay
    SCALEX_ROUTER_ADDRESS=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.ScaleXRouter // "0x0000000000000000000000000000000000000000"')
    if [[ "$SCALEX_ROUTER_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  🔗 Configuring ScaleXRouter → LendingManager connection..."
        sleep 2  # Rate limiting delay
        CURRENT_ROUTER_LENDING=$(cast call $SCALEX_ROUTER_ADDRESS "lendingManager()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
        if [[ "$CURRENT_ROUTER_LENDING" == "0x0000000000000000000000000000000000000000" ]]; then
            echo "  🔗 Setting LendingManager in ScaleXRouter..."
            sleep 2  # Rate limiting delay
            if retry_rpc_call cast send $SCALEX_ROUTER_ADDRESS "setLendingManager(address)" $LENDING_MANAGER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1; then
                print_success "ScaleXRouter → LendingManager connection established"
                
                # Verify the connection was set correctly
                sleep 3
                VERIFIED_ROUTER_LENDING=$(cast call $SCALEX_ROUTER_ADDRESS "lendingManager()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
                if [[ "$(normalize_address "$VERIFIED_ROUTER_LENDING")" == "$(normalize_address "$LENDING_MANAGER_ADDRESS")" ]]; then
                    print_success "LendingManager address verified in ScaleXRouter: $VERIFIED_ROUTER_LENDING"
                else
                    print_error "ScaleXRouter LendingManager verification failed: $VERIFIED_ROUTER_LENDING (expected: $LENDING_MANAGER_ADDRESS)"
                fi
            else
                print_error "Failed to set LendingManager in ScaleXRouter after retries"
            fi
        else
            print_success "ScaleXRouter → LendingManager already configured: $CURRENT_ROUTER_LENDING"
        fi
    else
        print_warning "ScaleXRouter address not found - borrowing functionality may be limited"
    fi
    
        # Step 4.2: Set TokenRegistry in BalanceManager for local deposits (CRITICAL for depositLocal)
    print_step "Step 4.2: Configuring BalanceManager TokenRegistry link..."
    if [[ "$BALANCE_MANAGER_ADDRESS" != "0x0000000000000000000000000000000000000000" && "$TOKEN_REGISTRY_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        # Verify current TokenRegistry setting
        CURRENT_TOKEN_REGISTRY=$(cast call $BALANCE_MANAGER_ADDRESS "getTokenRegistry()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | tr -d '\n' || echo "0x0000000000000000000000000000000000000000")

        # Only set if not already configured correctly
        if [[ "$(normalize_address "$CURRENT_TOKEN_REGISTRY")" != "$(normalize_address "$TOKEN_REGISTRY_ADDRESS")" ]]; then
            echo "  📋 Setting TokenRegistry in BalanceManager..."
            if retry_rpc_call cast send $BALANCE_MANAGER_ADDRESS "setTokenRegistry(address)" $TOKEN_REGISTRY_ADDRESS \
                --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1 > /dev/null 2>&1; then
                # Verify the TokenRegistry was actually set
                sleep 2  # Wait for transaction confirmation
                VERIFIED_TOKEN_REGISTRY=$(cast call $BALANCE_MANAGER_ADDRESS "getTokenRegistry()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | tr -d '\n' || echo "0x0000000000000000000000000000000000000000")
                if [[ "$(normalize_address "$VERIFIED_TOKEN_REGISTRY")" == "$(normalize_address "$TOKEN_REGISTRY_ADDRESS")" ]]; then
                    print_success "BalanceManager TokenRegistry link configured - local deposits now enabled"
                else
                    print_error "TokenRegistry verification failed: got $VERIFIED_TOKEN_REGISTRY (expected: $TOKEN_REGISTRY_ADDRESS)"
                    print_error "depositLocal will NOT work without TokenRegistry being set!"
                    exit 1
                fi
            else
                print_error "Failed to set TokenRegistry in BalanceManager"
                print_error "depositLocal will NOT work without TokenRegistry being set!"
                exit 1
            fi
        else
            print_success "TokenRegistry already configured in BalanceManager"
        fi
    else
        print_error "Missing BalanceManager ($BALANCE_MANAGER_ADDRESS) or TokenRegistry ($TOKEN_REGISTRY_ADDRESS) addresses"
        print_error "Cannot configure TokenRegistry link - depositLocal will NOT work!"
        exit 1
    fi

    # Configure quote currency lending parameters
    if [[ "$QUOTE_TOKEN_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        # Configure quote currency asset parameters (dynamic based on QUOTE_* env vars)
        echo "  🔧 Configuring $QUOTE_SYMBOL asset parameters..."
        echo "     CF: $(echo "scale=2; $QUOTE_COLLATERAL_FACTOR / 100" | bc)%, LT: $(echo "scale=2; $QUOTE_LIQUIDATION_THRESHOLD / 100" | bc)%, LB: $(echo "scale=2; $QUOTE_LIQUIDATION_BONUS / 100" | bc)%, RF: $(echo "scale=2; $QUOTE_RESERVE_FACTOR / 100" | bc)%"
        if cast send $LENDING_MANAGER_ADDRESS "configureAsset(address,uint256,uint256,uint256,uint256)" \
            $QUOTE_TOKEN_ADDRESS $QUOTE_COLLATERAL_FACTOR $QUOTE_LIQUIDATION_THRESHOLD $QUOTE_LIQUIDATION_BONUS $QUOTE_RESERVE_FACTOR \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "$QUOTE_SYMBOL asset parameters configured"
            sleep 2  # Wait for nonce to update
        else
            print_error "Failed to configure $QUOTE_SYMBOL asset parameters"
            exit 1
        fi

        # Set quote currency interest rate parameters (dynamic based on QUOTE_* env vars)
        echo "  🔧 Setting $QUOTE_SYMBOL interest rate parameters..."
        echo "     Base: $(echo "scale=2; $QUOTE_BASE_RATE / 100" | bc)%, Optimal: $(echo "scale=2; $QUOTE_OPTIMAL_UTIL / 100" | bc)%, Slope1: $(echo "scale=2; $QUOTE_SLOPE1 / 100" | bc)%, Slope2: $(echo "scale=2; $QUOTE_SLOPE2 / 100" | bc)%"
        if cast send $LENDING_MANAGER_ADDRESS "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
            $QUOTE_TOKEN_ADDRESS $QUOTE_BASE_RATE $QUOTE_OPTIMAL_UTIL $QUOTE_SLOPE1 $QUOTE_SLOPE2 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "$QUOTE_SYMBOL interest rates configured"
            sleep 2  # Wait for nonce to update
        else
            print_error "Failed to set $QUOTE_SYMBOL interest rate parameters"
            exit 1
        fi
    fi

    # Configure WETH lending parameters
    if [[ "$WETH_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        # Configure WETH asset parameters (80% CF, 85% LT, 10% liquidation bonus, 12% reserve factor) - always set
        echo "  🔧 Configuring WETH asset parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "configureAsset(address,uint256,uint256,uint256,uint256)" \
            $WETH_ADDRESS 8000 8500 1000 1200 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "WETH asset parameters configured (80% CF, 85% LT, 10% LB, 12% RF)"
            sleep 2  # Wait for nonce to update
        else
            print_error "Failed to configure WETH asset parameters"
            exit 1
        fi

        # Set WETH interest rate parameters (3% base, 80% optimal, 12% slope1, 60% slope2) - always set
        echo "  🔧 Setting WETH interest rate parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
            $WETH_ADDRESS 300 8000 1200 6000 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "WETH interest rates configured (3% base, 80% optimal, 12% slope1, 60% slope2)"
            sleep 2  # Wait for nonce to update
        else
            print_error "Failed to set WETH interest rate parameters"
            exit 1
        fi
    fi

    # Configure WBTC lending parameters
    if [[ "$WBTC_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        # Configure WBTC asset parameters (75% CF, 85% LT, 9% liquidation bonus, 11% reserve factor) - always set
        echo "  🔧 Configuring WBTC asset parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "configureAsset(address,uint256,uint256,uint256,uint256)" \
            $WBTC_ADDRESS 7500 8500 900 1100 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "WBTC asset parameters configured (75% CF, 85% LT, 9% LB, 11% RF)"
            sleep 2  # Wait for nonce to update
        else
            print_error "Failed to configure WBTC asset parameters"
            exit 1
        fi

        # Set WBTC interest rate parameters (2.5% base, 80% optimal, 11% slope1, 55% slope2) - always set
        echo "  🔧 Setting WBTC interest rate parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
            $WBTC_ADDRESS 250 8000 1100 5500 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "WBTC interest rates configured (2.5% base, 80% optimal, 11% slope1, 55% slope2)"
            sleep 2  # Wait for nonce to update
        else
            print_error "Failed to set WBTC interest rate parameters"
            exit 1
        fi
    fi

    # Configure GOLD lending parameters (Commodity - Conservative profile)
    if [[ "$GOLD_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  🔧 Configuring GOLD asset parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "configureAsset(address,uint256,uint256,uint256,uint256)" \
            $GOLD_ADDRESS 6000 7000 1200 1800 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "GOLD asset parameters configured (60% CF, 70% LT, 12% LB, 18% RF)"
            sleep 2
        else
            print_error "Failed to configure GOLD asset parameters"
            exit 1
        fi

        echo "  🔧 Setting GOLD interest rate parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
            $GOLD_ADDRESS 250 7500 900 4000 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "GOLD interest rates configured (2.5% base, 75% optimal, 9% slope1, 40% slope2)"
            sleep 2
        else
            print_error "Failed to set GOLD interest rate parameters"
            exit 1
        fi
    fi

    # Configure SILVER lending parameters (Commodity - Conservative profile)
    if [[ "$SILVER_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  🔧 Configuring SILVER asset parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "configureAsset(address,uint256,uint256,uint256,uint256)" \
            $SILVER_ADDRESS 6000 7000 1200 1800 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "SILVER asset parameters configured (60% CF, 70% LT, 12% LB, 18% RF)"
            sleep 2
        else
            print_error "Failed to configure SILVER asset parameters"
            exit 1
        fi

        echo "  🔧 Setting SILVER interest rate parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
            $SILVER_ADDRESS 250 7500 900 4000 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "SILVER interest rates configured (2.5% base, 75% optimal, 9% slope1, 40% slope2)"
            sleep 2
        else
            print_error "Failed to set SILVER interest rate parameters"
            exit 1
        fi
    fi

    # Configure GOOGLE lending parameters (Stock - Conservative profile)
    if [[ "$GOOGLE_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  🔧 Configuring GOOGLE asset parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "configureAsset(address,uint256,uint256,uint256,uint256)" \
            $GOOGLE_ADDRESS 6500 7500 1000 1500 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "GOOGLE asset parameters configured (65% CF, 75% LT, 10% LB, 15% RF)"
            sleep 2
        else
            print_error "Failed to configure GOOGLE asset parameters"
            exit 1
        fi

        echo "  🔧 Setting GOOGLE interest rate parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
            $GOOGLE_ADDRESS 250 7500 900 3500 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "GOOGLE interest rates configured (2.5% base, 75% optimal, 9% slope1, 35% slope2)"
            sleep 2
        else
            print_error "Failed to set GOOGLE interest rate parameters"
            exit 1
        fi
    fi

    # Configure NVIDIA lending parameters (Stock - Conservative profile)
    if [[ "$NVIDIA_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  🔧 Configuring NVIDIA asset parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "configureAsset(address,uint256,uint256,uint256,uint256)" \
            $NVIDIA_ADDRESS 6500 7500 1000 1500 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "NVIDIA asset parameters configured (65% CF, 75% LT, 10% LB, 15% RF)"
            sleep 2
        else
            print_error "Failed to configure NVIDIA asset parameters"
            exit 1
        fi

        echo "  🔧 Setting NVIDIA interest rate parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
            $NVIDIA_ADDRESS 250 7500 900 3500 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "NVIDIA interest rates configured (2.5% base, 75% optimal, 9% slope1, 35% slope2)"
            sleep 2
        else
            print_error "Failed to set NVIDIA interest rate parameters"
            exit 1
        fi
    fi

    # Configure MNT lending parameters (Utility - Conservative profile, treated as commodity)
    if [[ "$MNT_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  🔧 Configuring MNT asset parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "configureAsset(address,uint256,uint256,uint256,uint256)" \
            $MNT_ADDRESS 6000 7000 1200 1800 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "MNT asset parameters configured (60% CF, 70% LT, 12% LB, 18% RF)"
            sleep 2
        else
            print_error "Failed to configure MNT asset parameters"
            exit 1
        fi

        echo "  🔧 Setting MNT interest rate parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
            $MNT_ADDRESS 250 7500 900 4000 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "MNT interest rates configured (2.5% base, 75% optimal, 9% slope1, 40% slope2)"
            sleep 2
        else
            print_error "Failed to set MNT interest rate parameters"
            exit 1
        fi
    fi

    # Configure APPLE lending parameters (Stock - Conservative profile)
    if [[ "$APPLE_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  🔧 Configuring APPLE asset parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "configureAsset(address,uint256,uint256,uint256,uint256)" \
            $APPLE_ADDRESS 6500 7500 1000 1500 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "APPLE asset parameters configured (65% CF, 75% LT, 10% LB, 15% RF)"
            sleep 2
        else
            print_error "Failed to configure APPLE asset parameters"
            exit 1
        fi

        echo "  🔧 Setting APPLE interest rate parameters..."
        if cast send $LENDING_MANAGER_ADDRESS "setInterestRateParams(address,uint256,uint256,uint256,uint256)" \
            $APPLE_ADDRESS 250 7500 900 3500 \
            --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1; then
            print_success "APPLE interest rates configured (2.5% base, 75% optimal, 9% slope1, 35% slope2)"
            sleep 2
        else
            print_error "Failed to set APPLE interest rate parameters"
            exit 1
        fi
    fi

        # Step 4.4: Deploy and configure SyntheticTokenFactory
        print_step "Step 4.4: Deploying SyntheticTokenFactory..."
        
        # Check if SyntheticTokenFactory already exists
        CURRENT_FACTORY=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.SyntheticTokenFactory // "0x0000000000000000000000000000000000000000"')
        FACTORY_ADDRESS=$CURRENT_FACTORY
        if [[ "$CURRENT_FACTORY" == "0x0000000000000000000000000000000000000000" ]]; then
            # Deploy SyntheticTokenFactory
            if [[ -n "$VERIFY_FLAGS" ]]; then
                # Use eval to properly split verification flags (safer approach with controlled input)
                FACTORY_ADDRESS=$(eval "forge create src/core/SyntheticTokenFactory.sol:SyntheticTokenFactory \
                    --rpc-url \"\${SCALEX_CORE_RPC}\" \
                    --private-key \$PRIVATE_KEY \
                    $VERIFY_FLAGS" \
                    | grep "Deployed to:" | awk '{print $3}')
            else
                FACTORY_ADDRESS=$(forge create src/core/SyntheticTokenFactory.sol:SyntheticTokenFactory \
                    --rpc-url "${SCALEX_CORE_RPC}" \
                    --private-key $PRIVATE_KEY \
                    $SLOW_FLAG \
                    | grep "Deployed to:" | awk '{print $3}')
            fi
            
            if [[ -n "$FACTORY_ADDRESS" ]]; then
                # Initialize SyntheticTokenFactory
                cast send $FACTORY_ADDRESS "initialize(address,address,address)" \
                    $(cast wallet address --private-key $PRIVATE_KEY) $TOKEN_REGISTRY_ADDRESS $BALANCE_MANAGER_ADDRESS \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1
                
                # Update deployment file with factory address
                jq --arg factory "$FACTORY_ADDRESS" '.SyntheticTokenFactory = $factory' ./deployments/${CORE_CHAIN_ID}.json > ./deployments/${CORE_CHAIN_ID}.json.tmp && \
                mv ./deployments/${CORE_CHAIN_ID}.json.tmp ./deployments/${CORE_CHAIN_ID}.json
                
                print_success "SyntheticTokenFactory deployed and initialized at $FACTORY_ADDRESS"
                
                # Validate that underlying token addresses exist
                if [[ "$USDC_ADDRESS" == "0x0000000000000000000000000000000000000000" ]]; then
                    print_error "USDC address is zero - cannot create synthetic tokens"
                    exit 1
                fi
                
                # Step 4.5: Create synthetic tokens
                print_step "Step 4.5: Creating synthetic tokens..."
                
                # Create synthetic tokens using the factory with retry logic
                SYNTHETIC_QUOTE_KEY=$(get_synthetic_quote_key)
                echo "  🏭 Creating $SYNTHETIC_QUOTE_KEY ($SYNTHETIC_QUOTE_KEY)..."
                for i in {1..3}; do
                    # Add delay to prevent rate limiting
                    if [[ $i -gt 1 ]]; then
                        echo "    ⏳ Waiting 10 seconds to prevent rate limiting..."
                        sleep 10
                    fi

                    # Get current nonce to avoid conflicts
                    DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
                    CURRENT_NONCE=$(cast nonce --rpc-url "${SCALEX_CORE_RPC}" $DEPLOYER_ADDRESS)
                    echo "    Using nonce: $CURRENT_NONCE (for $DEPLOYER_ADDRESS)"

                    # Calculate dynamic gas price to avoid "replacement transaction underpriced" (in wei)
                    BASE_GAS_PRICE=1000100000  # 0.0010001 gwei in wei
                    GAS_PRICE=$((BASE_GAS_PRICE + i * 100000000))

                    SYNTHETIC_QUOTE_TX=$(cast send $FACTORY_ADDRESS "createSyntheticToken(uint32,address,uint32,string,string,uint8,uint8)" \
                        $CORE_CHAIN_ID $QUOTE_TOKEN_ADDRESS $CORE_CHAIN_ID "$SYNTHETIC_QUOTE_KEY" "$SYNTHETIC_QUOTE_KEY" $QUOTE_DECIMALS $QUOTE_DECIMALS \
                        --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY \
                    $SLOW_FLAG \
                        --gas-price $GAS_PRICE \
                        --nonce $CURRENT_NONCE \
                        --confirmations 1 2>/dev/null)
                    if [[ $? -eq 0 ]]; then
                        echo "     Transaction submitted successfully, waiting for confirmation..."
                        sleep 3  # Wait for transaction to be processed
                        # Query the factory to get the synthetic token address (reliable method)
                        SYNTHETIC_QUOTE_ADDRESS_RAW=$(cast call $FACTORY_ADDRESS "getSyntheticToken(uint32,address)" $CORE_CHAIN_ID $QUOTE_TOKEN_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null)
                        SYNTHETIC_QUOTE_ADDRESS=$(convert_synthetic_address "$SYNTHETIC_QUOTE_ADDRESS_RAW")
                        if [[ -n "$SYNTHETIC_QUOTE_ADDRESS" && "$SYNTHETIC_QUOTE_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
                            break
                        fi
                    else
                        echo "     Transaction failed, waiting for next retry..."
                        sleep 8  # Longer wait between retries
                    fi
                    echo "    🔁 Retry $i/3 for $SYNTHETIC_QUOTE_KEY..."
                done
                
                echo "  🏭 Creating sxWETH (sxWETH)..."
                # Add delay between token creations to prevent rate limiting
                echo "    ⏳ Waiting 5 seconds before creating sxWETH..."
                sleep 5
                for i in {1..3}; do
                    # Add delay to prevent rate limiting
                    if [[ $i -gt 1 ]]; then
                        echo "    ⏳ Waiting 10 seconds to prevent rate limiting..."
                        sleep 10
                    fi
                    
                    # Get current nonce to avoid conflicts
                    DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
                    CURRENT_NONCE=$(cast nonce --rpc-url "${SCALEX_CORE_RPC}" $DEPLOYER_ADDRESS)
                    echo "    Using nonce: $CURRENT_NONCE (for $DEPLOYER_ADDRESS)"
                    
                    # Calculate dynamic gas price to avoid "replacement transaction underpriced" (in wei)
                    BASE_GAS_PRICE=1000200000  # 0.0010002 gwei in wei
                    GAS_PRICE=$((BASE_GAS_PRICE + i * 100000000))
                    
                    sxWETH_TX=$(cast send $FACTORY_ADDRESS "createSyntheticToken(uint32,address,uint32,string,string,uint8,uint8)" \
                        $CORE_CHAIN_ID $WETH_ADDRESS $CORE_CHAIN_ID "sxWETH" "sxWETH" 18 18 \
                        --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY \
                    $SLOW_FLAG \
                        --gas-price $GAS_PRICE \
                        --nonce $CURRENT_NONCE \
                        --confirmations 1 2>/dev/null)
                    if [[ $? -eq 0 ]]; then
                        echo "     Transaction submitted successfully, waiting for confirmation..."
                        sleep 3  # Wait for transaction to be processed
                        # Query the factory to get the synthetic token address (reliable method)
                        sxWETH_ADDRESS_RAW=$(cast call $FACTORY_ADDRESS "getSyntheticToken(uint32,address)" $CORE_CHAIN_ID $WETH_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null)
                        sxWETH_ADDRESS=$(convert_synthetic_address "$sxWETH_ADDRESS_RAW")
                        if [[ -n "$sxWETH_ADDRESS" && "$sxWETH_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
                            break
                        fi
                    else
                        echo "     Transaction failed, waiting for next retry..."
                        sleep 8  # Longer wait between retries
                    fi
                    echo "    🔁 Retry $i/3 for sxWETH..."
                done
                
                echo "  🏭 Creating sxWBTC (sxWBTC)..."
                # Add delay between token creations to prevent rate limiting
                echo "    ⏳ Waiting 5 seconds before creating sxWBTC..."
                sleep 5
                for i in {1..3}; do
                    # Add delay to prevent rate limiting
                    if [[ $i -gt 1 ]]; then
                        echo "    ⏳ Waiting 10 seconds to prevent rate limiting..."
                        sleep 10
                    fi
                    
                    # Get current nonce to avoid conflicts
                    DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
                    CURRENT_NONCE=$(cast nonce --rpc-url "${SCALEX_CORE_RPC}" $DEPLOYER_ADDRESS)
                    echo "    Using nonce: $CURRENT_NONCE (for $DEPLOYER_ADDRESS)"
                    
                    # Calculate dynamic gas price to avoid "replacement transaction underpriced" (in wei)
                    BASE_GAS_PRICE=1000300000  # 0.0010003 gwei in wei
                    GAS_PRICE=$((BASE_GAS_PRICE + i * 100000000))
                    
                    sxWBTC_TX=$(cast send $FACTORY_ADDRESS "createSyntheticToken(uint32,address,uint32,string,string,uint8,uint8)" \
                        $CORE_CHAIN_ID $WBTC_ADDRESS $CORE_CHAIN_ID "sxWBTC" "sxWBTC" 8 8 \
                        --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY \
                    $SLOW_FLAG \
                        --gas-price $GAS_PRICE \
                        --nonce $CURRENT_NONCE \
                        --confirmations 1 2>/dev/null)
                    if [[ $? -eq 0 ]]; then
                        echo "     Transaction submitted successfully, waiting for confirmation..."
                        sleep 3  # Wait for transaction to be processed
                        # Query the factory to get the synthetic token address (reliable method)
                        sxWBTC_ADDRESS_RAW=$(cast call $FACTORY_ADDRESS "getSyntheticToken(uint32,address)" $CORE_CHAIN_ID $WBTC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null)
                        sxWBTC_ADDRESS=$(convert_synthetic_address "$sxWBTC_ADDRESS_RAW")
                        if [[ -n "$sxWBTC_ADDRESS" && "$sxWBTC_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
                            break
                        fi
                    else
                        echo "     Transaction failed, waiting for next retry..."
                        sleep 8  # Longer wait between retries
                    fi
                    echo "    🔁 Retry $i/3 for sxWBTC..."
                done
                
                # Update deployment file with synthetic token addresses (only if valid addresses)
                echo "  📝 Updating deployment file with synthetic token addresses..."
                if [[ -n "$SYNTHETIC_QUOTE_ADDRESS" && "$SYNTHETIC_QUOTE_ADDRESS" != "0x0000000000000000000000000000000000000000" && "$SYNTHETIC_QUOTE_ADDRESS" != "0x" ]]; then
                    jq --arg sxquote "$SYNTHETIC_QUOTE_ADDRESS" ".$SYNTHETIC_QUOTE_KEY = \$sxquote" ./deployments/${CORE_CHAIN_ID}.json > ./deployments/${CORE_CHAIN_ID}.json.tmp && \
                    mv ./deployments/${CORE_CHAIN_ID}.json.tmp ./deployments/${CORE_CHAIN_ID}.json
                    echo "  $SYNTHETIC_QUOTE_KEY recorded: $SYNTHETIC_QUOTE_ADDRESS"
                else
                    echo "   $SYNTHETIC_QUOTE_KEY not recorded - invalid address"
                fi
                jq --arg sxweth "$sxWETH_ADDRESS" '.sxWETH = $sxweth' ./deployments/${CORE_CHAIN_ID}.json > ./deployments/${CORE_CHAIN_ID}.json.tmp && \
                mv ./deployments/${CORE_CHAIN_ID}.json.tmp ./deployments/${CORE_CHAIN_ID}.json
                jq --arg sxwbtc "$sxWBTC_ADDRESS" '.sxWBTC = $sxwbtc' ./deployments/${CORE_CHAIN_ID}.json > ./deployments/${CORE_CHAIN_ID}.json.tmp && \
                mv ./deployments/${CORE_CHAIN_ID}.json.tmp ./deployments/${CORE_CHAIN_ID}.json

                print_success "Synthetic tokens created:"
                echo "    🏭 $SYNTHETIC_QUOTE_KEY: $SYNTHETIC_QUOTE_ADDRESS"
                echo "    🏭 sxWETH: $sxWETH_ADDRESS"
                echo "    🏭 sxWBTC: $sxWBTC_ADDRESS"
                
                # Step 4.6: Register synthetic tokens in TokenRegistry
                print_step "Step 4.6: Registering synthetic tokens in TokenRegistry..."

                echo "  📋 Updating $SYNTHETIC_QUOTE_KEY mapping in TokenRegistry..."
                cast send $TOKEN_REGISTRY_ADDRESS "updateTokenMapping(uint32,address,uint32,address,uint8)" \
                    $CORE_CHAIN_ID $QUOTE_TOKEN_ADDRESS $CORE_CHAIN_ID $SYNTHETIC_QUOTE_ADDRESS $QUOTE_DECIMALS \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1
                print_success "$SYNTHETIC_QUOTE_KEY mapping updated in TokenRegistry"
                
                echo "  📋 Updating sxWETH mapping in TokenRegistry..."
                cast send $TOKEN_REGISTRY_ADDRESS "updateTokenMapping(uint32,address,uint32,address,uint8)" \
                    $CORE_CHAIN_ID $WETH_ADDRESS $CORE_CHAIN_ID $sxWETH_ADDRESS 18 \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1
                print_success "sxWETH mapping updated in TokenRegistry"
                
                echo "  📋 Updating sxWBTC mapping in TokenRegistry..."
                cast send $TOKEN_REGISTRY_ADDRESS "updateTokenMapping(uint32,address,uint32,address,uint8)" \
                    $CORE_CHAIN_ID $WBTC_ADDRESS $CORE_CHAIN_ID $sxWBTC_ADDRESS 8 \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1
                print_success "sxWBTC mapping updated in TokenRegistry"
                
            else
                print_warning "SyntheticTokenFactory deployment failed"
            fi
        else
            print_success "SyntheticTokenFactory already deployed at $CURRENT_FACTORY"
            
            # Step 4.5: Check if synthetic tokens already exist and register them
            print_step "Step 4.5: Checking existing synthetic tokens..."
            
            # Check for existing synthetic tokens (check if field exists AND is not zero address)
            SYNTHETIC_QUOTE_KEY=$(get_synthetic_quote_key)
            CURRENT_SYNTHETIC_QUOTE=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r "if has(\"$SYNTHETIC_QUOTE_KEY\") then .$SYNTHETIC_QUOTE_KEY else \"SYNTHETIC_NOT_FOUND\" end")
            CURRENT_GSWETH=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r 'if has("sxWETH") then .sxWETH else "0x0000000000000000000000000000000000000000" end')
            CURRENT_GSWBTC=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r 'if has("sxWBTC") then .sxWBTC else "0x0000000000000000000000000000000000000000" end')

            # Validate that underlying token addresses exist
            if [[ "$QUOTE_TOKEN_ADDRESS" == "0x0000000000000000000000000000000000000000" ]]; then
                print_error "$QUOTE_SYMBOL address is zero - cannot create/update synthetic tokens"
                exit 1
            fi

            # Check if CURRENT_SYNTHETIC_QUOTE is a valid synthetic token address
            # Use a more reliable check that also verifies string length
            if [[ -n "$CURRENT_SYNTHETIC_QUOTE" && "$CURRENT_SYNTHETIC_QUOTE" != "SYNTHETIC_NOT_FOUND" && "$CURRENT_SYNTHETIC_QUOTE" != "0x0000000000000000000000000000000000000000" && ${#CURRENT_SYNTHETIC_QUOTE} -eq 42 ]]; then
                echo "  $SYNTHETIC_QUOTE_KEY found: $CURRENT_SYNTHETIC_QUOTE"
            else
                print_warning "$SYNTHETIC_QUOTE_KEY not found, creating synthetic token..."
                # Add delay to prevent rate limiting
                echo "    ⏳ Waiting 3 seconds before creating $SYNTHETIC_QUOTE_KEY..."
                sleep 3
                # Get current nonce and use dynamic gas pricing
                DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
                CURRENT_NONCE=$(cast nonce --rpc-url "${SCALEX_CORE_RPC}" $DEPLOYER_ADDRESS)
                BASE_GAS_PRICE=0.0010001
                GAS_PRICE=$(echo "$BASE_GAS_PRICE + 0.0000001" | bc -l)

                SYNTHETIC_QUOTE_TX=$(cast send $CURRENT_FACTORY "createSyntheticToken(uint32,address,uint32,string,string,uint8,uint8)" \
                    $CORE_CHAIN_ID $QUOTE_TOKEN_ADDRESS $CORE_CHAIN_ID "$SYNTHETIC_QUOTE_KEY" "$SYNTHETIC_QUOTE_KEY" $QUOTE_DECIMALS $QUOTE_DECIMALS \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY \
                    $SLOW_FLAG \
                    --gas-price $GAS_PRICE \
                    --nonce $CURRENT_NONCE \
                    --confirmations 1 2>/dev/null)
                if [[ $? -ne 0 ]]; then
                    echo "  Failed to create $SYNTHETIC_QUOTE_KEY token"
                fi
                # Query the factory to get the synthetic token address (reliable method)
                SYNTHETIC_QUOTE_ADDRESS_RAW=$(cast call $CURRENT_FACTORY "getSyntheticToken(uint32,address)" $CORE_CHAIN_ID $QUOTE_TOKEN_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null)
                SYNTHETIC_QUOTE_ADDRESS=$(convert_synthetic_address "$SYNTHETIC_QUOTE_ADDRESS_RAW")
                # Validate the address before saving
                if [[ -n "$SYNTHETIC_QUOTE_ADDRESS" && "$SYNTHETIC_QUOTE_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
                    jq --arg sxquote "$SYNTHETIC_QUOTE_ADDRESS" ".$SYNTHETIC_QUOTE_KEY = \$sxquote" ./deployments/${CORE_CHAIN_ID}.json > ./deployments/${CORE_CHAIN_ID}.json.tmp && \
                    mv ./deployments/${CORE_CHAIN_ID}.json.tmp ./deployments/${CORE_CHAIN_ID}.json
                    echo "  $SYNTHETIC_QUOTE_KEY created: $SYNTHETIC_QUOTE_ADDRESS"
                else
                    echo "  Failed to create $SYNTHETIC_QUOTE_KEY token - invalid address returned"
                fi
            fi
            
            if [[ "$CURRENT_GSWETH" != "0x0000000000000000000000000000000000000000" ]]; then
                echo "  sxWETH found: $CURRENT_GSWETH"
            else
                print_warning "sxWETH not found, creating synthetic token..."
                # Add delay to prevent rate limiting
                echo "    ⏳ Waiting 3 seconds before creating sxWETH..."
                sleep 3
                # Get current nonce and use dynamic gas pricing
                DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
                CURRENT_NONCE=$(cast nonce --rpc-url "${SCALEX_CORE_RPC}" $DEPLOYER_ADDRESS)
                BASE_GAS_PRICE=0.0010002
                GAS_PRICE=$(echo "$BASE_GAS_PRICE + 0.0000001" | bc -l)
                
                sxWETH_TX=$(cast send $CURRENT_FACTORY "createSyntheticToken(uint32,address,uint32,string,string,uint8,uint8)" \
                    $CORE_CHAIN_ID $WETH_ADDRESS $CORE_CHAIN_ID "sxWETH" "sxWETH" 18 18 \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY \
                    $SLOW_FLAG \
                    --gas-price $GAS_PRICE \
                    --nonce $CURRENT_NONCE \
                    --confirmations 1 2>/dev/null)
                # Query the factory to get the synthetic token address (reliable method)
                sxWETH_ADDRESS_RAW=$(cast call $CURRENT_FACTORY "getSyntheticToken(uint32,address)" $CORE_CHAIN_ID $WETH_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
                sxWETH_ADDRESS=$(convert_synthetic_address "$sxWETH_ADDRESS_RAW")
                jq --arg sxweth "$sxWETH_ADDRESS" '.sxWETH = $gsweth' ./deployments/${CORE_CHAIN_ID}.json > ./deployments/${CORE_CHAIN_ID}.json.tmp && \
                mv ./deployments/${CORE_CHAIN_ID}.json.tmp ./deployments/${CORE_CHAIN_ID}.json
                echo "  sxWETH created: $sxWETH_ADDRESS"
            fi
            
            if [[ "$CURRENT_GSWBTC" != "0x0000000000000000000000000000000000000000" ]]; then
                echo "  sxWBTC found: $CURRENT_GSWBTC"
            else
                print_warning "sxWBTC not found, creating synthetic token..."
                # Add delay to prevent rate limiting
                echo "    ⏳ Waiting 3 seconds before creating sxWBTC..."
                sleep 3
                # Get current nonce and use dynamic gas pricing
                DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
                CURRENT_NONCE=$(cast nonce --rpc-url "${SCALEX_CORE_RPC}" $DEPLOYER_ADDRESS)
                BASE_GAS_PRICE=0.0010003
                GAS_PRICE=$(echo "$BASE_GAS_PRICE + 0.0000001" | bc -l)
                
                sxWBTC_TX=$(cast send $CURRENT_FACTORY "createSyntheticToken(uint32,address,uint32,string,string,uint8,uint8)" \
                    $CORE_CHAIN_ID $WBTC_ADDRESS $CORE_CHAIN_ID "sxWBTC" "sxWBTC" 8 8 \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY \
                    $SLOW_FLAG \
                    --gas-price $GAS_PRICE \
                    --nonce $CURRENT_NONCE \
                    --confirmations 1 2>/dev/null)
                # Query the factory to get the synthetic token address (reliable method)
                sxWBTC_ADDRESS_RAW=$(cast call $CURRENT_FACTORY "getSyntheticToken(uint32,address)" $CORE_CHAIN_ID $WBTC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
                sxWBTC_ADDRESS=$(convert_synthetic_address "$sxWBTC_ADDRESS_RAW")
                jq --arg sxwbtc "$sxWBTC_ADDRESS" '.sxWBTC = $gswbtc' ./deployments/${CORE_CHAIN_ID}.json > ./deployments/${CORE_CHAIN_ID}.json.tmp && \
                mv ./deployments/${CORE_CHAIN_ID}.json.tmp ./deployments/${CORE_CHAIN_ID}.json
                echo "  sxWBTC created: $sxWBTC_ADDRESS"
            fi
            
            # Register synthetic tokens in TokenRegistry
            print_step "Step 4.6: Registering synthetic tokens in TokenRegistry..."

            if [[ "$CURRENT_SYNTHETIC_QUOTE" != "0x0000000000000000000000000000000000000000" && "$CURRENT_SYNTHETIC_QUOTE" != "0x" && ${#CURRENT_SYNTHETIC_QUOTE} -gt 10 ]]; then
                echo "  📋 Registering $SYNTHETIC_QUOTE_KEY in TokenRegistry..."
                cast send $TOKEN_REGISTRY_ADDRESS "registerTokenMapping(uint32,address,uint32,address,string,uint8,uint8)" \
                    $CORE_CHAIN_ID $QUOTE_TOKEN_ADDRESS $CORE_CHAIN_ID $CURRENT_SYNTHETIC_QUOTE "$SYNTHETIC_QUOTE_KEY" $QUOTE_DECIMALS $QUOTE_DECIMALS \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1
                print_success "$SYNTHETIC_QUOTE_KEY registered in TokenRegistry"
            fi
            
            if [[ "$CURRENT_GSWETH" != "0x0000000000000000000000000000000000000000" ]]; then
                echo "  📋 Registering sxWETH in TokenRegistry..."
                cast send $TOKEN_REGISTRY_ADDRESS "registerTokenMapping(uint32,address,uint32,address,string,uint8,uint8)" \
                    $CORE_CHAIN_ID $WETH_ADDRESS $CORE_CHAIN_ID $CURRENT_GSWETH "sxWETH" 18 18 \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1
                print_success "sxWETH registered in TokenRegistry"
            fi
            
            if [[ "$CURRENT_GSWBTC" != "0x0000000000000000000000000000000000000000" ]]; then
                echo "  📋 Registering sxWBTC in TokenRegistry..."
                cast send $TOKEN_REGISTRY_ADDRESS "registerTokenMapping(uint32,address,uint32,address,string,uint8,uint8)" \
                    $CORE_CHAIN_ID $WBTC_ADDRESS $CORE_CHAIN_ID $CURRENT_GSWBTC "sxWBTC" 8 8 \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1
                print_success "sxWBTC registered in TokenRegistry"
            fi
        fi
        
        print_success "System integration configuration completed!"
        
        # Step 4.7: Create Trading Pools using DeployPhase3 script
        print_step "Step 4.7: Creating Trading Pools..."
        
        echo "  🏊 Using DeployPhase3 script for reliable pool creation..."
        
        # Run DeployPhase3 script to create pools
        echo "  📊 Running Phase 3 deployment (this will show transaction details)..."
        if [[ -n "$VERIFY_FLAGS" ]]; then
            # Use eval to properly split verification flags (safer approach with controlled input)
            if eval "forge script script/deployments/DeployPhase3.s.sol:DeployPhase3 \
                    --rpc-url \"\${SCALEX_CORE_RPC}\" \
                    --broadcast \
                    --private-key \$PRIVATE_KEY \
                    --gas-estimate-multiplier 120 \
                    $SLOW_FLAG \
                    --legacy \
                    $VERIFY_FLAGS"; then
                print_success "Phase 3 pool creation completed successfully"
            else
                print_error "Phase 3 pool creation failed"
                echo "  Check the forge script output above for error details"
                return 1
            fi
        else
            if forge script script/deployments/DeployPhase3.s.sol:DeployPhase3 \
                --rpc-url "${SCALEX_CORE_RPC}" \
                --broadcast \
                --private-key $PRIVATE_KEY \
                --gas-estimate-multiplier 120 \
                $SLOW_FLAG \
                --legacy; then
                print_success "Phase 3 pool creation completed successfully"
            else
                print_error "Phase 3 pool creation failed"
                echo "  Check the forge script output above for error details"
                return 1
            fi
        fi
        
        echo "  📊 Verifying pool addresses in deployment file..."

        # Verify pools were created and addresses are not zero (using dynamic quote currency)
        WETH_POOL_KEY=$(get_pool_key "WETH")
        WBTC_POOL_KEY=$(get_pool_key "WBTC")

        WETH_QUOTE_POOL=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r ".$WETH_POOL_KEY // \"0x0000000000000000000000000000000000000000\"")
        WBTC_QUOTE_POOL=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r ".$WBTC_POOL_KEY // \"0x0000000000000000000000000000000000000000\"")

        if [[ "$WETH_QUOTE_POOL" != "0x0000000000000000000000000000000000000000" ]]; then
            print_success "WETH/$QUOTE_SYMBOL pool created: $WETH_QUOTE_POOL"
        else
            print_error "WETH/$QUOTE_SYMBOL pool address is zero - creation failed"
        fi

        if [[ "$WBTC_QUOTE_POOL" != "0x0000000000000000000000000000000000000000" ]]; then
            print_success "WBTC/$QUOTE_SYMBOL pool created: $WBTC_QUOTE_POOL"
        else
            print_error "WBTC/$QUOTE_SYMBOL pool address is zero - creation failed"
        fi

        if [[ "$WETH_QUOTE_POOL" != "0x0000000000000000000000000000000000000000" && "$WBTC_QUOTE_POOL" != "0x0000000000000000000000000000000000000000" ]]; then
            print_success "All trading pools created successfully!"
        else
            print_error "Some pools failed to create - check the DeployPhase3 script output"
        fi

        # Add delay before Phase 4
        echo "⏳ Waiting 15 seconds before Phase 4 to prevent rate limiting..."
        sleep 15

        # Step 3.5: Phase 4 - AutoBorrowHelper Deployment
        print_step "Step 3.5: Phase 4 - AutoBorrowHelper Deployment..."

        echo "  📊 Deploying AutoBorrowHelper (this will show transaction details)..."
        if [[ -n "$VERIFY_FLAGS" ]]; then
            if eval "forge script script/deployments/DeployPhase4.s.sol:DeployPhase4 \
                --rpc-url \"\${SCALEX_CORE_RPC}\" \
                --broadcast \
                --private-key \$PRIVATE_KEY \
                --gas-estimate-multiplier 120 \
                \$SLOW_FLAG \
                --legacy \
                $VERIFY_FLAGS"; then
                print_success "Phase 4 AutoBorrowHelper deployment completed successfully"
            else
                print_error "Phase 4 AutoBorrowHelper deployment failed"
                echo "  Check the forge script output above for error details"
                return 1
            fi
        else
            if forge script script/deployments/DeployPhase4.s.sol:DeployPhase4 \
                --rpc-url "${SCALEX_CORE_RPC}" \
                --broadcast \
                --private-key $PRIVATE_KEY \
                --gas-estimate-multiplier 120 \
                $SLOW_FLAG \
                --legacy; then
                print_success "Phase 4 AutoBorrowHelper deployment completed successfully"
            else
                print_error "Phase 4 AutoBorrowHelper deployment failed"
                echo "  Check the forge script output above for error details"
                return 1
            fi
        fi

        # Verify AutoBorrowHelper was deployed
        AUTO_BORROW_HELPER=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.AutoBorrowHelper // "0x0000000000000000000000000000000000000000"')

        if [[ "$AUTO_BORROW_HELPER" != "0x0000000000000000000000000000000000000000" ]]; then
            print_success "AutoBorrowHelper deployed: $AUTO_BORROW_HELPER"
        else
            print_error "AutoBorrowHelper address is zero - deployment failed"
        fi

        # Add delay before Phase 5
        echo "⏳ Waiting 15 seconds before Phase 5 to prevent rate limiting..."
        sleep 15

        # Step 3.6: Phase 5 - AI Agent Infrastructure Deployment
        print_step "Step 3.6: Phase 5 - AI Agent Infrastructure Deployment..."

        echo "  🤖 Deploying Agent Infrastructure (Upgradeable ERC-8004)..."

        if [[ -n "$VERIFY_FLAGS" ]]; then
            if eval "forge script script/deployments/DeployPhase5.s.sol:DeployPhase5 \
                --rpc-url \"\${SCALEX_CORE_RPC}\" \
                --broadcast \
                --private-key \$PRIVATE_KEY \
                --gas-estimate-multiplier 120 \
                \$SLOW_FLAG \
                --legacy \
                $VERIFY_FLAGS"; then
                print_success "Phase 5 AI Agent Infrastructure deployment completed successfully"
            else
                print_error "Phase 5 AI Agent Infrastructure deployment failed"
                echo "  Check the forge script output above for error details"
                return 1
            fi
        else
            if forge script script/deployments/DeployPhase5.s.sol:DeployPhase5 \
                --rpc-url "${SCALEX_CORE_RPC}" \
                --broadcast \
                --private-key $PRIVATE_KEY \
                --gas-estimate-multiplier 120 \
                $SLOW_FLAG \
                --legacy; then
                print_success "Phase 5 AI Agent Infrastructure deployment completed successfully"
            else
                print_error "Phase 5 AI Agent Infrastructure deployment failed"
                echo "  Check the forge script output above for error details"
                return 1
            fi
        fi

        # Verify Agent Infrastructure was deployed
        POLICY_FACTORY=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.PolicyFactory // "0x0000000000000000000000000000000000000000"')
        AGENT_ROUTER=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.AgentRouter // "0x0000000000000000000000000000000000000000"')
        IDENTITY_REGISTRY=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.IdentityRegistry // "0x0000000000000000000000000000000000000000"')
        REPUTATION_REGISTRY=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.ReputationRegistry // "0x0000000000000000000000000000000000000000"')
        VALIDATION_REGISTRY=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.ValidationRegistry // "0x0000000000000000000000000000000000000000"')

        if [[ "$POLICY_FACTORY" != "0x0000000000000000000000000000000000000000" ]] && [[ "$AGENT_ROUTER" != "0x0000000000000000000000000000000000000000" ]]; then
            print_success "Agent Infrastructure deployed successfully:"
            echo "  📋 Core Contracts:"
            echo "    - PolicyFactory: $POLICY_FACTORY"
            echo "    - AgentRouter: $AGENT_ROUTER"

            if [[ "$IDENTITY_REGISTRY" != "0x0000000000000000000000000000000000000000" ]]; then
                echo "  🔐 ERC-8004 Registries (Upgradeable):"
                echo "    - IdentityRegistry: $IDENTITY_REGISTRY"
                echo "    - ReputationRegistry: $REPUTATION_REGISTRY"
                echo "    - ValidationRegistry: $VALIDATION_REGISTRY"
            fi
        else
            print_error "Agent Infrastructure deployment failed - core addresses are zero"
        fi

        # Add delay before Oracle Token Configuration
        echo "⏳ Waiting 10 seconds before Oracle Token Configuration..."
        sleep 10

        # Step 3.7: Configure All Oracle Tokens
        print_step "Step 3.7: Configuring All Oracle Tokens..."

        echo "  🔮 Configuring oracle tokens for ALL synthetic assets (crypto + RWA)..."
        if [[ -n "$VERIFY_FLAGS" ]]; then
            if eval "forge script script/deployments/ConfigureAllOracleTokens.s.sol:ConfigureAllOracleTokens \
                --rpc-url \"\${SCALEX_CORE_RPC}\" \
                --broadcast \
                --private-key \$PRIVATE_KEY \
                --gas-estimate-multiplier 120 \
                \$SLOW_FLAG \
                --legacy \
                $VERIFY_FLAGS"; then
                print_success "Oracle token configuration completed successfully"
            else
                print_warning "Oracle token configuration encountered issues (may be partially complete)"
                echo "  Check the forge script output above for details"
            fi
        else
            if forge script script/deployments/ConfigureAllOracleTokens.s.sol:ConfigureAllOracleTokens \
                --rpc-url "${SCALEX_CORE_RPC}" \
                --broadcast \
                --private-key $PRIVATE_KEY \
                --gas-estimate-multiplier 120 \
                $SLOW_FLAG \
                --legacy; then
                print_success "Oracle token configuration completed successfully"
            else
                print_warning "Oracle token configuration encountered issues (may be partially complete)"
                echo "  Check the forge script output above for details"
            fi
        fi

        # Verify oracle tokens are registered
        ORACLE_ADDRESS=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.Oracle // "0x0000000000000000000000000000000000000000"')
        if [[ "$ORACLE_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
            echo "  🔍 Verifying oracle token registration..."

            # Get synthetic token addresses
            SX_QUOTE_KEY="sx${QUOTE_SYMBOL}"
            SX_QUOTE=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r ".$SX_QUOTE_KEY // \"0x0000000000000000000000000000000000000000\"")
            SX_WETH=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.sxWETH // "0x0000000000000000000000000000000000000000"')
            SX_WBTC=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.sxWBTC // "0x0000000000000000000000000000000000000000"')
            SX_GOLD=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.sxGOLD // "0x0000000000000000000000000000000000000000"')
            SX_SILVER=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.sxSILVER // "0x0000000000000000000000000000000000000000"')

            # Verify prices are set (quick spot check on a few tokens)
            if [[ "$SX_WETH" != "0x0000000000000000000000000000000000000000" ]]; then
                WETH_PRICE=$(cast call $ORACLE_ADDRESS "getSpotPrice(address)" $SX_WETH --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
                if [[ "$WETH_PRICE" != "0" ]] && [[ "$WETH_PRICE" != "0x0" ]]; then
                    print_success "  ✅ sxWETH registered in oracle (price set)"
                else
                    print_warning "  ⚠️  sxWETH may not be fully configured in oracle"
                fi
            fi

            if [[ "$SX_GOLD" != "0x0000000000000000000000000000000000000000" ]]; then
                GOLD_PRICE=$(cast call $ORACLE_ADDRESS "getSpotPrice(address)" $SX_GOLD --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
                if [[ "$GOLD_PRICE" != "0" ]] && [[ "$GOLD_PRICE" != "0x0" ]]; then
                    print_success "  ✅ sxGOLD registered in oracle (price set)"
                else
                    print_warning "  ⚠️  sxGOLD may not be fully configured in oracle"
                fi
            fi

            print_success "Oracle token verification complete"
        fi

        # Step 4.8: Verify OrderBook Authorizations and Oracle Configuration
        print_step "Step 4.8: Verifying OrderBook Authorizations and Oracle Configuration..."

        ORACLE_ADDRESS=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.Oracle // "0x0000000000000000000000000000000000000000"')

        # Verify WETH/{QUOTE} OrderBook
        if [[ "$WETH_QUOTE_POOL" != "0x0000000000000000000000000000000000000000" ]]; then
            echo "  🔍 Verifying WETH/$QUOTE_SYMBOL OrderBook..."

            # Check authorization
            if verify_authorization "$BALANCE_MANAGER_ADDRESS" "$WETH_QUOTE_POOL" "WETH/$QUOTE_SYMBOL OrderBook"; then
                true  # Already authorized
            else
                print_warning "WETH/$QUOTE_SYMBOL OrderBook not authorized. Attempting to authorize..."
                if ! authorize_operator "$BALANCE_MANAGER_ADDRESS" "$WETH_QUOTE_POOL" "WETH/$QUOTE_SYMBOL OrderBook"; then
                    print_error "Failed to authorize WETH/$QUOTE_SYMBOL OrderBook"
                fi
            fi

            # Check Oracle configuration
            sleep 2
            WETH_QUOTE_ORACLE=$(cast call $WETH_QUOTE_POOL "oracle()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | tail -1)
            # Convert to address format
            WETH_QUOTE_ORACLE="0x$(echo $WETH_QUOTE_ORACLE | sed 's/^0x//' | tail -c 41)"

            if [[ "${WETH_QUOTE_ORACLE,,}" == "${ORACLE_ADDRESS,,}" ]]; then
                print_success "  ✅ WETH/$QUOTE_SYMBOL OrderBook Oracle configured correctly"
            else
                print_error "  ❌ WETH/$QUOTE_SYMBOL OrderBook Oracle mismatch"
                print_error "     Expected: $ORACLE_ADDRESS"
                print_error "     Got: $WETH_QUOTE_ORACLE"
                print_warning "  Attempting to set Oracle..."
                sleep 2
                if cast send $WETH_QUOTE_POOL "setOracle(address)" $ORACLE_ADDRESS \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1 2>/dev/null; then
                    print_success "  ✅ Oracle set successfully"
                else
                    print_error "  ❌ Failed to set Oracle"
                fi
            fi
        fi

        # Verify WBTC/{QUOTE} OrderBook
        if [[ "$WBTC_QUOTE_POOL" != "0x0000000000000000000000000000000000000000" ]]; then
            echo "  🔍 Verifying WBTC/$QUOTE_SYMBOL OrderBook..."

            # Check authorization
            if verify_authorization "$BALANCE_MANAGER_ADDRESS" "$WBTC_QUOTE_POOL" "WBTC/$QUOTE_SYMBOL OrderBook"; then
                true  # Already authorized
            else
                print_warning "WBTC/$QUOTE_SYMBOL OrderBook not authorized. Attempting to authorize..."
                if ! authorize_operator "$BALANCE_MANAGER_ADDRESS" "$WBTC_QUOTE_POOL" "WBTC/$QUOTE_SYMBOL OrderBook"; then
                    print_error "Failed to authorize WBTC/$QUOTE_SYMBOL OrderBook"
                fi
            fi

            # Check Oracle configuration
            sleep 2
            WBTC_QUOTE_ORACLE=$(cast call $WBTC_QUOTE_POOL "oracle()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | tail -1)
            # Convert to address format
            WBTC_QUOTE_ORACLE="0x$(echo $WBTC_QUOTE_ORACLE | sed 's/^0x//' | tail -c 41)"

            if [[ "${WBTC_QUOTE_ORACLE,,}" == "${ORACLE_ADDRESS,,}" ]]; then
                print_success "  ✅ WBTC/$QUOTE_SYMBOL OrderBook Oracle configured correctly"
            else
                print_error "  ❌ WBTC/$QUOTE_SYMBOL OrderBook Oracle mismatch"
                print_error "     Expected: $ORACLE_ADDRESS"
                print_error "     Got: $WBTC_QUOTE_ORACLE"
                print_warning "  Attempting to set Oracle..."
                sleep 2
                if cast send $WBTC_QUOTE_POOL "setOracle(address)" $ORACLE_ADDRESS \
                    --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1 2>/dev/null; then
                    print_success "  ✅ Oracle set successfully"
                else
                    print_error "  ❌ Failed to set Oracle"
                fi
            fi
        fi

        # Step 4.8.1: Verify PoolKey Storage Integrity
        print_step "Step 4.8.1: Verifying PoolKey storage integrity..."

        # Load expected synthetic token addresses
        QUOTE_TOKEN_KEY=$(get_quote_token_key)
        SYNTHETIC_QUOTE_KEY="sx${QUOTE_SYMBOL}"
        EXPECTED_QUOTE=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r ".$SYNTHETIC_QUOTE_KEY // \"0x0000000000000000000000000000000000000000\"")
        EXPECTED_WETH=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.sxWETH // "0x0000000000000000000000000000000000000000"')
        EXPECTED_WBTC=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.sxWBTC // "0x0000000000000000000000000000000000000000"')

        # Verify WETH pool poolKey
        if [[ "$WETH_QUOTE_POOL" != "0x0000000000000000000000000000000000000000" ]]; then
            echo "  🔍 Verifying WETH/$QUOTE_SYMBOL poolKey storage..."

            WETH_BASE=$(cast call $WETH_QUOTE_POOL "getBaseCurrency()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | tail -1)
            WETH_QUOTE=$(cast call $WETH_QUOTE_POOL "getQuoteCurrency()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | tail -1)

            # Normalize addresses
            WETH_BASE="0x$(echo $WETH_BASE | sed 's/^0x//' | tail -c 41)"
            WETH_QUOTE="0x$(echo $WETH_QUOTE | sed 's/^0x//' | tail -c 41)"

            if [[ "${WETH_BASE,,}" == "${EXPECTED_WETH,,}" ]] && [[ "${WETH_QUOTE,,}" == "${EXPECTED_QUOTE,,}" ]]; then
                print_success "  ✅ WETH/$QUOTE_SYMBOL poolKey correct (base: sxWETH, quote: $SYNTHETIC_QUOTE_KEY)"
            else
                print_error "  ❌ WETH/$QUOTE_SYMBOL poolKey CORRUPTED!"
                print_error "     Expected base: $EXPECTED_WETH"
                print_error "     Got base:      $WETH_BASE"
                print_error "     Expected quote: $EXPECTED_QUOTE"
                print_error "     Got quote:      $WETH_QUOTE"
                print_error ""
                print_error "  🚨 CRITICAL: Storage layout corruption detected!"
                print_error "     This usually happens when struct fields are added/removed in upgrades."
                print_error "     You may need to run a storage fix script."
                return 1
            fi
        fi

        # Verify WBTC pool poolKey
        if [[ "$WBTC_QUOTE_POOL" != "0x0000000000000000000000000000000000000000" ]]; then
            echo "  🔍 Verifying WBTC/$QUOTE_SYMBOL poolKey storage..."

            WBTC_BASE=$(cast call $WBTC_QUOTE_POOL "getBaseCurrency()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | tail -1)
            WBTC_QUOTE=$(cast call $WBTC_QUOTE_POOL "getQuoteCurrency()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | tail -1)

            # Normalize addresses
            WBTC_BASE="0x$(echo $WBTC_BASE | sed 's/^0x//' | tail -c 41)"
            WBTC_QUOTE="0x$(echo $WBTC_QUOTE | sed 's/^0x//' | tail -c 41)"

            if [[ "${WBTC_BASE,,}" == "${EXPECTED_WBTC,,}" ]] && [[ "${WBTC_QUOTE,,}" == "${EXPECTED_QUOTE,,}" ]]; then
                print_success "  ✅ WBTC/$QUOTE_SYMBOL poolKey correct (base: sxWBTC, quote: $SYNTHETIC_QUOTE_KEY)"
            else
                print_error "  ❌ WBTC/$QUOTE_SYMBOL poolKey CORRUPTED!"
                print_error "     Expected base: $EXPECTED_WBTC"
                print_error "     Got base:      $WBTC_BASE"
                print_error "     Expected quote: $EXPECTED_QUOTE"
                print_error "     Got quote:      $WBTC_QUOTE"
                print_error ""
                print_error "  🚨 CRITICAL: Storage layout corruption detected!"
                return 1
            fi
        fi

        print_success "✅ PoolKey storage integrity verified successfully"
        echo ""

        # Verify RWA pool OrderBooks if they exist
        GOLD_USDC_POOL=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.GOLD_USDC_Pool // "0x0000000000000000000000000000000000000000"')
        SILVER_USDC_POOL=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r '.SILVER_USDC_Pool // "0x0000000000000000000000000000000000000000"')

        for pool_name in "GOLD_USDC" "SILVER_USDC" "GOOGLE_USDC" "NVIDIA_USDC" "MNT_USDC" "APPLE_USDC"; do
            POOL_ADDRESS=$(cat ./deployments/${CORE_CHAIN_ID}.json | jq -r ".${pool_name}_Pool // \"0x0000000000000000000000000000000000000000\"")

            if [[ "$POOL_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
                echo "  🔍 Verifying $pool_name OrderBook..."

                # Check authorization
                if verify_authorization "$BALANCE_MANAGER_ADDRESS" "$POOL_ADDRESS" "$pool_name OrderBook"; then
                    true  # Already authorized
                else
                    print_warning "$pool_name OrderBook not authorized. Attempting to authorize..."
                    if ! authorize_operator "$BALANCE_MANAGER_ADDRESS" "$POOL_ADDRESS" "$pool_name OrderBook"; then
                        print_error "Failed to authorize $pool_name OrderBook"
                    fi
                fi

                # Check Oracle configuration
                sleep 2
                POOL_ORACLE=$(cast call $POOL_ADDRESS "oracle()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | tail -1)
                # Convert to address format
                POOL_ORACLE="0x$(echo $POOL_ORACLE | sed 's/^0x//' | tail -c 41)"

                if [[ "${POOL_ORACLE,,}" == "${ORACLE_ADDRESS,,}" ]]; then
                    print_success "  ✅ $pool_name OrderBook Oracle configured correctly"
                else
                    print_warning "  ⚠️  $pool_name OrderBook Oracle mismatch (Expected: $ORACLE_ADDRESS, Got: $POOL_ORACLE)"
                    # Attempt to fix
                    sleep 2
                    if cast send $POOL_ADDRESS "setOracle(address)" $ORACLE_ADDRESS \
                        --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --confirmations 1 2>/dev/null; then
                        print_success "  ✅ Oracle set successfully"
                    fi
                fi
            fi
        done

        print_success "✅ OrderBook authorization and Oracle configuration verification completed"


# Step 5: Comprehensive Verification
print_step "Step 5: Comprehensive Verification..."

# 5.1 Verify Synthetic Tokens
print_step "5.1: Verifying Synthetic Tokens..."
if [[ -f "deployments/${CORE_CHAIN_ID}.json" ]]; then
    SXUSDC=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.sxUSDC // "0x0000000000000000000000000000000000000000"')
    SXWETH=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.sxWETH // "0x0000000000000000000000000000000000000000"')
    SXWBTC=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.sxWBTC // "0x0000000000000000000000000000000000000000"')
    
    if [[ "$GSUSDC" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  sxUSDC: $GSUSDC"
        # Test basic token functionality
        SXUSDC_NAME=$(cast call $GSUSDC "name()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | sed 's/^0x//' | xxd -r -p 2>/dev/null | tr -d '\0\n\r' | sed 's/[^[:print:]]//g' | xargs 2>/dev/null || echo "ERROR")
        if [[ "$GSUSDC_NAME" == "sxUSDC" ]]; then
            echo "    Token name verified"
        else
            echo "    Token name verification failed (got: '$GSUSDC_NAME')"
        fi
    else
        echo "  sxUSDC not found"
    fi
    
    if [[ "$GSWETH" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  sxWETH: $GSWETH"
        # Test basic token functionality
        SXWETH_NAME=$(cast call $GSWETH "name()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | sed 's/^0x//' | xxd -r -p 2>/dev/null | tr -d '\0\n\r' | sed 's/[^[:print:]]//g' | xargs 2>/dev/null || echo "ERROR")
        if [[ "$GSWETH_NAME" == "sxWETH" ]]; then
            echo "    Token name verified"
        else
            echo "    Token name verification failed (got: '$GSWETH_NAME')"
        fi
    else
        echo "  sxWETH not found"
    fi
    
    if [[ "$GSWBTC" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  sxWBTC: $GSWBTC"
        # Test basic token functionality
        SXWBTC_NAME=$(cast call $GSWBTC "name()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | sed 's/^0x//' | xxd -r -p 2>/dev/null | tr -d '\0\n\r' | sed 's/[^[:print:]]//g' | xargs 2>/dev/null || echo "ERROR")
        if [[ "$GSWBTC_NAME" == "sxWBTC" ]]; then
            echo "    Token name verified"
        else
            echo "    Token name verification failed (got: '$GSWBTC_NAME')"
        fi
    else
        echo "  sxWBTC not found"
    fi
fi

# 5.1.1 Verify Contract Linkage (Critical for deposits to work)
print_step "5.1.1: Verifying Contract Linkage..."
if [[ -f "deployments/${CORE_CHAIN_ID}.json" ]]; then
    BALANCE_MANAGER_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.BalanceManager // "0x0000000000000000000000000000000000000000"')
    LENDING_MANAGER_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.LendingManager // "0x0000000000000000000000000000000000000000"')
    
    if [[ "$BALANCE_MANAGER_ADDRESS" != "0x0000000000000000000000000000000000000000" && "$LENDING_MANAGER_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  📋 Checking BalanceManager -> LendingManager linkage..."
        BALANCE_MANAGER_LENDING=$(cast call $BALANCE_MANAGER_ADDRESS "getLendingManager()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
        # Normalize addresses (remove padding and convert to lowercase)
        NORMALIZED_LENDING=$(echo "$BALANCE_MANAGER_LENDING" | sed 's/^0x000000000000000000000000/0x/' | tr '[:upper:]' '[:lower:]')
        NORMALIZED_EXPECTED_LENDING=$(echo "$LENDING_MANAGER_ADDRESS" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$NORMALIZED_LENDING" == "$NORMALIZED_EXPECTED_LENDING" ]]; then
            echo "    BalanceManager correctly linked to LendingManager"
        else
            echo "    BalanceManager linkage failed (got: '$NORMALIZED_LENDING', expected: '$NORMALIZED_EXPECTED_LENDING')"
        fi
        
        echo "  📋 Checking LendingManager -> BalanceManager linkage..."
        LENDING_MANAGER_BALANCE=$(cast call $LENDING_MANAGER_ADDRESS "balanceManager()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
        # Normalize addresses (remove padding and convert to lowercase)
        NORMALIZED_BALANCE=$(echo "$LENDING_MANAGER_BALANCE" | sed 's/^0x000000000000000000000000/0x/' | tr '[:upper:]' '[:lower:]')
        NORMALIZED_EXPECTED_BALANCE=$(echo "$BALANCE_MANAGER_ADDRESS" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$NORMALIZED_BALANCE" == "$NORMALIZED_EXPECTED_BALANCE" ]]; then
            echo "    LendingManager correctly linked to BalanceManager"
        else
            echo "    LendingManager linkage failed (got: '$NORMALIZED_BALANCE', expected: '$NORMALIZED_EXPECTED_BALANCE')"
        fi
        
        # Also check ScaleXRouter -> LendingManager linkage (critical for borrowing)
        SCALEX_ROUTER_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.ScaleXRouter // "0x0000000000000000000000000000000000000000"')
        if [[ "$SCALEX_ROUTER_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
            echo "  📋 Checking ScaleXRouter -> LendingManager linkage..."
            ROUTER_LENDING=$(cast call $SCALEX_ROUTER_ADDRESS "lendingManager()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
            # Normalize addresses (remove padding and convert to lowercase)
            NORMALIZED_ROUTER_LENDING=$(echo "$ROUTER_LENDING" | sed 's/^0x000000000000000000000000/0x/' | tr '[:upper:]' '[:lower:]')
            NORMALIZED_EXPECTED_ROUTER_LENDING=$(echo "$LENDING_MANAGER_ADDRESS" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$NORMALIZED_ROUTER_LENDING" == "$NORMALIZED_EXPECTED_ROUTER_LENDING" ]]; then
                echo "    ScaleXRouter correctly linked to LendingManager"
            else
                echo "    ScaleXRouter linkage failed (got: '$NORMALIZED_ROUTER_LENDING', expected: '$NORMALIZED_EXPECTED_ROUTER_LENDING')"
            fi
        else
            echo "   ScaleXRouter address missing - skipping linkage check"
        fi
        
        # Overall linkage status
        if [[ "$NORMALIZED_LENDING" == "$NORMALIZED_EXPECTED_LENDING" && "$NORMALIZED_BALANCE" == "$NORMALIZED_EXPECTED_BALANCE" && ( "$NORMALIZED_ROUTER_LENDING" == "$NORMALIZED_EXPECTED_ROUTER_LENDING" || "$SCALEX_ROUTER_ADDRESS" == "0x0000000000000000000000000000000000000000" ) ]]; then
            print_success "🔗 Contract linkage verified - deposits and borrowing should work correctly"
        else
            print_error "Contract linkage broken - some functionality may fail"
            echo "    Fix: Run deployment script to reconfigure contract relationships"
        fi
    else
        print_warning " BalanceManager or LendingManager address missing - skipping linkage check"
    fi
fi

# 5.2 Verify Trading Pools
print_step "5.2: Verifying Trading Pools..."
if [[ -f "deployments/${CORE_CHAIN_ID}.json" ]]; then
    WETH_USDC_POOL=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.WETH_USDC_Pool // "0x0000000000000000000000000000000000000000"')
    WBTC_USDC_POOL=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.WBTC_USDC_Pool // "0x0000000000000000000000000000000000000000"')
    
    if [[ "$WETH_USDC_POOL" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  WETH/USDC Pool: $WETH_USDC_POOL"
        # Test basic pool functionality
        if cast call $WETH_USDC_POOL "token0()" --rpc-url "${SCALEX_CORE_RPC}" > /dev/null 2>&1; then
            echo "    Pool is accessible"
        else
            echo "    Pool access failed"
        fi
    else
        echo "  WETH/USDC Pool not found"
    fi
    
    if [[ "$WBTC_USDC_POOL" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  WBTC/USDC Pool: $WBTC_USDC_POOL"
        # Test basic pool functionality
        if cast call $WBTC_USDC_POOL "token0()" --rpc-url "${SCALEX_CORE_RPC}" > /dev/null 2>&1; then
            echo "    Pool is accessible"
        else
            echo "    Pool access failed"
        fi
    else
        echo "  WBTC/USDC Pool not found"
    fi
fi

# 5.3 Test Basic Trading Functionality
print_step "5.3: Testing Basic Trading Functionality..."
if [[ "$GSUSDC" != "0x0000000000000000000000000000000000000000" && "$GSWETH" != "0x0000000000000000000000000000000000000000" ]]; then
    # Test trader balance
    TRADER_BALANCE=$(cast call $GSUSDC "balanceOf(address)" 0x27dD1eBE7D826197FD163C134E79502402Fd7cB7 --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    if [[ "$TRADER_BALANCE" != "0" ]]; then
        echo "  Trader has synthetic token balance: $TRADER_BALANCE"
    else
        echo "   Trader has no synthetic token balance"
    fi
fi

# 5.3.1 Test Local Deposit Functionality
print_step "5.3.1: Testing Local Deposit Functionality..."
if [[ -f "deployments/${CORE_CHAIN_ID}.json" ]]; then
    USDC_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.USDC // "0x0000000000000000000000000000000000000000"')
    BALANCE_MANAGER_ADDRESS=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.BalanceManager // "0x0000000000000000000000000000000000000000"')
    
    if [[ "$BALANCE_MANAGER_ADDRESS" != "0x0000000000000000000000000000000000000000" && "$USDC_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "  🧪 Testing small USDC deposit to BalanceManager..."
        
        # Check if user has USDC balance
        DEPLOYER_USDC_BALANCE=$(cast call $USDC_ADDRESS "balanceOf(address)" 0x27dD1eBE7D826197FD163C134E79502402Fd7cB7 --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
        if [[ "$DEPLOYER_USDC_BALANCE" != "0" ]]; then
            echo "    Deployer USDC balance: $DEPLOYER_USDC_BALANCE"
            
            # Test small deposit (1000 USDC)
            TEST_DEPOSIT_AMOUNT=1000000000
            echo "    Testing deposit of 1000 USDC..."
            
            # Approve BalanceManager
            cast send $USDC_ADDRESS "approve(address,uint256)" $BALANCE_MANAGER_ADDRESS $TEST_DEPOSIT_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1
            if [[ $? -eq 0 ]]; then
                echo "    Approval successful"
                
                # Test actual deposit (read-only call)
                if cast call $BALANCE_MANAGER_ADDRESS "depositLocal(address,uint256,address)" $USDC_ADDRESS $TEST_DEPOSIT_AMOUNT 0x27dD1eBE7D826197FD163C134E79502402Fd7cB7 --rpc-url "${SCALEX_CORE_RPC}" > /dev/null 2>&1; then
                    echo "    DepositLocal call successful - deposits should work!"
                else
                    echo "    DepositLocal call failed - check linkage and configuration"
                fi
            else
                echo "    Approval failed - deposits may not work"
            fi
        else
            echo "     Deployer has no USDC balance - skipping deposit test"
        fi
    else
        echo "     BalanceManager or USDC address missing - skipping deposit test"
    fi
fi

# 5.4 Verification Complete
print_step "5.4: Verification Complete..."
print_success "All verification steps completed"

print_success "Comprehensive verification completed!"

echo ""
print_success " Core Chain Deployment completed successfully!"

# Post-deployment: Verify on Tenderly if configured
if [[ "$VERIFIER" == "tenderly" || "$VERIFIER" == "both" ]]; then
    echo ""
    verify_on_tenderly $CORE_CHAIN_ID
fi

# Validation - Local Deployment Only
print_step "Validating Local Deployment..."
# Simplified local validation
if [[ -f "deployments/${CORE_CHAIN_ID}.json" ]]; then
    print_success "Local deployment validation passed!"
    print_success "Core contracts deployed"
    print_success "Oracle deployed"
    
    # Quick health checks
    BALANCE_MANAGER=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.BalanceManager // "N/A"')
    ORACLE=$(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.Oracle // "N/A"')
    
    if [[ "$BALANCE_MANAGER" != "N/A" ]] && [[ "$ORACLE" != "N/A" ]]; then
        print_success "Contract addresses are valid"
    else
        print_warning " Some contract addresses may be missing"
    fi
else
    print_error "Local deployment validation failed - deployment files missing!"
    exit 1
fi

echo ""
print_success " SCALEX Core Chain CLOB DEX + Lending Protocol deployment completed successfully!"

# Check if deployment files exist
if [[ -f "deployments/${CORE_CHAIN_ID}.json" ]]; then
    print_success "Core Chain deployment files created successfully:"
    echo "  📁 deployments/${CORE_CHAIN_ID}.json - Core chain contracts"
    echo "  📁 deployments/oracle.json - Oracle contract"
    echo "  📁 deployments/unified_lending_${CORE_CHAIN_ID}.json - Lending protocol"
    echo "  📁 deployments/focused_tokens.json - Focused token ecosystem (USDC + 12 tokens)"
    echo "  📁 deployments/focused_ecosystem_summary.json - Token configuration summary"
else
    print_warning " Core Chain deployment files may be missing. Check for errors above."
fi

# Display deployed contracts summary
echo ""
print_step "📋 Core Chain Deployed Contracts (Chain ID: $CORE_CHAIN_ID):"
if [[ -f "deployments/${CORE_CHAIN_ID}.json" ]]; then
    echo "  🏛️  SCALEXRouter: $(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.SCALEXRouter // "N/A"')"
    echo "  💰 BalanceManager: $(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.BalanceManager // "N/A"')"
    echo "  📊 OrderBook: $(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.OrderBook // "N/A"')"
    echo "  📋 TokenRegistry: $(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.TokenRegistry // "N/A"')"
fi
echo "  🔮 Oracle: $(cat deployments/${CORE_CHAIN_ID}.json | jq -r '.Oracle // "N/A"')"
echo "  🏦 LendingManager: $(cat deployments/unified_lending_${CORE_CHAIN_ID}.json | jq -r '.lendingManagerProxy // "N/A"')"
echo "  🏭 SyntheticTokenFactory: $(cat deployments/unified_lending_${CORE_CHAIN_ID}.json | jq -r '.syntheticTokenFactory // "N/A"')"

echo ""
print_step "🚀 Core Chain Features:"
echo "  CLOB Trading with limit/market orders"
echo "  Lending protocol with collateralized borrowing"
echo "  Focused token ecosystem (USDC + 12 selected tokens)"
echo "  Real-time price oracle with TWAP"
echo "  Yield farming and interest accrual"
echo "  Health factor monitoring and liquidations"
echo "  Synthetic token creation for qualified assets"
echo "  Enhanced indexer with full API support"
echo "  🔗 Cross-chain ready (use deploy-sidechain.sh for side chains)"
echo ""
print_step "🪙 Focused Token Ecosystem (USDC + 12 selected tokens):"
echo "  💰 Primary Stablecoin: USDC (95% collateral factor - highest priority)"
echo "  🏛️  Blue-chips: WETH, WBTC, LINK, UNI (70-80% collateral factors)"
echo "  🔗 Layer-2: ARB, OP, MATIC (60-70% collateral factors)"
echo "  💸 Yield Tokens: stETH, wstETH (80-82% collateral factors - premium for yield)"
echo "  🏦 DeFi: AAVE, COMP (65-70% collateral factors)"
echo "  🎮 Gaming: SAND (50% collateral factor - controlled risk)"
echo "  📊 Total: 13 carefully selected tokens with USDC as the foundation"
echo "  🎯 Trading pairs: 9 USDC-centric pools for optimal liquidity"
echo "  🔗 Cross-chain: USDC + 5 major tokens enabled for cross-chain"

echo ""
print_success " Local Development Environment Ready!"

echo ""
echo "🚀 Quick Commands:"
echo "  🧪 Test Lending: forge script script/lending/PopulateLendingData.sol:PopulateLendingData --rpc-url ${SCALEX_CORE_RPC}"
echo "  💰 Fill OrderBook: make fill-orderbook network=scalex_core_devnet"
echo "  📈 Market Order: make market-order network=scalex_core_devnet"
echo "  🧪 Local Deposit: make test-local-deposit network=scalex_core_devnet token=USDC amount=1000000000"

echo ""
echo "📁 Deployment files created:"
echo "  📁 deployments/${CORE_CHAIN_ID}.json - All contract & token addresses"
echo "  📁 deployments/oracle.json - Oracle contract address"
echo "  📁 deployments/unified_lending_${CORE_CHAIN_ID}.json - Lending contracts"

echo ""
echo "🔧 Development Configuration:"
echo "  • Core RPC: ${SCALEX_CORE_RPC}"
echo "  • Side RPC: ${SCALEX_SIDE_RPC}"
echo "  • Private Key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

echo ""
echo "🌐 RPC Detection Strategy:"
echo "  • Auto-detected from environment or Makefile defaults"
echo "  • Override: SCALEX_CORE_RPC=<URL> bash shellscripts/deploy.sh"
echo "  • Local Anvil: anvil --host 0.0.0.0 (fallback)"
echo "  • Dedicated Devnet: Uses Makefile defaults when available"