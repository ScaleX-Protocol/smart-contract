# OrderBook Router Authorization - Solution Plan

## Problem
OrderBook.placeOrder() has `onlyRouter` modifier that only accepts:
- `$.router` (single authorized router, currently ScaleXRouter)
- `owner()` (PoolManager)
- `address(this)` (self-calls)

AgentRouter cannot place orders because it's not authorized.

---

## Solution Options

### Option 1: Add updatePoolRouter() to PoolManager ⭐ RECOMMENDED

**Description**: Add a function to PoolManager that calls setRouter() on OrderBook contracts.

**Changes Required**:
```solidity
// In PoolManager.sol
function updatePoolRouter(PoolId _poolId, address _newRouter) external onlyOwner {
    Storage storage $ = getStorage();
    require(address($.pools[_poolId].orderBook) != address(0), "Pool does not exist");
    require(_newRouter != address(0), "Invalid router");

    IOrderBook(address($.pools[_poolId].orderBook)).setRouter(_newRouter);

    emit PoolRouterUpdated(_poolId, _newRouter);
}
```

**Pros**:
- ✅ Minimal code changes (1 function, ~10 lines)
- ✅ No contract redeployment needed
- ✅ Follows existing pattern (see updatePoolTradingRules at line 109)
- ✅ No breaking changes to architecture
- ✅ Can update existing pools on mainnet/testnet
- ✅ Least error-prone - simple function call

**Cons**:
- ⚠️ Still single-router architecture (can only have AgentRouter OR ScaleXRouter, not both)
- ⚠️ Need to decide: keep ScaleXRouter or switch to AgentRouter

**Implementation Steps**:
1. Add `updatePoolRouter()` function to PoolManager.sol
2. Add event `PoolRouterUpdated(PoolId poolId, address newRouter)`
3. Redeploy PoolManager proxy implementation
4. Call `updatePoolRouter()` for WETH/IDRX pool to set AgentRouter
5. Test agent order execution

**Risk Level**: LOW
**Effort**: LOW (30 minutes)

---

### Option 2: Multi-Router Support in OrderBook

**Description**: Modify OrderBook to support multiple authorized routers via mapping.

**Changes Required**:
```solidity
// In OrderBook.sol storage
mapping(address => bool) authorizedRouters;

// Modifier change
modifier onlyRouter() {
    if (!authorizedRouters[msg.sender] && msg.sender != owner() && msg.sender != address(this)) {
        revert UnauthorizedRouter(msg.sender);
    }
    _;
}

// New functions
function addAuthorizedRouter(address router) external onlyOwner { ... }
function removeAuthorizedRouter(address router) external onlyOwner { ... }
```

**Pros**:
- ✅ Both ScaleXRouter and AgentRouter can work simultaneously
- ✅ More flexible architecture
- ✅ No conflicts between different router types

**Cons**:
- ❌ Requires OrderBook contract changes
- ❌ All OrderBooks need redeployment or upgrade
- ❌ Need to migrate existing orders and liquidity
- ❌ Storage layout changes (if using upgradeable proxies, need careful slot management)
- ❌ More complex - multiple authorization points
- ❌ Higher risk of introducing bugs

**Risk Level**: MEDIUM-HIGH
**Effort**: HIGH (2-3 hours + testing)

---

### Option 3: AgentRouter Routes Through ScaleXRouter

**Description**: Make AgentRouter call ScaleXRouter instead of OrderBook directly.

**Changes Required**:
```solidity
// In AgentRouter.executeLimitOrder()
// Instead of: orderBook.placeOrder(...)
// Do: IScaleXRouter(scaleXRouter).placeOrder(...)
```

**Pros**:
- ✅ No OrderBook changes needed
- ✅ Works with existing infrastructure

**Cons**:
- ❌ Coupling between AgentRouter and ScaleXRouter
- ❌ Need to understand ScaleXRouter interface
- ❌ Potential circular dependencies
- ❌ ScaleXRouter may not support all AgentRouter features
- ❌ ScaleXRouter may have its own authorization checks
- ❌ Adds extra hop in execution (gas cost)

**Risk Level**: MEDIUM
**Effort**: MEDIUM (1-2 hours)

---

### Option 4: Deploy New OrderBooks

**Description**: Create new pools with AgentRouter as the authorized router.

**Cons**:
- ❌ Breaks existing liquidity
- ❌ Breaks existing orders
- ❌ Users need to migrate
- ❌ Two separate order books for same pairs
- ❌ Not a real solution, just avoidance

**Risk Level**: HIGH (user impact)
**Effort**: LOW (but wrong approach)

---

## RECOMMENDATION: Option 1

**Rationale**:
1. **Simplest**: Just add 1 function to PoolManager
2. **Safest**: Follows existing pattern (updatePoolTradingRules)
3. **No redeployment**: Works with current OrderBook contracts
4. **Quick**: Can be implemented and tested in < 1 hour

**Trade-off**:
- Must choose between ScaleXRouter and AgentRouter (can't have both)
- **Proposed**: Switch to AgentRouter since:
  - AgentRouter is newer, more feature-rich
  - Includes all standard order placement logic
  - Adds policy enforcement and agent authorization on top
  - Can handle both agent and non-agent orders

**Implementation Priority**: HIGH
**Timeline**: Immediate (can fix today)

---

## Next Steps

1. Implement Option 1 (updatePoolRouter in PoolManager)
2. Test with existing pools on Base Sepolia
3. Run TestAgentOrderExecution.s.sol to verify
4. If single-router limitation becomes issue, revisit Option 2

---

## Decision

**Selected Solution**: Option 1 - Add updatePoolRouter() to PoolManager

**Reason**: Lowest risk, minimal code, follows existing patterns, no breaking changes
