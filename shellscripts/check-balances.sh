#!/bin/bash

# Check Token Balances Script
# Usage: ./shellscripts/check-balances.sh <account_address>

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if account address is provided
if [ $# -ne 1 ]; then
    print_error "Usage: $0 <account_address>"
    print_info "Example: $0 0x1234567890123456789012345678901234567890"
    exit 1
fi

ACCOUNT_ADDRESS=$1

# Validate account address format (basic check)
if [[ ! $ACCOUNT_ADDRESS =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    print_error "Invalid account address format. Please provide a valid Ethereum address."
    exit 1
fi

print_info "Checking token balances for account: $ACCOUNT_ADDRESS"
echo

# Export the account address for use in the Solidity script
export ACCOUNT_ADDRESS=$ACCOUNT_ADDRESS

# Check Core Chain (31337) balances
print_info "Checking Core Chain (31337) - gsWETH and gsUSDC balances..."
if forge script script/utils/CheckTokenBalances.s.sol:CheckTokenBalances --rpc-url https://core-devnet.scalex.money --legacy; then
    print_success "Core chain balance check completed"
else
    print_error "Failed to check core chain balances"
fi

echo
echo "=================================================="
echo

# Check Side Chain (31337) balances  
print_info "Checking Side Chain (31337) - WETH and USDC balances..."
if forge script script/utils/CheckTokenBalances.s.sol:CheckTokenBalances --rpc-url https://side-devnet.scalex.money --legacy; then
    print_success "Side chain balance check completed"
else
    print_error "Failed to check side chain balances"
fi

echo
print_success "Balance check completed for both chains!"