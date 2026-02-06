# Auto-Borrow Bug Report: Market BUY Orders

**Date:** 2026-02-06
**Severity:** High
**Status:** Identified - Pending Fix
**Affected Component:** OrderBook.sol - Market Order Execution

---

## Executive Summary

Auto-borrow functionality is **broken for market BUY orders** but works correctly for market SELL orders. When users place market BUY orders with `autoBorrow = true` and insufficient balance, the order executes with only the available balance instead of borrowing the shortfall.

**Impact:**
- Users cannot leverage auto-borrow for market BUY orders
- Orders execute partially even when user expects full execution with borrowed funds
- No borrow events are emitted
- Frontend shows misleading behavior (order seems to succeed but executes less than requested)

---

## Feature Status Matrix

| Feature | Market BUY | Market SELL | Status |
|---------|------------|-------------|--------|
| **Auto-Repay** | ✅ Works | ✅ Works | **GOOD** |
| **Auto-Borrow** | ❌ Broken | ✅ Works | **BUG** |

---

## Root Cause Analysis

### Different Execution Paths

The OrderBook contract uses **different matching algorithms** for market BUY vs SELL orders:

#### Market SELL Orders (✅ Auto-Borrow Works)
```
placeMarketOrder (line 452)
  → validateOrderBalance with autoBorrow check (line 476)
  → _matchOrder (line 498)
  → _processMatchingOrder (line 1002)
  → _handleAutoBorrow (lines 835-844) ✅ TRIGGERED
```

#### Market BUY Orders (❌ Auto-Borrow Broken)
```
placeMarketOrder (line 469)
  → _placeMarketOrderWithQuoteAmount (line 470)
  → validateOrderBalance with autoBorrow check (line 539)
  → _matchOrderWithQuoteAmount (line 561)
  → Balance check at line 682
  → ❌ _handleAutoBorrow NEVER CALLED
  → Order quantity reduced to available balance (lines 683-690)
```

### The Critical Code Section

**File:** `src/core/OrderBook.sol`
**Function:** `_matchOrderWithQuoteAmount`
**Lines:** 682-690

```solidity
if (bm.getBalance(ctx.user, ctx.quoteCurrency) < quoteAmount) {
    // BUG: This reduces the order size instead of borrowing
    baseAmount = uint128(
        PoolIdLibrary.quoteToBase(
            bm.getBalance(ctx.user, ctx.quoteCurrency),
            ctx.bestPrice,
            ctx.baseDecimals
        )
    );
    if (baseAmount == 0) break;
    quoteAmount = uint128(
        PoolIdLibrary.baseToQuote(baseAmount, ctx.bestPrice, ctx.baseDecimals)
    );
}
// Missing: _handleAutoBorrow call
```

**What should happen:**
1. Detect insufficient balance
2. If `order.autoBorrow == true`, call `_handleAutoBorrow` to borrow the shortfall
3. Re-check balance after borrow
4. Proceed with full execution if borrow succeeded

**What actually happens:**
1. Detect insufficient balance
2. Reduce `baseAmount` to only what user can afford
3. Execute partial order
4. No borrow event emitted

---

## Detailed Issue Report

### Observed Behavior

**Transaction:** `0xdb617c71cb4d6b103ea42e81555fc937fa130ab2cf78e51edc6fc06cb2103e1f`
**Network:** Base Sepolia

**Setup:**
- User balance: 250 IDRX
- Order placed: Market BUY for > 250 IDRX
- Auto-borrow: `true`
- Expected: Borrow shortfall and execute full order

**Result:**
- Executed quantity: < 250 IDRX (only available balance)
- No `AutoBorrowExecuted` event emitted
- No `Borrow` event from LendingManager
- Order marked as successful but partially filled

**Indexer Data:**
```
Previous Balance: 250 IDRX
Order Quantity: >250 IDRX (exact amount from frontend)
Executed Quantity: <250 IDRX (from indexer)
Borrowed Amount: 0 IDRX ❌
```

### Expected Behavior

**Transaction Flow:**
```
1. User places market BUY order: 300 IDRX
2. User has balance: 250 IDRX
3. Auto-borrow enabled: true
4. System detects shortfall: 50 IDRX
5. System borrows: 50 IDRX ✅
6. Order executes: 300 IDRX ✅
7. Events emitted:
   - OrderPlaced
   - AutoBorrowExecuted (50 IDRX) ✅
   - OrderMatched
   - Borrow (from LendingManager)
```

