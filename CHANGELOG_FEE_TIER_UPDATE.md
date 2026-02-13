# Fee Tier and Tick Spacing Update Changelog

## Summary

Updated the liquidity provider system to support Uniswap v3-style fee tiers with tick-based pricing. LPs now earn yield from the spread between fee tier and protocol fee.

## Key Changes

### 1. Fee Tiers Implemented
- **0.2% (20 bps)** - Low fee tier for stable pairs
- **0.5% (50 bps)** - Medium fee tier for volatile pairs

### 2. Tick Spacing
- **50** - Tick spacing for 0.2% fee tier
- **200** - Tick spacing for 0.5% fee tier

### 3. LP Yield Mechanism
- LPs earn yield from: `Fee Tier - Protocol Fee`
- Example: 0.5% fee tier - 0.1% protocol fee = 0.4% LP yield
- Fees accumulate and can be collected via `collectFees()`

## Modified Files

### Core Libraries

#### `src/core/libraries/Pool.sol`
**Changes:**
- Added `feeTier` field to `PoolKey` struct
- Added fee tier constants: `FEE_TIER_LOW` (20 bps), `FEE_TIER_MEDIUM` (50 bps)
- Added tick spacing constants: `TICK_SPACING_LOW` (50), `TICK_SPACING_MEDIUM` (200)
- Updated `toId()` function to include feeTier in hash calculation
- Added `getTickSpacing()` helper function

**Impact:** All PoolKey usages must now include feeTier

#### `src/core/libraries/RangeLiquidityDistribution.sol`
**Changes:**
- Updated `calculateTickPrices()` to accept `tickSpacing` parameter
- Added tick spacing alignment logic for consistent price levels
- Maintained backward compatibility with overloaded function (defaults to tickSpacing=50)

**Impact:** Tick prices are now aligned to tick spacing boundaries

### New Files Created

#### `src/core/libraries/FeeTier.sol`
**Purpose:** Helper library for fee tier calculations and validation

**Functions:**
- `isValidFeeTier()` - Validate fee tier (20 or 50 bps)
- `isValidTickSpacing()` - Validate tick spacing (50 or 200)
- `getTickSpacingForFeeTier()` - Get tick spacing for a fee tier
- `getFeeTierForTickSpacing()` - Get fee tier for a tick spacing
- `calculateLPFee()` - Calculate LP fee from total fee tier
- `calculateFee()` - Calculate fee amount for a transaction
- `splitFee()` - Split fee between protocol and LP

### Core Contracts

#### `src/core/interfaces/IRangeLiquidityManager.sol`
**Changes:**
- Added `tickSpacing` field to `RangePosition` struct
- Added `feesCollectedBase` and `feesCollectedQuote` fields to `RangePosition`
- Added `tickSpacing` parameter to `PositionParams` struct
- Added `feesEarnedBase` and `feesEarnedQuote` to `PositionValue` struct
- Updated `PositionCreated` event to include `tickSpacing` and `feeTier`
- Updated `PositionClosed` event to include fees earned
- Added new `FeesCollected` event
- Added `InvalidTickSpacing` and `InvalidFeeTier` errors
- Added `collectFees()` function declaration
- Added `getFeeTierForPool()` function declaration

**Impact:** All position creation must specify tick spacing and fee tier

#### `src/core/storages/RangeLiquidityManagerStorage.sol`
**Changes:**
- Added `accumulatedFees` mapping to track fees per position
- Added `protocolFeeBps` to store protocol fee percentage

**Impact:** Storage layout updated for fee tracking

#### `src/core/RangeLiquidityManager.sol`
**Changes:**
- Updated `initialize()` to set default protocol fee (10 bps = 0.1%)
- Updated `_validatePositionParams()` to validate tick spacing and fee tier
- Updated `createPosition()` to use tick spacing in tick price calculation
- Updated position struct initialization to include `tickSpacing`, `feesCollectedBase`, `feesCollectedQuote`
- Updated `PositionCreated` event emission to include tick spacing and fee tier
- Updated `closePosition()` to emit fees earned
- Updated `rebalancePosition()` to use tick spacing
- Updated `getPositionValue()` to include fees earned
- Added `collectFees()` function for fee collection
- Added `getFeeTierForPool()` view function
- Added `setProtocolFee()` owner function
- Added `getProtocolFee()` view function
- Added `getLPYield()` view function

**Impact:** Full fee tier support with fee collection mechanism

#### `src/core/interfaces/IPoolManager.sol`
**Changes:**
- Added `feeTier` field to `Pool` struct
- Updated `PoolCreated` event to include `feeTier`
- Updated `createPool()` function signature to include `_feeTier` parameter

**Impact:** Pool creation must now specify fee tier

### Documentation

#### `docs/FeeTierAndLiquidity.md`
**Purpose:** Comprehensive documentation of fee tier system

**Sections:**
- Overview of fee tiers and tick spacing
- LP yield mechanism explanation
- Creating liquidity positions
- Collecting fees
- Protocol configuration
- Fee tier selection guidelines
- Integration examples
- Security considerations

## Breaking Changes

### 1. PoolKey Structure
**Before:**
```solidity
struct PoolKey {
    Currency baseCurrency;
    Currency quoteCurrency;
}
```

**After:**
```solidity
struct PoolKey {
    Currency baseCurrency;
    Currency quoteCurrency;
    uint24 feeTier;
}
```

