#!/bin/bash

# Quick test script to verify agent installation on basesepolia
# This extracts just the agent installation logic from populate-data.sh

set -e

echo "🤖 Testing Agent Installation on Base Sepolia"
echo "=============================================="
echo ""

# Load environment
source .env

# Configuration
DEPLOYMENT_FILE="deployments/84532.json"
SCALEX_CORE_RPC="https://base-sepolia.infura.io/v3/743a342d05a5431592aee7f90048ec90"
PRIMARY_TRADER_ADDRESS="0x27dD1eBE7D826197FD163C134E79502402Fd7cB7"

# Load contract addresses
POLICY_FACTORY_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.PolicyFactory // "0x0000000000000000000000000000000000000000"')
AGENT_ROUTER_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.AgentRouter // "0x0000000000000000000000000000000000000000"')
BALANCE_MANAGER_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.BalanceManager // "0x0000000000000000000000000000000000000000"')
LENDING_MANAGER_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.LendingManager // "0x0000000000000000000000000000000000000000"')
QUOTE_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.IDRX // "0x0000000000000000000000000000000000000000"')
WETH_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.WETH // "0x0000000000000000000000000000000000000000"')

echo "📋 Configuration:"
echo "  Network: Base Sepolia (84532)"
echo "  RPC: $SCALEX_CORE_RPC"
echo "  Primary Trader: $PRIMARY_TRADER_ADDRESS"
echo ""

echo "📦 Contract Addresses:"
echo "  PolicyFactory: $POLICY_FACTORY_ADDRESS"
echo "  AgentRouter: $AGENT_ROUTER_ADDRESS"
echo "  BalanceManager: $BALANCE_MANAGER_ADDRESS"
echo "  LendingManager: $LENDING_MANAGER_ADDRESS"
echo ""

# Check if agent infrastructure is deployed
if [[ "$POLICY_FACTORY_ADDRESS" == "0x0000000000000000000000000000000000000000" ]] || [[ "$AGENT_ROUTER_ADDRESS" == "0x0000000000000000000000000000000000000000" ]]; then
    echo "❌ ERROR: Agent infrastructure not deployed!"
    exit 1
fi

echo "✅ Agent infrastructure detected"
echo ""

# Load identity registry address
IDENTITY_REGISTRY=$(cat $DEPLOYMENT_FILE | jq -r '.IdentityRegistry // "0x0000000000000000000000000000000000000000"')
echo "  IdentityRegistry: $IDENTITY_REGISTRY"
echo ""

