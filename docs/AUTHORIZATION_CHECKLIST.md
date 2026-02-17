# Authorization Checklist - Agent Infrastructure Deployment

## Overview

This document lists **all authorizations** that are automatically configured during Phase 5 deployment to prevent common authorization issues.

---

## Previous Issues (Now Fixed)

### ❌ Issues Encountered in Previous Deployments

1. **OrderBook authorization in BalanceManager**
   - OrderBooks couldn't access user funds
   - Trades would fail

2. **AutoBorrowHelper authorization**
   - Auto-borrow feature not working
   - Already handled in Phase 4

3. **AgentRouter authorization**
   - AgentRouter couldn't execute trades
   - AgentRouter couldn't manage lending positions

### ✅ All Issues Fixed in Current Deployment

Phase 5 deployment now includes **comprehensive authorizations** to prevent these issues.

---

## Configuration Done in Phase 5

### Oracle Configuration

#### IDRX and sxIDRX Oracle Prices ✅

```solidity
// IDRX: $1.00 (1e2 = 100 raw, since IDRX has 2 decimals)
Oracle(oracle).setPrice(IDRX, 1e2);

// sxIDRX: $1.00 (1:1 peg with IDRX)
Oracle(oracle).setPrice(sxIDRX, 1e2);
```

**Why needed:**
- IDRX is the quote currency for all trading pairs
- sxIDRX is the synthetic version used in lending
- Oracle needs prices for both tokens for proper valuation

**Without this:**
- Cannot calculate trade values
- Lending health factors broken
- Trading may fail due to missing oracle prices

---

## Authorizations Done in Phase 5

### 1. AgentRouter in PolicyFactory ✅

```solidity
policyFactory.setAuthorizedRouter(address(agentRouter), true);
```

**Why needed:**
- Allows AgentRouter to check and enforce policies
- Required for all agent trading operations

**Without this:**
- Policy checks would fail
- Agents cannot trade

---

### 2. AgentRouter in BalanceManager ✅

```solidity
BalanceManager(balanceManager).addAuthorizedOperator(address(agentRouter));
```

**Why needed:**
- Allows AgentRouter to access user balances
- Required for placing orders and managing funds

**Without this:**
- Cannot place orders (no balance access)
- Cannot transfer funds for trades

---

### 3. AgentRouter in LendingManager ✅

```solidity
LendingManager(lendingManager).addAuthorizedOperator(address(agentRouter));
```

**Why needed:**
- Allows AgentRouter to execute borrow/repay operations
- Required for agent lending features

**Without this:**
- `executeBorrow()` fails
- `executeRepay()` fails
- `executeSupplyCollateral()` fails
- `executeWithdrawCollateral()` fails

---

### 4. AgentRouter in PoolManager ✅

```solidity
IPoolManager(poolManager).addAuthorizedRouter(address(agentRouter));
```

**Why needed:**
- Allows AgentRouter to route trades through pools
- Required for all trading operations

**Without this:**
- Cannot execute limit orders
- Cannot execute market orders
- Cannot cancel orders

---

## Complete Authorization Flow

### Phase 4 (AutoBorrowHelper) - Already Done

```
AutoBorrowHelper deployed
├── Authorized in BalanceManager ✓
├── Authorized in LendingManager ✓
└── Authorized in all OrderBooks ✓
```

**This is already handled by Phase 4 deployment script.**

### Phase 5 (AgentRouter) - Now Complete

```
AgentRouter deployed
├── Authorized in PolicyFactory ✓
├── Authorized in BalanceManager ✓
├── Authorized in LendingManager ✓
└── Authorized in PoolManager ✓
```

**All authorizations automated in Phase 5 deployment script.**

---

## Verification

### After Deployment

The script will show:

```
[SUCCESS] Phase 5 completed with official ERC-8004 contracts!

Authorizations completed:
  [OK] AgentRouter authorized in PolicyFactory
  [OK] AgentRouter authorized in BalanceManager
  [OK] AgentRouter authorized in LendingManager
  [OK] AgentRouter authorized in PoolManager

Ready for marketplace deployment!
```

### Manual Verification (Optional)

```bash
# Read deployed addresses
CHAIN_ID=$(cast chain-id --rpc-url $SCALEX_CORE_RPC)
AGENT_ROUTER=$(cat deployments/${CHAIN_ID}.json | jq -r '.AgentRouter')
BALANCE_MANAGER=$(cat deployments/${CHAIN_ID}.json | jq -r '.BalanceManager')
LENDING_MANAGER=$(cat deployments/${CHAIN_ID}.json | jq -r '.LendingManager')
POOL_MANAGER=$(cat deployments/${CHAIN_ID}.json | jq -r '.PoolManager')
POLICY_FACTORY=$(cat deployments/${CHAIN_ID}.json | jq -r '.PolicyFactory')

# Verify BalanceManager authorization
cast call $BALANCE_MANAGER "isAuthorizedOperator(address)" $AGENT_ROUTER --rpc-url $SCALEX_CORE_RPC
# Should return: true (0x0000...0001)

# Verify LendingManager authorization
cast call $LENDING_MANAGER "isAuthorizedOperator(address)" $AGENT_ROUTER --rpc-url $SCALEX_CORE_RPC
# Should return: true (0x0000...0001)

# Verify PoolManager authorization
cast call $POOL_MANAGER "isAuthorizedRouter(address)" $AGENT_ROUTER --rpc-url $SCALEX_CORE_RPC
# Should return: true (0x0000...0001)

# Verify PolicyFactory authorization
cast call $POLICY_FACTORY "authorizedRouters(address)" $AGENT_ROUTER --rpc-url $SCALEX_CORE_RPC
# Should return: true (0x0000...0001)
```

