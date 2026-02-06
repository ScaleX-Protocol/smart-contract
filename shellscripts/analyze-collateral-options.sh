#!/bin/bash

# Comprehensive analysis script for achieving 2% WETH APY target
# Account: 0x27dD1eBE7D826197FD163C134E79502402Fd7cB7

set -e

source .env

# Contract addresses
SCALEX_ROUTER=$(jq -r '.ScaleXRouter' deployments/84532.json)
LENDING_MANAGER=$(jq -r '.LendingManager' deployments/84532.json)
BALANCE_MANAGER=$(jq -r '.BalanceManager' deployments/84532.json)
ORACLE=$(jq -r '.Oracle' deployments/84532.json)
WETH=$(jq -r '.WETH' deployments/84532.json)
IDRX=$(jq -r '.IDRX' deployments/84532.json)
sxWETH=$(jq -r '.sxWETH' deployments/84532.json)

# Account addresses
ACCOUNT1=0x27dD1eBE7D826197FD163C134E79502402Fd7cB7
ACCOUNT2=0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a

echo "=========================================="
echo "WETH LENDING ANALYSIS - 2% APY TARGET"
echo "=========================================="
echo ""

echo "=== ACCOUNT INFORMATION ==="
echo "Account 1 (Main): $ACCOUNT1"
echo "Account 2 (Secondary): $ACCOUNT2"
echo ""

