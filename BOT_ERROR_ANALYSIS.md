# Bot Error Analysis - Bots Are Stopped

## 🚨 CRITICAL ISSUE: Both Bots Are Not Running 🚨

**Container Status:**
- `base-sepolia-trading-bots`: **Exited (128)** - Stopped 7 days ago (Jan 28, 12:42 PM)
- `base-sepolia-mm-bot`: **Exited (137)** - Stopped 4 days ago (Jan 31)

**Exit Codes:**
- Exit 128: Process was terminated (received SIGTERM or manual stop)
- Exit 137: Process was killed (received SIGKILL, possibly OOM or forced kill)

This explains why there are **NO NEW TRADES** on the indexer since Jan 28th.

### Immediate Actions Required

**1. Restart the bots:**
```bash
# Restart trading bot
docker start base-sepolia-trading-bots

# Restart MM bot
docker start base-sepolia-mm-bot

# Verify they're running
docker ps | grep base-sepolia

# Monitor logs in real-time
docker logs -f base-sepolia-trading-bots
docker logs -f base-sepolia-mm-bot
```

**2. Investigate why they stopped:**

**Trading Bot** - Last log shows:
```
[2026-01-28T12:42:52.757Z] "Trading bot stopped"
[2026-01-28T12:42:52.762Z] "Cleanup scheduler stopped"
```
This was a **graceful shutdown** - likely triggered by:
- Manual stop command
- Process received SIGTERM
- Application logic shutdown condition met

**MM Bot** - Exit code 137 suggests:
- Out of Memory (OOM) kill
- Force killed by system or orchestrator
- Check system memory usage

**3. Check for auto-restart configuration:**
```bash
# Check restart policy
docker inspect base-sepolia-trading-bots | grep -A 3 RestartPolicy
docker inspect base-sepolia-mm-bot | grep -A 3 RestartPolicy
```

**4. Set up auto-restart (recommended):**
```bash
# Update restart policy to always restart
docker update --restart=unless-stopped base-sepolia-trading-bots
docker update --restart=unless-stopped base-sepolia-mm-bot
```

## Historical Errors (When Bots Were Running)

The bots were experiencing a massive number of errors (108,732 total `OrderIsNotOpenOrder` errors), but these were **NOT actual order placement failures**. They were order **cancellation** errors caused by a race condition between the indexer API and on-chain state.

## Error Breakdown

### Market Maker Bot (base-sepolia-mm-bot)

#### Primary Error: OrderIsNotOpenOrder (108,732 occurrences)
- **57,260 errors**: Trying to cancel orders with status 2 (FILLED)
- **26,380 errors**: Trying to cancel orders with status 3 (CANCELLED)
- **25,092 errors**: Other status codes

**What's happening:**
The MM bot tries to cancel orders that have already been filled or cancelled on-chain. The bot's local order tracking (via indexer API) is out of sync with the actual blockchain state.

#### Secondary Error: NegativeSpreadCreated (204 occurrences)
The bot occasionally tries to place limit orders that would create a negative spread (bid > ask), which the contract rejects.

**Example:**
```
Error: NegativeSpreadCreated(uint128 bestBid, uint128 bestAsk)
                            (298500, 272700)
```
The bot tried to place a bid at 298,500 when the best ask was 272,700, which would cross the spread.

### Trading Bot (base-sepolia-trading-bots)
No significant errors in recent logs. Orders are simulating and placing successfully.

## Order Status Enum (from IOrderBook.sol)
```solidity
enum Status {
    OPEN,            // 0
    PARTIALLY_FILLED, // 1
    FILLED,          // 2
    CANCELLED,       // 3
    REJECTED,        // 4
    EXPIRED          // 5
}
```

## Root Causes

### 1. Race Condition in Order Cancellation
**Problem:** The MM bot workflow:
1. Fetches "active orders" from indexer API (500 orders)
2. Decides which orders to cancel
3. Attempts to cancel them via smart contract
4. By the time cancellation is attempted, orders are already filled/cancelled

**Evidence:**
```
[2026-01-31T07:46:09.093Z] API request successful - ordersCount: 500
[2026-01-31T07:46:09.868Z] ERROR - Order cancellation failed: OrderIsNotOpenOrder (status: 2)
```

The indexer API returns orders as "active" that have already been filled/cancelled on-chain.

