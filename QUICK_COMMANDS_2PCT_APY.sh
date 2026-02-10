#!/bin/bash

# Quick Reference: Commands to Achieve 2% WETH APY
# Account: 0x27dD1eBE7D826197FD163C134E79502402Fd7cB7

source .env

# Contract addresses
SCALEX_ROUTER=0x7D6657eB26636D2007be6a058b1fc4F50919142c
LENDING_MANAGER=0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c
WETH=0x8b732595a59c9a18acA0Aca3221A656Eb38158fC
DEPLOYER=0x27dD1eBE7D826197FD163C134E79502402Fd7cB7

# Required borrow amount (in wei)
BORROW_AMOUNT=80259050000000000000000  # 80,259.05 WETH

echo "=========================================="
echo "QUICK COMMANDS - 2% WETH APY TARGET"
echo "=========================================="
echo ""
echo "Required Action: Borrow 80,259.05 WETH from Account 1"
echo "NO additional collateral needed!"
echo ""

# Check current status
echo "=== STEP 1: Check Current Status ==="
echo ""
echo "WETH Supplied:"
cast call $SCALEX_ROUTER "getUserSupply(address,address)(uint256)" $DEPLOYER $WETH --rpc-url $SCALEX_CORE_RPC

echo ""
echo "WETH Borrowed:"
cast call $SCALEX_ROUTER "getUserBorrow(address,address)(uint256)" $DEPLOYER $WETH --rpc-url $SCALEX_CORE_RPC

echo ""
echo ""
echo "=== STEP 2: Execute Borrow (80,259.05 WETH) ==="
echo ""
echo "Command to run:"
echo ""
echo "cast send $SCALEX_ROUTER \"borrow(address,uint256)\" \\"
echo "  $WETH \\"
echo "  $BORROW_AMOUNT \\"
echo "  --private-key \$PRIVATE_KEY \\"
echo "  --rpc-url \$SCALEX_CORE_RPC \\"
echo "  --gas-limit 500000"
echo ""
echo "NOTE: This command currently fails due to known blocker."
echo "      See LENDING_COMPLETE_SUMMARY.md for details."
echo ""
echo ""
echo "=== STEP 3: Verify Results (After Borrow Succeeds) ==="
echo ""
echo "# Check new borrowed amount"
echo "cast call $SCALEX_ROUTER \"getUserBorrow(address,address)\" $DEPLOYER $WETH --rpc-url \$SCALEX_CORE_RPC"
echo ""
echo "# Check health factor (should be ~2.13)"
echo "cast call $LENDING_MANAGER \"getHealthFactor(address)\" $DEPLOYER --rpc-url \$SCALEX_CORE_RPC"
echo ""
echo "# Check pool utilization (should be ~20%)"
echo "cast call $SCALEX_ROUTER \"getUtilization(address)\" $WETH --rpc-url \$SCALEX_CORE_RPC"
echo ""
echo "# Wait 5-10 minutes, then check APY (should be ~2%)"
echo "cast call $SCALEX_ROUTER \"getSupplyAPY(address)\" $WETH --rpc-url \$SCALEX_CORE_RPC"
echo ""
echo ""
echo "=== ALTERNATIVE: Use Account 2 ==="
echo ""
echo "export PRIVATE_KEY=\$(grep '^PRIVATE_KEY_2=' .env | cut -d'=' -f2)"
echo "DEPLOYER=0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a"
echo ""
echo "cast send $SCALEX_ROUTER \"borrow(address,uint256)\" \\"
echo "  $WETH \\"
echo "  $BORROW_AMOUNT \\"
echo "  --private-key \$PRIVATE_KEY \\"
echo "  --rpc-url \$SCALEX_CORE_RPC \\"
echo "  --gas-limit 500000"
echo ""
echo ""
echo "=== MONITORING ==="
echo ""
echo "# Check health factor regularly"
echo "cast call $LENDING_MANAGER \"getHealthFactor(address)\" $DEPLOYER --rpc-url \$SCALEX_CORE_RPC"
echo ""
echo "# If HF < 1.5, add collateral:"
echo "SUPPLY_AMOUNT=10000 bash shellscripts/supply-weth-collateral.sh"
echo ""
echo ""
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo "Target: Borrow 80,259.05 WETH"
echo "Collateral: Already sufficient (201,264.60 WETH)"
echo "Health Factor: Will be 2.13 (safe)"
echo "Expected APY: 2.00%"
echo ""
echo "Status: Ready to execute once borrow blocker is fixed"
echo "=========================================="
