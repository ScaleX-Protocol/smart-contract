# Oracle Auto-Fallback: Underlying → Synthetic Token Prices

## Overview

This feature enables the Oracle to automatically return synthetic token prices when queried for underlying token addresses. This eliminates redundant conversion logic across the codebase and prevents price lookup bugs.

## Problem Statement

Previously, when components like `LendingManager` needed token prices, they had to:
1. Manually convert underlying token addresses to synthetic token addresses
2. Query the Oracle with the synthetic token address
3. Handle cases where conversion failed

This led to:
- Duplicated conversion logic in multiple places
- Risk of forgetting conversion in new code
- Health factor calculation bugs (e.g., returning 0.000433 instead of 1.27)

## Solution

The Oracle now automatically resolves underlying tokens to their corresponding synthetic tokens before price lookups, using the authoritative `SyntheticTokenFactory` as the source of truth.

### Key Benefits

✅ **Centralized Logic**: Single source of truth for token resolution
✅ **Backwards Compatible**: Direct synthetic token queries still work
✅ **Error Prevention**: Impossible to forget conversion
✅ **Authoritative Source**: Uses factory where tokens are created
✅ **Active Validation**: Filters inactive/deprecated tokens

## Implementation Details

### Changes Made

1. **Oracle.sol** (`src/core/Oracle.sol`):
   - Added `SyntheticTokenFactory` reference storage
   - Added `setSyntheticTokenFactory()` owner function
   - Added `_resolveToken()` internal helper for fallback logic
   - Updated all price query functions to use `_resolveToken()`:
     - `getSpotPrice()`
     - `getTWAP()`
     - `getPriceForCollateral()`
     - `getPriceForBorrowing()`

2. **IOracle Interface** (`src/core/interfaces/IOracle.sol`):
   - Added `setSyntheticTokenFactory()` function signature

3. **LendingManager.sol** (`src/yield/LendingManager.sol`):
   - Simplified `_getTokenPrice()` to remove manual conversion
   - Now passes underlying token directly to Oracle

### Resolution Logic

```solidity
function _resolveToken(address token) internal view returns (address) {
    // CASE 1: Token already has direct price data (synthetic token)
    if (tokenPriceData[token].supported) {
        return token; // Direct hit - e.g., getSpotPrice(sxWETH) → sxWETH
    }

    // CASE 2: Token is underlying, find its synthetic via factory
    if (address(syntheticTokenFactory) != address(0)) {
        address syntheticToken = syntheticTokenFactory.getSyntheticToken(
            uint32(block.chainid),
            token
        );

        // Validate: exists, active, and has price data
        if (syntheticToken != address(0) &&
            syntheticTokenFactory.isSyntheticTokenActive(syntheticToken) &&
            tokenPriceData[syntheticToken].supported) {
            return syntheticToken; // Fallback - e.g., getSpotPrice(WETH) → sxWETH
        }
    }

    // CASE 3: Unknown token - fall back to original
    // Will revert with TokenNotSupported in calling function
    return token;
}
```

## Deployment Guide

### Prerequisites

- Oracle contract deployed and initialized
- SyntheticTokenFactory contract deployed and initialized
- Both contracts have synthetic tokens registered with prices

### Step 1: Identify Contract Addresses

From your deployment logs or registry, find:

```bash
# Example addresses (Testnet 11155111)
ORACLE_ADDRESS=0x...
SYNTHETIC_TOKEN_FACTORY_ADDRESS=0x...
```

### Step 2: Link Oracle to Factory

Run the linking script:

```bash
# Set environment variables
export ORACLE_ADDRESS=<your_oracle_address>
export SYNTHETIC_TOKEN_FACTORY_ADDRESS=<your_factory_address>
export RPC_URL=<your_rpc_url>
export PRIVATE_KEY=<owner_private_key>

# Run linking script
forge script script/LinkOracleToFactory.s.sol:LinkOracleToFactory \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

Or call directly via cast:

```bash
cast send $ORACLE_ADDRESS \
  "setSyntheticTokenFactory(address)" \
  $SYNTHETIC_TOKEN_FACTORY_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

### Step 3: Verify Configuration

Run the verification script:

```bash
forge script script/VerifyOracleFallback.s.sol:VerifyOracleFallback \
  --rpc-url $RPC_URL
```

Expected output:
```
=== Verifying Oracle Auto-Fallback ===
Oracle: 0x...
Factory: 0x...

1. Factory Configuration:
   Oracle.syntheticTokenFactory(): 0x...
   ✅ Factory configured correctly

2. Testing WETH:
   Synthetic WETH (sxWETH): 0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6
   Underlying WETH: 0x8b732595a59c9a18acA0Aca3221A656Eb38158fC
   Oracle.getSpotPrice(sxWETH): 300000000000
   Oracle.getSpotPrice(underlying): 300000000000
   ✅ Underlying query returns synthetic price ($ 3000)

3. Testing IDRX:
   ...
   ✅ Underlying query returns synthetic price ($ 1)

=== All Tests Passed ===
```