# Get current positions for Account 1
echo "=== ACCOUNT 1 - CURRENT POSITION ==="
WETH_SUPPLIED_1=$(cast call $SCALEX_ROUTER "getUserSupply(address,address)(uint256)" $ACCOUNT1 $WETH --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')
WETH_BORROWED_1=$(cast call $SCALEX_ROUTER "getUserBorrow(address,address)(uint256)" $ACCOUNT1 $WETH --rpc-url $SCALEX_CORE_RPC 2>/dev/null | awk '{print $1}' || echo "0")
WETH_BALANCE_1=$(cast call $WETH "balanceOf(address)(uint256)" $ACCOUNT1 --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')
IDRX_BALANCE_1=$(cast call $IDRX "balanceOf(address)(uint256)" $ACCOUNT1 --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')

echo "WETH Supplied:  $(python3 -c "print(f'{${WETH_SUPPLIED_1} / 1e18:,.2f}')") WETH"
echo "WETH Borrowed:  $(python3 -c "print(f'{${WETH_BORROWED_1:-0} / 1e18:,.2f}')") WETH"
echo "WETH in Wallet: $(python3 -c "print(f'{${WETH_BALANCE_1} / 1e18:,.2f}')") WETH"
echo "IDRX Balance:   $(python3 -c "print(f'{${IDRX_BALANCE_1} / 1e2:,.2f}')") IDRX"
echo ""

# Get current positions for Account 2
echo "=== ACCOUNT 2 - CURRENT POSITION ==="
WETH_SUPPLIED_2=$(cast call $SCALEX_ROUTER "getUserSupply(address,address)(uint256)" $ACCOUNT2 $WETH --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')
WETH_BORROWED_2=$(cast call $SCALEX_ROUTER "getUserBorrow(address,address)(uint256)" $ACCOUNT2 $WETH --rpc-url $SCALEX_CORE_RPC 2>/dev/null | awk '{print $1}' || echo "0")
WETH_BALANCE_2=$(cast call $WETH "balanceOf(address)(uint256)" $ACCOUNT2 --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')
IDRX_BALANCE_2=$(cast call $IDRX "balanceOf(address)(uint256)" $ACCOUNT2 --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')

echo "WETH Supplied:  $(python3 -c "print(f'{${WETH_SUPPLIED_2} / 1e18:,.2f}')") WETH"
echo "WETH Borrowed:  $(python3 -c "print(f'{${WETH_BORROWED_2:-0} / 1e18:,.2f}')") WETH"
echo "WETH in Wallet: $(python3 -c "print(f'{${WETH_BALANCE_2} / 1e18:,.2f}')") WETH"
echo "IDRX Balance:   $(python3 -c "print(f'{${IDRX_BALANCE_2} / 1e2:,.2f}')") IDRX"
echo ""

# Get prices
echo "=== PRICE INFORMATION ==="
WETH_PRICE=$(cast call $ORACLE "getPriceForBorrowing(address)(uint256)" $WETH --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')
sxWETH_PRICE=$(cast call $ORACLE "getPriceForCollateral(address)(uint256)" $sxWETH --rpc-url $SCALEX_CORE_RPC | awk '{print $1}')
echo "WETH Borrow Price: $(python3 -c "print(f'{${WETH_PRICE} / 1e18:,.2f}')") (18 decimals)"
echo "sxWETH Collateral Price: $(python3 -c "print(f'{${sxWETH_PRICE} / 1e8:,.2f}')") (8 decimals)"
echo ""

# Calculate required borrow to achieve 2% APY
echo "=== TARGET CALCULATIONS ==="
echo "Target APY: 2.00%"
echo "Current APY: 0.80% (estimated)"
echo ""

# Total supply calculation
TOTAL_SUPPLY=$(python3 -c "print(int(${WETH_SUPPLIED_1} + ${WETH_SUPPLIED_2}))")
echo "Total WETH Supplied (Both Accounts): $(python3 -c "print(f'{${TOTAL_SUPPLY} / 1e18:,.2f}')") WETH"

# We need to calculate required utilization for 2% APY
# Using interest rate model: baseRate=200bps, optimalUtil=8000bps, slope1=1000bps, slope2=5000bps
# For 2% APY, we need utilization around 20%
TARGET_UTILIZATION=0.20  # 20%

REQUIRED_TOTAL_BORROWED=$(python3 << EOF
import sys
total_supply = ${TOTAL_SUPPLY} / 1e18
target_util = ${TARGET_UTILIZATION}
required_borrowed = total_supply * target_util
print(int(required_borrowed * 1e18))
EOF
)

CURRENT_TOTAL_BORROWED=$(python3 -c "print(int(${WETH_BORROWED_1:-0} + ${WETH_BORROWED_2:-0}))")
ADDITIONAL_BORROW_NEEDED=$(python3 -c "print(int(${REQUIRED_TOTAL_BORROWED} - ${CURRENT_TOTAL_BORROWED}))")

echo "Required Total Borrowed: $(python3 -c "print(f'{${REQUIRED_TOTAL_BORROWED} / 1e18:,.2f}')") WETH"
echo "Current Total Borrowed:  $(python3 -c "print(f'{${CURRENT_TOTAL_BORROWED} / 1e18:,.2f}')") WETH"
echo "Additional Borrow Needed: $(python3 -c "print(f'{${ADDITIONAL_BORROW_NEEDED} / 1e18:,.2f}')") WETH"
echo ""

# Calculate collateral requirements for additional borrow
echo "=== COLLATERAL REQUIREMENTS ==="
echo ""
echo "Assumptions:"
echo "- Collateral Factor (LTV): 80% (8000 bps)"
echo "- Liquidation Threshold: 85% (8500 bps)"
echo "- Target Health Factor: 1.8 (safety buffer above 1.5)"
echo ""

# Calculate required collateral at 1.8 health factor
# Health Factor = (Collateral Value * Liquidation Threshold) / Debt Value
# 1.8 = (Collateral * 0.85) / Debt
# Collateral = (Debt * 1.8) / 0.85

python3 << 'EOF'
import sys

# Input parameters
additional_borrow_weth = ${ADDITIONAL_BORROW_NEEDED} / 1e18
current_supplied_1 = ${WETH_SUPPLIED_1} / 1e18
current_borrowed_1 = ${WETH_BORROWED_1:-0} / 1e18
current_supplied_2 = ${WETH_SUPPLIED_2} / 1e18
current_borrowed_2 = ${WETH_BORROWED_2:-0} / 1e18

liquidation_threshold = 0.85
collateral_factor = 0.80
target_health_factor = 1.8
minimum_health_factor = 1.5

print("OPTION 1: BORROW FROM ACCOUNT 1 (Main Account)")
print("=" * 60)
new_borrowed_1 = current_borrowed_1 + additional_borrow_weth
required_collateral_1_target = (new_borrowed_1 * target_health_factor) / liquidation_threshold
required_collateral_1_minimum = (new_borrowed_1 * minimum_health_factor) / liquidation_threshold
additional_collateral_1_target = max(0, required_collateral_1_target - current_supplied_1)
additional_collateral_1_minimum = max(0, required_collateral_1_minimum - current_supplied_1)

print(f"Current Collateral:        {current_supplied_1:,.2f} WETH")
print(f"Current Borrowed:          {current_borrowed_1:,.2f} WETH")
print(f"Additional Borrow:         {additional_borrow_weth:,.2f} WETH")
print(f"New Total Borrowed:        {new_borrowed_1:,.2f} WETH")
print(f"")
print(f"Required Collateral (HF=1.8): {required_collateral_1_target:,.2f} WETH")
print(f"Additional Needed (HF=1.8):   {additional_collateral_1_target:,.2f} WETH")
print(f"")
print(f"Required Collateral (HF=1.5): {required_collateral_1_minimum:,.2f} WETH")
print(f"Additional Needed (HF=1.5):   {additional_collateral_1_minimum:,.2f} WETH")
print(f"")

if additional_collateral_1_target <= 0:
    print("✅ ACCOUNT 1 HAS SUFFICIENT COLLATERAL (HF=1.8)!")
    projected_hf_1 = (current_supplied_1 * liquidation_threshold) / new_borrowed_1
    print(f"   Projected Health Factor: {projected_hf_1:.2f}")
elif additional_collateral_1_minimum <= 0:
    print("⚠️  ACCOUNT 1 HAS SUFFICIENT COLLATERAL (HF=1.5), but below target")
    projected_hf_1 = (current_supplied_1 * liquidation_threshold) / new_borrowed_1
    print(f"   Projected Health Factor: {projected_hf_1:.2f}")
else:
    print("❌ ACCOUNT 1 NEEDS MORE COLLATERAL")
    print(f"   Shortfall: {additional_collateral_1_minimum:,.2f} WETH")

print("")
print("")

print("OPTION 2: BORROW FROM ACCOUNT 2 (Secondary Account)")
print("=" * 60)
new_borrowed_2 = current_borrowed_2 + additional_borrow_weth
required_collateral_2_target = (new_borrowed_2 * target_health_factor) / liquidation_threshold
required_collateral_2_minimum = (new_borrowed_2 * minimum_health_factor) / liquidation_threshold
additional_collateral_2_target = max(0, required_collateral_2_target - current_supplied_2)
additional_collateral_2_minimum = max(0, required_collateral_2_minimum - current_supplied_2)

print(f"Current Collateral:        {current_supplied_2:,.2f} WETH")
print(f"Current Borrowed:          {current_borrowed_2:,.2f} WETH")
print(f"Additional Borrow:         {additional_borrow_weth:,.2f} WETH")
print(f"New Total Borrowed:        {new_borrowed_2:,.2f} WETH")
print(f"")
print(f"Required Collateral (HF=1.8): {required_collateral_2_target:,.2f} WETH")
print(f"Additional Needed (HF=1.8):   {additional_collateral_2_target:,.2f} WETH")
print(f"")
print(f"Required Collateral (HF=1.5): {required_collateral_2_minimum:,.2f} WETH")
print(f"Additional Needed (HF=1.5):   {additional_collateral_2_minimum:,.2f} WETH")
print(f"")

if additional_collateral_2_target <= 0:
    print("✅ ACCOUNT 2 HAS SUFFICIENT COLLATERAL (HF=1.8)!")
    projected_hf_2 = (current_supplied_2 * liquidation_threshold) / new_borrowed_2
    print(f"   Projected Health Factor: {projected_hf_2:.2f}")
elif additional_collateral_2_minimum <= 0:
    print("⚠️  ACCOUNT 2 HAS SUFFICIENT COLLATERAL (HF=1.5), but below target")
    projected_hf_2 = (current_supplied_2 * liquidation_threshold) / new_borrowed_2
    print(f"   Projected Health Factor: {projected_hf_2:.2f}")
else:
    print("❌ ACCOUNT 2 NEEDS MORE COLLATERAL")
    print(f"   Shortfall: {additional_collateral_2_minimum:,.2f} WETH")

print("")
print("")

print("OPTION 3: SPLIT BORROW ACROSS BOTH ACCOUNTS")
print("=" * 60)
split_borrow = additional_borrow_weth / 2
new_borrowed_1_split = current_borrowed_1 + split_borrow
new_borrowed_2_split = current_borrowed_2 + split_borrow

required_collateral_1_split = (new_borrowed_1_split * target_health_factor) / liquidation_threshold
required_collateral_2_split = (new_borrowed_2_split * target_health_factor) / liquidation_threshold
additional_collateral_1_split = max(0, required_collateral_1_split - current_supplied_1)
additional_collateral_2_split = max(0, required_collateral_2_split - current_supplied_2)

print(f"Each Account Borrows:      {split_borrow:,.2f} WETH")
print(f"")
print(f"Account 1:")
print(f"  New Borrowed:            {new_borrowed_1_split:,.2f} WETH")
print(f"  Required Collateral:     {required_collateral_1_split:,.2f} WETH")
print(f"  Additional Needed:       {additional_collateral_1_split:,.2f} WETH")
if additional_collateral_1_split <= 0:
    projected_hf = (current_supplied_1 * liquidation_threshold) / new_borrowed_1_split
    print(f"  Status: ✅ Sufficient (Projected HF: {projected_hf:.2f})")
else:
    print(f"  Status: ❌ Needs {additional_collateral_1_split:,.2f} more WETH")
print(f"")
print(f"Account 2:")
print(f"  New Borrowed:            {new_borrowed_2_split:,.2f} WETH")
print(f"  Required Collateral:     {required_collateral_2_split:,.2f} WETH")
print(f"  Additional Needed:       {additional_collateral_2_split:,.2f} WETH")
if additional_collateral_2_split <= 0:
    projected_hf = (current_supplied_2 * liquidation_threshold) / new_borrowed_2_split
    print(f"  Status: ✅ Sufficient (Projected HF: {projected_hf:.2f})")
else:
    print(f"  Status: ❌ Needs {additional_collateral_2_split:,.2f} more WETH")

EOF

echo ""
echo ""
echo "=== AVAILABLE RESOURCES ==="
echo "Account 1 Wallet: $(python3 -c "print(f'{${WETH_BALANCE_1} / 1e18:,.2f}')") WETH available to supply"
echo "Account 2 Wallet: $(python3 -c "print(f'{${WETH_BALANCE_2} / 1e18:,.2f}')") WETH available to supply"
echo ""

echo "=== RECOMMENDATIONS ==="
echo ""
echo "Based on the analysis above:"
echo ""
echo "1. Review which option has sufficient collateral"
echo "2. If additional collateral is needed, check wallet balances"
echo "3. Supply additional WETH using: bash shellscripts/supply-weth-collateral.sh"
echo "4. Execute borrow using the recommended option"
echo ""
echo "Note: Borrow functionality may be blocked (see LENDING_COMPLETE_SUMMARY.md)"
echo "      This analysis shows what SHOULD work mathematically."
echo ""