**Actual Flow:**
```
1. User places market BUY order: 300 IDRX
2. User has balance: 250 IDRX
3. Auto-borrow enabled: true
4. System detects shortfall: 50 IDRX
5. System reduces order: 250 IDRX ❌
6. Order executes: 250 IDRX ❌
7. Events emitted:
   - OrderPlaced
   - OrderMatched
   - (No borrow events) ❌
```

---

## Code Locations

### Primary Bug Location
- **File:** `src/core/OrderBook.sol`
- **Function:** `_matchOrderWithQuoteAmount`
- **Lines:** 682-690
- **Issue:** Missing `_handleAutoBorrow` call

### Related Code

#### Validation (Works Correctly)
- **Line 539:** `_validateOrderBalance(user, $.poolKey.quoteCurrency, quoteAmount, autoBorrow);`
- This correctly validates health factor for auto-borrow
- But validation alone doesn't trigger the borrow

#### Matching Entry Point
- **Line 561:** `uint128 baseAmountFilled = _matchOrderWithQuoteAmount(marketOrder, side, user, quoteAmount);`
- This is where BUY orders enter the broken path

#### Working Implementation (SELL Orders)
- **Function:** `_processMatchingOrder`
- **Lines 835-844:** Correctly calls `_handleAutoBorrow`
```solidity
// Check for auto-borrow on successful order fills
if (matchingOrder.autoBorrow) {
    _handleAutoBorrow(matchingOrder.user, executedQuantity, ctx.bestPrice, matchingOrder.side, matchingOrder.id);
}

if (ctx.order.autoBorrow) {
    uint256 primaryOrderAmount = executedQuantity;
    _handleAutoBorrow(ctx.user, primaryOrderAmount, ctx.bestPrice, ctx.order.side, ctx.order.id);
}
```

#### Borrow Implementation
- **Function:** `_handleAutoBorrow`
- **Lines:** 1342-1375
- This function works correctly when called

---

## Proposed Fix

### Option 1: Add Auto-Borrow to Quote Matching (Recommended)

**Location:** `src/core/OrderBook.sol`, function `_matchOrderWithQuoteAmount`, around line 682

```solidity
IBalanceManager bm = IBalanceManager($.balanceManager);
uint256 currentBalance = bm.getBalance(ctx.user, ctx.quoteCurrency);

if (currentBalance < quoteAmount) {
    // NEW: If auto-borrow is enabled, attempt to borrow the shortfall
    if (order.autoBorrow) {
        uint256 shortfall = quoteAmount - currentBalance;

        // Attempt to borrow the shortfall
        _handleAutoBorrow(ctx.user, shortfall, ctx.bestPrice, Side.BUY, order.id);

        // Re-check balance after borrow attempt
        uint256 newBalance = bm.getBalance(ctx.user, ctx.quoteCurrency);

        // If borrow was successful and we now have enough balance, continue with full amount
        if (newBalance >= quoteAmount) {
            // Proceed with full execution
            continue to next iteration with full quoteAmount
        }

        // If borrow failed or wasn't enough, update currentBalance for fallback
        currentBalance = newBalance;
    }

    // EXISTING FALLBACK: Reduce execution to available balance
    // This now only triggers if:
    // - autoBorrow is false, OR
    // - autoBorrow failed to provide sufficient funds
    baseAmount = uint128(
        PoolIdLibrary.quoteToBase(currentBalance, ctx.bestPrice, ctx.baseDecimals)
    );
    if (baseAmount == 0) break;
    quoteAmount = uint128(
        PoolIdLibrary.baseToQuote(baseAmount, ctx.bestPrice, ctx.baseDecimals)
    );
}
```

### Option 2: Refactor to Use Unified Matching

Refactor market BUY orders to use the same matching logic as SELL orders:
- Remove `_matchOrderWithQuoteAmount` or make it call `_matchOrder`
- Ensure `_processMatchingOrder` handles both BUY and SELL properly
- This would ensure consistent auto-borrow behavior

**Pros:**
- More maintainable (single code path)
- Less likely to have feature parity issues
- Auto-borrow works automatically

**Cons:**
- Larger refactor
- More testing required
- May affect performance

---

## Implementation Details

### Required Changes

1. **Modify `_matchOrderWithQuoteAmount`** (lines 682-690):
   - Add auto-borrow check before reducing order size
   - Call `_handleAutoBorrow` when shortfall detected
   - Re-check balance after borrow attempt
   - Only reduce order size if borrow failed

2. **Update `_matchAtPriceLevelWithQuoteAmount`** (if needed):
   - Ensure context includes `order.autoBorrow` flag
   - Pass order reference to matching function

