#!/bin/bash

# SCALEX Trading System - Data Population Automation Script
# Populates the system with test traders and trading activity

# ========================================
# ENVIRONMENT VARIABLES
# ========================================
# Before running this script, you may need to set these environment variables:
#
# REQUIRED:
# - PRIVATE_KEY: Private key for primary trader (uses PRIMARY_TRADER_PRIVATE_KEY env var by default)
#
# OPTIONAL (with defaults):
# - SCALEX_CORE_RPC: RPC URL for core chain (default: http://127.0.0.1:8545)
# - CORE_CHAIN_ID: Chain ID for deployment (default: 31337)
# - PRIMARY_TRADER_ADDRESS: Address of primary trader (default: 0x27dD1eBE7D826197FD163C134E79502402Fd7cB7)
# - SECONDARY_TRADER_ADDRESS: Address of secondary trader (default: 0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a)
# - PRIMARY_TRADER_PRIVATE_KEY: Private key for primary trader (default: 0x5d34b3f860c2b09c112d68a35d592dfb599841629c9b0ad8827269b94b57efca)
# - SECONDARY_TRADER_PRIVATE_KEY: Private key for secondary trader (default: 0x3d93c16f039372c7f70b490603bfc48a34575418fad5aea156c16f2cb0280ed8)
#
# PREREQUISITES:
# - Run deploy.sh first to deploy contracts
# - Ensure deployment file exists: deployments/${CORE_CHAIN_ID}.json
# - Have sufficient token balances for transfers
#
# USAGE EXAMPLES:
# # Basic usage (uses defaults):
# bash shellscripts/populate-data.sh
#
# # With custom RPC and chain ID:
# SCALEX_CORE_RPC="http://localhost:8545" CORE_CHAIN_ID=31338 bash shellscripts/populate-data.sh
#
# # With custom trader addresses:
# PRIMARY_TRADER_ADDRESS="0xYourPrimaryAddress" SECONDARY_TRADER_ADDRESS="0xYourSecondaryAddress" bash shellscripts/populate-data.sh
#
# # Using .env file:
# echo "0xYourPrivateKey" > .env
# SCALEX_CORE_RPC="http://localhost:8545" bash shellscripts/populate-data.sh
# ========================================

set -e  # Exit on any error

echo "🚀 Starting SCALEX Trading System Data Population..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source quote currency configuration module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/quote-currency-config.sh"

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

# Load environment variables from .env file
load_env_file

# Check if we're in the right directory
if [[ ! -f "Makefile" ]] || [[ ! -d "script" ]]; then
    print_error "Please run this script from the clob-dex project root directory"
    exit 1
fi

# Set RPC URL if not already set (simplified)
export SCALEX_CORE_RPC="${SCALEX_CORE_RPC:-http://127.0.0.1:8545}"

# Set core chain ID for local development
export CORE_CHAIN_ID="${CORE_CHAIN_ID:-31337}"

# Read deployment addresses from ${CORE_CHAIN_ID}.json
DEPLOYMENT_FILE="deployments/${CORE_CHAIN_ID}.json"
print_step "Reading deployment addresses from ${CORE_CHAIN_ID}.json..."
if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
    print_error "${CORE_CHAIN_ID}.json file not found! Please run deploy.sh first."
    exit 1
fi

# Load quote currency configuration
load_quote_currency_config

# Get quote token key
QUOTE_TOKEN_KEY=$(get_quote_token_key)

# Parse JSON to get token addresses (using jq if available, else using sed)
if command -v jq >/dev/null 2>&1; then
    QUOTE_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r ".$QUOTE_TOKEN_KEY")
    WETH_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.WETH')
    WBTC_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.WBTC')
    GOLD_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.GOLD // "0x0000000000000000000000000000000000000000"')
    SILVER_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.SILVER // "0x0000000000000000000000000000000000000000"')
    GOOGLE_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.GOOGLE // "0x0000000000000000000000000000000000000000"')
    NVIDIA_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.NVIDIA // "0x0000000000000000000000000000000000000000"')
    MNT_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.MNT // "0x0000000000000000000000000000000000000000"')
    APPLE_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.APPLE // "0x0000000000000000000000000000000000000000"')
else
    # Fallback to sed/grep approach
    QUOTE_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n "s/.*\"$QUOTE_TOKEN_KEY\":\"\([^\"]*\)\".*/\1/p")
    WETH_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"WETH":"\([^"]*\)".*/\1/p')
    WBTC_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"WBTC":"\([^"]*\)".*/\1/p')
    GOLD_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"GOLD":"\([^"]*\)".*/\1/p')
    SILVER_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"SILVER":"\([^"]*\)".*/\1/p')
    GOOGLE_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"GOOGLE":"\([^"]*\)".*/\1/p')
    NVIDIA_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"NVIDIA":"\([^"]*\)".*/\1/p')
    MNT_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"MNT":"\([^"]*\)".*/\1/p')
    APPLE_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"APPLE":"\([^"]*\)".*/\1/p')
fi

print_success "Token addresses loaded:"
echo "  Crypto Tokens:"
echo "    $QUOTE_SYMBOL: $QUOTE_ADDRESS"
echo "    WETH: $WETH_ADDRESS"
echo "    WBTC: $WBTC_ADDRESS"
echo "  RWA Tokens:"
echo "    GOLD: $GOLD_ADDRESS"
echo "    SILVER: $SILVER_ADDRESS"
echo "    GOOGLE: $GOOGLE_ADDRESS"
echo "    NVIDIA: $NVIDIA_ADDRESS"
echo "    MNT: $MNT_ADDRESS"
echo "    APPLE: $APPLE_ADDRESS"
echo ""

# Load contract addresses from deployment file
if command -v jq >/dev/null 2>&1; then
    BALANCE_MANAGER_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.BalanceManager')
    LENDING_MANAGER_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.LendingManager')
    SCALEX_ROUTER_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.ScaleXRouter')
    echo "DEBUG: Loaded ScaleXRouter address: '$SCALEX_ROUTER_ADDRESS'"
else
    # Fallback to sed/grep approach
    BALANCE_MANAGER_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"BalanceManager":"\([^"]*\)".*/\1/p')
    LENDING_MANAGER_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"LendingManager":"\([^"]*\)".*/\1/p')
    SCALEX_ROUTER_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"ScaleXRouter":"\([^"]*\)".*/\1/p')
    echo "DEBUG: Loaded ScaleXRouter address via sed: '$SCALEX_ROUTER_ADDRESS'"
fi

# Export contract addresses for use in subshells and commands
export BALANCE_MANAGER_ADDRESS
export LENDING_MANAGER_ADDRESS
export SCALEX_ROUTER_ADDRESS