### 2. Indexer Lag
The indexer API (`https://base-sepolia-indexer.scalex.money/api/openOrders`) is slightly behind the blockchain state, causing stale data to be returned.

### 3. Order Lifecycle Timing
With high trading activity, orders placed by the MM bot are being filled almost immediately by the trading bots or external users, but the MM bot still tries to cancel them as part of its rebalancing logic.

## Impact Assessment

### Severity: Low to Medium
- ✅ **Orders ARE being placed successfully** - No order placement failures detected
- ✅ **Trading is functioning** - The errors don't prevent new orders from being created
- ❌ **High error volume** - 108K+ errors in logs create noise and may impact performance
- ❌ **Wasted gas** - Attempting to cancel already-filled orders consumes gas unnecessarily

### Performance Impact
- The bot makes hundreds of failed contract simulation calls per minute
- API is being queried frequently (every few seconds)
- Error handling and logging overhead

## Recommended Fixes

### Priority 1: Add Order State Validation Before Cancellation
**File:** `../mm-bot/src/services/contractService.ts` (line ~280)

Before attempting to cancel an order:
1. Query the on-chain order status directly from the contract
2. Only attempt cancellation if status is OPEN (0) or PARTIALLY_FILLED (1)
3. Cache order statuses briefly to reduce RPC calls

```typescript
// Pseudo-code
async function cancelOrder(orderId) {
  const onChainOrder = await contract.getOrder(orderId);

  if (onChainOrder.status !== Status.OPEN &&
      onChainOrder.status !== Status.PARTIALLY_FILLED) {
    logger.debug(`Order ${orderId} is not cancellable (status: ${onChainOrder.status})`);
    return { success: false, reason: 'already_finalized' };
  }

  // Proceed with cancellation
  return await contract.cancelOrder(...);
}
```

### Priority 2: Handle OrderIsNotOpenOrder Gracefully
This error is **expected** in a high-frequency trading environment. Treat it as a non-error:

```typescript
try {
  await cancelOrder(orderId);
} catch (error) {
  if (error.name === 'OrderIsNotOpenOrder') {
    // This is fine - order was already filled/cancelled
    logger.debug(`Order ${orderId} already finalized`);
    return;
  }
  // Only log as ERROR for unexpected failures
  logger.error('Unexpected cancellation error', error);
}
```

### Priority 3: Improve Indexer Freshness
**Option A:** Add a real-time event listener in the MM bot
- Listen to `OrderFilled`, `OrderCancelled`, `UpdateOrder` events
- Update local order cache immediately when events are received
- Fall back to API only for initial sync

**Option B:** Add a timestamp check
- Compare order's last update timestamp with current time
- Skip cancellation attempts for orders updated in last 2-3 blocks

### Priority 4: Fix NegativeSpread Errors
**File:** `../mm-bot/src/services/priceCalculation.ts` (or similar)

Before placing orders:
1. Fetch current best bid/ask from contract
2. Validate that new bid < best ask and new ask > best bid
3. Add a minimum spread buffer (e.g., 1% minimum spread)

```typescript
const bestAsk = await contract.getBestPrice(Side.SELL);
const bestBid = await contract.getBestPrice(Side.BUY);

// Ensure we maintain spread
if (side === Side.BUY && newBidPrice >= bestAsk) {
  newBidPrice = bestAsk * 0.99; // 1% below ask
}
if (side === Side.SELL && newAskPrice <= bestBid) {
  newAskPrice = bestBid * 1.01; // 1% above bid
}
```

## Quick Wins

1. **Change log level** - Move `OrderIsNotOpenOrder` errors to DEBUG level
2. **Add metrics** - Track cancellation success rate to monitor improvement
3. **Reduce API polling** - Increase interval between `getUserActiveOrders` calls
4. **Add circuit breaker** - If >80% of cancellations fail, pause and resync state

## Testing Recommendations

After implementing fixes:
1. Monitor error rate for 1 hour - should drop by 90%+
2. Check gas consumption - should decrease significantly
3. Verify order placement still works correctly
4. Ensure spread maintenance logic works properly

## Contract References

- Order status validation: `/Users/renaka/gtx/clob-dex/src/core/OrderBook.sol:743-745`
- Error definition: `/Users/renaka/gtx/clob-dex/src/core/interfaces/IOrderBookErrors.sol:24`
- Status enum: `/Users/renaka/gtx/clob-dex/src/core/interfaces/IOrderBook.sol:13-20`
