# Fee Tier System - Quick Reference

## Constants

```solidity
// Fee Tiers (basis points)
FEE_TIER_LOW    = 20   // 0.2%
FEE_TIER_MEDIUM = 50   // 0.5%

// Tick Spacing
TICK_SPACING_LOW    = 50   // For 0.2% fee tier
TICK_SPACING_MEDIUM = 200  // For 0.5% fee tier

// Default Protocol Fee
PROTOCOL_FEE = 10  // 0.1%
```

## Fee Tier Mapping

| Fee Tier | Percentage | Tick Spacing | Best For |
|----------|------------|--------------|----------|
| 20 bps   | 0.2%       | 50           | Stable pairs (USDC/USDT) |
| 50 bps   | 0.5%       | 200          | Volatile pairs (ETH/ALT) |

## LP Yield Formula

```
LP Yield = Fee Tier - Protocol Fee

Examples:
- 0.2% fee tier → 0.2% - 0.1% = 0.1% for LP
- 0.5% fee tier → 0.5% - 0.1% = 0.4% for LP
```

## Code Examples

### 1. Create Pool with Fee Tier

```solidity
// Create a pool with 0.2% fee tier
PoolId poolId = poolManager.createPool(
    USDC,           // base currency
    USDT,           // quote currency
    tradingRules,   // trading rules
    20              // fee tier (0.2%)
);
```

### 2. Create Liquidity Position

```solidity
// Create position with 0.5% fee tier
PositionParams memory params = PositionParams({
    poolKey: PoolKey({
        baseCurrency: WETH,
        quoteCurrency: USDC,
        feeTier: 50  // 0.5%
    }),
    strategy: Strategy.UNIFORM,
    lowerPrice: 1800e8,
    upperPrice: 2200e8,
    tickCount: 10,
    tickSpacing: 200,  // Must match fee tier
    depositAmount: 10000e6,
    depositCurrency: USDC,
    autoRebalance: true,
    rebalanceThresholdBps: 500
});

uint256 positionId = rangeLiquidityManager.createPosition(params);
```

### 3. Collect Fees

```solidity
// Collect accumulated fees
rangeLiquidityManager.collectFees(positionId);
```

### 4. Query Position Value

```solidity
PositionValue memory value = rangeLiquidityManager.getPositionValue(positionId);
console.log("Total Value:", value.totalValueInQuote);
console.log("Base Fees:", value.feesEarnedBase);
console.log("Quote Fees:", value.feesEarnedQuote);
```

### 5. Get LP Yield

```solidity
uint24 yieldBps = rangeLiquidityManager.getLPYield(positionId);
// Returns: 40 (0.4% for 0.5% fee tier with 0.1% protocol fee)
```

### 6. Set Protocol Fee (Owner)

```solidity
rangeLiquidityManager.setProtocolFee(15);  // Set to 0.15%
```

## Common Patterns

### Stable Pair Setup (0.2% Fee Tier)

```solidity
// USDC/USDT pool
PoolKey memory poolKey = PoolKey({
    baseCurrency: USDC,
    quoteCurrency: USDT,
    feeTier: 20  // 0.2%
});

PositionParams memory params = PositionParams({
    poolKey: poolKey,
    strategy: Strategy.UNIFORM,
    lowerPrice: 0.98e8,
    upperPrice: 1.02e8,
    tickCount: 20,
    tickSpacing: 50,  // Matches 0.2% tier
    depositAmount: 100000e6,
    depositCurrency: USDC,
    autoRebalance: true,
    rebalanceThresholdBps: 100  // 1%
});
```

### Volatile Pair Setup (0.5% Fee Tier)

```solidity
// ETH/BTC pool
PoolKey memory poolKey = PoolKey({
    baseCurrency: WETH,
    quoteCurrency: WBTC,
    feeTier: 50  // 0.5%
});

PositionParams memory params = PositionParams({
    poolKey: poolKey,
    strategy: Strategy.UNIFORM,
    lowerPrice: 0.04e8,
    upperPrice: 0.08e8,
    tickCount: 10,
    tickSpacing: 200,  // Matches 0.5% tier
    depositAmount: 10e18,
    depositCurrency: WETH,
    autoRebalance: true,
    rebalanceThresholdBps: 1000  // 10%
});
```

## Validation Checklist

Before creating a position, ensure:
- [ ] Fee tier is 20 or 50
- [ ] Tick spacing is 50 or 200
- [ ] Tick spacing matches fee tier (20→50, 50→200)
- [ ] Price range is valid (lower < upper)
- [ ] Deposit amount > 0
- [ ] Rebalance threshold ≤ 10000 bps

## Events to Monitor