3. **Add balance refresh logic**:
   - After `_handleAutoBorrow`, re-query balance
   - Continue with full order if borrow succeeded

### Edge Cases to Handle

1. **Partial Borrow Success:**
   - Borrow partially succeeds (not enough collateral for full amount)
   - Should execute with available + borrowed amount
   - May still be less than requested

2. **Borrow Failure:**
   - Health factor too low
   - No collateral
   - LendingManager unavailable
   - Fall back to current behavior (execute with available balance)

3. **Multiple Price Levels:**
   - Order may match against multiple price levels
   - May need to borrow at each level
   - Track cumulative borrows

4. **Gas Limits:**
   - Multiple borrow calls could increase gas
   - Consider batching or limiting borrow attempts

---

## Testing Plan

### Unit Tests

1. **Test: Market BUY with sufficient balance**
   - No borrow should trigger
   - Full execution

2. **Test: Market BUY with insufficient balance, autoBorrow=false**
   - No borrow attempt
   - Partial execution up to available balance

3. **Test: Market BUY with insufficient balance, autoBorrow=true**
   - Borrow triggered for shortfall
   - Full execution
   - Verify `AutoBorrowExecuted` event
   - Verify debt increased in LendingManager

4. **Test: Market BUY with insufficient balance, autoBorrow=true, insufficient collateral**
   - Borrow fails (health factor)
   - Partial execution with available balance
   - Verify `AutoBorrowFailed` event

5. **Test: Market BUY with zero balance, autoBorrow=true**
   - Borrow full amount
   - Full execution
   - Verify events

6. **Test: Market BUY across multiple price levels with autoBorrow**
   - May need multiple borrows
   - Verify all borrow events
   - Verify cumulative debt

### Integration Tests

1. **Test: Complete market BUY flow with auto-borrow**
   - Real LendingManager integration
   - Real BalanceManager integration
   - Verify balance changes
   - Verify debt changes
   - Verify collateral requirements

2. **Test: Market BUY auto-borrow with health factor limits**
   - Order size that would exceed safe HF
   - Should fail validation or partial execution

3. **Test: Combined auto-borrow scenarios**
   - Multiple users with auto-borrow
   - Concurrent orders
   - Edge cases with liquidity

### Comparison Tests

1. **Test: Verify parity between BUY and SELL**
   - Same scenario for BUY vs SELL
   - Both should auto-borrow correctly
   - Both should emit same events

2. **Test: Verify auto-repay still works**
   - Ensure fix doesn't break auto-repay
   - Test both BUY and SELL with auto-repay

---

## Frontend Implications

### Current Frontend Behavior

The frontend correctly:
1. Calculates `borrowAmountNeeded = max(0, amount - balance)`
2. Shows health factor projection
3. Passes `autoBorrow = true` to contract
4. Shows slider with max = balance + maxSafeBorrow

But the contract doesn't honor the auto-borrow request for BUY orders.

### Post-Fix Behavior

After the fix:
1. Frontend logic can remain unchanged
2. Orders will execute with full requested amount
3. Borrow events will appear in transaction logs
4. Indexer will show borrowed amount correctly
5. User debt will increase as expected

### User Experience Improvements

**Before Fix:**
- User requests 300 IDRX with 250 balance
- Expects full execution with 50 borrowed
- Actually gets 250 execution with 0 borrowed
- Confusing: "Why didn't it borrow?"

**After Fix:**
- User requests 300 IDRX with 250 balance
- Gets full 300 execution with 50 borrowed
- Clear events in transaction log
- Matches user expectations

---

## Risk Assessment

### Severity: High

**Impact:**
- Core feature (auto-borrow) not working for 50% of market orders
- Users may lose trading opportunities
- Inconsistent behavior between BUY/SELL creates confusion
- Potential loss of user trust

**Likelihood:**
- Any user attempting market BUY with auto-borrow is affected
- 100% reproduction rate

### Mitigation During Fix

1. **Add frontend warning:**
   - "Note: Auto-borrow currently only works for SELL orders"
   - Remove after fix deployed

2. **Document workaround:**
   - Use limit orders with auto-borrow (works correctly)
   - Pre-borrow before market BUY order

3. **Monitor:**
   - Track failed auto-borrow attempts
   - Notify users of fix deployment

---

## Related Issues

### Auto-Repay Status: ✅ Working

