#!/bin/bash

# Check Agent Wallet Balances
# Shows ETH and IDRX balances for all agent wallets

source .env

RPC="${SCALEX_CORE_RPC}"
IDRX=$(cat deployments/84532.json | jq -r '.IDRX')
DECIMALS="${QUOTE_DECIMALS:-6}"  # Default to 6 if not set

echo "=== CHECKING AGENT WALLET BALANCES ==="
echo ""

# Primary Wallet
PRIMARY="0x85C67299165117acAd97C2c5ECD4E642dFbF727E"
echo "Primary Wallet: $PRIMARY"
echo -n "  ETH: "
cast balance $PRIMARY --rpc-url $RPC --ether 2>/dev/null || echo "0"
echo -n "  IDRX: "
if [ ! -z "$IDRX" ] && [ "$IDRX" != "null" ]; then
    BALANCE=$(cast call $IDRX "balanceOf(address)" $PRIMARY --rpc-url $RPC 2>/dev/null || echo "0")
    DIVISOR=$(python3 -c "print(10 ** $DECIMALS)")
    python3 -c "print(f'{$BALANCE / $DIVISOR:.2f}')" 2>/dev/null || echo "0"
else
    echo "N/A (IDRX not found)"
fi
echo "  Status: $([ $(cast balance $PRIMARY --rpc-url $RPC 2>/dev/null | cut -d' ' -f1 | cut -d'.' -f1) -gt 0 ] && echo 'Has ETH ✅' || echo 'Needs ETH ❌')"
echo ""

# Executor 1
EXEC1="0xfc98C3eD81138d8A5f35b30A3b735cB5362e14Dc"
echo "Executor 1: $EXEC1"
echo -n "  ETH: "
cast balance $EXEC1 --rpc-url $RPC --ether 2>/dev/null || echo "0"
echo "  Status: $([ $(cast balance $EXEC1 --rpc-url $RPC 2>/dev/null | cut -d' ' -f1 | cut -d'.' -f1) -gt 0 ] && echo 'Has ETH ✅' || echo 'Needs ETH ❌')"
echo ""

# Executor 2
EXEC2="0x6CDD4354114Eae313972C99457E4f85eb6dc5295"
echo "Executor 2: $EXEC2"
echo -n "  ETH: "
cast balance $EXEC2 --rpc-url $RPC --ether 2>/dev/null || echo "0"
echo "  Status: $([ $(cast balance $EXEC2 --rpc-url $RPC 2>/dev/null | cut -d' ' -f1 | cut -d'.' -f1) -gt 0 ] && echo 'Has ETH ✅' || echo 'Needs ETH ❌')"
echo ""

# Executor 3
EXEC3="0xfA1Bb09a1318459061ECca7Cf23021843d5dB9c2"
echo "Executor 3: $EXEC3"
echo -n "  ETH: "
cast balance $EXEC3 --rpc-url $RPC --ether 2>/dev/null || echo "0"
echo "  Status: $([ $(cast balance $EXEC3 --rpc-url $RPC 2>/dev/null | cut -d' ' -f1 | cut -d'.' -f1) -gt 0 ] && echo 'Has ETH ✅' || echo 'Needs ETH ❌')"
echo ""

echo "=== REQUIREMENTS ==="
echo "Primary: 10,000 IDRX + 0.1 ETH"
echo "Each Executor: 0.01 ETH"
echo ""
echo "Get testnet ETH: https://www.alchemy.com/faucets/base-sepolia"
