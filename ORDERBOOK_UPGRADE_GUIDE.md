# OrderBook Upgrade Guide - Auto-Borrow Fix

**Date:** 2026-02-06
**Network:** Base Sepolia (Chain ID: 84532)
**Fix:** Auto-borrow for market BUY orders

---

## Overview

This guide walks through upgrading the OrderBook contract using the Beacon Proxy pattern. The upgrade includes the fix for auto-borrow functionality in market BUY orders.

### What Gets Upgraded

✅ **OrderBook Implementation** - New logic deployed
✅ **All OrderBook Proxies** - Automatically point to new implementation via Beacon
✅ **No Address Changes** - All proxy addresses remain the same

---

## Deployment Information

### Base Sepolia Addresses

```
Network: Base Sepolia
Chain ID: 84532
RPC URL: https://base-sepolia.g.alchemy.com/v2/jBG4sMyhez7V13jNTeQKfVfgNa54nCmF

PoolManager: 0xb301317d0b5f771d802598b5a9a4a331b8c97f05
OrderBook Beacon: 0x2f95340989818766fe0bf339028208f93191953a

Deployer/Owner: 0x27dD1eBE7D826197FD163C134E79502402Fd7cB7
```

### How Beacon Upgrades Work

```
┌─────────────────────────────────────────────┐
│ Before Upgrade                              │
├─────────────────────────────────────────────┤
│                                             │
│  OrderBook Beacon (0x2f95...)              │
│      │                                       │
│      └─> Implementation (OLD)               │
│              └─> Old code (no auto-borrow)  │
│                                             │
│  OrderBook Proxy 1 ──────┐                 │
│  OrderBook Proxy 2 ──────┤ Point to Beacon │
│  OrderBook Proxy 3 ──────┘                 │
│                                             │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ After Upgrade                               │
├─────────────────────────────────────────────┤
│                                             │
│  OrderBook Beacon (0x2f95...)              │
│      │                                       │
│      └─> Implementation (NEW) ✅            │
│              └─> New code (with fix) ✅     │
│                                             │
│  OrderBook Proxy 1 ──────┐                 │
│  OrderBook Proxy 2 ──────┤ Point to Beacon │
│  OrderBook Proxy 3 ──────┘                 │
│  (Same addresses! No migration needed) ✅   │
│                                             │
└─────────────────────────────────────────────┘
```

---

## Pre-Upgrade Checklist

### 1. Environment Setup

```bash
cd /Users/renaka/gtx/clob-dex

# Load Base Sepolia environment
export $(cat .env.base-sepolia | xargs)

# Verify environment variables
echo "Private Key Set: ${PRIVATE_KEY:0:10}..."
echo "Owner Address: $OWNER_ADDRESS"
echo "RPC URL: $SCALEX_CORE_RPC"
```

### 2. Verify Ownership

```bash
# Check beacon owner
cast call 0x2f95340989818766fe0bf339028208f93191953a \
  "owner()(address)" \
  --rpc-url $SCALEX_CORE_RPC

# Should return: 0x27dD1eBE7D826197FD163C134E79502402Fd7cB7
```

### 3. Check Current Implementation

```bash
# Get current implementation
cast call 0x2f95340989818766fe0bf339028208f93191953a \
  "implementation()(address)" \
  --rpc-url $SCALEX_CORE_RPC

# Note this address for verification later
```

### 4. Verify Funds for Gas

```bash
# Check deployer balance
cast balance $OWNER_ADDRESS --rpc-url $SCALEX_CORE_RPC --ether

# Should have at least 0.01 ETH for gas
```

---

## Upgrade Process

### Option 1: Using Forge Script (Recommended)

```bash
# Navigate to project root
cd /Users/renaka/gtx/clob-dex

# Set environment variables
export PRIVATE_KEY=0x5d34b3f860c2b09c112d68a35d592dfb599841629c9b0ad8827269b94b57efca
export ORDERBOOK_BEACON=0x2f95340989818766fe0bf339028208f93191953a
export RPC_URL=https://base-sepolia.g.alchemy.com/v2/jBG4sMyhez7V13jNTeQKfVfgNa54nCmF

# Run upgrade script
forge script script/maintenance/UpgradeOrderBook.s.sol:UpgradeOrderBook \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv

# The script will:
# 1. Deploy new OrderBook implementation
# 2. Upgrade beacon to point to new implementation
# 3. Verify the upgrade
```

