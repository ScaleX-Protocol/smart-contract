#!/usr/bin/env bash

#############################################################################
# update-env.sh - Update environment files across projects after deployment
#
# This script updates contract addresses in:
# - clob-indexer/ponder/.env.<chain-name>
# - mm-bot/.env.<chain-name>
# - frontend/apps/web/src/configs/contracts.ts
#
# Usage:
#   ./update-env.sh <chain-id> [deployment-output-file]
#   ./update-env.sh 84532                    # Interactive mode
#   ./update-env.sh 84532 deployment.log     # Parse from log file
#
# Examples:
#   ./update-env.sh 84532                    # Update base-sepolia configs
#   ./update-env.sh 1116                     # Update core-chain configs
#   ./update-env.sh 5003                     # Update mantle-sepolia configs
#############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

#############################################################################
# Chain ID to Chain Name Mapping
#############################################################################
get_chain_name() {
    local chain_id="$1"
    case "$chain_id" in
        84532) echo "base-sepolia" ;;
        1116) echo "core-chain" ;;
        5003) echo "mantle-sepolia" ;;
        11155111) echo "sepolia" ;;
        1) echo "mainnet" ;;
        31337) echo "local" ;;
        31338) echo "anvil" ;;
        *) echo "" ;;
    esac
}

get_all_chain_ids() {
    echo "84532 -> base-sepolia"
    echo "1116 -> core-chain"
    echo "5003 -> mantle-sepolia"
    echo "11155111 -> sepolia"
    echo "1 -> mainnet"
    echo "31337 -> local"
    echo "31338 -> anvil"
}

#############################################################################
# Helper Functions
#############################################################################
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_section() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

#############################################################################
# Parse deployment output or prompt for addresses
#############################################################################
get_contract_addresses() {
    local deployment_file="$1"
    
    if [[ -n "$deployment_file" && -f "$deployment_file" ]]; then
        print_info "Parsing deployment file: $deployment_file"
        
        # Extract addresses from deployment output
        BALANCE_MANAGER=$(grep -E "BalanceManager:|BALANCE_MANAGER" "$deployment_file" | grep -oE "0x[a-fA-F0-9]{40}" | head -1 || echo "")
        SCALEX_ROUTER=$(grep -E "ScaleXRouter:|SCALEX_ROUTER" "$deployment_file" | grep -oE "0x[a-fA-F0-9]{40}" | head -1 || echo "")
        POOL_MANAGER=$(grep -E "PoolManager:|POOL_MANAGER" "$deployment_file" | grep -oE "0x[a-fA-F0-9]{40}" | head -1 || echo "")
        FAUCET=$(grep -E "Faucet:|FAUCET_ADDRESS" "$deployment_file" | grep -oE "0x[a-fA-F0-9]{40}" | head -1 || echo "")
        LENDING_MANAGER=$(grep -E "LendingManager:|LENDING_MANAGER" "$deployment_file" | grep -oE "0x[a-fA-F0-9]{40}" | head -1 || echo "")
        ORACLE=$(grep -E "Oracle:|ORACLE_ADDRESS" "$deployment_file" | grep -oE "0x[a-fA-F0-9]{40}" | head -1 || echo "")
        TOKEN_REGISTRY=$(grep -E "TokenRegistry:|TOKEN_REGISTRY" "$deployment_file" | grep -oE "0x[a-fA-F0-9]{40}" | head -1 || echo "")
    else
        print_info "Enter contract addresses (press Enter to skip):"
        
        read -p "BalanceManager address: " BALANCE_MANAGER
        read -p "ScaleXRouter address: " SCALEX_ROUTER
        read -p "PoolManager address: " POOL_MANAGER
        read -p "Faucet address (optional): " FAUCET
        read -p "LendingManager address (optional): " LENDING_MANAGER
        read -p "Oracle address (optional): " ORACLE
        read -p "TokenRegistry address (optional): " TOKEN_REGISTRY
    fi
    
    # Validate required addresses
    if [[ -z "$BALANCE_MANAGER" || -z "$SCALEX_ROUTER" || -z "$POOL_MANAGER" ]]; then
        print_error "Required addresses missing (BalanceManager, ScaleXRouter, PoolManager)"
        return 1
    fi
    
    print_section "Contract Addresses"
    echo "BalanceManager:   $BALANCE_MANAGER"
    echo "ScaleXRouter:     $SCALEX_ROUTER"
    echo "PoolManager:      $POOL_MANAGER"
    [[ -n "$FAUCET" ]] && echo "Faucet:           $FAUCET"
    [[ -n "$LENDING_MANAGER" ]] && echo "LendingManager:   $LENDING_MANAGER"
    [[ -n "$ORACLE" ]] && echo "Oracle:           $ORACLE"
    [[ -n "$TOKEN_REGISTRY" ]] && echo "TokenRegistry:    $TOKEN_REGISTRY"
    
    return 0
}

