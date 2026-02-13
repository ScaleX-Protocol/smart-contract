#!/bin/bash

# Debug Health Factor Calculation
# Network: Base Sepolia

USER="0xC21C5b2d33b791BEb51360a6dcb592ECdE37DB2C"
LENDING_MANAGER="0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c"
WETH="0x8b732595a59c9a18aca0aca3221a656eb38158fc"
IDRX="0x80fd9a0f8bca5255692016d67e0733bf5262c142"
BORROW_AMOUNT="25648196098739855" # 0.025648 WETH in wei
RPC="https://sepolia.base.org"

echo "=== DEBUGGING HEALTH FACTOR CALCULATION ==="
echo "User: $USER"
echo "Borrow Amount: $BORROW_AMOUNT wei (0.025648 WETH)"
echo ""

echo "=== CURRENT POSITION ==="
echo -n "Current Health Factor: "
cast call $LENDING_MANAGER "getHealthFactor(address)(uint256)" $USER --rpc-url $RPC
echo ""

echo "=== USER SUPPLIES ==="
echo -n "IDRX Supply: "
cast call $LENDING_MANAGER "getUserSupply(address,address)(uint256)" $USER $IDRX --rpc-url $RPC
echo -n "WETH Supply: "
cast call $LENDING_MANAGER "getUserSupply(address,address)(uint256)" $USER $WETH --rpc-url $RPC
echo ""

echo "=== USER DEBTS ==="
echo -n "IDRX Debt: "
cast call $LENDING_MANAGER "getUserDebt(address,address)(uint256)" $USER $IDRX --rpc-url $RPC
echo -n "WETH Debt: "
cast call $LENDING_MANAGER "getUserDebt(address,address)(uint256)" $USER $WETH --rpc-url $RPC
echo ""

echo "=== ORACLE PRICES ==="
# Get oracle address first
echo -n "Getting oracle address... "
ORACLE=$(cast call $LENDING_MANAGER "oracle()(address)" --rpc-url $RPC 2>/dev/null)
if [ -z "$ORACLE" ]; then
    echo "Failed to get oracle address"
else
    echo "$ORACLE"
    echo -n "IDRX Price (8 decimals): "
    cast call $ORACLE "getTokenPrice(address)(uint256)" $IDRX --rpc-url $RPC
    echo -n "WETH Price (8 decimals): "
    cast call $ORACLE "getTokenPrice(address)(uint256)" $WETH --rpc-url $RPC
fi
echo ""

echo "=== PROJECTED HEALTH FACTOR ==="
echo -n "Projected HF (if borrow $BORROW_AMOUNT WETH): "
PROJECTED_HF=$(cast call $LENDING_MANAGER "getProjectedHealthFactor(address,address,uint256)(uint256)" $USER $WETH $BORROW_AMOUNT --rpc-url $RPC)
echo "$PROJECTED_HF"
echo ""

echo "=== ANALYSIS ==="
echo "Projected HF in decimal form:"
python3 -c "print(f'{int('$PROJECTED_HF') / 1e18:.18f}')"
echo ""

echo "Required HF: 1.0 (1000000000000000000)"
echo ""

if [ "$PROJECTED_HF" -lt "1000000000000000000" ]; then
    echo "❌ FAILED: Projected HF < 1.0"
    echo "This borrow would put your account at risk of liquidation!"
else
    echo "✅ PASSED: Projected HF >= 1.0"
fi
