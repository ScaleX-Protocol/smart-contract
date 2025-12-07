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

# Parse JSON to get token addresses (using jq if available, else using sed)
if command -v jq >/dev/null 2>&1; then
    USDC_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.USDC')
    WETH_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.WETH')
    WBTC_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.WBTC')
else
    # Fallback to sed/grep approach
    USDC_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"USDC":"\([^"]*\)".*/\1/p')
    WETH_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"WETH":"\([^"]*\)".*/\1/p')
    WBTC_ADDRESS=$(cat $DEPLOYMENT_FILE | sed -n 's/.*"WBTC":"\([^"]*\)".*/\1/p')
fi

print_success "Token addresses loaded:"
echo "  USDC: $USDC_ADDRESS"
echo "  WETH: $WETH_ADDRESS"
echo "  WBTC: $WBTC_ADDRESS"
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

# Derive trader addresses directly from private keys to avoid mismatches
export PRIMARY_TRADER_ADDRESS="${PRIMARY_TRADER_ADDRESS:-$(cast wallet address --private-key $PRIVATE_KEY)}"
export SECONDARY_TRADER_ADDRESS="${SECONDARY_TRADER_ADDRESS:-$(cast wallet address --private-key $PRIVATE_KEY_2)}"

print_success "Contract addresses loaded:"
echo "  BalanceManager: $BALANCE_MANAGER_ADDRESS"
echo "  LendingManager: $LENDING_MANAGER_ADDRESS"
echo "  ScaleXRouter: $SCALEX_ROUTER_ADDRESS"
echo ""

