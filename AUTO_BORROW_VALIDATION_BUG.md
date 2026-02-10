# Auto-Borrow Validation Bug Fix

**Date:** 2026-02-06
**Severity:** Critical
**Status:** ✅ Fixed
**Affected Component:** OrderBook.sol - `_validateAutoBorrow` function

---

## Executive Summary

The `_validateAutoBorrow` function contained **fundamentally flawed logic** that prevented users from placing orders with auto-borrow enabled, even when they had sufficient collateral.

---

## The Bug

### Broken Logic (Lines 306-334)

```solidity
function _validateAutoBorrow(address user, Side side) private view {
    // For SELL orders, determine token to borrow
    if (side == Side.SELL) {
        tokenToBorrow = baseCurrency; // e.g., WETH
    } else {
        tokenToBorrow = quoteCurrency; // e.g., IDRX
    }

    // ❌ WRONG: Check if user has SUPPLIED the token they want to BORROW
    getUserSupply(user, tokenToBorrow)
    if (userSupply == 0) {
        revert NoCollateralToBorrow();
    }
}
```

### Why This Is Wrong

The function checks if the user has **supplied** the same token they want to **borrow**. This is backwards logic:

**Example Scenario:**
- User wants to place a SELL order for WETH/IDRX
- User has 1000 IDRX as collateral
- User wants to **borrow** WETH to sell
- Validation checks: "Do you have WETH supplied?"
- User: "No, I want to borrow WETH using my IDRX collateral!"
- Contract: `NoCollateralToBorrow()` ❌

**The Logic Should Be:**
- Check if user has **ANY** collateral (not specifically the token being borrowed)
- User with IDRX collateral should be able to borrow WETH
- User with WETH collateral should be able to borrow IDRX

---

## The Fix

### New Logic

```solidity
function _validateAutoBorrow(address user, Side side) private view {
    IBalanceManager bm = IBalanceManager(getStorage().balanceManager);
    address lendingManager = bm.lendingManager();

    if (lendingManager == address(0)) {
        return;
    }

    // Check if user has ANY collateral by checking their health factor
    try ILendingManager(lendingManager).getHealthFactor(user) returns (uint256 healthFactor) {
        // Health factor of 0 means no collateral supplied
        // Health factor of type(uint256).max means collateral but no debt (perfect for borrowing)
        // Any positive health factor means user has collateral
        if (healthFactor == 0) {
            revert NoCollateralToBorrow();
        }
    } catch {
        // If health factor check fails, allow to proceed
        // Actual borrow will fail if insufficient collateral
    }
}
```

### What Changed

✅ **Before:** Checked if user has supplied the specific token they want to borrow
✅ **After:** Checks if user has ANY collateral via health factor
✅ **Result:** Users with collateral can now use auto-borrow for any token

---

## Impact

### Affected Orders

This bug affected **ALL orders** with `autoBorrow = true`:
- ❌ Limit BUY orders with autoBorrow
- ❌ Limit SELL orders with autoBorrow
- ❌ Market BUY orders with autoBorrow
- ❌ Market SELL orders with autoBorrow

### User Experience Before Fix

Users would see:
```
Error: NoCollateralToBorrow()
```

Even when they had:
- ✅ Sufficient collateral deposited
- ✅ Good health factor
- ✅ Borrowing power available

---

## Testing

### Test Scenarios

1. **User with IDRX collateral borrowing WETH:**
   - Supply: 1000 IDRX
   - Order: SELL WETH (requires borrowing WETH)
   - Before: ❌ `NoCollateralToBorrow()`
   - After: ✅ Order placed successfully

2. **User with WETH collateral borrowing IDRX:**
   - Supply: 1 WETH
   - Order: BUY WETH (requires borrowing IDRX)
   - Before: ❌ `NoCollateralToBorrow()`
   - After: ✅ Order placed successfully

3. **User with no collateral:**
   - Supply: 0
   - Order: Any order with autoBorrow
   - Before: ❌ `NoCollateralToBorrow()`
   - After: ❌ `NoCollateralToBorrow()` (correct behavior)

---

## Related Issues

This fix complements the **Market Order Auto-Borrow Fix** deployed earlier:
- **Validation Fix:** Allows orders to be placed (this fix)
- **Execution Fix:** Ensures auto-borrow executes during market order matching (previous fix)

Both fixes were needed for complete auto-borrow functionality.

---

## Deployment

**Network:** Base Sepolia (84532)
**Beacon:** 0x2f95340989818766fe0bf339028208f93191953a
**Previous Implementation:** 0x67606a5fa1d1a1CF802a95133c538159af66016c (market order fix)
**New Implementation:** 0xe8a7ae54BbccB2ce015A54b161252E18ab930948 ✅ (validation fix)

**Deployment Status:** ✅ SUCCESSFUL
**Verification:**
```bash
cast call 0x2f95340989818766fe0bf339028208f93191953a "implementation()(address)" --rpc-url https://sepolia.base.org
# Returns: 0xe8a7ae54BbccB2ce015A54b161252E18ab930948 ✅
```

---

## Timeline

- **Jan 27, 2026:** Original deployment with bug
- **Feb 6, 2026:** Market order auto-borrow bug discovered and fixed
- **Feb 6, 2026:** Validation bug discovered and fixed (this fix)