**Migration:** All PoolKey instances must include feeTier

### 2. Pool Creation
**Before:**
```solidity
poolManager.createPool(baseCurrency, quoteCurrency, tradingRules);
```

**After:**
```solidity
poolManager.createPool(baseCurrency, quoteCurrency, tradingRules, feeTier);
```

**Migration:** Add fee tier parameter (20 or 50) to all createPool calls

### 3. Position Creation
**Before:**
```solidity
PositionParams({
    poolKey: poolKey,
    strategy: strategy,
    lowerPrice: lower,
    upperPrice: upper,
    tickCount: count,
    depositAmount: amount,
    depositCurrency: currency,
    autoRebalance: true,
    rebalanceThresholdBps: threshold
})
```

**After:**
```solidity
PositionParams({
    poolKey: poolKey,  // Now includes feeTier
    strategy: strategy,
    lowerPrice: lower,
    upperPrice: upper,
    tickCount: count,
    tickSpacing: 50,  // NEW: Must be 50 or 200
    depositAmount: amount,
    depositCurrency: currency,
    autoRebalance: true,
    rebalanceThresholdBps: threshold
})
```

**Migration:** Add tickSpacing parameter to all position creation calls

## New Features

### 1. Fee Collection
LPs can now collect accumulated fees:
```solidity
rangeLiquidityManager.collectFees(positionId);
```

### 2. LP Yield Query
Query the yield percentage for a position:
```solidity
uint24 yieldBps = rangeLiquidityManager.getLPYield(positionId);
```

### 3. Fee Tier Query
Get fee tier for a pool:
```solidity
uint24 feeTier = rangeLiquidityManager.getFeeTierForPool(poolKey);
```

### 4. Protocol Fee Management
Owner can adjust protocol fee:
```solidity
rangeLiquidityManager.setProtocolFee(15); // Set to 0.15%
uint16 currentFee = rangeLiquidityManager.getProtocolFee();
```

## Validation Rules

### Fee Tier Validation
- Must be 20 (0.2%) or 50 (0.5%)
- Validated in `_validatePositionParams()`

### Tick Spacing Validation
- Must be 50 or 200
- Must match fee tier:
  - 0.2% fee tier → 50 tick spacing
  - 0.5% fee tier → 200 tick spacing
- Validated in `_validatePositionParams()`

### Protocol Fee Validation
- Cannot exceed 1000 bps (10%)
- Validated in `setProtocolFee()`

## Testing Recommendations

### Unit Tests Needed
1. Fee tier validation
2. Tick spacing validation
3. Fee calculation and splitting
4. Fee collection
5. LP yield calculation
6. Position creation with different fee tiers
7. Rebalancing with tick spacing

### Integration Tests Needed
1. End-to-end position creation and fee collection
2. Multiple positions with different fee tiers
3. Pool creation with fee tiers
4. Fee accumulation over multiple trades
5. Protocol fee adjustment

## Gas Impact

### Optimizations
- Efficient basis point arithmetic
- Batch fee collection (base + quote)
- No loops in fee calculations
- Storage-efficient fee tracking

### Expected Gas Changes
- Position creation: +~5,000 gas (additional validations and storage)
- Fee collection: ~60,000 gas (new function)
- Position value query: +~2,000 gas (fee tracking)

## Deployment Steps

1. **Deploy New Libraries**
   - Deploy `FeeTier.sol`
   - Link to contracts if needed

2. **Upgrade Contracts**
   - Upgrade `RangeLiquidityManager` (proxy pattern)
   - Update storage layout if needed

3. **Update Pool Creation**
   - Update pool creation scripts to include fee tier
   - Set default fee tiers for different pool types

4. **Migrate Existing Positions** (if any)
   - Close old positions
   - Recreate with fee tier specification
   - Ensure fee collection before migration

5. **Update Frontend/SDK**
   - Update PoolKey type to include feeTier
   - Add tick spacing input
   - Add fee collection UI
   - Display LP yield

## Backward Compatibility

### Compatible
- Existing pool queries (returns updated Pool struct)
- Position value queries (includes new fee fields)
- Position history (new fields added, old data preserved)

### Not Compatible
- Direct pool creation (requires fee tier parameter)
- Direct position creation (requires tick spacing)
- PoolKey hash calculation (includes feeTier now)

## Security Audit Items

1. Fee calculation overflow protection
2. Protocol fee cap enforcement
3. Fee collection authorization checks
4. Reentrancy protection in collectFees
5. Fee tier validation completeness
6. Storage slot collision in upgrades

## Future Enhancements

1. **Additional Fee Tiers**
   - 0.05% for ultra-stable pairs
   - 1% for high-risk pairs

2. **Dynamic Fees**
   - Adjust based on volatility
   - Time-weighted fee structures

3. **Fee Sharing**
   - Governance token holder rewards
   - Volume-based rebates

4. **Advanced Features**
   - Auto-compounding fees
   - Fee voting mechanisms
   - Cross-pool fee optimization

## Support and Questions

For questions or issues:
1. Check `docs/FeeTierAndLiquidity.md` for detailed documentation
2. Review test cases for usage examples
3. Contact development team for migration support

---

**Version:** 1.0.0
**Date:** 2026-02-12
**Author:** ScaleX Protocol Team