```solidity
// Position created with fee tier info
event PositionCreated(
    uint256 indexed positionId,
    address indexed owner,
    PoolKey poolKey,
    uint128 lowerPrice,
    uint128 upperPrice,
    uint256 totalLiquidity,
    Strategy strategy,
    uint16 tickSpacing,
    uint24 feeTier
);

// Fees collected
event FeesCollected(
    uint256 indexed positionId,
    uint256 baseAmount,
    uint256 quoteAmount
);

// Position closed with fees
event PositionClosed(
    uint256 indexed positionId,
    address indexed owner,
    uint256 baseReturned,
    uint256 quoteReturned,
    uint256 feesEarnedBase,
    uint256 feesEarnedQuote
);
```

## Error Reference

```solidity
error InvalidFeeTier(uint24 feeTier);
error InvalidTickSpacing(uint16 tickSpacing);
error NotPositionOwner(uint256 positionId, address caller);
error PositionNotActive(uint256 positionId);
```

## Gas Estimates

| Operation | Estimated Gas |
|-----------|--------------|
| Create Position | ~250,000 |
| Collect Fees | ~60,000 |
| Close Position | ~180,000 |
| Get Position Value | ~5,000 (view) |
| Get LP Yield | ~3,000 (view) |

## Helper Functions

```solidity
// From FeeTier.sol library
FeeTier.getTickSpacingForFeeTier(20);  // Returns 50
FeeTier.getFeeTierForTickSpacing(200); // Returns 50
FeeTier.calculateLPFee(50, 10);        // Returns 40 (0.4%)
FeeTier.calculateFee(10000, 50);       // Returns 50 (0.5% of 10000)
FeeTier.splitFee(100, 50, 10);         // Returns (20, 80) - protocol:LP
```

## TypeScript/JavaScript Integration

```typescript
// Constants
const FEE_TIER_LOW = 20;      // 0.2%
const FEE_TIER_MEDIUM = 50;   // 0.5%
const TICK_SPACING_LOW = 50;
const TICK_SPACING_MEDIUM = 200;

// Create position
const poolKey = {
    baseCurrency: USDC_ADDRESS,
    quoteCurrency: USDT_ADDRESS,
    feeTier: FEE_TIER_LOW
};

const params = {
    poolKey: poolKey,
    strategy: 0, // UNIFORM
    lowerPrice: ethers.utils.parseUnits("0.98", 8),
    upperPrice: ethers.utils.parseUnits("1.02", 8),
    tickCount: 10,
    tickSpacing: TICK_SPACING_LOW,
    depositAmount: ethers.utils.parseUnits("10000", 6),
    depositCurrency: USDC_ADDRESS,
    autoRebalance: true,
    rebalanceThresholdBps: 500
};

const tx = await rangeLiquidityManager.createPosition(params);
const receipt = await tx.wait();

// Listen for events
rangeLiquidityManager.on("FeesCollected", (positionId, baseAmount, quoteAmount) => {
    console.log(`Fees collected for position ${positionId}`);
    console.log(`Base: ${baseAmount}, Quote: ${quoteAmount}`);
});
```

## Testing Snippets

```solidity
// Test fee collection
function testCollectFees() public {
    // Create position
    uint256 positionId = createTestPosition();

    // Simulate trading to accumulate fees
    vm.prank(trader);
    router.swap(poolKey, 1000e6, Side.BUY);

    // Collect fees
    vm.prank(lpProvider);
    rangeLiquidityManager.collectFees(positionId);

    // Check fees collected
    PositionValue memory value = rangeLiquidityManager.getPositionValue(positionId);
    assertGt(value.feesEarnedQuote, 0, "Should collect fees");
}
```

## Troubleshooting

### "Invalid fee tier" error
- Ensure feeTier is 20 or 50
- Check PoolKey struct includes feeTier

### "Invalid tick spacing" error
- Ensure tickSpacing is 50 or 200
- Match tick spacing to fee tier (20→50, 50→200)

### No fees collected
- Ensure trades have occurred in the pool
- Check if position price range includes current price
- Verify orders are being filled

### Gas too high
- Consider using lower tick count
- Batch operations when possible
- Collect fees less frequently

## Best Practices

1. **Choose appropriate fee tier**
   - Stable pairs → 0.2%
   - Volatile pairs → 0.5%

2. **Match tick spacing to fee tier**
   - Always use correct mapping

3. **Monitor position health**
   - Check `canRebalance()` regularly
   - Enable auto-rebalance for active management

4. **Collect fees periodically**
   - Balance gas costs vs. fee accumulation
   - Consider collecting during rebalancing

5. **Track LP yield**
   - Monitor `getLPYield()` for profitability
   - Compare across different pools

---

**Quick Links:**
- Full Documentation: [FeeTierAndLiquidity.md](./FeeTierAndLiquidity.md)
- Changelog: [CHANGELOG_FEE_TIER_UPDATE.md](../CHANGELOG_FEE_TIER_UPDATE.md)
- Library: [FeeTier.sol](../src/core/libraries/FeeTier.sol)
