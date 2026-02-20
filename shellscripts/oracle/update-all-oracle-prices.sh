#!/bin/bash

set -e

# Source quote currency configuration module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/quote-currency-config.sh"

CHAIN_ID="${CORE_CHAIN_ID:-4202}"
DEPLOYMENT_FILE="deployments/${CHAIN_ID}.json"
RPC_URL="${SCALEX_CORE_RPC:-https://lisk-sepolia.drpc.org}"
PRIVATE_KEY="${PRIVATE_KEY:-0x5d34b3f860c2b09c112d68a35d592dfb599841629c9b0ad8827269b94b57efca}"

echo "🔄 Updating all Oracle prices..."
echo ""

# Load quote currency configuration
load_quote_currency_config

# Get synthetic quote token key
SYNTHETIC_QUOTE_KEY=$(get_synthetic_quote_key)

# Load addresses
ORACLE=$(jq -r '.Oracle' $DEPLOYMENT_FILE)
sxQUOTE=$(jq -r ".$SYNTHETIC_QUOTE_KEY" $DEPLOYMENT_FILE)
sxWETH=$(jq -r '.sxWETH' $DEPLOYMENT_FILE)
sxWBTC=$(jq -r '.sxWBTC' $DEPLOYMENT_FILE)
sxGOLD=$(jq -r '.sxGOLD // "0x0"' $DEPLOYMENT_FILE)
sxSILVER=$(jq -r '.sxSILVER // "0x0"' $DEPLOYMENT_FILE)
sxGOOGLE=$(jq -r '.sxGOOGLE // "0x0"' $DEPLOYMENT_FILE)
sxNVIDIA=$(jq -r '.sxNVIDIA // "0x0"' $DEPLOYMENT_FILE)
sxMNT=$(jq -r '.sxMNT // "0x0"' $DEPLOYMENT_FILE)
sxAPPLE=$(jq -r '.sxAPPLE // "0x0"' $DEPLOYMENT_FILE)

echo "Oracle: $ORACLE"
echo ""

# Update crypto tokens
echo "Updating $SYNTHETIC_QUOTE_KEY price..."
cast send $ORACLE "updatePrice(address)" $sxQUOTE --rpc-url $RPC_URL --private-key $PRIVATE_KEY > /dev/null 2>&1 && echo "✅ $SYNTHETIC_QUOTE_KEY updated"

echo "Updating sxWETH price..."
cast send $ORACLE "updatePrice(address)" $sxWETH --rpc-url $RPC_URL --private-key $PRIVATE_KEY > /dev/null 2>&1 && echo "✅ sxWETH updated"

echo "Updating sxWBTC price..."
cast send $ORACLE "updatePrice(address)" $sxWBTC --rpc-url $RPC_URL --private-key $PRIVATE_KEY > /dev/null 2>&1 && echo "✅ sxWBTC updated"

# Update RWA tokens if they exist
if [[ "$sxGOLD" != "0x0" ]] && [[ "$sxGOLD" != "null" ]]; then
    echo "Updating sxGOLD price..."
    cast send $ORACLE "updatePrice(address)" $sxGOLD --rpc-url $RPC_URL --private-key $PRIVATE_KEY > /dev/null 2>&1 && echo "✅ sxGOLD updated"
fi

if [[ "$sxSILVER" != "0x0" ]] && [[ "$sxSILVER" != "null" ]]; then
    echo "Updating sxSILVER price..."
    cast send $ORACLE "updatePrice(address)" $sxSILVER --rpc-url $RPC_URL --private-key $PRIVATE_KEY > /dev/null 2>&1 && echo "✅ sxSILVER updated"
fi

if [[ "$sxGOOGLE" != "0x0" ]] && [[ "$sxGOOGLE" != "null" ]]; then
    echo "Updating sxGOOGLE price..."
    cast send $ORACLE "updatePrice(address)" $sxGOOGLE --rpc-url $RPC_URL --private-key $PRIVATE_KEY > /dev/null 2>&1 && echo "✅ sxGOOGLE updated"
fi

if [[ "$sxNVIDIA" != "0x0" ]] && [[ "$sxNVIDIA" != "null" ]]; then
    echo "Updating sxNVIDIA price..."
    cast send $ORACLE "updatePrice(address)" $sxNVIDIA --rpc-url $RPC_URL --private-key $PRIVATE_KEY > /dev/null 2>&1 && echo "✅ sxNVIDIA updated"
fi

if [[ "$sxMNT" != "0x0" ]] && [[ "$sxMNT" != "null" ]]; then
    echo "Updating sxMNT price..."
    cast send $ORACLE "updatePrice(address)" $sxMNT --rpc-url $RPC_URL --private-key $PRIVATE_KEY > /dev/null 2>&1 && echo "✅ sxMNT updated"
fi

if [[ "$sxAPPLE" != "0x0" ]] && [[ "$sxAPPLE" != "null" ]]; then
    echo "Updating sxAPPLE price..."
    cast send $ORACLE "updatePrice(address)" $sxAPPLE --rpc-url $RPC_URL --private-key $PRIVATE_KEY > /dev/null 2>&1 && echo "✅ sxAPPLE updated"
fi

echo ""
echo "✅ All oracle prices updated!"