#############################################################################
# Get START_BLOCK from deployment JSON
#############################################################################
get_start_block() {
    local chain_id="$1"
    local deployment_json="$PROJECT_ROOT/deployments/${chain_id}.json"
    
    START_BLOCK=""
    USDC_ADDRESS=""
    
    # Try to get block number from deployment JSON
    if [[ -f "$deployment_json" ]]; then
        print_info "Checking deployment JSON: $deployment_json"
        
        # Extract block number and USDC address
        if command -v jq >/dev/null 2>&1; then
            START_BLOCK=$(jq -r '.blockNumber // empty' "$deployment_json" 2>/dev/null || echo "")
            USDC_ADDRESS=$(jq -r '.USDC // empty' "$deployment_json" 2>/dev/null || echo "")
            
            if [[ -n "$START_BLOCK" ]]; then
                print_success "Found START_BLOCK from deployment: $START_BLOCK"
            fi
        else
            print_warning "jq not installed - cannot parse deployment JSON"
        fi
    else
        print_warning "Deployment JSON not found: $deployment_json"
    fi
    
    # If no block found, prompt user
    if [[ -z "$START_BLOCK" ]]; then
        print_info "START_BLOCK not found in deployment file"
        read -p "Enter START_BLOCK manually (or press Enter to skip): " START_BLOCK
    fi
    
    if [[ -n "$START_BLOCK" ]]; then
        echo "START_BLOCK:      $START_BLOCK"
    else
        print_warning "START_BLOCK not set - indexer env will not be updated with block number"
    fi
}

#############################################################################
# Update clob-indexer .env file
#############################################################################
update_indexer_env() {
    local chain_name="$1"
    local env_file="$PROJECT_ROOT/../clob-indexer/ponder/.env.$chain_name"
    
    print_section "Updating Indexer Environment"
    
    if [[ ! -f "$env_file" ]]; then
        print_warning "File not found: $env_file"
        read -p "Create new file? (y/n): " create_file
        if [[ "$create_file" != "y" ]]; then
            print_info "Skipping indexer update"
            return 0
        fi
        touch "$env_file"
    fi
    
    print_info "Updating: $env_file"
    
    # Create backup
    cp "$env_file" "$env_file.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update or append addresses
    update_or_append() {
        local key="$1"
        local value="$2"
        local file="$3"
        
        if grep -q "^${key}=" "$file" 2>/dev/null; then
            # Update existing line
            sed -i.tmp "s|^${key}=.*|${key}=${value}|" "$file"
            rm -f "$file.tmp"
            print_success "Updated $key"
        else
            # Append new line
            echo "${key}=${value}" >> "$file"
            print_success "Added $key"
        fi
    }
    
    update_or_append "POOLMANAGER_CONTRACT_RARI_ADDRESS" "$POOL_MANAGER" "$env_file"
    update_or_append "BALANCEMANAGER_CONTRACT_RARI_ADDRESS" "$BALANCE_MANAGER" "$env_file"
    update_or_append "ScaleXROUTER_CONTRACT_RARI_ADDRESS" "$SCALEX_ROUTER" "$env_file"
    
    [[ -n "$LENDING_MANAGER" ]] && update_or_append "LENDINGMANAGER_CONTRACT_ADDRESS" "$LENDING_MANAGER" "$env_file"
    [[ -n "$ORACLE" ]] && update_or_append "ORACLE_CONTRACT_ADDRESS" "$ORACLE" "$env_file"
    [[ -n "$TOKEN_REGISTRY" ]] && update_or_append "TOKENREGISTRY_CONTRACT_ADDRESS" "$TOKEN_REGISTRY" "$env_file"
    
    # Update START_BLOCK if available
    if [[ -n "$START_BLOCK" ]]; then
        update_or_append "START_BLOCK" "$START_BLOCK" "$env_file"
        update_or_append "SCALEX_CORE_DEVNET_START_BLOCK" "$START_BLOCK" "$env_file"
        update_or_append "FAUCET_START_BLOCK" "$START_BLOCK" "$env_file"
        print_success "Updated START_BLOCK variables to $START_BLOCK"
    fi
    
    print_success "Indexer environment updated successfully"
}

#############################################################################
# Update mm-bot .env file
#############################################################################
update_mmbot_env() {
    local chain_name="$1"
    local env_file="$PROJECT_ROOT/../mm-bot/.env.$chain_name"
    
    print_section "Updating MM-Bot Environment"
    
    if [[ ! -f "$env_file" ]]; then
        print_warning "File not found: $env_file"
        read -p "Create new file? (y/n): " create_file
        if [[ "$create_file" != "y" ]]; then
            print_info "Skipping mm-bot update"
            return 0
        fi
        touch "$env_file"
    fi
    
    print_info "Updating: $env_file"
    
    # Create backup
    cp "$env_file" "$env_file.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update or append addresses
    update_or_append() {
        local key="$1"
        local value="$2"
        local file="$3"
        
        if grep -q "^${key}=" "$file" 2>/dev/null; then
            sed -i.tmp "s|^${key}=.*|${key}=${value}|" "$file"
            rm -f "$file.tmp"
            print_success "Updated $key"
        else
            echo "${key}=${value}" >> "$file"
            print_success "Added $key"
        fi
    }
    
    update_or_append "PROXY_POOL_MANAGER" "$POOL_MANAGER" "$env_file"
    update_or_append "PROXY_GTX_ROUTER" "$SCALEX_ROUTER" "$env_file"
    update_or_append "PROXY_BALANCE_MANAGER" "$BALANCE_MANAGER" "$env_file"
    
    print_success "MM-Bot environment updated successfully"
}

