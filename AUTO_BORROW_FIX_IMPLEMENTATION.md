# Auto-Borrow Fix Implementation

**Date:** 2026-02-06
**Issue:** Auto-borrow not working for market BUY orders
**Status:** ✅ Fixed

---

## Summary

Implemented auto-borrow functionality for market BUY orders by adding the missing `_handleAutoBorrow` call in the `_matchAtPriceLevelWithQuoteAmount` function.

---

## Changes Made

### File Modified
- **File:** `src/core/OrderBook.sol`
- **Function:** `_matchAtPriceLevelWithQuoteAmount`
- **Lines:** 681-707 (updated balance check logic)

### Before (Broken Code)

```solidity
IBalanceManager bm = IBalanceManager($.balanceManager);
if (bm.getBalance(ctx.user, ctx.quoteCurrency) < quoteAmount) {
    // BUG: Just reduced order size without attempting to borrow
    baseAmount = uint128(
        PoolIdLibrary.quoteToBase(bm.getBalance(ctx.user, ctx.quoteCurrency), ctx.bestPrice, ctx.baseDecimals)
    );
    if (baseAmount == 0) break;
    quoteAmount = uint128(
        PoolIdLibrary.baseToQuote(baseAmount, ctx.bestPrice, ctx.baseDecimals)
    );
}
```

**Problem:** When insufficient balance was detected, the code immediately reduced the order size without checking if auto-borrow was enabled or attempting to borrow.

### After (Fixed Code)

```solidity
IBalanceManager bm = IBalanceManager($.balanceManager);
uint256 currentBalance = bm.getBalance(ctx.user, ctx.quoteCurrency);

if (currentBalance < quoteAmount) {
    // If auto-borrow is enabled, attempt to borrow the shortfall
    if (order.autoBorrow) {
        uint256 shortfall = quoteAmount - currentBalance;

        // Attempt to borrow the shortfall
        _handleAutoBorrow(ctx.user, shortfall, ctx.bestPrice, Side.BUY, order.id);

        // Re-check balance after borrow attempt
        currentBalance = bm.getBalance(ctx.user, ctx.quoteCurrency);
    }

    // If still insufficient balance (autoBorrow disabled, failed, or wasn't enough),
    // reduce execution to available balance
    if (currentBalance < quoteAmount) {
        baseAmount = uint128(
            PoolIdLibrary.quoteToBase(currentBalance, ctx.bestPrice, ctx.baseDecimals)
        );
        if (baseAmount == 0) break;
        quoteAmount = uint128(
            PoolIdLibrary.baseToQuote(baseAmount, ctx.bestPrice, ctx.baseDecimals)
        );
    }
}
```

**Improvements:**
1. ✅ Stores balance in `currentBalance` variable for reuse
2. ✅ Checks if `order.autoBorrow` is enabled
3. ✅ Calculates the shortfall amount
4. ✅ Calls `_handleAutoBorrow` to borrow the shortfall
5. ✅ Re-checks balance after borrow attempt
6. ✅ Only reduces order size if balance is still insufficient after borrow

---

## How It Works

### Flow Diagram

```
┌─────────────────────────────────────────┐
│ User places market BUY order            │
│ - Amount: 300 IDRX                      │
│ - Balance: 250 IDRX                     │
│ - autoBorrow: true                      │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ _matchAtPriceLevelWithQuoteAmount       │
│ - Calculate quote needed for match      │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ Check: currentBalance < quoteAmount?    │
│ - 250 < 300? YES                        │
└──────────────┬──────────────────────────┘
               │
               ▼
        ┌──────┴──────┐
        │ autoBorrow? │
        └──────┬──────┘
               │ YES
               ▼
┌─────────────────────────────────────────┐
│ Calculate shortfall                     │
│ - shortfall = 300 - 250 = 50 IDRX       │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ _handleAutoBorrow(user, 50, ...)        │
│ - Calls LendingManager.borrow()         │
│ - Emits AutoBorrowExecuted event        │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ Re-check balance                        │
│ - currentBalance = 300 IDRX ✅          │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ Check: currentBalance < quoteAmount?    │
│ - 300 < 300? NO                         │
│ - Skip reduction, use full amount       │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ Execute trade with full amount          │
│ - Executed: 300 IDRX ✅                 │
│ - Borrowed: 50 IDRX ✅                  │
└─────────────────────────────────────────┘
```

---

## Edge Cases Handled