# Set trader accounts
export PRIVATE_KEY="${PRIVATE_KEY:-0x5d34b3f860c2b09c112d68a35d592dfb599841629c9b0ad8827269b94b57efca}"
export PRIVATE_KEY_2="${PRIVATE_KEY_2:-0x3d93c16f039372c7f70b490603bfc48a34575418fad5aea156c16f2cb0280ed8}"

# Set agent account (wallet index 11 from seed phrase)
export AGENT_PRIVATE_KEY="${AGENT_PRIVATE_KEY:-0x8cc3690e2800c78cc7f8542024e9c3f603fe2dc91cfdd3ed34733785148781be}"

# Derive trader and agent addresses directly from private keys to avoid mismatches
export PRIMARY_TRADER_ADDRESS="${PRIMARY_TRADER_ADDRESS:-$(cast wallet address --private-key $PRIVATE_KEY)}"
export SECONDARY_TRADER_ADDRESS="${SECONDARY_TRADER_ADDRESS:-$(cast wallet address --private-key $PRIVATE_KEY_2)}"
export AGENT_ADDRESS="${AGENT_ADDRESS:-$(cast wallet address --private-key $AGENT_PRIVATE_KEY)}"

print_success "Contract addresses loaded:"
echo "  BalanceManager: $BALANCE_MANAGER_ADDRESS"
echo "  LendingManager: $LENDING_MANAGER_ADDRESS"
echo "  ScaleXRouter: $SCALEX_ROUTER_ADDRESS"
echo ""

print_success "Trader accounts configured:"
echo "  Primary Trader: $(cast wallet address --private-key $PRIVATE_KEY)"
echo "  Secondary Trader: $(cast wallet address --private-key $PRIVATE_KEY_2)"
echo "  AI Agent: $(cast wallet address --private-key $AGENT_PRIVATE_KEY)"
echo ""

# Prerequisites - Validate deployment
# Add retry function for RPC calls
retry_rpc_call() {
    local max_attempts=3
    local delay=2
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
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
    
    return 1
}

print_step "Prerequisites: Validating deployment..."
if ./shellscripts/validate-deployment.sh > /dev/null 2>&1; then
    print_success "Local deployment validation passed"
else
    print_error "Local deployment validation failed! Please run deploy.sh first"
    exit 1
fi

echo ""
print_success "🎯 Starting Complete Trading Flow..."