### Step 4: Manual Verification (Optional)

Test with cast commands:

```bash
# 1. Check factory is set
cast call $ORACLE_ADDRESS "syntheticTokenFactory()(address)" --rpc-url $RPC_URL
# Should return: <factory_address>

# 2. Query synthetic WETH price (direct - CASE 1)
cast call $ORACLE_ADDRESS "getSpotPrice(address)(uint256)" \
  0x49830c92204c0cBfc5c01B39E464A8Fa196ed6F6 --rpc-url $RPC_URL
# Should return: 300000000000 (3e11 = $3000.00)

# 3. Query underlying WETH price (fallback - CASE 2)
cast call $ORACLE_ADDRESS "getSpotPrice(address)(uint256)" \
  0x8b732595a59c9a18acA0Aca3221A656Eb38158fC --rpc-url $RPC_URL
# Should return: 300000000000 (SAME as synthetic!)

# 4. Query underlying IDRX price
cast call $ORACLE_ADDRESS "getSpotPrice(address)(uint256)" \
  0x80FD9a0F8BCA5255692016D67E0733bf5262C142 --rpc-url $RPC_URL
# Should return: 100000000 (1e8 = $1.00)
```

## End-to-End Testing

### Test Auto-Borrow with Correct Health Factor

The primary use case is ensuring auto-borrow calculations use correct prices:

```bash
# Test with real scenario from the bug report
# User: 0xC21C5b2d33b791BEb51360a6dcb592ECdE37DB2C
# Collateral: 100 IDRX (10000 raw units)
# Borrow: ~0.02 WETH

cast call $LENDING_MANAGER "getProjectedHealthFactor(address,address,uint256)(uint256)" \
  0xC21C5b2d33b791BEb51360a6dcb592ECdE37DB2C \
  0x8b732595a59c9a18acA0Aca3221A656Eb38158fC \
  20000000000000000 \
  --rpc-url $RPC_URL

# Expected: ~1270000000000000000 (1.27e18)
# Before fix: ~433000000000000 (0.000433e18)
```

### Place Limit Order with Auto-Borrow

1. User places limit SELL order with auto-borrow enabled
2. Collateral: 100 IDRX
3. Borrow needed: ~0.02 WETH
4. Expected health factor: ~1.27
5. Order should succeed (HF ≥ 1.0)

**Before Fix**: Order failed with `InsufficientHealthFactorForBorrow` (HF = 0.000433)
**After Fix**: Order succeeds (HF = 1.27)

## Rollback Plan

If issues arise, you can temporarily disable the fallback:

```bash
# Set factory to zero address (disables fallback)
cast send $ORACLE_ADDRESS \
  "setSyntheticTokenFactory(address)" \
  0x0000000000000000000000000000000000000000 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

Note: This will cause Oracle to revert on underlying token queries. You'll need to revert LendingManager changes to restore manual conversion.

## Security Considerations

1. **Factory Trust**: Oracle trusts factory's `getSyntheticToken()` and `isSyntheticTokenActive()` responses
2. **Active Validation**: Only active synthetic tokens are used for fallback
3. **Owner Only**: Only Oracle owner can set/change factory reference
4. **No Circular Dependency**: Factory doesn't depend on Oracle (one-way reference)
5. **Backwards Compatible**: Existing synthetic token queries unaffected

## Gas Impact

Minimal gas increase for underlying token queries:
- Direct synthetic query: No change (CASE 1 - early return)
- Underlying query: +2 external calls to factory (CASE 2)
  - `getSyntheticToken()`: ~2,100 gas
  - `isSyntheticTokenActive()`: ~2,100 gas
  - Total overhead: ~4,200 gas

Trade-off: Slight gas increase for much better developer experience and bug prevention.

## Related Files

- `src/core/Oracle.sol` - Main Oracle implementation
- `src/core/interfaces/IOracle.sol` - Oracle interface
- `src/core/SyntheticTokenFactory.sol` - Token factory (source of truth)
- `src/yield/LendingManager.sol` - Simplified price queries
- `script/LinkOracleToFactory.s.sol` - Deployment helper
- `script/VerifyOracleFallback.s.sol` - Verification script

## Support

For issues or questions:
1. Check deployment logs for correct addresses
2. Run verification script to diagnose problems
3. Verify factory has correct token mappings
4. Ensure synthetic tokens are marked as active
5. Check Oracle has price data for synthetic tokens