### 1. Auto-Borrow Disabled
```
User Balance: 250 IDRX
Order Amount: 300 IDRX
autoBorrow: false

Result:
- No borrow attempt
- Order reduced to 250 IDRX
- Executes with available balance
```

### 2. Auto-Borrow Succeeds
```
User Balance: 250 IDRX
Order Amount: 300 IDRX
autoBorrow: true
Collateral: Sufficient

Result:
- Borrows 50 IDRX ✅
- Order executes 300 IDRX ✅
- AutoBorrowExecuted event emitted ✅
```

### 3. Auto-Borrow Fails (Insufficient Collateral)
```
User Balance: 250 IDRX
Order Amount: 300 IDRX
autoBorrow: true
Collateral: Insufficient (HF would drop below 1.0)

Result:
- Borrow attempt fails
- AutoBorrowFailed event emitted
- Order reduced to 250 IDRX
- Executes with available balance (graceful degradation)
```

### 4. Auto-Borrow Partial Success
```
User Balance: 250 IDRX
Order Amount: 300 IDRX
autoBorrow: true
Max Safe Borrow: 30 IDRX (not enough for full 50)

Result:
- Borrows 30 IDRX (partial)
- New balance: 280 IDRX
- Order reduced to 280 IDRX
- Executes more than original balance, less than requested
```

### 5. Zero Balance with Auto-Borrow
```
User Balance: 0 IDRX
Order Amount: 100 IDRX
autoBorrow: true
Collateral: Sufficient

Result:
- Borrows full 100 IDRX ✅
- Order executes 100 IDRX ✅
- Fully borrowing-funded execution
```

---

## Testing Recommendations

### Unit Tests to Add

```solidity
// Test 1: Market BUY with sufficient balance (no borrow needed)
function test_marketBuy_sufficientBalance_noBorrow() public {
    // Setup: User has 300 IDRX
    // Order: 250 IDRX with autoBorrow=true
    // Expected: No borrow, full execution
}

// Test 2: Market BUY with insufficient balance, autoBorrow disabled
function test_marketBuy_insufficientBalance_autoBorrowDisabled() public {
    // Setup: User has 250 IDRX
    // Order: 300 IDRX with autoBorrow=false
    // Expected: No borrow attempt, partial execution (250)
}

// Test 3: Market BUY with insufficient balance, autoBorrow enabled, sufficient collateral
function test_marketBuy_insufficientBalance_autoBorrowSuccess() public {
    // Setup: User has 250 IDRX, sufficient collateral
    // Order: 300 IDRX with autoBorrow=true
    // Expected: Borrow 50, full execution (300)
    // Verify: AutoBorrowExecuted event emitted
    // Verify: LendingManager.getUserDebt increased by 50
}

// Test 4: Market BUY with insufficient balance, autoBorrow enabled, insufficient collateral
function test_marketBuy_insufficientBalance_autoBorrowFails() public {
    // Setup: User has 250 IDRX, insufficient collateral (HF would drop < 1.0)
    // Order: 300 IDRX with autoBorrow=true
    // Expected: Borrow attempt fails, partial execution (250)
    // Verify: AutoBorrowFailed event emitted
}

// Test 5: Market BUY with zero balance, autoBorrow enabled
function test_marketBuy_zeroBalance_autoBorrowSuccess() public {
    // Setup: User has 0 IDRX, sufficient collateral
    // Order: 100 IDRX with autoBorrow=true
    // Expected: Borrow full 100, full execution
}

// Test 6: Market BUY across multiple price levels with autoBorrow
function test_marketBuy_multiplePriceLevels_autoBorrow() public {
    // Setup: Order matches against 3 price levels
    // Each match may trigger borrow
    // Verify: Cumulative borrow amount correct
    // Verify: All AutoBorrowExecuted events emitted
}

// Test 7: Verify parity with market SELL
function test_marketBuyAndSell_autoBorrow_parity() public {
    // Run identical scenario for BUY and SELL
    // Both should auto-borrow correctly
    // Both should emit same events
}
```

### Integration Tests

```solidity
// Test: End-to-end market BUY with auto-borrow
function testIntegration_marketBuy_autoBorrow() public {
    // 1. Setup lending pool with liquidity
    // 2. Setup user with collateral but no quote currency
    // 3. Place market BUY order with autoBorrow=true
    // 4. Verify:
    //    - Order executes fully
    //    - Borrow event emitted
    //    - User debt increased
    //    - User received base tokens
    //    - Health factor updated correctly
}

// Test: Auto-borrow respects health factor limits
function testIntegration_autoBorrow_healthFactorLimit() public {
    // 1. Setup user with minimal collateral
    // 2. Place order that would exceed safe HF
    // 3. Verify borrow fails or partial execution
}
```