### Option 2: Using Cast Commands (Manual)

```bash
# Step 1: Build the contracts
forge build

# Step 2: Deploy new OrderBook implementation
NEW_IMPL=$(forge create src/core/OrderBook.sol:OrderBook \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --json | jq -r .deployedTo)

echo "New Implementation: $NEW_IMPL"

# Step 3: Upgrade the beacon
cast send 0x2f95340989818766fe0bf339028208f93191953a \
  "upgradeTo(address)" \
  $NEW_IMPL \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Step 4: Verify upgrade
CURRENT_IMPL=$(cast call 0x2f95340989818766fe0bf339028208f93191953a \
  "implementation()(address)" \
  --rpc-url $RPC_URL)

echo "Current Implementation: $CURRENT_IMPL"
echo "Expected: $NEW_IMPL"

if [ "$CURRENT_IMPL" = "$NEW_IMPL" ]; then
  echo "✅ Upgrade successful!"
else
  echo "❌ Upgrade failed!"
fi
```

---

## Post-Upgrade Verification

### 1. Verify Implementation Address

```bash
# Check new implementation
cast call 0x2f95340989818766fe0bf339028208f93191953a \
  "implementation()(address)" \
  --rpc-url $SCALEX_CORE_RPC

# Should return the new implementation address
```

### 2. Test Auto-Borrow Functionality

Run the original test scenario that failed:

```bash
# 1. Check user balance
cast call <BALANCE_MANAGER> \
  "getBalance(address,address)(uint256)" \
  <USER_ADDRESS> \
  <IDRX_ADDRESS> \
  --rpc-url $SCALEX_CORE_RPC

# 2. Place a market BUY order with autoBorrow=true
# (Use frontend or custom script)

# 3. Verify transaction events
cast receipt <TX_HASH> --rpc-url $SCALEX_CORE_RPC

# Should see:
# - OrderPlaced event
# - AutoBorrowExecuted event ✅ (NEW!)
# - OrderMatched event
# - Borrow event from LendingManager
```

### 3. Verify All Proxies Updated

Since all OrderBook proxies use the same Beacon, they all automatically use the new implementation:

```bash
# Get all OrderBook proxies from PoolManager
# Each trading pair has its own OrderBook proxy
# All now point to the upgraded implementation via the Beacon

# Example: Check WETH/IDRX pool
POOL_MANAGER=0xb301317d0b5f771d802598b5a9a4a331b8c97f05
```

### 4. Check Beacon Events

```bash
# Get upgrade event
cast logs --from-block <UPGRADE_BLOCK> \
  --address 0x2f95340989818766fe0bf339028208f93191953a \
  --rpc-url $SCALEX_CORE_RPC

# Should show "Upgraded" event with new implementation address
```

---

## Testing Checklist

After upgrade, test the following scenarios:

### Auto-Borrow Tests

- [ ] **Test 1:** Market BUY with sufficient balance (no borrow)
  - Expected: Order executes, no borrow event

- [ ] **Test 2:** Market BUY with insufficient balance, autoBorrow=false
  - Expected: Partial execution up to available balance

- [ ] **Test 3:** Market BUY with insufficient balance, autoBorrow=true ✅
  - Expected: Borrows shortfall, full execution, `AutoBorrowExecuted` event

- [ ] **Test 4:** Market BUY with insufficient collateral
  - Expected: Borrow fails, partial execution, `AutoBorrowFailed` event

- [ ] **Test 5:** Market SELL with autoBorrow (verify still works)
  - Expected: Borrows if needed, `AutoBorrowExecuted` event

### Regression Tests

- [ ] **Test 6:** Limit orders still work
- [ ] **Test 7:** Auto-repay still works for both BUY and SELL
- [ ] **Test 8:** Order cancellation works
- [ ] **Test 9:** Order matching works correctly
- [ ] **Test 10:** Fee calculation unchanged

---

## Rollback Procedure

If issues are found after upgrade:

### Emergency Rollback

