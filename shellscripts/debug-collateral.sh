#!/bin/bash

# Debug collateral check

source .env

DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)
LENDING_MANAGER=$(jq -r '.LendingManager' deployments/84532.json)
BALANCE_MANAGER=$(jq -r '.BalanceManager' deployments/84532.json)
ORACLE=$(jq -r '.Oracle' deployments/84532.json)
WETH=$(jq -r '.WETH' deployments/84532.json)
SXWETH=$(jq -r '.sxWETH' deployments/84532.json)

echo "=== Debugging Collateral Check ==="
echo ""
echo "Deployer: $DEPLOYER"
echo ""

# Check user supply in LendingManager
echo "1. User Supply in LendingManager:"
USER_SUPPLY=$(cast call $LENDING_MANAGER "getUserSupply(address,address)(uint256)" $DEPLOYER $WETH --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')
echo "   $USER_SUPPLY ($(python3 -c "print(f'{$USER_SUPPLY / 1e18:.6f}')") WETH)"
echo ""

# Check user sxWETH balance in BalanceManager
echo "2. User sxWETH Balance in BalanceManager:"
SXWETH_BAL=$(cast call $BALANCE_MANAGER "getBalance(address,address)(uint256)" $DEPLOYER $SXWETH --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')
echo "   $SXWETH_BAL ($(python3 -c "print(f'{$SXWETH_BAL / 1e18:.6f}')") sxWETH)"
echo ""

# Check sxWETH price
echo "3. sxWETH Price from Oracle:"
PRICE=$(cast call $ORACLE "getPriceForCollateral(address)(uint256)" $SXWETH --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')
echo "   $PRICE"
echo ""

# Check user borrow
echo "4. User Borrow in LendingManager:"
USER_BORROW=$(cast call $LENDING_MANAGER "getUserBorrow(address,address)(uint256)" $DEPLOYER $WETH --rpc-url $SCALEX_CORE_RPC 2>&1 | awk '{print $1}')
if [ -z "$USER_BORROW" ]; then
    USER_BORROW="0"
fi
echo "   $USER_BORROW ($(python3 -c "print(f'{${USER_BORROW:-0} / 1e18:.6f}')") WETH)"
echo ""

# Check health factor
echo "5. Current Health Factor:"
HEALTH=$(cast call $LENDING_MANAGER "getHealthFactor(address)(uint256)" $DEPLOYER --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')
echo "   $HEALTH ($(python3 -c "print(f'{$HEALTH / 1e18:.2f}')"))"
echo ""

# Check WETH asset config
echo "6. WETH Asset Config:"
cast call $LENDING_MANAGER "assetConfigs(address)(uint256,uint256,uint256,uint256,bool)" $WETH --rpc-url $SCALEX_CORE_RPC
echo ""

# Check if BalanceManager and Oracle are set
echo "7. LendingManager Configuration:"
BM_ADDR=$(cast call $LENDING_MANAGER "balanceManager()(address)" --rpc-url $SCALEX_CORE_RPC 2>&1)
ORACLE_ADDR=$(cast call $LENDING_MANAGER "oracle()(address)" --rpc-url $SCALEX_CORE_RPC 2>&1)
echo "   BalanceManager: $BM_ADDR"
echo "   Oracle: $ORACLE_ADDR"
echo ""

# Manual collateral calculation
echo "8. Manual Collateral Calculation:"
python3 << EOF
collateral_balance = $SXWETH_BAL
price = $PRICE
decimals = 18
quote_decimals = 2  # IDRX has 2 decimals

# Collateral value in quote currency
collateral_value = (collateral_balance * price) / (10 ** decimals)
print(f"   Collateral Value: {collateral_value:,.0f} (quote units)")

# Weighted by liquidation threshold (85%)
weighted_value = (collateral_value * 8500) / 10000
print(f"   Weighted (85%): {weighted_value:,.0f} (quote units)")

# For 1 WETH borrow
borrow_amount = 1e18
debt_value = (borrow_amount * price) / (10 ** decimals)
print(f"   Debt for 1 WETH: {debt_value:,.0f} (quote units)")

# Health factor
if debt_value > 0:
    health_factor = (weighted_value * 1e18) / debt_value
    print(f"   Projected Health Factor: {health_factor / 1e18:.2f}")
    print(f"   Should Pass: {health_factor >= 1e18}")
EOF