---

## Event Verification

After the fix, the following events should be emitted for a successful auto-borrow:

```solidity
// Event sequence for market BUY with auto-borrow
emit OrderPlaced(orderId, user, Side.BUY, 0, quoteAmount, expiry, true, Status.OPEN, false, true, TimeInForce.IOC);
emit AutoBorrowExecuted(user, quoteToken, borrowAmount, timestamp, orderId);  // ✅ NEW
emit OrderMatched(user, orderId, matchingOrderId, Side.BUY, timestamp, price, quantity);
emit UpdateOrder(orderId, timestamp, filled, Status.FILLED);
```

Previously, the `AutoBorrowExecuted` event was missing for market BUY orders.

---

## Performance Considerations

### Gas Impact

**Additional Operations:**
- 1 extra balance check (after borrow attempt)
- 1 call to `_handleAutoBorrow` (only when needed)
- 1 external call to `LendingManager.borrow()` (only when needed)

**Estimated Gas Increase:**
- ~50,000 gas when auto-borrow triggers
- ~5,000 gas overhead for extra balance check when auto-borrow enabled but not needed
- 0 gas increase when auto-borrow disabled

**Optimization Notes:**
- Balance is cached in `currentBalance` variable to avoid redundant reads
- Borrow only triggered when actually needed (insufficient balance)
- Graceful fallback if borrow fails (no revert, just partial execution)

---

## Backwards Compatibility

### ✅ Fully Backwards Compatible

**No Breaking Changes:**
- Function signature unchanged
- Existing orders without auto-borrow work identically
- Auto-repay functionality unaffected
- Market SELL orders unaffected

**New Behavior:**
- Only affects market BUY orders with `autoBorrow=true`
- Previously: partial execution
- Now: full execution with borrow

---

## Security Considerations

### Safety Measures

1. **Health Factor Validation:**
   - `_handleAutoBorrow` internally checks health factor
   - Borrow will fail if HF would drop below 1.0
   - Prevents over-leveraging

2. **Graceful Degradation:**
   - If borrow fails, order still executes with available balance
   - No transaction revert on borrow failure
   - User gets best possible execution

3. **Event Logging:**
   - `AutoBorrowExecuted` for successful borrows
   - `AutoBorrowFailed` for failed attempts
   - Full audit trail

4. **Reentrancy Protection:**
   - Function already has `nonReentrant` modifier (line 458)
   - LendingManager calls are external but safe

---

## Deployment Checklist

- [ ] Code review completed
- [ ] Unit tests written and passing
- [ ] Integration tests written and passing
- [ ] Gas benchmarking completed
- [ ] Security audit (if required)
- [ ] Deploy to testnet
- [ ] Verify fix with original transaction scenario
- [ ] Monitor auto-borrow events on testnet
- [ ] Deploy to mainnet
- [ ] Update documentation
- [ ] Notify users of fix

---

## Related Documentation

- **Bug Report:** `AUTO_BORROW_BUG_REPORT.md`
- **Function Reference:** `OrderBook.sol:_matchAtPriceLevelWithQuoteAmount`
- **Borrow Implementation:** `OrderBook.sol:_handleAutoBorrow`
- **Lending Manager:** `LendingManager.sol:borrow`

---

## Verification Steps

To verify the fix works:

1. **Deploy updated contract to testnet**
2. **Setup test scenario:**
   - User with 250 IDRX balance
   - User with sufficient collateral for borrowing
3. **Place market BUY order:**
   - Amount: 300 IDRX
   - autoBorrow: true
4. **Verify transaction:**
   - Check executed quantity = 300 IDRX ✅
   - Check `AutoBorrowExecuted` event present ✅
   - Check user debt increased by 50 IDRX ✅
   - Check user received 300 IDRX worth of base tokens ✅

---

## Success Criteria

✅ Market BUY orders with auto-borrow now:
- Borrow the shortfall when needed
- Execute full requested amount (if collateral allows)
- Emit `AutoBorrowExecuted` events
- Match behavior of market SELL orders
- Maintain backwards compatibility

---

**Implementation Complete:** 2026-02-06
**Ready for Testing:** Yes
**Ready for Deployment:** Pending test results