---

## What Each Authorization Enables

### Trading Operations

| Function | Requires Authorization In |
|----------|--------------------------|
| `executeLimitOrder()` | PoolManager, BalanceManager, PolicyFactory |
| `executeMarketOrder()` | PoolManager, BalanceManager, PolicyFactory |
| `cancelOrder()` | PoolManager, PolicyFactory |

### Lending Operations

| Function | Requires Authorization In |
|----------|--------------------------|
| `executeBorrow()` | LendingManager, PolicyFactory |
| `executeRepay()` | LendingManager, PolicyFactory |
| `executeSupplyCollateral()` | LendingManager, PolicyFactory |
| `executeWithdrawCollateral()` | LendingManager, PolicyFactory |

### Policy Operations

| Function | Requires Authorization In |
|----------|--------------------------|
| Policy enforcement | PolicyFactory |
| Policy validation | PolicyFactory |

---

## Troubleshooting

### If You Still Get Authorization Errors

#### Error: "Not authorized operator" (BalanceManager)

**Check:**
```bash
cast call $BALANCE_MANAGER "isAuthorizedOperator(address)" $AGENT_ROUTER --rpc-url $RPC
```

**Fix:**
```bash
cast send $BALANCE_MANAGER "addAuthorizedOperator(address)" $AGENT_ROUTER \
  --rpc-url $RPC \
  --private-key $PRIVATE_KEY
```

#### Error: "Not authorized operator" (LendingManager)

**Check:**
```bash
cast call $LENDING_MANAGER "isAuthorizedOperator(address)" $AGENT_ROUTER --rpc-url $RPC
```

**Fix:**
```bash
cast send $LENDING_MANAGER "addAuthorizedOperator(address)" $AGENT_ROUTER \
  --rpc-url $RPC \
  --private-key $PRIVATE_KEY
```

#### Error: "Not authorized router" (PoolManager)

**Check:**
```bash
cast call $POOL_MANAGER "isAuthorizedRouter(address)" $AGENT_ROUTER --rpc-url $RPC
```

**Fix:**
```bash
cast send $POOL_MANAGER "addAuthorizedRouter(address)" $AGENT_ROUTER \
  --rpc-url $RPC \
  --private-key $PRIVATE_KEY
```

#### Error: "Unauthorized router" (PolicyFactory)

**Check:**
```bash
cast call $POLICY_FACTORY "authorizedRouters(address)" $AGENT_ROUTER --rpc-url $RPC
```

**Fix:**
```bash
cast send $POLICY_FACTORY "setAuthorizedRouter(address,bool)" $AGENT_ROUTER true \
  --rpc-url $RPC \
  --private-key $PRIVATE_KEY
```

---

## Summary

**Before (Old Deployment):**
- ❌ Manual authorization needed after deployment
- ❌ Easy to forget authorizations
- ❌ Deployment failures common

**After (New Deployment):**
- ✅ All authorizations automated
- ✅ Comprehensive authorization in single deployment
- ✅ No manual steps needed
- ✅ Verification built-in

**Running Phase 5 deployment now includes:**

1. Deploy all agent contracts ✅
2. Authorize AgentRouter in PolicyFactory ✅
3. Authorize AgentRouter in BalanceManager ✅
4. Authorize AgentRouter in LendingManager ✅
5. Authorize AgentRouter in PoolManager ✅
6. Verify all authorizations ✅

**Result: Zero authorization issues!** 🎯

---

## Quick Reference

### Deployment Command

```bash
bash shellscripts/deploy.sh
```

### What Gets Authorized

```
AgentRouter
├── PolicyFactory ✅
├── BalanceManager ✅
├── LendingManager ✅
└── PoolManager ✅
```

### Expected Output

```
Step 6: Authorizing AgentRouter in PolicyFactory...
[OK] AgentRouter authorized in PolicyFactory

Step 7: Authorizing AgentRouter in BalanceManager...
[OK] AgentRouter authorized in BalanceManager

Step 8: Authorizing AgentRouter in LendingManager...
[OK] AgentRouter authorized in LendingManager

Step 9: Authorizing AgentRouter in PoolManager...
[OK] AgentRouter authorized in PoolManager
```

**All authorization issues prevented!** ✅