```bash
# Revert to previous implementation
OLD_IMPL=<address_from_pre_upgrade_check>

cast send 0x2f95340989818766fe0bf339028208f93191953a \
  "upgradeTo(address)" \
  $OLD_IMPL \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Verify rollback
cast call 0x2f95340989818766fe0bf339028208f93191953a \
  "implementation()(address)" \
  --rpc-url $SCALEX_CORE_RPC
```

### Rollback Considerations

⚠️ **Important:**
- Rollback reverts to old code (without auto-borrow fix)
- Any orders placed with auto-borrow during upgrade will need manual handling
- State changes (orders, balances) are preserved in proxies
- Only the implementation logic is reverted

---

## Monitoring After Upgrade

### 1. Watch for Events

```bash
# Monitor auto-borrow events
cast logs --follow \
  --address <ORDERBOOK_PROXIES> \
  --rpc-url $SCALEX_CORE_RPC | grep "AutoBorrow"
```

### 2. Check Indexer Sync

Monitor the indexer to ensure it's picking up:
- New `AutoBorrowExecuted` events
- Updated borrow amounts
- Correct executed quantities

### 3. User Experience

- Watch for user reports of auto-borrow working/not working
- Monitor transaction success rates
- Check health factor calculations

---

## Contract Verification

### Verify on BaseScan

After upgrade, verify the new implementation on BaseScan:

```bash
# Automatically verified if using --verify flag with forge script

# Manual verification:
forge verify-contract \
  <NEW_IMPL_ADDRESS> \
  src/core/OrderBook.sol:OrderBook \
  --chain-id 84532 \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### View on BaseScan

```
Beacon: https://sepolia.basescan.org/address/0x2f95340989818766fe0bf339028208f93191953a
Implementation: https://sepolia.basescan.org/address/<NEW_IMPL_ADDRESS>
```

---

## Upgrade Timeline

### Recommended Schedule

1. **T-0 (Now):** Review and approve upgrade
2. **T+1 hour:** Deploy to testnet (if not already done)
3. **T+4 hours:** Test thoroughly on testnet
4. **T+1 day:** Deploy to Base Sepolia mainnet
5. **T+1 day + 1 hour:** Monitor transactions
6. **T+1 day + 4 hours:** Declare success or rollback

### Communication

**Before Upgrade:**
- Notify users of upcoming upgrade
- Mention brief downtime if pausing orders
- Explain fix for auto-borrow

**After Upgrade:**
- Announce successful upgrade
- Highlight auto-borrow now works for BUY orders
- Provide example transaction

---

## Troubleshooting

### Issue: "Not beacon owner"

**Cause:** Wrong private key or deployer address
**Fix:** Verify PRIVATE_KEY matches OWNER_ADDRESS (0x27dD1eBE7D826197FD163C134E79502402Fd7cB7)

### Issue: "Out of gas"

**Cause:** Insufficient ETH for gas
**Fix:** Send more ETH to deployer address

### Issue: "Implementation unchanged"

**Cause:** New implementation same as old (unlikely)
**Fix:** Check if code was actually changed, recompile

### Issue: Auto-borrow still not working

**Cause:**
- Implementation not updated correctly
- Wrong beacon upgraded
- Frontend still using old ABI

**Fix:**
1. Verify implementation address changed
2. Clear frontend cache
3. Check transaction events

---

## Success Criteria

✅ Upgrade successful when:

1. **New implementation deployed** - Unique address different from old
2. **Beacon points to new implementation** - `beacon.implementation()` returns new address
3. **Auto-borrow works for BUY orders** - `AutoBorrowExecuted` events emitted
4. **All existing functionality works** - Limit orders, SELL orders, etc.
5. **No proxy address changes** - All integrations continue working
6. **Indexer syncs correctly** - Shows borrowed amounts

---

## Contact & Support

**Issues:** Report to development team
**Documentation:** `/Users/renaka/gtx/clob-dex/AUTO_BORROW_BUG_REPORT.md`
**Implementation:** `/Users/renaka/gtx/clob-dex/AUTO_BORROW_FIX_IMPLEMENTATION.md`

---

**Ready to Upgrade:** Yes ✅
**Estimated Time:** 5-10 minutes
**Risk Level:** Low (upgradeable, rollback available)