#############################################################################
# Update frontend contracts.ts
#############################################################################
update_frontend_config() {
    local chain_id="$1"
    local contracts_file="/Users/renaka/gtx/frontend/apps/web/src/configs/contracts.ts"
    
    print_section "Updating Frontend Contracts Config"
    
    if [[ ! -f "$contracts_file" ]]; then
        print_error "File not found: $contracts_file"
        return 1
    fi
    
    print_info "Updating: $contracts_file"
    
    # Create backup
    cp "$contracts_file" "$contracts_file.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Check if chain ID already exists in the config
    if grep -q "^    ${chain_id}:" "$contracts_file"; then
        print_info "Chain ID $chain_id found in config, updating addresses..."
        
        # Update existing chain config using sed
        # This is a simplified approach - might need adjustment based on exact file format
        sed -i.tmp "/^    ${chain_id}:/,/^    }/s|balanceManagerAddress: '0x[a-fA-F0-9]*'|balanceManagerAddress: '${BALANCE_MANAGER}'|" "$contracts_file"
        sed -i.tmp "/^    ${chain_id}:/,/^    }/s|scaleXRouterAddress: '0x[a-fA-F0-9]*'|scaleXRouterAddress: '${SCALEX_ROUTER}'|" "$contracts_file"
        sed -i.tmp "/^    ${chain_id}:/,/^    }/s|poolManagerAddress: '0x[a-fA-F0-9]*'|poolManagerAddress: '${POOL_MANAGER}'|" "$contracts_file"
        
        if [[ -n "$FAUCET" ]]; then
            sed -i.tmp "/^    ${chain_id}:/,/^    }/s|faucetAddress: '0x[a-fA-F0-9]*'|faucetAddress: '${FAUCET}'|" "$contracts_file"
        fi
        
        rm -f "$contracts_file.tmp"
        print_success "Updated chain $chain_id configuration"
    else
        print_warning "Chain ID $chain_id not found in config"
        print_info "You may need to manually add the chain configuration"
        
        echo -e "\nAdd this to contracts.ts:"
        echo "    ${chain_id}: {"
        echo "        faucetAddress: '${FAUCET:-0x0000000000000000000000000000000000000000}' as HexAddress,"
        echo "        balanceManagerAddress: '${BALANCE_MANAGER}' as HexAddress,"
        echo "        scaleXRouterAddress: '${SCALEX_ROUTER}' as HexAddress,"
        echo "        poolManagerAddress: '${POOL_MANAGER}' as HexAddress"
        echo "    }"
    fi
    
    print_success "Frontend config update completed"
}

#############################################################################
# Main execution
#############################################################################
main() {
    print_section "Contract Address Update Script"
    
    # Check arguments
    if [[ $# -lt 1 ]]; then
        print_error "Usage: $0 <chain-id> [deployment-output-file]"
        echo ""
        echo "Available chain IDs:"
        get_all_chain_ids | while read line; do
            echo "  $line"
        done
        exit 1
    fi
    
    local chain_id="$1"
    local deployment_file="${2:-}"
    
    # Get chain name from ID
    local chain_name=$(get_chain_name "$chain_id")
    if [[ -z "$chain_name" ]]; then
        print_error "Unknown chain ID: $chain_id"
        echo "Available chain IDs:"
        get_all_chain_ids
        exit 1
    fi
    
    print_info "Chain ID: $chain_id"
    print_info "Chain Name: $chain_name"
    
    # Get contract addresses
    if ! get_contract_addresses "$deployment_file"; then
        exit 1
    fi
    
    # Get START_BLOCK from deployment JSON or user input
    get_start_block "$chain_id"
    
    # Confirm before proceeding
    echo ""
    read -p "Proceed with updates? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        print_warning "Update cancelled"
        exit 0
    fi
    
    # Update all configs
    update_indexer_env "$chain_name"
    update_mmbot_env "$chain_name"
    update_frontend_config "$chain_id"
    
    print_section "Update Complete"
    print_success "All configurations have been updated successfully!"
    print_info "Backups were created with timestamp suffix"
    
    echo -e "\nNext steps:"
    echo "1. Review the changes in each file"
    echo "2. Test the configurations"
    echo "3. Commit the changes to git"
}

# Run main function
main "$@"