Auto-repay is implemented correctly for both BUY and SELL orders:
- Uses `transferBalances` which is called in both paths
- Line 1126: Handles BUY order auto-repay
- Line 1118: Handles SELL order auto-repay

**Key Difference:**
- Auto-repay triggers AFTER trade execution (when tokens are received)
- Auto-borrow must trigger BEFORE/DURING trade execution
- `transferBalances` is called in both paths ✅
- `_handleAutoBorrow` is only called in SELL path ❌

### Similar Issues to Check

1. **Limit orders with auto-borrow:**
   - Do both BUY and SELL limit orders support auto-borrow?
   - Check if they use the same broken path

2. **Other order types:**
   - FOK, IOC, PO orders with auto-borrow
   - Verify they route through correct matching logic

---

## References

### Transaction Evidence
- **TX Hash:** `0xdb617c71cb4d6b103ea42e81555fc937fa130ab2cf78e51edc6fc06cb2103e1f`
- **Explorer:** https://sepolia.basescan.org/tx/0xdb617c71cb4d6b103ea42e81555fc937fa130ab2cf78e51edc6fc06cb2103e1f
- **Indexer:** https://base-sepolia-indexer.scalex.money/

### Code References
- **Contract:** `src/core/OrderBook.sol`
- **Router:** `src/core/ScaleXRouter.sol` (passes flags correctly)
- **Frontend:** `apps/web/src/features/trade/hooks/order/usePrivyPlaceOrder.ts`

### Investigation Date
- **Reported:** 2026-02-06
- **Investigated:** 2026-02-06
- **Status:** Pending implementation

---

## Next Steps

1. ✅ Bug identified and documented
2. ⏳ Implement fix (Option 1 recommended)
3. ⏳ Write comprehensive unit tests
4. ⏳ Run integration tests
5. ⏳ Code review
6. ⏳ Deploy to testnet
7. ⏳ Verify with original transaction scenario
8. ⏳ Deploy to mainnet
9. ⏳ Update documentation
10. ⏳ Notify users

---

## Appendix: Code Snippets

### Working Auto-Borrow (SELL Orders)

```solidity
// From _processMatchingOrder (lines 833-844)
// Check for auto-borrow on successful order fills
if (matchingOrder.autoBorrow) {
    _handleAutoBorrow(
        matchingOrder.user,
        executedQuantity,
        ctx.bestPrice,
        matchingOrder.side,
        matchingOrder.id
    );
}

if (ctx.order.autoBorrow) {
    uint256 primaryOrderAmount = executedQuantity;
    _handleAutoBorrow(
        ctx.user,
        primaryOrderAmount,
        ctx.bestPrice,
        ctx.order.side,
        ctx.order.id
    );
}
```

### Broken Auto-Borrow (BUY Orders)

```solidity
// From _matchOrderWithQuoteAmount (lines 682-690)
if (bm.getBalance(ctx.user, ctx.quoteCurrency) < quoteAmount) {
    // BUG: Just reduces order size, never calls _handleAutoBorrow
    baseAmount = uint128(
        PoolIdLibrary.quoteToBase(
            bm.getBalance(ctx.user, ctx.quoteCurrency),
            ctx.bestPrice,
            ctx.baseDecimals
        )
    );
    if (baseAmount == 0) break;
    quoteAmount = uint128(
        PoolIdLibrary.baseToQuote(baseAmount, ctx.bestPrice, ctx.baseDecimals)
    );
}
// Missing: Call to _handleAutoBorrow
```

### Auto-Borrow Implementation

```solidity
// From _handleAutoBorrow (lines 1342-1375)
function _handleAutoBorrow(
    address user,
    uint256 amount,
    uint128 fillPrice,
    Side orderSide,
    uint48 orderId
) private {
    Storage storage $ = getStorage();

    IBalanceManager bm = IBalanceManager($.balanceManager);
    address lendingManager = bm.lendingManager();

    if (lendingManager == address(0)) {
        return;
    }

    // Determine which token needs to be borrowed
    address tokenToBorrow;
    if (orderSide == Side.SELL) {
        tokenToBorrow = Currency.unwrap($.poolKey.baseCurrency);
    } else {
        tokenToBorrow = Currency.unwrap($.poolKey.quoteCurrency);
    }

    try ILendingManager(lendingManager).borrow(tokenToBorrow, amount) {
        emit AutoBorrowExecuted(user, tokenToBorrow, amount, block.timestamp, orderId);
    } catch {
        emit AutoBorrowFailed(user, tokenToBorrow, amount, block.timestamp, orderId);
    }
}
```

---

**End of Report**
