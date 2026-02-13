#!/bin/bash

# Generate encoded policy calldata using the PolicyInstaller

source .env

INSTALLER="0x494456B0e3899F4D7163FEc924941dfDC149f027"
POLICY_FACTORY="0x4605f626dF4A684139186B7fF15C8cABD8178EC8"
AGENT_ID="100"
PRIMARY_KEY="$PRIMARY_WALLET_KEY"

echo "Getting encoded policy from PolicyInstaller..."
echo ""

# Call the contract to get the policy struct, but don't execute
# We'll use cast call to simulate and get the calldata
CALLDATA=$(cast calldata "installPermissivePolicy(uint256)" $AGENT_ID)

echo "Calldata for installPermissivePolicy: $CALLDATA"
echo ""

# Now we need to extract what the contract would call on PolicyFactory
# This is complex, so let's try a different approach:
# Use cast to call the installer with --trace to see what it would do

echo "Simulating the call to see the policy data..."
cast call $INSTALLER $CALLDATA --rpc-url $SCALEX_CORE_RPC --trace 2>&1 | grep -A 50 "installAgent"

echo ""
echo "Unfortunately, we need the actual encoded Policy struct"
echo "which is too complex to encode manually with cast."
echo ""
echo "Alternative: Deploy a modified PolicyInstaller that returns the policy"
echo "or use a Solidity script once forge is working."