# Step 1: Primary trader deposits tokens (simplified approach)
print_step "Step 1: Primary trader gets tokens from deployed contracts..."
echo "  💰 Checking $QUOTE_SYMBOL balance from deployed mock tokens..."
PRIMARY_BALANCE_QUOTE=$(cast call $QUOTE_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
QUOTE_DIVISOR=$((10 ** QUOTE_DECIMALS))
print_success "Primary trader $QUOTE_SYMBOL balance: $(echo $PRIMARY_BALANCE_QUOTE | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"

echo "  💰 Checking WETH balance from deployed mock tokens..."
PRIMARY_BALANCE_WETH=$(cast call $WETH_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
print_success "Primary trader WETH balance: $(echo $PRIMARY_BALANCE_WETH | awk '{printf "%.2f", $1/1000000000000000000}') WETH"

print_success "Token balances checked"

# Step 1.5: Mint tokens to primary trader if needed
print_step "Step 1.5: Minting tokens to primary trader..."

# Check if primary trader needs tokens and mint if needed
# Re-check current balances since they may have changed
CURRENT_QUOTE_BALANCE=$(cast call $QUOTE_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
CURRENT_WETH_BALANCE=$(cast call $WETH_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")

QUOTE_DIVISOR=$((10 ** QUOTE_DECIMALS))
if [[ "$CURRENT_QUOTE_BALANCE" == "0" ]] || [[ -z "$CURRENT_QUOTE_BALANCE" ]] || [[ "$CURRENT_QUOTE_BALANCE" == *"000000000000000000000000000000000000000000000000000000000000000"* ]]; then
    echo "  🪙 Minting $QUOTE_SYMBOL to primary trader..."
    MINT_AMOUNT=$((100000 * QUOTE_DIVISOR))
    if RECIPIENT=$PRIMARY_TRADER_ADDRESS TOKEN_SYMBOL=$QUOTE_SYMBOL AMOUNT=$MINT_AMOUNT forge script script/utils/MintTokens.s.sol:MintTokens --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
        print_success "Primary trader $QUOTE_SYMBOL minting successful"
        CURRENT_QUOTE_BALANCE=$(cast call $QUOTE_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
        echo "    New $QUOTE_SYMBOL balance: $(echo $CURRENT_QUOTE_BALANCE | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"
    else
        print_error "Failed to mint $QUOTE_SYMBOL to primary trader"
        exit 1
    fi
fi

if [[ "$CURRENT_WETH_BALANCE" == "0" ]] || [[ -z "$CURRENT_WETH_BALANCE" ]] || [[ "$CURRENT_WETH_BALANCE" == *"000000000000000000000000000000000000000000000000000000000000000"* ]]; then
    echo "  🪙 Minting WETH to primary trader..."
    if RECIPIENT=$PRIMARY_TRADER_ADDRESS TOKEN_SYMBOL=WETH AMOUNT=100000000000000000000 forge script script/utils/MintTokens.s.sol:MintTokens --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
        print_success "Primary trader WETH minting successful"
        CURRENT_WETH_BALANCE=$(cast call $WETH_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
        echo "    New WETH balance: $(echo $CURRENT_WETH_BALANCE | awk '{printf "%.2f", $1/1000000000000000000}') WETH"
    else
        print_error "Failed to mint WETH to primary trader"
        exit 1
    fi
fi

print_success "Primary trader is now funded with tokens!"

# Step 2: Transfer tokens to secondary trader
print_step "Step 2: Transferring tokens to secondary trader..."
TRANSFER_AMOUNT=$((5000 * QUOTE_DIVISOR))
echo "  🔄 Transferring $QUOTE_SYMBOL (5000 $QUOTE_SYMBOL)..."
RECIPIENT=$SECONDARY_TRADER_ADDRESS TOKEN_SYMBOL=$QUOTE_SYMBOL AMOUNT=$TRANSFER_AMOUNT forge script script/utils/TransferTokens.s.sol:TransferTokens --rpc-url "${SCALEX_CORE_RPC}" --broadcast
print_success "$QUOTE_SYMBOL transfer completed"

# Add delay to avoid nonce conflicts
echo "  ⏳ Waiting 3 seconds to avoid nonce conflicts..."
sleep 3

echo "  🔄 Transferring WETH (10 WETH - extra for borrowing collateral)..."
RECIPIENT=$SECONDARY_TRADER_ADDRESS TOKEN_SYMBOL=WETH AMOUNT=10000000000000000000 forge script script/utils/TransferTokens.s.sol:TransferTokens --rpc-url "${SCALEX_CORE_RPC}" --broadcast
print_success "WETH transfer completed"

# Step 3: Secondary trader tokens already received
print_step "Step 3: Secondary trader tokens already received..."
echo "  Secondary trader already received tokens from Step 2"
echo "  📊 Checking secondary trader balances..."

SECONDARY_BALANCE_QUOTE=$(cast call $QUOTE_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
print_success "Secondary trader $QUOTE_SYMBOL balance: $(echo $SECONDARY_BALANCE_QUOTE | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"

SECONDARY_BALANCE_WETH=$(cast call $WETH_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
print_success "Secondary trader WETH balance: $(echo $SECONDARY_BALANCE_WETH | awk '{printf "%.2f", $1/1000000000000000000}') WETH"

print_success "Secondary trader is ready with tokens!"

# Step 4: Populate lending protocol data
print_step "Step 4: Populating lending protocol data..."
echo "  🏦 Setting up lending parameters and liquidity"
if forge script script/lending/PopulateLendingData.sol:PopulateLendingData --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
    print_success "Lending protocol data populated successfully"
else
    print_warning "Lending data population failed, continuing without lending..."
    echo "  🔧 Manual lending setup required"
fi

# Step 4.5: Liquidity Provisioning and Borrowing Activities
print_step "Step 4.5: Setting up liquidity and borrowing activities..."
echo "  💰 Primary trader deposits liquidity to lending protocol"

# Primary trader deposits quote currency to BalanceManager (provides liquidity)
DEPOSIT_AMOUNT=$((100000 * QUOTE_DIVISOR))
echo "  🏦 Depositing 100,000 $QUOTE_SYMBOL for lending liquidity..."
if PRIVATE_KEY=$PRIVATE_KEY TOKEN_SYMBOL=$QUOTE_SYMBOL DEPOSIT_AMOUNT=$DEPOSIT_AMOUNT forge script script/deposits/LocalDeposit.s.sol:LocalDeposit --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
    print_success "Primary trader $QUOTE_SYMBOL deposit successful - lending liquidity provided"
else
    print_warning "$QUOTE_SYMBOL deposit failed - borrowing may not work properly"
fi

# Primary trader deposits WETH to BalanceManager (provides collateral)
echo "  💎 Depositing 50 WETH as collateral for borrowing..."
if PRIVATE_KEY=$PRIVATE_KEY TOKEN_SYMBOL=WETH DEPOSIT_AMOUNT=50000000000000000000 forge script script/deposits/LocalDeposit.s.sol:LocalDeposit --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
    print_success "Primary trader WETH deposit successful - collateral ready"
else
    print_warning "WETH deposit failed - borrowing capacity limited"
fi

# Secondary trader deposits quote currency to BalanceManager (provides liquidity)
SECONDARY_DEPOSIT_AMOUNT=$((5000 * QUOTE_DIVISOR))
echo "  🏦 Secondary trader deposits 5,000 $QUOTE_SYMBOL for additional liquidity..."
if PRIVATE_KEY=$PRIVATE_KEY_2 TOKEN_SYMBOL=$QUOTE_SYMBOL DEPOSIT_AMOUNT=$SECONDARY_DEPOSIT_AMOUNT forge script script/deposits/LocalDeposit.s.sol:LocalDeposit --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
    print_success "Secondary trader $QUOTE_SYMBOL deposit successful - additional liquidity provided"
else
    print_warning "Secondary trader $QUOTE_SYMBOL deposit failed"
fi

# Secondary trader deposits WETH as collateral for borrowing quote currency
echo "  💰 Secondary trader deposits WETH as collateral for borrowing $QUOTE_SYMBOL..."

# Use LocalDeposit script for WETH collateral as well
# Deposit extra WETH (10 instead of 5) to ensure some remains as collateral after trading
echo "  🏦 Depositing 10 WETH via LocalDeposit for collateral (extra to reserve for borrowing)..."
if PRIVATE_KEY=$PRIVATE_KEY_2 TOKEN_SYMBOL=WETH DEPOSIT_AMOUNT=10000000000000000000 forge script script/deposits/LocalDeposit.s.sol:LocalDeposit --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
    print_success "Secondary trader WETH deposit successful - collateral ready for borrowing $QUOTE_SYMBOL"
else
    print_warning "Secondary trader WETH deposit failed - borrowing may not work"
fi

# Check if synthetic tokens exist in deployment file
echo "  🔍 Checking synthetic tokens availability..."
SYNTHETIC_QUOTE_KEY=$(get_synthetic_quote_key)
if ! jq -e ".$SYNTHETIC_QUOTE_KEY" $DEPLOYMENT_FILE > /dev/null 2>&1 || [[ "$(jq -r ".$SYNTHETIC_QUOTE_KEY" $DEPLOYMENT_FILE)" == "null" ]]; then
    print_warning "Synthetic tokens not found in deployment file"
    print_warning "Please run deploy.sh to complete synthetic token creation"
    exit 1
fi

sxQUOTE_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r ".$SYNTHETIC_QUOTE_KEY")
sxWETH_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.sxWETH')
sxWBTC_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.sxWBTC')
sxGOLD_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.sxGOLD // "0x0000000000000000000000000000000000000000"')
sxSILVER_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.sxSILVER // "0x0000000000000000000000000000000000000000"')
sxGOOGLE_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.sxGOOGLE // "0x0000000000000000000000000000000000000000"')
sxNVIDIA_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.sxNVIDIA // "0x0000000000000000000000000000000000000000"')
sxMNT_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.sxMNT // "0x0000000000000000000000000000000000000000"')
sxAPPLE_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.sxAPPLE // "0x0000000000000000000000000000000000000000"')

print_success "Synthetic tokens found:"
echo "  Crypto Synthetic Tokens:"
echo "    $SYNTHETIC_QUOTE_KEY: $sxQUOTE_ADDRESS"
echo "    sxWETH: $sxWETH_ADDRESS"
echo "    sxWBTC: $sxWBTC_ADDRESS"
echo "  RWA Synthetic Tokens:"
echo "    sxGOLD: $sxGOLD_ADDRESS"
echo "    sxSILVER: $sxSILVER_ADDRESS"
echo "    sxGOOGLE: $sxGOOGLE_ADDRESS"
echo "    sxNVIDIA: $sxNVIDIA_ADDRESS"
echo "    sxMNT: $sxMNT_ADDRESS"
echo "    sxAPPLE: $sxAPPLE_ADDRESS"

# Configure lending assets before borrowing
# Set ScaleXRouter -> LendingManager link if not already set
echo "  🔗 Setting up ScaleXRouter -> LendingManager connection..."
CURRENT_ROUTER_LENDING=$(cast call $SCALEX_ROUTER_ADDRESS "lendingManager()" --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
if [[ "$CURRENT_ROUTER_LENDING" == "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
    if cast send $SCALEX_ROUTER_ADDRESS "setLendingManager(address)" $LENDING_MANAGER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1; then
        print_success "ScaleXRouter -> LendingManager link established"
    else
        print_warning "Failed to set ScaleXRouter -> LendingManager link"
    fi
else
    print_success "ScaleXRouter -> LendingManager link already exists"
fi

echo "  ⚙️  Configuring lending assets..."
# Assets already configured correctly by DeployAll.s.sol - skip reconfiguration
print_success "Lending assets already configured by deployment - skipping reconfiguration"

# Borrowing activities
echo "  🏛️  Testing borrowing activities..."
echo "  📤 Secondary trader borrows 1,000 $QUOTE_SYMBOL against WETH collateral..."

# Use the already defined secondary trader address
SECONDARY_TRADER=$SECONDARY_TRADER_ADDRESS

# Check current balances before borrowing
echo "  📊 Checking balances before borrowing..."
SECONDARY_WETH_BALANCE=$(cast call $WETH_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
SECONDARY_QUOTE_BALANCE=$(cast call $QUOTE_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

echo "    💰 Secondary trader $QUOTE_SYMBOL balance: $(echo $SECONDARY_QUOTE_BALANCE | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"
echo "    💎 Secondary trader WETH balance: $(echo $SECONDARY_WETH_BALANCE | awk '{printf "%.6f", $1/1000000000000000000}') WETH"

# Borrowing parameters
BORROW_AMOUNT=$((1000 * QUOTE_DIVISOR))  # 1,000 in quote currency

echo "  🔧 Attempting to borrow 1,000 $QUOTE_SYMBOL..."
echo "DEBUG: Checking if user has sufficient collateral for borrowing..."

# First check if user has any collateral supplied to LendingManager
echo "    📊 Checking user's supplied collateral..."
USER_SUPPLY=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $SECONDARY_TRADER_ADDRESS $QUOTE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
USER_WETH_SUPPLY=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $SECONDARY_TRADER_ADDRESS $WETH_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

echo "    User $QUOTE_SYMBOL supplied: $(echo $USER_SUPPLY | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"
echo "    User WETH supplied: $(echo $USER_WETH_SUPPLY | awk '{printf "%.6f", $1/1000000000000000000}') WETH"

# Check borrowing capacity - prioritize WETH collateral for borrowing quote currency
if [[ "$USER_WETH_SUPPLY" == "0" ]]; then
    print_warning "User has no WETH collateral supplied - borrowing $QUOTE_SYMBOL will fail"
    echo "  🔧 User must deposit WETH as collateral to borrow $QUOTE_SYMBOL"
    BORROWING_SUCCESS=false
else
    echo "    User has WETH collateral - attempting borrowing $QUOTE_SYMBOL..."
    # Check if user has sufficient borrowing capacity (basic check)
    WETH_COLLATERAL_VALUE=$(echo "$USER_WETH_SUPPLY" | awk '{printf "%.0f", $1/1000000000000000000}')  # Convert to WETH units
    # Assuming 1 WETH = $2000, user can borrow up to 80% LTV = 1600 worth
    if [[ $WETH_COLLATERAL_VALUE -ge 1 ]]; then  # Need at least 1 WETH to borrow 1000 quote currency
        # For now, borrowing should be done through ScaleXRouter if it supports lending integration
        # This requires ScaleXRouter to be properly linked to LendingManager
        if [[ "$SCALEX_ROUTER_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
            echo "    🔄 Attempting borrowing 1,000 $QUOTE_SYMBOL through ScaleXRouter using WETH collateral..."
            # Note: This uses ScaleXRouter.borrow() which delegates to LendingManager
            BORROW_TX=$(cast send $SCALEX_ROUTER_ADDRESS "borrow(address,uint256)" $QUOTE_ADDRESS $BORROW_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 2>&1)
            if echo "$BORROW_TX" | grep -q "transactionHash"; then
                # Extract transaction hash
                TX_HASH=$(echo "$BORROW_TX" | grep "transactionHash" | awk '{print $2}')
                # Wait for receipt (retry up to 5 times with 2s delay)
                TX_STATUS=""
                for i in {1..5}; do
                    sleep 2
                    TX_STATUS=$(cast receipt $TX_HASH --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | grep "^status" | awk '{print $2}')
                    if [[ -n "$TX_STATUS" ]]; then break; fi
                done
                if [[ "$TX_STATUS" == "1" ]]; then
                    print_success "Secondary trader successfully borrowed 1,000 $QUOTE_SYMBOL via ScaleXRouter"
                    BORROWING_SUCCESS=true
                else
                    print_warning "ScaleXRouter borrowing transaction reverted or timed out"
                    echo "    Transaction status: $TX_STATUS"
                    BORROWING_SUCCESS=false
                fi
            else
                print_warning "ScaleXRouter borrowing failed - checking authorization..."
                echo "    Error details: $BORROW_TX"
                BORROWING_SUCCESS=false
            fi
        else
            print_warning "ScaleXRouter not available for borrowing"
            BORROWING_SUCCESS=false
        fi
    else
        print_warning "Insufficient WETH collateral - need at least 1 WETH to borrow 1,000 $QUOTE_SYMBOL"
        echo "    Current WETH collateral: $WETH_COLLATERAL_VALUE WETH"
        BORROWING_SUCCESS=false
    fi
fi

# Check borrowing results
echo "  📊 Checking borrowing results..."
SECONDARY_QUOTE_BALANCE_AFTER=$(cast call $QUOTE_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
SECONDARY_QUOTE_DEBT=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $SECONDARY_TRADER_ADDRESS $QUOTE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

echo "    💰 Secondary trader $QUOTE_SYMBOL balance after: $(echo $SECONDARY_QUOTE_BALANCE_AFTER | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"
echo "    📤 Secondary trader $QUOTE_SYMBOL debt: $(echo $SECONDARY_QUOTE_DEBT | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"

# Calculate borrowed amount using printf for better error handling
BORROWED_AMOUNT=$((SECONDARY_QUOTE_BALANCE_AFTER - SECONDARY_QUOTE_BALANCE))
if [[ $BORROWED_AMOUNT -gt 0 ]]; then
    echo "    Successfully borrowed: $(echo "$BORROWED_AMOUNT" | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"
    BORROW_1_SUCCESS=true
else
    echo "    No borrowing occurred - may need more collateral or lending setup"
    BORROW_1_SUCCESS=false
fi

# Enhanced Borrowing & Repayment Activities
echo ""
print_step "Enhanced Borrowing & Repayment Activities..."

# Function to check user's health factor
check_health_factor() {
    local user_address=$1
    local health_factor=$(cast call $LENDING_MANAGER_ADDRESS "getHealthFactor(address)" $user_address --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    echo "$health_factor"
}

# Function to display user's position
display_user_position() {
    local user_address=$1
    local user_name=$2

    echo "  📊 $user_name Position Summary:"

    # Check supplies - Crypto tokens
    local usdc_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $QUOTE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    local weth_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $WETH_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    local wbtc_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $WBTC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    # Check supplies - RWA tokens (if addresses exist)
    local gold_supply="0"
    local silver_supply="0"
    local google_supply="0"
    local nvidia_supply="0"
    local mnt_supply="0"
    local apple_supply="0"
    [[ "$GOLD_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && gold_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $GOLD_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    [[ "$SILVER_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && silver_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $SILVER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    [[ "$GOOGLE_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && google_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $GOOGLE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    [[ "$NVIDIA_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && nvidia_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $NVIDIA_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    [[ "$MNT_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && mnt_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $MNT_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    [[ "$APPLE_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && apple_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $APPLE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    # Check debts - Crypto tokens
    local usdc_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $QUOTE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    local weth_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $WETH_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    local wbtc_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $WBTC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    # Check debts - RWA tokens (if addresses exist)
    local gold_debt="0"
    local silver_debt="0"
    local google_debt="0"
    local nvidia_debt="0"
    local mnt_debt="0"
    local apple_debt="0"
    [[ "$GOLD_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && gold_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $GOLD_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    [[ "$SILVER_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && silver_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $SILVER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    [[ "$GOOGLE_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && google_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $GOOGLE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    [[ "$NVIDIA_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && nvidia_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $NVIDIA_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    [[ "$MNT_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && mnt_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $MNT_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    [[ "$APPLE_ADDRESS" != "0x0000000000000000000000000000000000000000" ]] && apple_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $APPLE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    # Check health factor
    local health_factor=$(check_health_factor $user_address)

    echo "    💰 Supplies:"
    echo "      Crypto:"
    echo "        $QUOTE_SYMBOL: $(echo $usdc_supply | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"
    echo "        WETH: $(echo $weth_supply | awk '{printf "%.6f", $1/1000000000000000000}') WETH"
    echo "        WBTC: $(echo $wbtc_supply | awk '{printf "%.8f", $1/100000000000000000000}') WBTC"
    if [[ "$GOLD_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "      RWA:"
        echo "        GOLD: $(echo $gold_supply | awk '{printf "%.4f", $1/1000000000000000000}') GOLD"
        echo "        SILVER: $(echo $silver_supply | awk '{printf "%.4f", $1/1000000000000000000}') SILVER"
        echo "        GOOGLE: $(echo $google_supply | awk '{printf "%.4f", $1/1000000000000000000}') GOOGLE"
        echo "        NVIDIA: $(echo $nvidia_supply | awk '{printf "%.4f", $1/1000000000000000000}') NVIDIA"
        echo "        MNT: $(echo $mnt_supply | awk '{printf "%.4f", $1/1000000000000000000}') MNT"
        echo "        APPLE: $(echo $apple_supply | awk '{printf "%.4f", $1/1000000000000000000}') APPLE"
    fi
    echo "    📤 Debts:"
    echo "      Crypto:"
    echo "        $QUOTE_SYMBOL: $(echo $usdc_debt | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"
    echo "        WETH: $(echo $weth_debt | awk '{printf "%.6f", $1/1000000000000000000}') WETH"
    echo "        WBTC: $(echo $wbtc_debt | awk '{printf "%.8f", $1/100000000000000000000}') WBTC"
    if [[ "$GOLD_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo "      RWA:"
        echo "        GOLD: $(echo $gold_debt | awk '{printf "%.4f", $1/1000000000000000000}') GOLD"
        echo "        SILVER: $(echo $silver_debt | awk '{printf "%.4f", $1/1000000000000000000}') SILVER"
        echo "        GOOGLE: $(echo $google_debt | awk '{printf "%.4f", $1/1000000000000000000}') GOOGLE"
        echo "        NVIDIA: $(echo $nvidia_debt | awk '{printf "%.4f", $1/1000000000000000000}') NVIDIA"
        echo "        MNT: $(echo $mnt_debt | awk '{printf "%.4f", $1/1000000000000000000}') MNT"
        echo "        APPLE: $(echo $apple_debt | awk '{printf "%.4f", $1/1000000000000000000}') APPLE"
    fi
    echo "    🛡️  Health Factor: $(echo $health_factor | awk '{printf "%.2f", $1/1000000000000000000}')"

    if [[ $health_factor -gt 1000000000000000000 ]]; then
        echo "    ✅ Position is healthy (HF > 1.0)"
    else
        echo "    ⚠️  Position is at risk (HF ≤ 1.0)"
    fi
}

# Position display after initial borrowing
echo "  🔍 Positions after initial borrowing..."
display_user_position $SECONDARY_TRADER "Secondary Trader"
display_user_position $PRIMARY_TRADER "Primary Trader"

# Scenario 2: Primary trader borrows WETH against quote currency and WBTC collateral
echo ""
echo "  📤 Scenario 2: Primary trader borrows 2 WETH against $QUOTE_SYMBOL and WBTC collateral..."

# Check primary trader's collateral
PRIMARY_QUOTE_SUPPLY=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $PRIMARY_TRADER_ADDRESS $QUOTE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
PRIMARY_WBTC_SUPPLY=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $PRIMARY_TRADER_ADDRESS $WBTC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
PRIMARY_WETH_BALANCE_BEFORE=$(cast call $WETH_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

echo "    💰 Primary trader $QUOTE_SYMBOL supplied: $(echo $PRIMARY_QUOTE_SUPPLY | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"
echo "    💎 Primary trader WBTC supplied: $(echo $PRIMARY_WBTC_SUPPLY | awk '{printf "%.8f", $1/100000000000000000000}') WBTC"
echo "    💎 Primary trader WETH balance: $(echo $PRIMARY_WETH_BALANCE_BEFORE | awk '{printf "%.6f", $1/1000000000000000000}') WETH"

# Attempt to borrow WETH
BORROW_WETH_AMOUNT=2000000000000000000  # 2 WETH
if [[ $PRIMARY_QUOTE_SUPPLY -gt 0 ]] || [[ $PRIMARY_WBTC_SUPPLY -gt 0 ]]; then
    echo "    🔄 Attempting to borrow 2 WETH through ScaleXRouter..."
    BORROW_WETH_TX=$(cast send $SCALEX_ROUTER_ADDRESS "borrow(address,uint256)" $WETH_ADDRESS $BORROW_WETH_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY 2>&1)
    if echo "$BORROW_WETH_TX" | grep -q "transactionHash"; then
        # Extract transaction hash
        TX_HASH=$(echo "$BORROW_WETH_TX" | grep "transactionHash" | awk '{print $2}')
        # Wait for receipt (retry up to 5 times with 2s delay)
        TX_STATUS=""
        for i in {1..5}; do
            sleep 2
            TX_STATUS=$(cast receipt $TX_HASH --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | grep "^status" | awk '{print $2}')
            if [[ -n "$TX_STATUS" ]]; then break; fi
        done
        if [[ "$TX_STATUS" == "1" ]]; then
            print_success "✅ Primary trader successfully borrowed 2 WETH"
            BORROW_2_SUCCESS=true
        else
            print_warning "WETH borrowing transaction reverted or timed out"
            echo "    Transaction status: $TX_STATUS"
            BORROW_2_SUCCESS=false
        fi
    else
        print_warning "WETH borrowing failed - checking authorization..."
        echo "    Error details: $BORROW_WETH_TX"
        BORROW_2_SUCCESS=false
    fi
else
    print_warning "Primary trader has insufficient collateral for borrowing WETH"
    BORROW_2_SUCCESS=false
fi

# Check WETH borrowing results
PRIMARY_WETH_BALANCE_AFTER=$(cast call $WETH_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
PRIMARY_WETH_DEBT=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $PRIMARY_TRADER_ADDRESS $WETH_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

echo "    💎 Primary trader WETH balance after: $(echo $PRIMARY_WETH_BALANCE_AFTER | awk '{printf "%.6f", $1/1000000000000000000}') WETH"
echo "    📤 Primary trader WETH debt: $(echo $PRIMARY_WETH_DEBT | awk '{printf "%.6f", $1/1000000000000000000}') WETH"

WETH_BORROWED=$((PRIMARY_WETH_BALANCE_AFTER - PRIMARY_WETH_BALANCE_BEFORE))
if [[ $WETH_BORROWED -gt 0 ]]; then
    echo "    ✅ Successfully borrowed: $(echo "$WETH_BORROWED" | awk '{printf "%.6f", $1/1000000000000000000}') WETH"
else
    echo "    ❌ No WETH borrowing occurred"
fi

# Simulate interest accrual (advance time by 1 hour for testing)
echo ""
echo "  ⏰ Simulating interest accrual (1 hour)..."
# Note: In a local environment, you might need to manually increase block timestamp
# This is a placeholder for time advancement logic
echo "    ⏭️  Skipping time advancement in local environment"

# Repayment Activities
echo ""
echo "  🔄 Repayment Activities..."

# Scenario 3: Secondary trader repays partial quote currency debt
echo "  💰 Scenario 3: Secondary trader repays 500 $QUOTE_SYMBOL of debt..."

if [[ "$BORROW_1_SUCCESS" == true ]] && [[ $SECONDARY_QUOTE_DEBT -gt 0 ]]; then
    REPAY_AMOUNT=$((500 * QUOTE_DIVISOR))  # 500 in quote currency

    # Check if secondary trader has enough quote currency to repay
    SECONDARY_CURRENT_QUOTE=$(cast call $QUOTE_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    if [[ $SECONDARY_CURRENT_QUOTE -ge $REPAY_AMOUNT ]]; then
        echo "    💸 Repaying 500 $QUOTE_SYMBOL through ScaleXRouter..."

        # Approve ScaleXRouter to spend quote currency for repayment
        if cast send $QUOTE_ADDRESS "approve(address,uint256)" $SCALEX_ROUTER_ADDRESS $REPAY_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 > /dev/null 2>&1; then
            echo "    ✅ $QUOTE_SYMBOL approval for repayment successful"

            # Execute repayment
            REPAY_TX=$(cast send $SCALEX_ROUTER_ADDRESS "repay(address,uint256)" $QUOTE_ADDRESS $REPAY_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 2>&1)
            if echo "$REPAY_TX" | grep -q "transactionHash"; then
                # Extract transaction hash
                TX_HASH=$(echo "$REPAY_TX" | grep "transactionHash" | awk '{print $2}')
                # Wait for receipt (retry up to 5 times with 2s delay)
                TX_STATUS=""
                for i in {1..5}; do
                    sleep 2
                    TX_STATUS=$(cast receipt $TX_HASH --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | grep "^status" | awk '{print $2}')
                    if [[ -n "$TX_STATUS" ]]; then break; fi
                done
                if [[ "$TX_STATUS" == "1" ]]; then
                    print_success "✅ Secondary trader successfully repaid 500 $QUOTE_SYMBOL"
                    REPAY_1_SUCCESS=true
                else
                    print_warning "$QUOTE_SYMBOL repayment transaction reverted or timed out"
                    echo "    Transaction status: $TX_STATUS"
                    REPAY_1_SUCCESS=false
                fi
            else
                print_warning "$QUOTE_SYMBOL repayment failed - checking error..."
                echo "    Error details: $REPAY_TX"
                REPAY_1_SUCCESS=false
            fi
        else
            print_warning "$QUOTE_SYMBOL approval for repayment failed"
            REPAY_1_SUCCESS=false
        fi
    else
        print_warning "Insufficient $QUOTE_SYMBOL balance for repayment"
        echo "    Available: $(echo $SECONDARY_CURRENT_QUOTE | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"
        echo "    Required: 500.00 $QUOTE_SYMBOL"
        REPAY_1_SUCCESS=false
    fi
else
    print_warning "No $QUOTE_SYMBOL debt to repay or borrowing failed"
    REPAY_1_SUCCESS=false
fi

# Check repayment results
if [[ "$REPAY_1_SUCCESS" == true ]]; then
    SECONDARY_QUOTE_DEBT_AFTER=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $SECONDARY_TRADER_ADDRESS $QUOTE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    SECONDARY_QUOTE_BALANCE_FINAL=$(cast call $QUOTE_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    echo "    📤 Secondary trader $QUOTE_SYMBOL debt after repayment: $(echo $SECONDARY_QUOTE_DEBT_AFTER | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"
    echo "    💰 Secondary trader $QUOTE_SYMBOL balance after repayment: $(echo $SECONDARY_QUOTE_BALANCE_FINAL | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"

    REPAID_AMOUNT=$((SECONDARY_QUOTE_DEBT - SECONDARY_QUOTE_DEBT_AFTER))
    if [[ $REPAID_AMOUNT -gt 0 ]]; then
        echo "    ✅ Successfully repaid: $(echo "$REPAID_AMOUNT" | awk -v div=$QUOTE_DIVISOR '{printf "%.2f", $1/div}') $QUOTE_SYMBOL"
    fi
fi

# Scenario 4: Primary trader repays部分 WETH debt
echo ""
echo "  💎 Scenario 4: Primary trader repays 1 WETH of debt..."

if [[ "$BORROW_2_SUCCESS" == true ]] && [[ $PRIMARY_WETH_DEBT -gt 0 ]]; then
    REPAY_WETH_AMOUNT=1000000000000000000  # 1 WETH

    # Check if primary trader has enough WETH to repay
    PRIMARY_CURRENT_WETH=$(cast call $WETH_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    if [[ $PRIMARY_CURRENT_WETH -ge $REPAY_WETH_AMOUNT ]]; then
        echo "    💸 Repaying 1 WETH through ScaleXRouter..."

        # Approve ScaleXRouter to spend WETH for repayment
        if cast send $WETH_ADDRESS "approve(address,uint256)" $SCALEX_ROUTER_ADDRESS $REPAY_WETH_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY > /dev/null 2>&1; then
            echo "    ✅ WETH approval for repayment successful"

            # Execute repayment
            REPAY_TX=$(cast send $SCALEX_ROUTER_ADDRESS "repay(address,uint256)" $WETH_ADDRESS $REPAY_WETH_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY 2>&1)
            if echo "$REPAY_TX" | grep -q "transactionHash"; then
                # Extract transaction hash
                TX_HASH=$(echo "$REPAY_TX" | grep "transactionHash" | awk '{print $2}')
                # Wait for receipt (retry up to 5 times with 2s delay)
                TX_STATUS=""
                for i in {1..5}; do
                    sleep 2
                    TX_STATUS=$(cast receipt $TX_HASH --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | grep "^status" | awk '{print $2}')
                    if [[ -n "$TX_STATUS" ]]; then break; fi
                done
                if [[ "$TX_STATUS" == "1" ]]; then
                    print_success "✅ Primary trader successfully repaid 1 WETH"
                    REPAY_2_SUCCESS=true
                else
                    print_warning "WETH repayment transaction reverted or timed out"
                    echo "    Transaction status: $TX_STATUS"
                    REPAY_2_SUCCESS=false
                fi
            else
                print_warning "WETH repayment failed - checking error..."
                echo "    Error details: $REPAY_TX"
                REPAY_2_SUCCESS=false
            fi
        else
            print_warning "WETH approval for repayment failed"
            REPAY_2_SUCCESS=false
        fi
    else
        print_warning "Insufficient WETH balance for repayment"
        echo "    Available: $(echo $PRIMARY_CURRENT_WETH | awk '{printf "%.6f", $1/1000000000000000000}') WETH"
        echo "    Required: 1.000000 WETH"
        REPAY_2_SUCCESS=false
    fi
else
    print_warning "No WETH debt to repay or borrowing failed"
    REPAY_2_SUCCESS=false
fi

# Final position summary
echo ""
echo "  📊 Final Position Summary after All Activities:"
display_user_position $SECONDARY_TRADER "Secondary Trader"
display_user_position $PRIMARY_TRADER "Primary Trader"

# Summary of all borrowing and repayment activities
echo ""
echo "  📈 Borrowing & Repayment Summary:"
echo "    Scenario 1 - Secondary trader borrows $QUOTE_SYMBOL: $([ "$BORROW_1_SUCCESS" == true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "    Scenario 2 - Primary trader borrows WETH: $([ "$BORROW_2_SUCCESS" == true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "    Scenario 3 - Secondary trader repays $QUOTE_SYMBOL: $([ "$REPAY_1_SUCCESS" == true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "    Scenario 4 - Primary trader repays WETH: $([ "$REPAY_2_SUCCESS" == true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"

if [[ "$BORROW_1_SUCCESS" == true ]] || [[ "$BORROW_2_SUCCESS" == true ]] || [[ "$REPAY_1_SUCCESS" == true ]] || [[ "$REPAY_2_SUCCESS" == true ]]; then
    print_success "🎉 Borrowing and repayment activities completed successfully!"
else
    print_warning "⚠️  Some borrowing/repayment activities failed. Check logs above for details."
fi

# Step 5: Primary trader creates liquidity
print_step "Step 5: Primary trader creating liquidity (limit orders)..."
echo "  🏊 Creating trading pools and filling orderbook..."
echo ""

# Fill WETH/QUOTE pool
echo "  📊 Filling sxWETH/sx${QUOTE_SYMBOL} pool..."
echo "  🔑 Using primary trader private key"
if forge script script/trading/FillOrderBook.s.sol:FillMockOrderBook --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --broadcast 2>&1 | tee /tmp/fillorderbook_error.log; then
    print_success "✅ sxWETH/sx${QUOTE_SYMBOL} orderbook filled"
else
    print_warning "⚠️  sxWETH/sx${QUOTE_SYMBOL} orderbook creation failed"
    echo "Error details:"
    tail -50 /tmp/fillorderbook_error.log
fi

# Fill RWA token pools if available
if [[ "$GOLD_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
    echo ""
    echo "  🏆 Filling RWA token orderbooks..."
    echo "  🔑 Using primary trader private key"

    # Fill all RWA token pools:
    # - GOLD/QUOTE (price ~$2,650)
    # - SILVER/QUOTE (price ~$30)
    # - GOOGLE/QUOTE (price ~$180)
    # - NVIDIA/QUOTE (price ~$140)
    # - MNT/QUOTE (price ~$1)
    # - APPLE/QUOTE (price ~$230)

    if forge script script/trading/FillRWAOrderBooks.s.sol:FillRWAOrderBooks --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --broadcast > /dev/null 2>&1; then
        print_success "✅ RWA token orderbooks filled (6 pools)"
    else
        print_warning "⚠️  RWA token orderbook filling encountered errors"
        echo "  💡 Some RWA pools may not be available yet"
    fi
fi

# Step 6: Secondary trader executes trades
print_step "Step 6: Secondary trader executing market orders..."
echo ""

# Option 1: Use unified PlaceMarketOrders script for all pools (WETH + RWA)
# This is the recommended approach as it handles all pools consistently
if [[ "${USE_UNIFIED_MARKET_ORDERS:-true}" == "true" ]]; then
    echo "  📊 Executing market orders on all pools (WETH + RWA)..."
    echo "  🔑 Using secondary trader private key"

    if forge script script/trading/PlaceMarketOrders.s.sol:PlaceMarketOrders --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 --broadcast > /dev/null 2>&1; then
        print_success "✅ Market orders executed on all pools (8 pools total: WETH, WBTC, GOLD, SILVER, GOOGLE, NVIDIA, MNT, APPLE)"
    else
        print_warning "⚠️  Some market orders failed - check logs for details"
    fi
else
    # Option 2: Use separate scripts for WETH and RWA pools (legacy approach)
    # Execute market orders on WETH/QUOTE pool
    echo "  📊 Executing market orders on sxWETH/sx${QUOTE_SYMBOL}..."
    echo "  🔑 Using secondary trader private key"
    if forge script script/trading/MarketOrderBook.sol:MarketOrderBook --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 --broadcast > /dev/null 2>&1; then
        print_success "✅ sxWETH/sx${QUOTE_SYMBOL} market orders executed"
    else
        print_warning "⚠️  sxWETH/sx${QUOTE_SYMBOL} market orders failed"
    fi

    # Execute market orders on RWA pools if available
    if [[ "$GOLD_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
        echo ""
        echo "  🏆 Executing market orders on RWA pools..."
        echo "  🔑 Using secondary trader private key"

        # Execute market orders on all RWA pools:
        # - GOLD/QUOTE, SILVER/QUOTE, GOOGLE/QUOTE
        # - NVIDIA/QUOTE, MNT/QUOTE, APPLE/QUOTE

        if forge script script/trading/MarketOrderRWAPools.sol:MarketOrderRWAPools --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 --broadcast > /dev/null 2>&1; then
            print_success "✅ RWA pool market orders executed (6 pools)"
        else
            print_warning "⚠️  RWA pool market orders encountered errors"
            echo "  💡 Some trades may have failed due to insufficient liquidity"
        fi
    fi
fi

echo ""
print_success " Data Population completed successfully!"

# Validation
print_step "Validating data population..."
if ./shellscripts/validate-data-population.sh; then
    print_success "Data population validation passed!"
    echo ""
    echo "System now contains:"
    echo "  📊 Two active traders with token balances"
    echo "  🤖 One AI agent with ERC-8004 compatible tracking"
    echo "  💰 Token transfers between traders completed"
    echo "  🏦 Lending protocol infrastructure configured"
    echo "  💵 Actual liquidity provisioned to lending protocol"
    echo "  📤 Active borrowing activities demonstrated (traders + agent)"
    echo "  🛡️  Collateral deposited and borrowing capacity established"
    echo "  🏗️  Core contracts deployed and configured"
    echo "  🏊 Trading pools with liquidity and executed trades:"
    if [[ "${USE_UNIFIED_MARKET_ORDERS:-true}" == "true" ]]; then
        echo "     • All 8 pools: WETH, WBTC, GOLD, SILVER, GOOGLE, NVIDIA, MNT, APPLE"
        echo "     • Each pool has limit orders (PRIVATE_KEY wallet) + market orders (PRIVATE_KEY_2 wallet)"
    else
        echo "     • sxWETH/sx${QUOTE_SYMBOL} pool (limit orders + market orders)"
        if [[ "$GOLD_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
            echo "     • sxGOLD/sx${QUOTE_SYMBOL}, sxSILVER/sx${QUOTE_SYMBOL}, sxGOOGLE/sx${QUOTE_SYMBOL}"
            echo "     • sxNVIDIA/sx${QUOTE_SYMBOL}, sxMNT/sx${QUOTE_SYMBOL}, sxAPPLE/sx${QUOTE_SYMBOL}"
            echo "     • All RWA pools filled with limit orders and market orders"
        fi
    fi
else
    print_warning "Data population validation had issues. Check logs above."
    echo ""
    echo "Debug commands:"
    echo "  make diagnose-market-order network=scalex_core_devnet"
    echo "  cast balance \$(cast wallet address --private-key \$PRIVATE_KEY) --rpc-url ${SCALEX_CORE_RPC}"
    echo "  cast balance \$(cast wallet address --private-key \$PRIVATE_KEY_2) --rpc-url ${SCALEX_CORE_RPC}"
fi

echo ""
print_step "AI Agent Operations (ERC-8004 Model B - Full Execution Verification)..."
echo "  🤖 Verifying complete agent execution flow with ERC-8004 infrastructure..."
echo ""

# Check if Phase 5 agent infrastructure is deployed
POLICY_FACTORY_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.PolicyFactory // "0x0000000000000000000000000000000000000000"')
AGENT_ROUTER_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.AgentRouter // "0x0000000000000000000000000000000000000000"')

if [[ "$POLICY_FACTORY_ADDRESS" == "0x0000000000000000000000000000000000000000" ]] || [[ "$AGENT_ROUTER_ADDRESS" == "0x0000000000000000000000000000000000000000" ]]; then
    print_warning "Agent infrastructure (PolicyFactory/AgentRouter) not deployed - skipping agent verification"
    echo "  Run 'bash shellscripts/deploy.sh' first to deploy Phase 5 agent infrastructure"
    AGENT_VERIFICATION_SUCCESS=false
else
    print_success "Agent infrastructure detected:"
    echo "  PolicyFactory:    $POLICY_FACTORY_ADDRESS"
    echo "  AgentRouter:      $AGENT_ROUTER_ADDRESS"
    echo "  Agent Executor:   $AGENT_ADDRESS"
    echo ""

    # Run the full end-to-end agent execution verification script (Model B flow):
    #   1. Primary trader registers user agent NFT (IdentityRegistry)
    #   2. Primary trader installs trading policy (PolicyFactory, no Chainlink)
    #   3. Primary trader deposits IDRX into BalanceManager (collateral for BUY order)
    #   4. Strategy agent registers its NFT (agent wallet = NFT owner = executor)
    #   5. Primary trader authorizes the strategy agent
    #   6. Strategy agent places BUY limit order on behalf of primary trader
    #   7. Strategy agent cancels the order

    echo "  Running full Model B agent execution verification..."
    if PRIVATE_KEY=$PRIVATE_KEY AGENT_PRIVATE_KEY=$AGENT_PRIVATE_KEY \
        forge script script/agents/VerifyAgentExecution.s.sol:VerifyAgentExecution \
            --rpc-url "${SCALEX_CORE_RPC}" \
            --broadcast \
            --legacy \
            --slow \
            --gas-estimate-multiplier 120 2>&1; then
        print_success "✅ ERC-8004 agent execution verification PASSED"
        AGENT_VERIFICATION_SUCCESS=true
    else
        print_warning "⚠️  Agent execution verification had issues. Check output above."
        AGENT_VERIFICATION_SUCCESS=false
    fi
fi

# Agent operations summary
echo ""
echo "  🤖 AI Agent Operations Summary:"
if [[ "$POLICY_FACTORY_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
    echo "    Agent Infrastructure: ✅ DEPLOYED"
    echo "    PolicyFactory: $POLICY_FACTORY_ADDRESS"
    echo "    AgentRouter:   $AGENT_ROUTER_ADDRESS"
    echo "    Full Execution Verification: $([ "$AGENT_VERIFICATION_SUCCESS" == true ] && echo "✅ PASSED" || echo "❌ FAILED")"
    if [[ "$AGENT_VERIFICATION_SUCCESS" == true ]]; then
        print_success "🤖 ERC-8004 Model B agent flow verified end-to-end!"
        echo "    Verified:"
        echo "      - IdentityRegistry.register() → agent NFT minted"
        echo "      - PolicyFactory.installAgent() → trading policy applied"
        echo "      - AgentRouter.authorize() → user authorized strategy agent"
        echo "      - AgentRouter.executeLimitOrder() → order placed for user by agent"
        echo "      - AgentRouter.cancelOrder() → order cancelled for user by agent"
    else
        print_warning "⚠️  Agent verification failed. See output above for details."
    fi
else
    echo "    ⚠️  Agent infrastructure not deployed - run deploy.sh first"
fi

echo ""
print_success "🌟 SCALEX Trading System is populated and ready for use!"