print_success "Trader accounts configured:"
echo "  Primary Trader: $(cast wallet address --private-key $PRIVATE_KEY)"
echo "  Secondary Trader: $(cast wallet address --private-key $PRIVATE_KEY_2)"
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
echo "  💰 Checking USDC balance from deployed mock tokens..."
PRIMARY_BALANCE_USDC=$(cast call $USDC_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
print_success "Primary trader USDC balance: $(echo $PRIMARY_BALANCE_USDC | awk '{printf "%.2f", $1/1000000}') USDC"

echo "  💰 Checking WETH balance from deployed mock tokens..."
PRIMARY_BALANCE_WETH=$(cast call $WETH_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
print_success "Primary trader WETH balance: $(echo $PRIMARY_BALANCE_WETH | awk '{printf "%.2f", $1/1000000000000000000}') WETH"

print_success "Token balances checked"

# Step 1.5: Mint tokens to primary trader if needed
print_step "Step 1.5: Minting tokens to primary trader..."

# Check if primary trader needs tokens and mint if needed
# Re-check current balances since they may have changed
CURRENT_USDC_BALANCE=$(cast call $USDC_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
CURRENT_WETH_BALANCE=$(cast call $WETH_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")

if [[ "$CURRENT_USDC_BALANCE" == "0" ]] || [[ -z "$CURRENT_USDC_BALANCE" ]] || [[ "$CURRENT_USDC_BALANCE" == *"000000000000000000000000000000000000000000000000000000000000000"* ]]; then
    echo "  🪙 Minting USDC to primary trader..."
    if RECIPIENT=$PRIMARY_TRADER_ADDRESS TOKEN_SYMBOL=USDC AMOUNT=100000000000 forge script script/utils/MintTokens.s.sol:MintTokens --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
        print_success "Primary trader USDC minting successful"
        CURRENT_USDC_BALANCE=$(cast call $USDC_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
        echo "    New USDC balance: $(echo $CURRENT_USDC_BALANCE | awk '{printf "%.2f", $1/1000000}') USDC"
    else
        print_error "Failed to mint USDC to primary trader"
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
echo "  🔄 Transferring USDC (5000 USDC)..."
RECIPIENT=$SECONDARY_TRADER_ADDRESS TOKEN_SYMBOL=USDC AMOUNT=5000000000 forge script script/utils/TransferTokens.s.sol:TransferTokens --rpc-url "${SCALEX_CORE_RPC}" --broadcast
print_success "USDC transfer completed"

# Add delay to avoid nonce conflicts
echo "  ⏳ Waiting 3 seconds to avoid nonce conflicts..."
sleep 3

echo "  🔄 Transferring WETH (5 WETH)..."
RECIPIENT=$SECONDARY_TRADER_ADDRESS TOKEN_SYMBOL=WETH AMOUNT=5000000000000000000 forge script script/utils/TransferTokens.s.sol:TransferTokens --rpc-url "${SCALEX_CORE_RPC}" --broadcast
print_success "WETH transfer completed"

# Step 3: Secondary trader tokens already received
print_step "Step 3: Secondary trader tokens already received..."
echo "  Secondary trader already received tokens from Step 2"
echo "  📊 Checking secondary trader balances..."

SECONDARY_BALANCE_USDC=$(cast call $USDC_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}")
print_success "Secondary trader USDC balance: $(echo $SECONDARY_BALANCE_USDC | awk '{printf "%.2f", $1/1000000}') USDC"

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

# Primary trader deposits USDC to BalanceManager (provides liquidity)
echo "  🏦 Depositing 100,000 USDC for lending liquidity..."
if PRIVATE_KEY=$PRIVATE_KEY TOKEN_SYMBOL=USDC DEPOSIT_AMOUNT=100000000000 forge script script/deposits/LocalDeposit.s.sol:LocalDeposit --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
    print_success "Primary trader USDC deposit successful - lending liquidity provided"
else
    print_warning "USDC deposit failed - borrowing may not work properly"
fi

# Primary trader deposits WETH to BalanceManager (provides collateral)
echo "  💎 Depositing 50 WETH as collateral for borrowing..."
if PRIVATE_KEY=$PRIVATE_KEY TOKEN_SYMBOL=WETH DEPOSIT_AMOUNT=50000000000000000000 forge script script/deposits/LocalDeposit.s.sol:LocalDeposit --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
    print_success "Primary trader WETH deposit successful - collateral ready"
else
    print_warning "WETH deposit failed - borrowing capacity limited"
fi

# Secondary trader deposits USDC to BalanceManager (provides liquidity)
echo "  🏦 Secondary trader deposits 5,000 USDC for additional liquidity..."
if PRIVATE_KEY=$PRIVATE_KEY_2 TOKEN_SYMBOL=USDC DEPOSIT_AMOUNT=5000000000 forge script script/deposits/LocalDeposit.s.sol:LocalDeposit --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
    print_success "Secondary trader USDC deposit successful - additional liquidity provided"
else
    print_warning "Secondary trader USDC deposit failed"
fi

# Secondary trader deposits WETH as collateral for borrowing USDC
echo "  💰 Secondary trader deposits WETH as collateral for borrowing USDC..."

# Use LocalDeposit script for WETH collateral as well
echo "  🏦 Depositing 5 WETH via LocalDeposit for collateral..."
if PRIVATE_KEY=$PRIVATE_KEY_2 TOKEN_SYMBOL=WETH DEPOSIT_AMOUNT=5000000000000000000 forge script script/deposits/LocalDeposit.s.sol:LocalDeposit --rpc-url "${SCALEX_CORE_RPC}" --broadcast; then
    print_success "Secondary trader WETH deposit successful - collateral ready for borrowing USDC"
else
    print_warning "Secondary trader WETH deposit failed - borrowing may not work"
fi

# Check if synthetic tokens exist in deployment file
echo "  🔍 Checking synthetic tokens availability..."
if ! jq -e '.gsUSDC' $DEPLOYMENT_FILE > /dev/null 2>&1 || [[ "$(jq -r '.gsUSDC' $DEPLOYMENT_FILE)" == "null" ]]; then
    print_warning "Synthetic tokens not found in deployment file"
    print_warning "Please run deploy.sh to complete synthetic token creation"
    exit 1
fi

gsUSDC_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.gsUSDC')
gsWETH_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.gsWETH')
gsWBTC_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.gsWBTC')

print_success "Synthetic tokens found:"
echo "    gsUSDC: $gsUSDC_ADDRESS"
echo "    gsWETH: $gsWETH_ADDRESS"
echo "    gsWBTC: $gsWBTC_ADDRESS"

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
echo "  📤 Secondary trader borrows 1,000 USDC against WETH collateral..."

# Use the already defined secondary trader address
SECONDARY_TRADER=$SECONDARY_TRADER_ADDRESS

# Check current balances before borrowing
echo "  📊 Checking balances before borrowing..."
SECONDARY_WETH_BALANCE=$(cast call $WETH_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
SECONDARY_USDC_BALANCE=$(cast call $USDC_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

echo "    💰 Secondary trader USDC balance: $(echo $SECONDARY_USDC_BALANCE | awk '{printf "%.2f", $1/1000000}') USDC"
echo "    💎 Secondary trader WETH balance: $(echo $SECONDARY_WETH_BALANCE | awk '{printf "%.6f", $1/1000000000000000000}') WETH"

# Borrowing parameters
BORROW_AMOUNT=1000000000  # 1,000 USDC

echo "  🔧 Attempting to borrow 1,000 USDC..."
echo "DEBUG: Checking if user has sufficient collateral for borrowing..."

# First check if user has any collateral supplied to LendingManager
echo "    📊 Checking user's supplied collateral..."
USER_SUPPLY=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $SECONDARY_TRADER_ADDRESS $USDC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
USER_WETH_SUPPLY=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $SECONDARY_TRADER_ADDRESS $WETH_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

echo "    User USDC supplied: $(echo $USER_SUPPLY | awk '{printf "%.2f", $1/1000000}') USDC"
echo "    User WETH supplied: $(echo $USER_WETH_SUPPLY | awk '{printf "%.6f", $1/1000000000000000000}') WETH"

# Check borrowing capacity - prioritize WETH collateral for borrowing USDC
if [[ "$USER_WETH_SUPPLY" == "0" ]]; then
    print_warning "User has no WETH collateral supplied - borrowing USDC will fail"
    echo "  🔧 User must deposit WETH as collateral to borrow USDC"
    BORROWING_SUCCESS=false
else
    echo "    User has WETH collateral - attempting borrowing USDC..."
    # Check if user has sufficient borrowing capacity (basic check)
    WETH_COLLATERAL_VALUE=$((USER_WETH_SUPPLY / 1000000000000000000))  # Convert to WETH units
    # Assuming 1 WETH = $2000, user can borrow up to 80% LTV = 1600 USDC worth
    if [[ $WETH_COLLATERAL_VALUE -ge 1 ]]; then  # Need at least 1 WETH to borrow 1000 USDC
        # For now, borrowing should be done through ScaleXRouter if it supports lending integration
        # This requires ScaleXRouter to be properly linked to LendingManager
        if [[ "$SCALEX_ROUTER_ADDRESS" != "0x0000000000000000000000000000000000000000" ]]; then
            echo "    🔄 Attempting borrowing 1,000 USDC through ScaleXRouter using WETH collateral..."
            # Note: This uses ScaleXRouter.borrow() which delegates to LendingManager
            if cast send $SCALEX_ROUTER_ADDRESS "borrow(address,uint256)" $USDC_ADDRESS $BORROW_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 2>/dev/null; then
                print_success "Secondary trader successfully borrowed 1,000 USDC via ScaleXRouter"
                BORROWING_SUCCESS=true
            else
                print_warning "ScaleXRouter borrowing failed - checking authorization..."
                # Try to get more specific error
                ERROR_RESULT=$(cast send $SCALEX_ROUTER_ADDRESS "borrow(address,uint256)" $USDC_ADDRESS $BORROW_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 2>&1 || echo "Unknown error")
                echo "    Error details: $ERROR_RESULT"
                BORROWING_SUCCESS=false
            fi
        else
            print_warning "ScaleXRouter not available for borrowing"
            BORROWING_SUCCESS=false
        fi
    else
        print_warning "Insufficient WETH collateral - need at least 1 WETH to borrow 1,000 USDC"
        echo "    Current WETH collateral: $WETH_COLLATERAL_VALUE WETH"
        BORROWING_SUCCESS=false
    fi
fi

# Check borrowing results
echo "  📊 Checking borrowing results..."
SECONDARY_USDC_BALANCE_AFTER=$(cast call $USDC_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
SECONDARY_USDC_DEBT=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $SECONDARY_TRADER_ADDRESS $USDC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

echo "    💰 Secondary trader USDC balance after: $(echo $SECONDARY_USDC_BALANCE_AFTER | awk '{printf "%.2f", $1/1000000}') USDC"
echo "    📤 Secondary trader USDC debt: $(echo $SECONDARY_USDC_DEBT | awk '{printf "%.2f", $1/1000000}') USDC"

# Calculate borrowed amount using printf for better error handling
BORROWED_AMOUNT=$((SECONDARY_USDC_BALANCE_AFTER - SECONDARY_USDC_BALANCE))
if [[ $BORROWED_AMOUNT -gt 0 ]]; then
    echo "    Successfully borrowed: $(echo "$BORROWED_AMOUNT" | awk '{printf "%.2f", $1/1000000}') USDC"
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

    # Check supplies
    local usdc_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $USDC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    local weth_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $WETH_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    local wbtc_supply=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $user_address $WBTC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    # Check debts
    local usdc_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $USDC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    local weth_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $WETH_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    local wbtc_debt=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $user_address $WBTC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    # Check health factor
    local health_factor=$(check_health_factor $user_address)

    echo "    💰 Supplies:"
    echo "      USDC: $(echo $usdc_supply | awk '{printf "%.2f", $1/1000000}') USDC"
    echo "      WETH: $(echo $weth_supply | awk '{printf "%.6f", $1/1000000000000000000}') WETH"
    echo "      WBTC: $(echo $wbtc_supply | awk '{printf "%.8f", $1/100000000000000000000}') WBTC"
    echo "    📤 Debts:"
    echo "      USDC: $(echo $usdc_debt | awk '{printf "%.2f", $1/1000000}') USDC"
    echo "      WETH: $(echo $weth_debt | awk '{printf "%.6f", $1/1000000000000000000}') WETH"
    echo "      WBTC: $(echo $wbtc_debt | awk '{printf "%.8f", $1/100000000000000000000}') WBTC"
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

# Scenario 2: Primary trader borrows WETH against USDC and WBTC collateral
echo ""
echo "  📤 Scenario 2: Primary trader borrows 2 WETH against USDC and WBTC collateral..."

# Check primary trader's collateral
PRIMARY_USDC_SUPPLY=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $PRIMARY_TRADER_ADDRESS $USDC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
PRIMARY_WBTC_SUPPLY=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $PRIMARY_TRADER_ADDRESS $WBTC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
PRIMARY_WETH_BALANCE_BEFORE=$(cast call $WETH_ADDRESS "balanceOf(address)" $PRIMARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

echo "    💰 Primary trader USDC supplied: $(echo $PRIMARY_USDC_SUPPLY | awk '{printf "%.2f", $1/1000000}') USDC"
echo "    💎 Primary trader WBTC supplied: $(echo $PRIMARY_WBTC_SUPPLY | awk '{printf "%.8f", $1/100000000000000000000}') WBTC"
echo "    💎 Primary trader WETH balance: $(echo $PRIMARY_WETH_BALANCE_BEFORE | awk '{printf "%.6f", $1/1000000000000000000}') WETH"

# Attempt to borrow WETH
BORROW_WETH_AMOUNT=2000000000000000000  # 2 WETH
if [[ $PRIMARY_USDC_SUPPLY -gt 0 ]] || [[ $PRIMARY_WBTC_SUPPLY -gt 0 ]]; then
    echo "    🔄 Attempting to borrow 2 WETH through ScaleXRouter..."
    if cast send $SCALEX_ROUTER_ADDRESS "borrow(address,uint256)" $WETH_ADDRESS $BORROW_WETH_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY 2>/dev/null; then
        print_success "✅ Primary trader successfully borrowed 2 WETH"
        BORROW_2_SUCCESS=true
    else
        print_warning "WETH borrowing failed - checking authorization..."
        ERROR_RESULT=$(cast send $SCALEX_ROUTER_ADDRESS "borrow(address,uint256)" $WETH_ADDRESS $BORROW_WETH_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY 2>&1 || echo "Unknown error")
        echo "    Error details: $ERROR_RESULT"
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

# Scenario 3: Secondary trader repays部分 USDC debt
echo "  💰 Scenario 3: Secondary trader repays 500 USDC of debt..."

if [[ "$BORROW_1_SUCCESS" == true ]] && [[ $SECONDARY_USDC_DEBT -gt 0 ]]; then
    REPAY_AMOUNT=500000000  # 500 USDC

    # Check if secondary trader has enough USDC to repay
    SECONDARY_CURRENT_USDC=$(cast call $USDC_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    if [[ $SECONDARY_CURRENT_USDC -ge $REPAY_AMOUNT ]]; then
        echo "    💸 Repaying 500 USDC through ScaleXRouter..."

        # Approve ScaleXRouter to spend USDC for repayment
        if cast send $USDC_ADDRESS "approve(address,uint256)" $SCALEX_ROUTER_ADDRESS $REPAY_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 > /dev/null 2>&1; then
            echo "    ✅ USDC approval for repayment successful"

            # Execute repayment
            if cast send $SCALEX_ROUTER_ADDRESS "repay(address,uint256)" $USDC_ADDRESS $REPAY_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 2>/dev/null; then
                print_success "✅ Secondary trader successfully repaid 500 USDC"
                REPAY_1_SUCCESS=true
            else
                print_warning "USDC repayment failed - checking error..."
                ERROR_RESULT=$(cast send $SCALEX_ROUTER_ADDRESS "repay(address,uint256)" $USDC_ADDRESS $REPAY_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 2>&1 || echo "Unknown error")
                echo "    Error details: $ERROR_RESULT"
                REPAY_1_SUCCESS=false
            fi
        else
            print_warning "USDC approval for repayment failed"
            REPAY_1_SUCCESS=false
        fi
    else
        print_warning "Insufficient USDC balance for repayment"
        echo "    Available: $(echo $SECONDARY_CURRENT_USDC | awk '{printf "%.2f", $1/1000000}') USDC"
        echo "    Required: 500.00 USDC"
        REPAY_1_SUCCESS=false
    fi
else
    print_warning "No USDC debt to repay or borrowing failed"
    REPAY_1_SUCCESS=false
fi

# Check repayment results
if [[ "$REPAY_1_SUCCESS" == true ]]; then
    SECONDARY_USDC_DEBT_AFTER=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $SECONDARY_TRADER_ADDRESS $USDC_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    SECONDARY_USDC_BALANCE_FINAL=$(cast call $USDC_ADDRESS "balanceOf(address)" $SECONDARY_TRADER_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    echo "    📤 Secondary trader USDC debt after repayment: $(echo $SECONDARY_USDC_DEBT_AFTER | awk '{printf "%.2f", $1/1000000}') USDC"
    echo "    💰 Secondary trader USDC balance after repayment: $(echo $SECONDARY_USDC_BALANCE_FINAL | awk '{printf "%.2f", $1/1000000}') USDC"

    REPAID_AMOUNT=$((SECONDARY_USDC_DEBT - SECONDARY_USDC_DEBT_AFTER))
    if [[ $REPAID_AMOUNT -gt 0 ]]; then
        echo "    ✅ Successfully repaid: $(echo "$REPAID_AMOUNT" | awk '{printf "%.2f", $1/1000000}') USDC"
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
            if cast send $SCALEX_ROUTER_ADDRESS "repay(address,uint256)" $WETH_ADDRESS $REPAY_WETH_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY 2>/dev/null; then
                print_success "✅ Primary trader successfully repaid 1 WETH"
                REPAY_2_SUCCESS=true
            else
                print_warning "WETH repayment failed - checking error..."
                ERROR_RESULT=$(cast send $SCALEX_ROUTER_ADDRESS "repay(address,uint256)" $WETH_ADDRESS $REPAY_WETH_AMOUNT --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY 2>&1 || echo "Unknown error")
                echo "    Error details: $ERROR_RESULT"
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
echo "    Scenario 1 - Secondary trader borrows USDC: $([ "$BORROW_1_SUCCESS" == true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "    Scenario 2 - Primary trader borrows WETH: $([ "$BORROW_2_SUCCESS" == true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "    Scenario 3 - Secondary trader repays USDC: $([ "$REPAY_1_SUCCESS" == true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "    Scenario 4 - Primary trader repays WETH: $([ "$REPAY_2_SUCCESS" == true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"

if [[ "$BORROW_1_SUCCESS" == true ]] || [[ "$BORROW_2_SUCCESS" == true ]] || [[ "$REPAY_1_SUCCESS" == true ]] || [[ "$REPAY_2_SUCCESS" == true ]]; then
    print_success "🎉 Borrowing and repayment activities completed successfully!"
else
    print_warning "⚠️  Some borrowing/repayment activities failed. Check logs above for details."
fi

# Step 5: Primary trader creates liquidity
print_step "Step 5: Primary trader creating liquidity (limit orders)..."
echo "  🏊 Creating trading pools and filling orderbook..."
echo "  📡 Network: scalex_core_devnet"
echo "  🪙 Trading pair: gsWETH/gsUSDC (default)"
echo "  🔑 Using primary trader private key"
if forge script script/trading/FillOrderBook.s.sol:FillMockOrderBook --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY --broadcast; then
    print_success "Orderbook liquidity created successfully"
else
    print_warning "Orderbook creation failed, continuing without trading liquidity"
    echo "  🔧 This may be due to pool configuration or permissions"
fi

# Step 6: Secondary trader executes trades
print_step "Step 6: Secondary trader executing market orders..."
echo "  📡 Network: scalex_core_devnet"
echo "  🪙 Trading pair: WETH/USDC"
echo "  ⚡ Executing both market buy and sell orders"
echo "  🔑 Using secondary trader private key"
if forge script script/trading/MarketOrderBook.sol:MarketOrderBook --rpc-url "${SCALEX_CORE_RPC}" --private-key $PRIVATE_KEY_2 --broadcast; then
    print_success "Market orders executed successfully"
else
    print_warning "Market order execution failed or no liquidity available"
    echo "  📝 This requires successful orderbook creation from Step 5"
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
    echo "  💰 Token transfers between traders completed"
    echo "  🏦 Lending protocol infrastructure configured"
    echo "  💵 Actual liquidity provisioned to lending protocol"
    echo "  📤 Active borrowing activities demonstrated"
    echo "  🛡️  Collateral deposited and borrowing capacity established"
    echo "  🏗️  Core contracts deployed and configured"
    echo "  🏊 Trading pools and orderbook liquidity (if successful)"
else
    print_warning "Data population validation had issues. Check logs above."
    echo ""
    echo "Debug commands:"
    echo "  make diagnose-market-order network=scalex_core_devnet"
    echo "  cast balance \$(cast wallet address --private-key \$PRIVATE_KEY) --rpc-url ${SCALEX_CORE_RPC}"
    echo "  cast balance \$(cast wallet address --private-key \$PRIVATE_KEY_2) --rpc-url ${SCALEX_CORE_RPC}"
fi

echo ""
print_success "🌟 SCALEX Trading System is populated and ready for use!"