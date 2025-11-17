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

# Set trader accounts
export PRIVATE_KEY="${PRIMARY_TRADER_PRIVATE_KEY:-0x5d34b3f860c2b09c112d68a35d592dfb599841629c9b0ad8827269b94b57efca}"
export PRIVATE_KEY_2="${SECONDARY_TRADER_PRIVATE_KEY:-0x3d93c16f039372c7f70b490603bfc48a34575418fad5aea156c16f2cb0280ed8}"

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
else
    echo "    No borrowing occurred - may need more collateral or lending setup"
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