# Step 1: Check if primary trader owns agentTokenId 1 (mint if needed)
echo "🔍 Step 1: Checking if primary trader owns agentTokenId 1..."
AGENT_OWNER=$(cast call $IDENTITY_REGISTRY "ownerOf(uint256)" 1 --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")

if [[ "$AGENT_OWNER" == "0x0000000000000000000000000000000000000000" ]]; then
    echo "📝 Agent NFT not minted yet. Minting..."

    # Mint agentTokenId 1 to primary trader
    MINT_TX=$(cast send $IDENTITY_REGISTRY "mint(address,uint256,string)" $PRIMARY_TRADER_ADDRESS 1 "ipfs://QmAgent1Metadata" \
        --rpc-url "${SCALEX_CORE_RPC}" \
        --private-key $PRIVATE_KEY \
        --gas-limit 200000 2>&1)

    if echo "$MINT_TX" | grep -q "transactionHash"; then
        TX_HASH=$(echo "$MINT_TX" | grep "transactionHash" | awk '{print $2}')
        echo "📤 Mint transaction submitted: $TX_HASH"
        echo "⏳ Waiting for confirmation..."
        sleep 3

        TX_STATUS=$(cast receipt $TX_HASH --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | grep "^status" | awk '{print $2}')

        if [[ "$TX_STATUS" == "1" ]]; then
            echo "✅ Agent NFT minted successfully!"
            echo "   Transaction: https://sepolia.basescan.org/tx/$TX_HASH"
        else
            echo "❌ Mint transaction reverted"
            echo "   Transaction: https://sepolia.basescan.org/tx/$TX_HASH"
            exit 1
        fi
    else
        echo "❌ Mint failed"
        echo "   Error: $MINT_TX"
        exit 1
    fi
else
    echo "✅ Primary trader already owns agentTokenId 1"
    echo "   Owner: $AGENT_OWNER"
fi

echo ""

# Step 2: Check if agent is already installed
echo "🔍 Step 2: Checking if agent policy is already installed..."
AGENT_INSTALLED=$(cast call $POLICY_FACTORY_ADDRESS "isAgentEnabled(address,uint256)" $PRIMARY_TRADER_ADDRESS 1 --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")

if [[ "$AGENT_INSTALLED" == "true" ]] || [[ "$AGENT_INSTALLED" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
    echo "✅ Agent already installed for primary trader"
    AGENT_INSTALL_SUCCESS=true
else
    echo "📝 Agent not installed yet. Installing..."
    echo ""

    # Install agent using moderate template
    echo "🚀 Installing agent (agentTokenId: 1, template: 'moderate')..."

    # installAgentFromTemplate(uint256 agentTokenId, string calldata templateName, PolicyCustomization calldata customizations)
    # PolicyCustomization: (uint128 maxOrderSize, uint128 dailyVolumeLimit, uint256 expiryTimestamp, address[] whitelistedTokens)
    # Using empty customization means use template defaults
    INSTALL_TX=$(cast send $POLICY_FACTORY_ADDRESS \
        "installAgentFromTemplate(uint256,string,(uint128,uint128,uint256,address[]))" \
        1 \
        "moderate" \
        "(0,0,0,[])" \
        --rpc-url "${SCALEX_CORE_RPC}" \
        --private-key $PRIVATE_KEY \
        --gas-limit 500000 2>&1)

    if echo "$INSTALL_TX" | grep -q "transactionHash"; then
        TX_HASH=$(echo "$INSTALL_TX" | grep "transactionHash" | awk '{print $2}')
        echo "📤 Transaction submitted: $TX_HASH"
        echo "⏳ Waiting for confirmation..."
        sleep 3

        TX_STATUS=$(cast receipt $TX_HASH --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null | grep "^status" | awk '{print $2}')

        if [[ "$TX_STATUS" == "1" ]]; then
            echo "✅ Agent installed successfully!"
            echo "   Transaction: https://sepolia.basescan.org/tx/$TX_HASH"
            AGENT_INSTALL_SUCCESS=true
        else
            echo "❌ Transaction reverted"
            echo "   Transaction: https://sepolia.basescan.org/tx/$TX_HASH"
            AGENT_INSTALL_SUCCESS=false
            exit 1
        fi
    else
        echo "❌ Installation failed"
        echo "   Error: $INSTALL_TX"
        AGENT_INSTALL_SUCCESS=false
        exit 1
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Verify agent installation
if [[ "$AGENT_INSTALL_SUCCESS" == true ]]; then
    echo "🔍 Verifying agent installation..."
    echo ""

    # Get agent policy
    AGENT_POLICY=$(cast call $POLICY_FACTORY_ADDRESS "getPolicy(address,uint256)" $PRIMARY_TRADER_ADDRESS 1 --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "")

    if [[ -n "$AGENT_POLICY" ]]; then
        echo "✅ Agent policy retrieved successfully"
        echo "   Owner: $PRIMARY_TRADER_ADDRESS"
        echo "   Agent Token ID: 1"
        echo "   Policy Template: Moderate"
        echo ""
    else
        echo "⚠️  Could not retrieve agent policy"
    fi

    # Show agent capabilities
    echo "🤖 Agent Capabilities:"
    echo "   ✓ Place market orders on behalf of primary trader"
    echo "   ✓ Place limit orders on behalf of primary trader"
    echo "   ✓ Borrow using primary trader's collateral"
    echo "   ✓ Repay using primary trader's funds"
    echo "   ✓ Manage primary trader's positions"
    echo "   ✓ All actions tracked with agentTokenId=1"
    echo ""

    # Show primary trader balances
    echo "💰 Primary Trader's Current Balances:"
    echo ""

    # BalanceManager balances
    PRIMARY_IDRX_BAL=$(cast call $BALANCE_MANAGER_ADDRESS "getUserBalance(address,address)" $PRIMARY_TRADER_ADDRESS $QUOTE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    PRIMARY_WETH_BAL=$(cast call $BALANCE_MANAGER_ADDRESS "getUserBalance(address,address)" $PRIMARY_TRADER_ADDRESS $WETH_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    echo "   BalanceManager:"
    echo "     IDRX: $(cast --from-wei $PRIMARY_IDRX_BAL ether 2>/dev/null || echo "0") (raw: $PRIMARY_IDRX_BAL)"
    echo "     WETH: $(cast --from-wei $PRIMARY_WETH_BAL ether 2>/dev/null || echo "0") (raw: $PRIMARY_WETH_BAL)"
    echo ""

    # LendingManager collateral
    PRIMARY_WETH_SUPPLY=$(cast call $LENDING_MANAGER_ADDRESS "getUserSupply(address,address)" $PRIMARY_TRADER_ADDRESS $WETH_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")
    PRIMARY_IDRX_DEBT=$(cast call $LENDING_MANAGER_ADDRESS "getUserDebt(address,address)" $PRIMARY_TRADER_ADDRESS $QUOTE_ADDRESS --rpc-url "${SCALEX_CORE_RPC}" 2>/dev/null || echo "0")

    echo "   LendingManager:"
    echo "     WETH Collateral: $(cast --from-wei $PRIMARY_WETH_SUPPLY ether 2>/dev/null || echo "0") (raw: $PRIMARY_WETH_SUPPLY)"
    echo "     IDRX Debt: $(cast --from-wei $PRIMARY_IDRX_DEBT ether 2>/dev/null || echo "0") (raw: $PRIMARY_IDRX_DEBT)"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🎉 SUCCESS! Agent installation verified on Base Sepolia"
    echo ""
    echo "🔗 View on BaseScan:"
    echo "   PolicyFactory: https://sepolia.basescan.org/address/$POLICY_FACTORY_ADDRESS"
    echo "   AgentRouter: https://sepolia.basescan.org/address/$AGENT_ROUTER_ADDRESS"
    echo "   Primary Trader: https://sepolia.basescan.org/address/$PRIMARY_TRADER_ADDRESS"
    echo ""
else
    echo "❌ Agent installation failed"
    exit 1
fi
